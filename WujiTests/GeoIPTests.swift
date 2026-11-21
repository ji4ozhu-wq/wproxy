import XCTest
@testable import Wuji

// MARK: - GeoIP asset pipeline tests (task-8 / docs/deps.md)

/// Covers the pure, offline-testable parts of the GeoIP pipeline:
///  * scanning/assembling the v2ray `GeoIPList` protobuf (no CIDR decoding),
///  * gzip + JSON codec,
///  * `CountryDirectory` metadata override precedence,
///  * `GeoIPAssetManager` extraction rules / file naming / cleanup,
///  * `GeoIPUpdater` 7-day policy, 1-hour retry, connectivity gate, verification
///    and persistence.
///
/// No test touches the network: the updater is always constructed with a mock
/// downloader. Tests that need the real bundled dataset decompress it locally.
final class GeoIPTests: XCTestCase {
    // MARK: - Fixture helpers

    /// Minimal protobuf wire encoder mirroring the v2ray GeoIPList schema.
    private enum Proto {
        static func varint(_ value: UInt64) -> [UInt8] {
            var result: [UInt8] = []
            var remaining = value
            repeat {
                var byte = UInt8(remaining & 0x7F)
                remaining >>= 7
                if remaining != 0 { byte |= 0x80 }
                result.append(byte)
            } while remaining != 0
            return result
        }

        static func tag(_ field: Int, _ wireType: Int) -> [UInt8] {
            varint(UInt64(field) << 3 | UInt64(wireType))
        }

        static func lengthDelimited(_ field: Int, _ payload: [UInt8]) -> [UInt8] {
            tag(field, 2) + varint(UInt64(payload.count)) + payload
        }

        static func varintField(_ field: Int, _ value: UInt64) -> [UInt8] {
            tag(field, 0) + varint(value)
        }

        static func cidr(ipv4: String, prefix: Int) -> [UInt8] {
            let bytes = ipv4.split(separator: ".").compactMap { UInt8($0) }
            return lengthDelimited(1, bytes) + varintField(2, UInt64(prefix))
        }

        static func cidr(ipv6: [UInt8], prefix: Int) -> [UInt8] {
            lengthDelimited(1, ipv6) + varintField(2, UInt64(prefix))
        }

        static func entry(code: String, cidrs: [[UInt8]]) -> [UInt8] {
            var out = lengthDelimited(1, Array(code.utf8))
            for cidr in cidrs {
                out += lengthDelimited(2, cidr)
            }
            return out
        }

        static func list(_ entries: [[UInt8]]) -> Data {
            var out: [UInt8] = []
            for entry in entries {
                out += lengthDelimited(1, entry)
            }
            return Data(out)
        }
    }

    private static let v6Address: [UInt8] = [0x20, 0x01, 0x0d, 0xb8] + [UInt8](repeating: 0, count: 12)

    /// Small synthetic GeoIPList: CN (2×IPv4 + 1×IPv6), JP, PRIVATE, TEST.
    func testChineseCountryNamesPrefixTaiwanHongKongMacau() {
        XCTAssertEqual(CountryDirectory.localizedName(for: "TW", languageCode: "zh-Hans"), "中国台湾")
        XCTAssertEqual(CountryDirectory.localizedName(for: "HK", languageCode: "zh-Hans"), "中国香港")
        XCTAssertEqual(CountryDirectory.localizedName(for: "MO", languageCode: "zh-Hans"), "中国澳门")
        XCTAssertEqual(CountryDirectory.localizedName(for: "TW", languageCode: "zh-Hant"), "中國台灣")
        XCTAssertEqual(CountryDirectory.localizedName(for: "HK", languageCode: "zh-Hant"), "中國香港")
        XCTAssertEqual(CountryDirectory.localizedName(for: "MO", languageCode: "zh-Hant"), "中國澳門")
        // Other languages keep the neutral region name.
        XCTAssertNotEqual(CountryDirectory.localizedName(for: "TW", languageCode: "en"), "中国台湾")
    }

    func testCountryDirectoryFollowsPreferredInAppLanguage() {
        let original = CountryDirectory.preferredLanguageCode
        defer { CountryDirectory.preferredLanguageCode = original }
        let directory = CountryDirectory(metadataURL: URL(fileURLWithPath: "/nonexistent.json"))
        directory.setPreferredLanguageCode("zh-Hans")
        XCTAssertEqual(CountryDirectory.preferredLanguageCode, "zh-Hans")
        directory.setPreferredLanguageCode("en")
        XCTAssertEqual(CountryDirectory.preferredLanguageCode, "en")
    }

    private func makeDataset() -> Data {
        Proto.list([
            Proto.entry(code: "CN", cidrs: [
                Proto.cidr(ipv4: "1.0.1.0", prefix: 24),
                Proto.cidr(ipv4: "1.0.2.0", prefix: 23),
                Proto.cidr(ipv6: Self.v6Address, prefix: 32)
            ]),
            Proto.entry(code: "JP", cidrs: [
                Proto.cidr(ipv4: "1.0.16.0", prefix: 20)
            ]),
            Proto.entry(code: "PRIVATE", cidrs: [
                Proto.cidr(ipv4: "10.0.0.0", prefix: 8),
                Proto.cidr(ipv4: "192.168.0.0", prefix: 16)
            ]),
            Proto.entry(code: "TEST", cidrs: [
                Proto.cidr(ipv4: "192.0.2.0", prefix: 24)
            ])
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wuji-geoip-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeMetadata(_ counts: [String: Int],
                               source: String = "test fixture",
                               dataVersion: String = "abcdef123456",
                               to url: URL) throws {
        let metadata = GeoIPMetadataStore.make(
            source: source,
            license: "test license",
            dataVersion: dataVersion,
            sha256: nil,
            generated: "2026-01-01",
            counts: counts
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: url)
    }

    // MARK: - GeoIPProtoParser: scanning

    func testParserListsEveryEntryWithRawRanges() throws {
        let dataset = makeDataset()
        let entries = try GeoIPProtoParser.entries(in: dataset)
        XCTAssertEqual(entries.map(\.code), ["CN", "JP", "PRIVATE", "TEST"])
        XCTAssertEqual(entries.map(\.cidrCount), [3, 1, 2, 1])
        for entry in entries {
            XCTAssertFalse(entry.payloadRange.isEmpty)
            XCTAssertLessThanOrEqual(entry.payloadRange.upperBound, dataset.count)
        }
        XCTAssertEqual(try GeoIPProtoParser.countryCounts(in: dataset),
                       ["CN": 3, "JP": 1, "PRIVATE": 2, "TEST": 1])
    }

    func testParserSkipsUnknownFieldsAtEveryLevel() throws {
        var cidr = Proto.cidr(ipv4: "1.2.3.0", prefix: 24)
        cidr += Proto.varintField(9, 42)                 // unknown CIDR field
        cidr += Proto.lengthDelimited(7, [0xDE, 0xAD])   // unknown CIDR field

        var entry = Proto.lengthDelimited(1, Array("CN".utf8))
        entry += Proto.varintField(3, 1)                 // unknown GeoIP field
        entry += Proto.lengthDelimited(6, [1, 2, 3])     // unknown GeoIP field
        entry += Proto.lengthDelimited(2, cidr)

        var payload: [UInt8] = []
        payload += Proto.varintField(5, 0xFFFF)          // unknown top-level field
        payload += Proto.lengthDelimited(1, entry)
        payload += Proto.lengthDelimited(4, [9, 9])      // unknown top-level field

        let entries = try GeoIPProtoParser.entries(in: Data(payload))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].code, "CN")
        XCTAssertEqual(entries[0].cidrCount, 1)
    }

    func testParserRejectsTruncatedGarbageAndEmptyPayloads() {
        let dataset = makeDataset()
        XCTAssertThrowsError(try GeoIPProtoParser.entries(in: dataset.dropLast(3)))
        XCTAssertThrowsError(try GeoIPProtoParser.entries(in: dataset.prefix(dataset.count / 2)))
        XCTAssertThrowsError(try GeoIPProtoParser.entries(in: Data((0..<64).map { UInt8(0xFF - $0) })))
        XCTAssertThrowsError(try GeoIPProtoParser.entries(in: Data())) { error in
            XCTAssertEqual(error as? GeoIPProtoError, .emptyPayload)
        }
    }

    func testParserHandlesMultiByteLengths() throws {
        let cidrs = (0..<120).map { index in
            Proto.cidr(ipv4: "10.\(index / 2).0.0", prefix: 24)
        }
        let dataset = Proto.list([Proto.entry(code: "CN", cidrs: cidrs)])
        XCTAssertGreaterThan(dataset.count, 1_000)
        let entries = try GeoIPProtoParser.entries(in: dataset)
        XCTAssertEqual(entries.first?.cidrCount, 120)
    }

    // MARK: - GeoIPProtoParser: assembly

    func testAssembleCopiesEntryPayloadBytesVerbatim() throws {
        let dataset = makeDataset()
        let entries = try GeoIPProtoParser.entries(in: dataset)
        let selected = entries.filter { $0.code == "CN" || $0.code == "PRIVATE" }
        let assembled = try GeoIPProtoParser.assembleList(from: dataset, entries: selected)

        let rebuilt = try GeoIPProtoParser.entries(in: assembled)
        XCTAssertEqual(rebuilt.map(\.code), ["CN", "PRIVATE"])
        XCTAssertEqual(rebuilt.map(\.cidrCount), [3, 2])
        for (source, copy) in zip(selected, rebuilt) {
            XCTAssertEqual(dataset.subdata(in: source.payloadRange),
                           assembled.subdata(in: copy.payloadRange),
                           "entry bytes must be copied verbatim, not re-encoded")
        }
        // The assembled list is a valid GeoIPList: one tag+length frame per entry.
        XCTAssertGreaterThan(assembled.count, dataset.count / 4)
    }

    func testAssembleRejectsOutOfBoundsRange() throws {
        let dataset = makeDataset()
        let bogus = GeoIPListEntry(code: "CN",
                                   payloadRange: (dataset.count - 2)..<(dataset.count + 10),
                                   cidrCount: 1)
        XCTAssertThrowsError(try GeoIPProtoParser.assembleList(from: dataset, entries: [bogus]))
    }

    // MARK: - GeoIPCodec (gzip envelope)

    func testCodecRoundTripsGzip() throws {
        let payload = makeDataset()
        let compressed = try GeoIPCodec.gzip(payload)
        XCTAssertTrue(GeoIPCodec.isGzip(compressed))
        XCTAssertEqual(Array(compressed.prefix(3)), [0x1F, 0x8B, 0x08])
        XCTAssertEqual(try GeoIPCodec.decompressedIfNeeded(compressed), payload)
    }

    func testCodecPassesThroughPlainData() throws {
        let payload = makeDataset()
        XCTAssertFalse(GeoIPCodec.isGzip(payload))
        XCTAssertEqual(try GeoIPCodec.decompressedIfNeeded(payload), payload)
    }

    func testCodecRejectsCorruptedAndTruncatedGzip() throws {
        var compressed = try GeoIPCodec.gzip(makeDataset())
        compressed[compressed.count / 2] ^= 0xFF
        XCTAssertThrowsError(try GeoIPCodec.gunzip(compressed))

        let intact = try GeoIPCodec.gzip(makeDataset())
        // Cutting the trailer also truncates the DEFLATE stream: any typed error is
        // acceptable, as long as nothing is decoded.
        XCTAssertThrowsError(try GeoIPCodec.gunzip(intact.prefix(intact.count - 6)))
        XCTAssertThrowsError(try GeoIPCodec.gunzip(Data([0x1F, 0x8B]))) { error in
            XCTAssertEqual(error as? GeoIPCodec.CodecError, .truncated)
        }
    }

    func testCodecDecodesStandardGzipFromAnotherTool() throws {
        // `gzip.compress(b'{"source":"external"}', 9, mtime=0)` produced by Python,
        // i.e. a normal gzip envelope rather than our own writer.
        let base64 = "H4sIAAAAAAAC/6tWKs4vLUpOVbJSSq0oSS3KS8xRqgUA2euO6xUAAAA="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let decoded = try GeoIPCodec.decompressedIfNeeded(data)
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "{\"source\":\"external\"}")
    }

    // MARK: - Bundled assets

    private func bundledDatasetURL() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: GeoIPAssetManager.bundleResourceName,
                                      withExtension: GeoIPAssetManager.bundleResourceExtension),
                      "geoip.dat.gz must be bundled")
    }

    func testBundledDatasetMatchesItsMetadata() throws {
        let metadata = try XCTUnwrap(GeoIPMetadataStore.bundled(.main))
        let compressed = try Data(contentsOf: try bundledDatasetURL())
        XCTAssertLessThan(compressed.count, 6 * 1024 * 1024, "the gzipped dataset must stay below 6 MB")
        let dataset = try GeoIPCodec.decompressedIfNeeded(compressed)
        XCTAssertEqual(dataset.count, 23_876_117, "the full v2fly/DB-IP dataset must be shipped")
        XCTAssertEqual(GeoIPAssetManager.sha256Hex(dataset), metadata.sha256,
                       "the bundled gzip must match the metadata sha256")
        XCTAssertEqual(metadata.dataVersion, String(try XCTUnwrap(metadata.sha256).prefix(12)))
        XCTAssertEqual(try GeoIPProtoParser.countryCounts(in: dataset), metadata.countries,
                       "metadata counts must match a fresh scan of the dataset")
        XCTAssertEqual(metadata.entryCount, 253)
        XCTAssertEqual(metadata.countryCount, 250)
        for code in ["CN", "JP", "US", "DE", "GB", "SG", "HK", "TW", "KR"] {
            XCTAssertGreaterThan(metadata.countries[code] ?? 0, 0, "\(code) must be present")
        }
        XCTAssertEqual(metadata.countries["CN"], 15_189)
        XCTAssertEqual(metadata.countries["PRIVATE"], 18)
        XCTAssertEqual(metadata.countries["US"], 271_874)
        XCTAssertEqual(GeoIPMetadataStore.totalCIDRCount(metadata), 1_410_686)
        XCTAssertEqual(metadata.license?.contains("CC BY-SA 4.0"), true)
        XCTAssertEqual(metadata.license?.contains("CC BY 4.0"), true)
        XCTAssertEqual(metadata.source.contains("DB-IP"), true)
    }

    func testBundledMetadataFileIsSmall() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: CountryDirectory.resourceName,
                                                withExtension: CountryDirectory.resourceExtension))
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        XCTAssertLessThan(size, 64 * 1024, "geoip_countries.json must stay a few KB")
    }

    // MARK: - CountryDirectory (metadata only)

    func testCountryDirectoryLoadsBundledMetadata() throws {
        let bundleMetadataURL = try XCTUnwrap(
            Bundle.main.url(forResource: CountryDirectory.resourceName,
                            withExtension: CountryDirectory.resourceExtension))
        let directory = CountryDirectory(metadataURL: bundleMetadataURL)
        XCTAssertGreaterThanOrEqual(directory.countries.count, 240)
        XCTAssertEqual(directory.countries.count, 250)
        XCTAssertEqual(directory.totalCIDRCount, 1_410_686)
        XCTAssertEqual(directory.datasetDataVersion?.count, 12)
        XCTAssertFalse(directory.datasetSource.isEmpty)
        XCTAssertEqual(directory.isUsingDownloadedSnapshot, false)
        XCTAssertEqual(directory.cidrCount(for: "CN"), 15_189)
        XCTAssertEqual(directory.cidrCount(for: "JP"), 38_106)
        XCTAssertEqual(directory.country(code: "JP")?.englishName, "Japan")
        XCTAssertEqual(directory.country(code: "cn")?.code, "CN")
        XCTAssertTrue(directory.searchCountries("jap").contains { $0.code == "JP" })
        XCTAssertEqual(CountryInfo(code: "JP", name: "Japan", cidrCount: 1).flag, "🇯🇵")
        // Pseudo lists are never offered as countries.
        for code in GeoIPMetadataStore.nonCountryCodes {
            XCTAssertFalse(directory.countries.contains { $0.code == code })
            XCTAssertNil(directory.country(code: code))
        }
    }

    func testCountryDirectoryPrefersOverrideMetadata() throws {
        let directoryURL = try makeTemporaryDirectory()
        let override = directoryURL.appendingPathComponent(GeoIPMetadataStore.fileName)
        try writeMetadata(["AA": 7, "BB": 9], source: "downloaded fixture", to: override)

        let directory = CountryDirectory(metadataURL: override, isOverride: true)
        XCTAssertTrue(directory.isUsingDownloadedSnapshot)
        XCTAssertEqual(Set(directory.countries.map(\.code)), ["AA", "BB"])
        XCTAssertEqual(directory.cidrCount(for: "AA"), 7)
        XCTAssertEqual(directory.datasetSource, "downloaded fixture")
    }

    func testCountryDirectoryIgnoresCorruptOverrideAndUsesBundle() throws {
        let directoryURL = try makeTemporaryDirectory()
        let override = directoryURL.appendingPathComponent(GeoIPMetadataStore.fileName)
        try Data("not json".utf8).write(to: override)

        let directory = CountryDirectory(metadataURL: override, isOverride: true)
        XCTAssertEqual(directory.countries.count, 250, "a corrupt override falls back to the bundle")
        XCTAssertFalse(directory.isUsingDownloadedSnapshot)
    }

    func testCountryDirectoryReloadPicksUpNewMetadata() throws {
        let directoryURL = try makeTemporaryDirectory()
        let override = directoryURL.appendingPathComponent(GeoIPMetadataStore.fileName)
        try writeMetadata(["AA": 7], to: override)
        let directory = CountryDirectory(metadataURL: override, isOverride: true)
        XCTAssertEqual(directory.countries.map(\.code), ["AA"])

        try writeMetadata(["BB": 3], to: override)
        directory.reload()
        XCTAssertEqual(directory.countries.map(\.code), ["BB"])
    }

    // MARK: - GeoIPAssetManager

    private func makeInstalledDataset(at container: URL) throws -> Data {
        let dataset = makeDataset()
        try dataset.write(to: container.appendingPathComponent(GeoIPAssetManager.datasetFileName))
        return dataset
    }

    func testAssetManagerBuildsSelectedEntries() throws {
        let container = try makeTemporaryDirectory()
        let dataset = try makeInstalledDataset(at: container)
        let manager = GeoIPAssetManager(containerURL: container)

        let asset = try XCTUnwrap(manager.makeAsset(codes: ["CN"], includePrivate: true,
                                                    dataVersion: "abcdef123456"))
        XCTAssertEqual(asset.directory, container)
        XCTAssertTrue(asset.fileName.hasPrefix("wuji-geoip-"))
        XCTAssertTrue(asset.fileName.hasSuffix(".dat"))
        let hashPart = asset.fileName
            .replacingOccurrences(of: "wuji-geoip-", with: "")
            .replacingOccurrences(of: ".dat", with: "")
        XCTAssertEqual(hashPart.count, 12)
        XCTAssertTrue(hashPart.allSatisfy(\.isHexDigit))
        XCTAssertEqual(asset.ruleTargets,
                       ["ext:\(asset.fileName):cn", "ext:\(asset.fileName):private"])
        XCTAssertEqual(asset.entryCodes, ["CN", "PRIVATE"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.fileURL.path))

        let assetData = try Data(contentsOf: asset.fileURL)
        let extracted = try GeoIPProtoParser.entries(in: assetData)
        XCTAssertEqual(extracted.map(\.code), ["CN", "PRIVATE"])
        XCTAssertEqual(extracted.map(\.cidrCount), [3, 2])
        for (source, copy) in zip(
            try GeoIPProtoParser.entries(in: dataset).filter { $0.code == "CN" || $0.code == "PRIVATE" },
            extracted
        ) {
            XCTAssertEqual(dataset.subdata(in: source.payloadRange),
                           assetData.subdata(in: copy.payloadRange))
        }
        // The asset manager also repaired the missing metadata sidecar.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: container.appendingPathComponent(GeoIPMetadataStore.fileName).path))
    }

    func testAssetFileNameIsStableAndOrderIndependent() throws {
        let container = try makeTemporaryDirectory()
        _ = try makeInstalledDataset(at: container)
        let manager = GeoIPAssetManager(containerURL: container)

        let first = try XCTUnwrap(manager.makeAsset(codes: ["CN", "JP"], includePrivate: false,
                                                    dataVersion: "abcdef123456"))
        let second = try XCTUnwrap(manager.makeAsset(codes: ["JP", "CN", "CN"], includePrivate: false,
                                                     dataVersion: "abcdef123456"))
        XCTAssertEqual(first.fileName, second.fileName,
                       "the asset name must depend on the data version + selected set, not its order")
        XCTAssertEqual(second.ruleTargets, ["ext:\(second.fileName):jp", "ext:\(second.fileName):cn"])

        let nextVersion = try XCTUnwrap(manager.makeAsset(codes: ["CN", "JP"], includePrivate: false,
                                                          dataVersion: "ffffffffffff"))
        XCTAssertNotEqual(first.fileName, nextVersion.fileName,
                          "a new dataset version must yield a new asset file name")
    }

    func testAssetManagerReturnsNilWithoutUsableSelection() throws {
        let container = try makeTemporaryDirectory()
        _ = try makeInstalledDataset(at: container)
        let manager = GeoIPAssetManager(containerURL: container)

        XCTAssertNil(manager.makeAsset(codes: [], includePrivate: false, dataVersion: "abcdef123456"))
        XCTAssertNil(manager.makeAsset(codes: ["ZZ"], includePrivate: false, dataVersion: "abcdef123456"))
        // PRIVATE alone is a valid asset: LAN bypass may be on with no country selected.
        let privateOnly = try XCTUnwrap(manager.makeAsset(codes: ["NOPE"], includePrivate: true,
                                                          dataVersion: "abcdef123456"))
        XCTAssertEqual(privateOnly.entryCodes, ["PRIVATE"])
        XCTAssertEqual(privateOnly.ruleTargets, ["ext:\(privateOnly.fileName):private"])
    }

    func testAssetManagerKeepsOnlyRecentAssets() throws {
        let container = try makeTemporaryDirectory()
        _ = try makeInstalledDataset(at: container)
        let manager = GeoIPAssetManager(containerURL: container)
        let selections: [([String], Bool)] = [
            (["CN"], false), (["JP"], false), (["CN", "JP"], false), (["CN"], true), (["JP"], true)
        ]
        var names: [String] = []
        for (index, selection) in selections.enumerated() {
            let asset = try XCTUnwrap(manager.makeAsset(codes: selection.0,
                                                        includePrivate: selection.1,
                                                        dataVersion: "abcdef123456"))
            names.append(asset.fileName)
            _ = index
        }
        let assets = try FileManager.default.contentsOfDirectory(atPath: container.path)
            .filter { $0.hasPrefix(GeoIPAssetManager.assetPrefix) && $0.hasSuffix(".dat") }
        XCTAssertLessThanOrEqual(assets.count, GeoIPAssetManager.retainedAssetCount)
        XCTAssertTrue(assets.contains(names.last!))

        let kept = assets.sorted()
        XCTAssertEqual(kept.contains(names[0]), assets.count < 3 ? true : false,
                       "only the newest assets are kept")
    }

    func testAssetManagerMaterializesBundledDatasetForFirstLaunch() throws {
        let container = try makeTemporaryDirectory()
        let manager = GeoIPAssetManager(containerURL: container)

        XCTAssertTrue(manager.prepareDatasetIfNeeded())
        let datasetURL = container.appendingPathComponent(GeoIPAssetManager.datasetFileName)
        let dataset = try Data(contentsOf: datasetURL)
        let metadata = try XCTUnwrap(GeoIPMetadataStore.bundled(.main))
        XCTAssertEqual(dataset.count, 23_876_117)
        XCTAssertEqual(GeoIPAssetManager.sha256Hex(dataset), metadata.sha256)
        let installed = try XCTUnwrap(
            GeoIPMetadataStore.load(from: container.appendingPathComponent(GeoIPMetadataStore.fileName)))
        XCTAssertEqual(installed.countries, metadata.countries)
        XCTAssertEqual(installed.sha256, metadata.sha256)
        XCTAssertTrue(manager.isDatasetReady)

        // Second call is a no-op returning the same readiness.
        XCTAssertTrue(manager.prepareDatasetIfNeeded())

        // Real-asset extraction from the installed dataset.
        let asset = try XCTUnwrap(manager.makeAsset(codes: ["HK"], includePrivate: true,
                                                    dataVersion: installed.dataVersion ?? "unknown"))
        let entries = try GeoIPProtoParser.entries(in: Data(contentsOf: asset.fileURL))
        XCTAssertEqual(entries.map(\.code), ["HK", "PRIVATE"])
        XCTAssertEqual(entries.first?.cidrCount, 18_572)
        XCTAssertEqual(entries.last?.cidrCount, 18)
    }

    func testAssetManagerCannotBuildWithoutDatasetOrBundle() throws {
        let container = try makeTemporaryDirectory()
        // The test bundle carries no geoip.dat.gz, so this simulates a missing bundle.
        let manager = GeoIPAssetManager(containerURL: container, bundle: Bundle(for: GeoIPTests.self))
        XCTAssertFalse(manager.prepareDatasetIfNeeded())
        XCTAssertNil(manager.makeAsset(codes: ["CN"], includePrivate: false, dataVersion: "abcdef123456"))
    }

    // MARK: - GeoIPUpdater: policy

    private final class MockDownloader: GeoIPDownloading {
        var responses: [URL: Result<GeoIPDownload, Error>] = [:]
        private(set) var requestedURLs: [URL] = []

        func fetch(_ url: URL) async throws -> GeoIPDownload {
            requestedURLs.append(url)
            guard let response = responses[url] else {
                throw URLError(.cannotFindHost)
            }
            return try response.get()
        }
    }

    private func makeMockDownloader(dataset: Data) -> MockDownloader {
        let downloader = MockDownloader()
        let mirror = GeoIPUpdater.mirrors[0]
        let checksum = GeoIPUpdater.sha256Hex(dataset)
        downloader.responses[mirror.checksumURL] = .success(
            GeoIPDownload(data: Data("\(checksum)  geoip.dat\n".utf8), etag: nil))
        downloader.responses[mirror.datasetURL] = .success(
            GeoIPDownload(data: dataset, etag: "\"fixture-etag\""))
        return downloader
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeUpdater(containerURL: URL,
                             downloader: MockDownloader,
                             now: @escaping () -> Date = { GeoIPTests.fixedNow },
                             bundle: Bundle = .main,
                             installed: (() -> Void)? = nil) -> GeoIPUpdater {
        GeoIPUpdater(containerURL: containerURL,
                     downloader: downloader,
                     now: now,
                     bundle: bundle,
                     assetManager: GeoIPAssetManager(containerURL: containerURL, bundle: bundle),
                     datasetInstalledHandler: installed)
    }

    func testUpdateDuePolicyUsesSevenDays() {
        let now = Self.fixedNow
        XCTAssertTrue(GeoIPUpdater.isUpdateDue(lastUpdatedAt: nil, now: now))
        XCTAssertFalse(GeoIPUpdater.isUpdateDue(lastUpdatedAt: now.addingTimeInterval(-6 * 86_400), now: now))
        XCTAssertFalse(GeoIPUpdater.isUpdateDue(lastUpdatedAt: now.addingTimeInterval(-7 * 86_400 + 60), now: now))
        XCTAssertTrue(GeoIPUpdater.isUpdateDue(lastUpdatedAt: now.addingTimeInterval(-7 * 86_400), now: now))
        XCTAssertTrue(GeoIPUpdater.isUpdateDue(lastUpdatedAt: now.addingTimeInterval(-8 * 86_400), now: now))
    }

    func testUpdaterDoesNothingWhileDisconnected() async throws {
        let container = try makeTemporaryDirectory()
        let downloader = MockDownloader()
        let updater = makeUpdater(containerURL: container, downloader: downloader)
        await updater.updateIfNeeded(vpnConnected: false)
        XCTAssertTrue(downloader.requestedURLs.isEmpty)
        XCTAssertNil(updater.status.lastError)
        XCTAssertFalse(updater.status.isUsingDownloadedData)
    }

    func testUpdaterInstallsVerifiedDatasetAndMetadata() async throws {
        let container = try makeTemporaryDirectory()
        let dataset = makeDataset()
        let downloader = makeMockDownloader(dataset: dataset)
        var installedCount = 0
        let updater = makeUpdater(containerURL: container,
                                  downloader: downloader,
                                  installed: { installedCount += 1 })

        await updater.updateIfNeeded(vpnConnected: true)

        XCTAssertEqual(installedCount, 1)
        let datasetURL = container.appendingPathComponent(GeoIPAssetManager.datasetFileName)
        XCTAssertEqual(try Data(contentsOf: datasetURL), dataset)
        let metadata = try XCTUnwrap(
            GeoIPMetadataStore.load(from: container.appendingPathComponent(GeoIPMetadataStore.fileName)))
        XCTAssertEqual(metadata.countries, ["CN": 3, "JP": 1, "PRIVATE": 2, "TEST": 1])
        XCTAssertEqual(metadata.countryCount, 2, "PRIVATE/TEST are not countries")
        XCTAssertEqual(metadata.dataVersion, String(GeoIPUpdater.sha256Hex(dataset).prefix(12)))
        XCTAssertEqual(metadata.license?.contains("CC BY-SA 4.0"), true)

        let metaURL = container.appendingPathComponent(GeoIPUpdater.metaFileName)
        let meta = try JSONDecoder().decode(GeoIPMeta.self, from: Data(contentsOf: metaURL))
        XCTAssertEqual(meta.lastUpdatedAt, Self.fixedNow)
        XCTAssertEqual(meta.etag, "\"fixture-etag\"")
        XCTAssertEqual(meta.dataVersion, metadata.dataVersion)

        let status = updater.status
        XCTAssertEqual(status.lastUpdatedAt, Self.fixedNow)
        XCTAssertEqual(status.countryCount, 2)
        XCTAssertEqual(status.cidrCount, 7)
        XCTAssertNil(status.lastError)
        XCTAssertFalse(status.isUpdating)
        XCTAssertTrue(status.isUsingDownloadedData)
        XCTAssertFalse(status.isRefreshDue)
    }

    func testUpdaterSkipsFreshDatasetAndRefreshesAfterSevenDays() async throws {
        let container = try makeTemporaryDirectory()
        let downloader = makeMockDownloader(dataset: makeDataset())
        var currentNow = Self.fixedNow
        let updater = makeUpdater(containerURL: container,
                                  downloader: downloader,
                                  now: { currentNow })

        await updater.updateIfNeeded(vpnConnected: true)
        let firstCount = downloader.requestedURLs.count
        XCTAssertGreaterThan(firstCount, 0)

        currentNow = Self.fixedNow.addingTimeInterval(6 * 86_400)
        await updater.updateIfNeeded(vpnConnected: true)
        XCTAssertEqual(downloader.requestedURLs.count, firstCount, "a 6-day-old dataset is fresh")

        currentNow = Self.fixedNow.addingTimeInterval(8 * 86_400)
        await updater.updateIfNeeded(vpnConnected: true)
        XCTAssertGreaterThan(downloader.requestedURLs.count, firstCount,
                             "an 8-day-old dataset must be refreshed")
    }

    func testUpdaterRetriesAfterOneHourWhileConnected() async throws {
        let container = try makeTemporaryDirectory()
        let downloader = MockDownloader()  // no responses -> every mirror fails
        var currentNow = Self.fixedNow
        let updater = makeUpdater(containerURL: container,
                                  downloader: downloader,
                                  now: { currentNow })

        await updater.updateIfNeeded(vpnConnected: true)
        XCTAssertNotNil(updater.status.lastError)
        let attemptsAfterFailure = downloader.requestedURLs.count
        XCTAssertGreaterThan(attemptsAfterFailure, 0)

        currentNow = Self.fixedNow.addingTimeInterval(30 * 60)
        await updater.updateIfNeeded(vpnConnected: false)
        XCTAssertEqual(downloader.requestedURLs.count, attemptsAfterFailure,
                       "disconnected state never retries")

        await updater.updateIfNeeded(vpnConnected: true)
        XCTAssertEqual(downloader.requestedURLs.count, attemptsAfterFailure,
                       "the fixed retry interval is 1 hour")

        currentNow = Self.fixedNow.addingTimeInterval(61 * 60)
        await updater.updateIfNeeded(vpnConnected: true)
        XCTAssertGreaterThan(downloader.requestedURLs.count, attemptsAfterFailure,
                             "after the 1-hour backoff the update is retried")
    }

    func testUpdaterManualUpdateIgnoresGates() async throws {
        let container = try makeTemporaryDirectory()
        let downloader = MockDownloader()
        let updater = makeUpdater(containerURL: container, downloader: downloader)
        await updater.updateIfNeeded(vpnConnected: true)  // fails
        XCTAssertNotNil(updater.status.lastError)

        for mirror in GeoIPUpdater.mirrors {
            let checksum = GeoIPUpdater.sha256Hex(makeDataset())
            downloader.responses[mirror.checksumURL] = .success(
                GeoIPDownload(data: Data("\(checksum)  geoip.dat\n".utf8), etag: nil))
            downloader.responses[mirror.datasetURL] = .success(
                GeoIPDownload(data: makeDataset(), etag: nil))
        }
        let success = await updater.manualUpdate()
        XCTAssertTrue(success)
        XCTAssertNil(updater.status.lastError)
        XCTAssertTrue(updater.status.isUsingDownloadedData)
        XCTAssertEqual(updater.status.lastUpdatedAt, Self.fixedNow)
    }

    func testUpdaterRejectsChecksumMismatchAndKeepsInstalledData() async throws {
        let container = try makeTemporaryDirectory()
        let dataset = makeDataset()
        let goodUpdater = makeUpdater(containerURL: container,
                                      downloader: makeMockDownloader(dataset: dataset))
        await goodUpdater.updateIfNeeded(vpnConnected: true)
        let datasetURL = container.appendingPathComponent(GeoIPAssetManager.datasetFileName)
        let installedBefore = try Data(contentsOf: datasetURL)

        // Serve a different payload than the checksum advertises.
        let badDownloader = MockDownloader()
        let mirror = GeoIPUpdater.mirrors[0]
        let otherDataset = Proto.list([Proto.entry(code: "AA", cidrs: [Proto.cidr(ipv4: "9.9.9.0", prefix: 24)])])
        badDownloader.responses[mirror.checksumURL] = .success(
            GeoIPDownload(data: Data("\(GeoIPUpdater.sha256Hex(dataset))  geoip.dat\n".utf8), etag: nil))
        badDownloader.responses[mirror.datasetURL] = .success(GeoIPDownload(data: otherDataset, etag: nil))
        let laterNow = Self.fixedNow.addingTimeInterval(8 * 86_400)
        let badUpdater = makeUpdater(containerURL: container,
                                     downloader: badDownloader,
                                     now: { laterNow })
        await badUpdater.updateIfNeeded(vpnConnected: true)

        XCTAssertTrue(badUpdater.status.lastError?.contains("sha256 mismatch") ?? false)
        XCTAssertEqual(try Data(contentsOf: datasetURL), installedBefore,
                       "a failed verification must not replace the installed dataset")
        XCTAssertEqual(badUpdater.status.lastUpdatedAt, Self.fixedNow,
                       "the installed dataset metadata is untouched (reloaded from disk)")
    }

    func testUpdaterFallsBackToSecondMirror() async throws {
        let container = try makeTemporaryDirectory()
        let dataset = makeDataset()
        let checksum = GeoIPUpdater.sha256Hex(dataset)
        let downloader = MockDownloader()
        let first = GeoIPUpdater.mirrors[0]
        let second = GeoIPUpdater.mirrors[1]
        downloader.responses[first.checksumURL] = .failure(URLError(.timedOut))
        downloader.responses[second.checksumURL] = .success(
            GeoIPDownload(data: Data("\(checksum)  geoip.dat\n".utf8), etag: nil))
        downloader.responses[second.datasetURL] = .success(GeoIPDownload(data: dataset, etag: nil))
        let updater = makeUpdater(containerURL: container, downloader: downloader)

        await updater.updateIfNeeded(vpnConnected: true)

        XCTAssertNil(updater.status.lastError)
        XCTAssertTrue(updater.status.isUsingDownloadedData)
        XCTAssertTrue(updater.status.source?.contains(second.host) ?? false)
        XCTAssertEqual(downloader.requestedURLs.first, first.checksumURL)
        XCTAssertTrue(downloader.requestedURLs.contains(second.datasetURL))
    }

    func testUpdaterPersistsMetaAcrossInstances() async throws {
        let container = try makeTemporaryDirectory()
        let downloader = makeMockDownloader(dataset: makeDataset())
        let first = makeUpdater(containerURL: container, downloader: downloader)
        await first.updateIfNeeded(vpnConnected: true)

        let reopened = makeUpdater(containerURL: container, downloader: MockDownloader())
        XCTAssertEqual(reopened.status.lastUpdatedAt, Self.fixedNow)
        XCTAssertEqual(reopened.status.dataVersion, String(GeoIPUpdater.sha256Hex(makeDataset()).prefix(12)))
        XCTAssertTrue(reopened.status.isUsingDownloadedData)
        reopened.reloadStatusFromDisk()
        XCTAssertEqual(reopened.status.lastUpdatedAt, Self.fixedNow)
    }

    func testUpdaterPrepareInstallsBundledDatasetAndBaselineMeta() async throws {
        let container = try makeTemporaryDirectory()
        let updater = makeUpdater(containerURL: container, downloader: MockDownloader())

        let prepared = await updater.prepareIfNeeded()
        XCTAssertTrue(prepared)
        let datasetURL = container.appendingPathComponent(GeoIPAssetManager.datasetFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: datasetURL.path))
        let metadata = try XCTUnwrap(GeoIPMetadataStore.bundled(.main))
        let installedMetadata = try XCTUnwrap(
            GeoIPMetadataStore.load(from: container.appendingPathComponent(GeoIPMetadataStore.fileName)))
        XCTAssertEqual(installedMetadata.sha256, metadata.sha256)

        let status = updater.status
        XCTAssertNil(status.lastUpdatedAt, "the bundled snapshot has never been refreshed")
        XCTAssertEqual(status.dataVersion, metadata.dataVersion)
        XCTAssertEqual(status.countryCount, 250)
        XCTAssertTrue(status.isUsingDownloadedData)
        XCTAssertTrue(status.isRefreshDue, "a never-refreshed snapshot is due for the 7-day refresh")
    }

    func testChecksumParser() throws {
        let checksum = String(repeating: "a", count: 64)
        XCTAssertEqual(try GeoIPUpdater.parseChecksum(Data("\(checksum)  geoip.dat\n".utf8)), checksum)
        XCTAssertThrowsError(try GeoIPUpdater.parseChecksum(Data("not-a-checksum".utf8)))
        XCTAssertThrowsError(try GeoIPUpdater.parseChecksum(Data()))
    }
}
