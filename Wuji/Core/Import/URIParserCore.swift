import Foundation

// MARK: - Errors and results

enum URIParseError: LocalizedError, Equatable {
    case unsupportedScheme
    /// A user-readable problem; the associated value is a localization key.
    case malformed(String)
    case noRecognizedLinks

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return NSLocalizedString("error.uri.unsupported", comment: "")
        case .malformed(let key):
            return NSLocalizedString(key, comment: "")
        case .noRecognizedLinks:
            return NSLocalizedString("error.uri.none", comment: "")
        }
    }
}

/// One share link that could not be imported, with the reason for the UI.
struct URIParseFailure: Equatable, Sendable {
    var line: String
    var message: String
}

/// A node that could be imported, but whose share link carries parameters the data
/// model cannot represent (Shadowsocks `plugin`, VMess/VLESS ALPN, VMess header
/// obfuscation...). The importer reports them without blocking the import.
struct URIParseWarning: Equatable, Sendable {
    var nodeID: String
    var parameters: [String]
    var message: String
}

/// Result of parsing paste/QR/subscription text: the nodes that were recognized
/// plus per-line failures so the UI can report partial imports.
struct URIParseReport: Sendable {
    var profiles: [NodeProfile]
    var failures: [URIParseFailure]
    var warnings: [URIParseWarning]

    init(profiles: [NodeProfile] = [],
         failures: [URIParseFailure] = [],
         warnings: [URIParseWarning] = []) {
        self.profiles = profiles
        self.failures = failures
        self.warnings = warnings
    }

    var isEmpty: Bool { profiles.isEmpty && failures.isEmpty }

    /// Warnings keyed by node ID so import previews can badge a single row.
    var warningsByNodeID: [String: URIParseWarning] {
        Dictionary(warnings.map { ($0.nodeID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Parser

/// Parses and encodes proxy share links (`vmess://`, `vless://`, `trojan://`,
/// `ss://`) and subscription bodies.
///
/// Owned by the data role; see docs/impl-plan.md (B5) and docs/ids-data.md for the
/// full field mapping and compatibility notes.
final class URIParserCore {
    static let shared = URIParserCore()
    private init() {}

    static let supportedSchemes: Set<String> = ["vmess", "vless", "trojan", "ss", "socks", "socks5"]

    // MARK: Public API

    /// Parses every recognized link in `text`. Throws when no link could be read.
    func parse(_ text: String, groupID: String) throws -> [NodeProfile] {
        let report = parseDetailed(text, groupID: groupID)
        guard !report.profiles.isEmpty else {
            throw URIParseError.noRecognizedLinks
        }
        return report.profiles
    }

    /// Parses `text` and keeps the failures instead of throwing them away.
    /// Lines that look like links (`...://...`) but are not supported share links
    /// are reported as failures too, so import screens can explain the rejection.
    func parseDetailed(_ text: String, groupID: String) -> URIParseReport {
        let candidates = Self.extractCandidates(from: text)
        var profiles: [NodeProfile] = []
        var failures = candidates.rejected
        var warnings: [URIParseWarning] = []
        for link in candidates.links {
            do {
                let profile = try parseLink(link, groupID: groupID)
                profiles.append(profile)
                let parameters = unsupportedParameters(in: link)
                if !parameters.isEmpty {
                    warnings.append(URIParseWarning(nodeID: profile.id,
                                                    parameters: parameters,
                                                    message: Self.unsupportedParametersMessage(parameters)))
                }
            } catch {
                failures.append(URIParseFailure(line: link, message: error.localizedDescription))
            }
        }
        return URIParseReport(profiles: profiles, failures: failures, warnings: warnings)
    }

    /// Parses exactly one share link.
    func parseLink(_ link: String, groupID: String) throws -> NodeProfile {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "://") else {
            throw URIParseError.malformed("error.uri.malformed.notLink")
        }
        let scheme = trimmed[..<separator.lowerBound].lowercased()
        switch scheme {
        case "vmess":
            return try parseVMess(trimmed, groupID: groupID)
        case "vless":
            return try parseVLESS(trimmed, groupID: groupID)
        case "trojan":
            return try parseTrojan(trimmed, groupID: groupID)
        case "ss":
            return try parseShadowsocks(trimmed, groupID: groupID)
        case "socks", "socks5":
            return try parseSOCKS(trimmed, groupID: groupID)
        default:
            throw URIParseError.unsupportedScheme
        }
    }

    /// `true` when the first token of `text` is a supported share link.
    func isSupportedLink(_ text: String) -> Bool {
        guard let first = Self.extractLinks(from: text).first else { return false }
        return (try? parseLink(first, groupID: ProfileStore.manualGroupID)) != nil
    }

    /// Encodes a node back into a share link for copy/share/QR.
    ///
    /// The original imported link is preserved when it still matches the node, so
    /// unknown fields (ALPN, SS plugins, padding style) survive a round trip.
    func encode(_ profile: NodeProfile) -> String {
        // SOCKS5 always re-encodes to the canonical share form so a plaintext
        // userinfo link becomes `socks://base64(user:pass)@host:port`.
        if profile.proto == .socks {
            return encodeSOCKS(profile)
        }
        if !profile.rawURI.isEmpty,
           let parsed = try? parseLink(profile.rawURI, groupID: profile.groupID),
           Self.matches(parsed, profile) {
            return profile.rawURI
        }
        switch profile.proto {
        case .vmess: return encodeVMess(profile)
        case .vless: return encodeVLESS(profile)
        case .trojan: return encodeTrojan(profile)
        case .shadowsocks: return encodeShadowsocks(profile)
        case .socks: return encodeSOCKS(profile)
        }
    }

    /// Extracts the share links from a subscription body. Handles plain text and
    /// base64 (standard or URL-safe, padded or not).
    func parseSubscriptionBody(_ body: String) -> [String] {
        Self.extractLinks(from: body)
    }

    // MARK: - Unsupported parameters

    /// Names of the parameters in `link` that the data model cannot represent.
    /// The importer imports the node anyway and reports them as warnings (see
    /// `parseDetailed`); an empty array means the link maps cleanly.
    func unsupportedParameters(in link: String) -> [String] {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.range(of: "://") else { return [] }
        switch trimmed[..<separator.lowerBound].lowercased() {
        case "vmess": return Self.unsupportedVMessParameters(trimmed)
        case "vless", "trojan": return Self.unsupportedQueryParameters(trimmed)
        case "ss": return Self.unsupportedShadowsocksParameters(trimmed)
        case "socks", "socks5": return Self.unsupportedSOCKS5Parameters(trimmed)
        default: return []
        }
    }

    /// `true` when the two profiles point at the same connection: same protocol,
    /// same server/port and the same credential (UUID for VMess/VLESS, password for
    /// Trojan/Shadowsocks). Used by paste/QR imports to skip duplicates.
    static func isDuplicate(_ lhs: NodeProfile, of rhs: NodeProfile) -> Bool {
        guard lhs.proto == rhs.proto,
              lhs.server.caseInsensitiveCompare(rhs.server) == .orderedSame,
              lhs.port == rhs.port else { return false }
        switch lhs.proto {
        case .vmess, .vless:
            return !lhs.uuid.isEmpty && lhs.uuid.caseInsensitiveCompare(rhs.uuid) == .orderedSame
        case .trojan:
            return !lhs.password.isEmpty && lhs.password == rhs.password
        case .shadowsocks:
            return !lhs.password.isEmpty
                && lhs.password == rhs.password
                && lhs.ssMethod.caseInsensitiveCompare(rhs.ssMethod) == .orderedSame
        case .socks:
            // Unauthenticated SOCKS5 nodes are valid, so the credential pair may be
            // empty on both sides: only equality matters.
            return lhs.socksUsername.caseInsensitiveCompare(rhs.socksUsername) == .orderedSame
                && lhs.password == rhs.password
        }
    }

    private static func unsupportedParametersMessage(_ parameters: [String]) -> String {
        String(format: NSLocalizedString("error.uri.unsupportedParams", comment: ""),
               parameters.joined(separator: ", "))
    }

    private static func unsupportedVMessParameters(_ link: String) -> [String] {
        var payload = String(link.dropFirst("vmess://".count))
        if let hash = payload.firstIndex(of: "#") {
            payload = String(payload[..<hash])
        }
        guard let object = try? URIParserCore.shared.decodeVMessJSON(payload) else { return [] }
        var parameters: [String] = []
        if !stringValue(object["alpn"]).trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append("alpn")
        }
        let headerType = stringValue(object["type"]).trimmingCharacters(in: .whitespaces).lowercased()
        if !headerType.isEmpty && headerType != "none" {
            parameters.append("type")
        }
        return parameters
    }

    private static func unsupportedQueryParameters(_ link: String) -> [String] {
        guard let parsed = try? URIParserCore.shared.splitURI(link) else { return [] }
        var parameters: [String] = []
        if !(parsed.query["alpn"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append("alpn")
        }
        if !(parsed.query["headertype"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append("headerType")
        }
        return parameters
    }

    private static func unsupportedShadowsocksParameters(_ link: String) -> [String] {
        var rest = String(link.dropFirst("ss://".count))
        if let hash = rest.firstIndex(of: "#") {
            rest = String(rest[..<hash])
        }
        guard let question = rest.firstIndex(of: "?") else { return [] }
        let query = Self.parseQuery(String(rest[rest.index(after: question)...]))
        var parameters: [String] = []
        if !(query["plugin"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append("plugin")
        }
        if !(query["uot"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            parameters.append("uot")
        }
        return parameters
    }

    private static func unsupportedSOCKS5Parameters(_ link: String) -> [String] {
        // No SOCKS5 URI query parameter is represented in the data model.
        guard let question = link.firstIndex(of: "?") else { return [] }
        var raw = String(link[link.index(after: question)...])
        if let hash = raw.firstIndex(of: "#") {
            raw = String(raw[..<hash])
        }
        return Self.parseQuery(raw).keys.sorted()
    }

    // MARK: - Link extraction

    /// Turns arbitrary paste/QR/subscription text into share links: decodes a
    /// base64 body when necessary, then scans line by line for supported schemes.
    static func extractLinks(from text: String) -> [String] {
        extractCandidates(from: text).links
    }

    private static func extractCandidates(from text: String) -> (links: [String], rejected: [URIParseFailure]) {
        var body = text
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if let decoded = decodeBase64Body(body) {
            body = decoded
        }
        var links: [String] = []
        var rejected: [URIParseFailure] = []
        for rawLine in body.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let ranges = schemeRanges(in: line)
            if ranges.isEmpty {
                if line.contains("://") {
                    rejected.append(URIParseFailure(
                        line: line,
                        message: NSLocalizedString("error.uri.unsupported", comment: "")
                    ))
                }
                continue
            }
            if ranges.count == 1 {
                links.append(String(line[ranges[0].lowerBound...]).trimmingCharacters(in: .whitespaces))
                continue
            }
            for (index, range) in ranges.enumerated() {
                let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : line.endIndex
                let piece = line[range.lowerBound..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { links.append(piece) }
            }
        }
        return (links, rejected)
    }

    /// Decodes a whole subscription body that is base64 encoded, e.g. the common
    /// `base64(vmess://...\nvless://...)` format used by most panels.
    private static func decodeBase64Body(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains("://") else { return nil }
        let compact = trimmed.components(separatedBy: .whitespacesAndNewlines).joined()
        guard compact.count >= 8 else { return nil }
        if let text = decodedUTF8(base64Data(compact)), text.contains("://") {
            return text
        }
        // Some panels base64-encode the body twice.
        if let first = decodedUTF8(base64Data(compact)), let second = decodedUTF8(base64Data(
            first.components(separatedBy: .whitespacesAndNewlines).joined()
        )), second.contains("://") {
            return second
        }
        return nil
    }

    /// Returns the ranges of the supported `scheme://` tokens that start a token
    /// (so `ss://` inside `vless://` is ignored). `socks5://` and `socks://` are
    /// distinct prefixes, so both are matched.
    private static func schemeRanges(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for scheme in ["vmess", "vless", "trojan", "ss", "socks5", "socks"] {
            var searchStart = line.startIndex
            while searchStart < line.endIndex,
                  let range = line.range(of: "\(scheme)://", options: .caseInsensitive,
                                         range: searchStart..<line.endIndex) {
                if isTokenBoundary(line, at: range.lowerBound) {
                    ranges.append(range)
                }
                searchStart = range.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func isTokenBoundary(_ line: String, at index: String.Index) -> Bool {
        guard index > line.startIndex else { return true }
        let previous = line[line.index(before: index)]
        return previous.isWhitespace || ",;|'\"([{<".contains(previous)
    }

    // MARK: - Base64

    /// Lenient base64 decoding: URL-safe alphabet and missing padding are accepted.
    static func base64Data(_ raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        text = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .components(separatedBy: .whitespacesAndNewlines).joined()
        while text.hasSuffix("=") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        let remainder = text.count % 4
        if remainder != 0 { text += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: text, options: .ignoreUnknownCharacters)
    }

    private static func decodedUTF8(_ data: Data?) -> String? {
        guard let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func base64URLString(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Generic URI splitting

    private struct ParsedURI {
        var userinfo: String = ""
        var host: String = ""
        var port: Int?
        var query: [String: String] = [:]
        var fragment: String = ""
    }

    private func splitURI(_ link: String) throws -> ParsedURI {
        guard let schemeRange = link.range(of: "://") else {
            throw URIParseError.malformed("error.uri.malformed.noScheme")
        }
        var rest = String(link[schemeRange.upperBound...])
        var parsed = ParsedURI()

        if let hash = rest.firstIndex(of: "#") {
            parsed.fragment = Self.percentDecoded(String(rest[rest.index(after: hash)...]))
            rest = String(rest[..<hash])
        }
        if let question = rest.firstIndex(of: "?") {
            parsed.query = Self.parseQuery(String(rest[rest.index(after: question)...]))
            rest = String(rest[..<question])
        }
        if let at = rest.lastIndex(of: "@") {
            parsed.userinfo = Self.percentDecoded(String(rest[..<at]))
            rest = String(rest[rest.index(after: at)...])
        }
        if rest.hasSuffix("/") { rest.removeLast() }
        (parsed.host, parsed.port) = try Self.hostAndPort(from: rest)
        return parsed
    }

    private static func hostAndPort(from authority: String) throws -> (String, Int?) {
        var host = ""
        var portText: String?
        if authority.hasPrefix("["), let closing = authority.firstIndex(of: "]") {
            host = String(authority[authority.index(after: authority.startIndex)..<closing])
            let suffix = authority[authority.index(after: closing)...]
            if suffix.hasPrefix(":") { portText = String(suffix.dropFirst()) }
        } else if let colon = authority.lastIndex(of: ":") {
            let candidate = String(authority[authority.index(after: colon)...])
            if Int(candidate) != nil {
                host = String(authority[..<colon])
                portText = candidate
            } else {
                host = authority
            }
        } else {
            host = authority
        }
        host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.noServer")
        }
        if let portText {
            guard let port = Int(portText), (1...65535).contains(port) else {
                throw URIParseError.malformed("error.uri.malformed.badPort")
            }
            return (host, port)
        }
        return (host, nil)
    }

    private func requireHostAndPort(_ parsed: ParsedURI) throws -> (String, Int) {
        guard !parsed.host.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.noServer")
        }
        guard let port = parsed.port, (1...65535).contains(port) else {
            throw URIParseError.malformed("error.uri.malformed.badPort")
        }
        return (parsed.host, port)
    }

    private static func parseQuery(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
            let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let keyPiece = pieces.first else { continue }
            let key = percentDecoded(String(keyPiece)).lowercased()
            guard !key.isEmpty else { continue }
            let value = pieces.count > 1 ? percentDecoded(String(pieces[1])) : ""
            result[key] = value
        }
        return result
    }

    private static func percentDecoded(_ raw: String) -> String {
        raw.removingPercentEncoding ?? raw
    }

    // MARK: - VMess

    private func parseVMess(_ link: String, groupID: String) throws -> NodeProfile {
        var payload = String(link.dropFirst("vmess://".count))
        var fragment = ""
        if let hash = payload.firstIndex(of: "#") {
            fragment = Self.percentDecoded(String(payload[payload.index(after: hash)...]))
            payload = String(payload[..<hash])
        }
        guard let json = try decodeVMessJSON(payload) else {
            throw URIParseError.malformed("error.uri.malformed.vmessJSON")
        }

        let server = Self.firstNonEmpty([
            Self.stringValue(json["add"]), Self.stringValue(json["address"]), Self.stringValue(json["server"])
        ]).trimmingCharacters(in: .whitespaces)
        guard !server.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.vmessServer")
        }
        let port = Self.intValue(json["port"], default: 0)
        guard (1...65535).contains(port) else {
            throw URIParseError.malformed("error.uri.malformed.vmessPort")
        }
        let uuid = Self.firstNonEmpty([Self.stringValue(json["id"]), Self.stringValue(json["uuid"])])
        guard !uuid.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.vmessUUID")
        }

        let network = Self.transport(from: Self.stringValue(json["net"]))
        let security = Self.securityLayer(from: Self.firstNonEmpty([
            Self.stringValue(json["tls"]), Self.stringValue(json["security"])
        ]))
        let host = Self.stringValue(json["host"])
        let path = Self.stringValue(json["path"])
        let securityCipher = Self.firstNonEmpty([
            Self.stringValue(json["scy"]), Self.stringValue(json["security"])
        ])

        var profile = NodeProfile(
            id: UUID().uuidString,
            groupID: groupID,
            name: Self.displayName(fragment: fragment, vmessName: Self.stringValue(json["ps"]), server: server, port: port),
            proto: .vmess,
            server: server,
            port: port
        )
        profile.uuid = uuid
        profile.vmessSecurity = securityCipher.isEmpty ? "auto" : securityCipher.lowercased()
        profile.alterID = Self.intValue(json["aid"], default: Self.intValue(json["alterId"], default: 0))
        profile.network = network
        profile.security = security
        profile.sni = Self.firstNonEmpty([Self.stringValue(json["sni"]), Self.stringValue(json["serverName"])])
        profile.wsHost = host
        profile.wsPath = network == .grpc ? "" : path
        profile.grpcService = network == .grpc ? Self.firstNonEmpty([path, Self.stringValue(json["serviceName"])]) : ""
        profile.fingerprint = Self.stringValue(json["fp"])
        profile.allowInsecure = Self.boolValue(json["allowInsecure"]) || Self.boolValue(json["insecure"])
        profile.rawURI = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    private func decodeVMessJSON(_ payload: String) throws -> [String: Any]? {
        var text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("{"), let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        if text.contains("%") {
            text = text.removingPercentEncoding ?? text
        }
        guard let data = Self.base64Data(text),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func encodeVMess(_ profile: NodeProfile) -> String {
        var json: [String: Any] = [
            "v": "2",
            "ps": profile.displayName,
            "add": profile.server,
            "port": String(profile.port),
            "id": profile.uuid,
            "aid": String(profile.alterID),
            "scy": profile.vmessSecurity.isEmpty ? "auto" : profile.vmessSecurity,
            "net": Self.networkName(profile.network),
            "type": "none",
            "host": profile.wsHost,
            "path": Self.transportPath(profile),
            "tls": Self.tlsName(profile.security),
            "sni": profile.sni,
            "alpn": "",
            "fp": profile.fingerprint
        ]
        if profile.allowInsecure { json["allowInsecure"] = true }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
            return ""
        }
        return "vmess://" + data.base64EncodedString()
    }

    // MARK: - VLESS

    private func parseVLESS(_ link: String, groupID: String) throws -> NodeProfile {
        let parsed = try splitURI(link)
        let (server, port) = try requireHostAndPort(parsed)
        let uuid = parsed.userinfo.trimmingCharacters(in: .whitespaces)
        guard !uuid.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.vlessUUID")
        }
        guard UUID(uuidString: uuid) != nil else {
            throw URIParseError.malformed("error.uri.malformed.vlessUUIDInvalid")
        }
        let query = parsed.query
        let network = Self.transport(from: query["type"] ?? "")
        let security = Self.securityLayer(from: query["security"] ?? "")

        var profile = NodeProfile(
            id: UUID().uuidString,
            groupID: groupID,
            name: Self.displayName(fragment: parsed.fragment, server: server, port: port),
            proto: .vless,
            server: server,
            port: port
        )
        profile.uuid = uuid.lowercased()
        profile.flow = query["flow"] ?? ""
        profile.network = network
        profile.security = security
        profile.sni = Self.firstNonEmpty([query["sni"] ?? "", query["peer"] ?? ""])
        profile.fingerprint = query["fp"] ?? ""
        profile.wsPath = network == .grpc ? "" : (query["path"] ?? "")
        profile.wsHost = query["host"] ?? ""
        profile.grpcService = network == .grpc ? Self.firstNonEmpty([query["servicename"] ?? "", query["path"] ?? ""]) : ""
        profile.realityPublicKey = query["pbk"] ?? ""
        profile.realityShortID = query["sid"] ?? ""
        profile.allowInsecure = Self.boolValue(query["allowinsecure"]) || Self.boolValue(query["insecure"])
        profile.rawURI = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    private func encodeVLESS(_ profile: NodeProfile) -> String {
        var query: [(String, String)] = [("encryption", "none"), ("type", Self.networkName(profile.network))]
        if profile.security != .none { query.append(("security", Self.securityName(profile.security))) }
        if !profile.sni.isEmpty { query.append(("sni", profile.sni)) }
        if !profile.fingerprint.isEmpty { query.append(("fp", profile.fingerprint)) }
        if !profile.flow.isEmpty { query.append(("flow", profile.flow)) }
        switch profile.network {
        case .grpc:
            if !profile.grpcService.isEmpty { query.append(("serviceName", profile.grpcService)) }
        default:
            if !profile.wsPath.isEmpty { query.append(("path", profile.wsPath)) }
            if !profile.wsHost.isEmpty { query.append(("host", profile.wsHost)) }
        }
        if profile.security == .reality {
            if !profile.realityPublicKey.isEmpty { query.append(("pbk", profile.realityPublicKey)) }
            if !profile.realityShortID.isEmpty { query.append(("sid", profile.realityShortID)) }
        }
        if profile.allowInsecure { query.append(("allowInsecure", "1")) }
        let queryString = query
            .map { "\($0.0)=\(Self.queryEncoded($0.1))" }
            .joined(separator: "&")
        return "vless://\(Self.hostEncoded(profile.uuid))@\(Self.hostEncoded(profile.server)):\(profile.port)?\(queryString)#\(Self.fragmentEncoded(profile.displayName))"
    }

    // MARK: - Trojan

    private func parseTrojan(_ link: String, groupID: String) throws -> NodeProfile {
        let parsed = try splitURI(link)
        let (server, port) = try requireHostAndPort(parsed)
        let password = parsed.userinfo.trimmingCharacters(in: .whitespaces)
        guard !password.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.trojanPassword")
        }
        let query = parsed.query
        let network = Self.transport(from: query["type"] ?? "")
        let security = query["security"].map(Self.securityLayer(from:)) ?? .tls

        var profile = NodeProfile(
            id: UUID().uuidString,
            groupID: groupID,
            name: Self.displayName(fragment: parsed.fragment, server: server, port: port),
            proto: .trojan,
            server: server,
            port: port
        )
        profile.password = password
        profile.network = network
        profile.security = security
        profile.sni = Self.firstNonEmpty([query["sni"] ?? "", query["peer"] ?? ""])
        profile.fingerprint = query["fp"] ?? ""
        profile.wsPath = network == .grpc ? "" : (query["path"] ?? "")
        profile.wsHost = query["host"] ?? ""
        profile.grpcService = network == .grpc ? Self.firstNonEmpty([query["servicename"] ?? "", query["path"] ?? ""]) : ""
        profile.allowInsecure = Self.boolValue(query["allowinsecure"]) || Self.boolValue(query["insecure"])
        profile.rawURI = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    private func encodeTrojan(_ profile: NodeProfile) -> String {
        var query: [(String, String)] = [
            ("security", Self.securityName(profile.security)),
            ("type", Self.networkName(profile.network))
        ]
        if !profile.sni.isEmpty { query.append(("sni", profile.sni)) }
        if !profile.fingerprint.isEmpty { query.append(("fp", profile.fingerprint)) }
        switch profile.network {
        case .grpc:
            if !profile.grpcService.isEmpty { query.append(("serviceName", profile.grpcService)) }
        default:
            if !profile.wsPath.isEmpty { query.append(("path", profile.wsPath)) }
            if !profile.wsHost.isEmpty { query.append(("host", profile.wsHost)) }
        }
        if profile.allowInsecure { query.append(("allowInsecure", "1")) }
        let queryString = query
            .map { "\($0.0)=\(Self.queryEncoded($0.1))" }
            .joined(separator: "&")
        return "trojan://\(Self.queryEncoded(profile.password))@\(Self.hostEncoded(profile.server)):\(profile.port)?\(queryString)#\(Self.fragmentEncoded(profile.displayName))"
    }

    // MARK: - Shadowsocks

    private func parseShadowsocks(_ link: String, groupID: String) throws -> NodeProfile {
        var rest = String(link.dropFirst("ss://".count))
        var fragment = ""
        if let hash = rest.firstIndex(of: "#") {
            fragment = Self.percentDecoded(String(rest[rest.index(after: hash)...]))
            rest = String(rest[..<hash])
        }
        var query: [String: String] = [:]
        if let question = rest.firstIndex(of: "?") {
            query = Self.parseQuery(String(rest[rest.index(after: question)...]))
            rest = String(rest[..<question])
        }
        if rest.hasSuffix("/") { rest.removeLast() }

        var userinfo = ""
        var authority = rest
        if let at = rest.lastIndex(of: "@") {
            userinfo = Self.percentDecoded(String(rest[..<at]))
            authority = String(rest[rest.index(after: at)...])
        } else {
            // Legacy format: ss://base64(method:password@host:port)
            guard let decoded = Self.decodedUTF8(Self.base64Data(rest)),
                  let decodedAt = decoded.lastIndex(of: "@") else {
                throw URIParseError.malformed("error.uri.malformed.ssFormat")
            }
            let credentials = String(decoded[..<decodedAt]).trimmingCharacters(in: .whitespacesAndNewlines)
            userinfo = credentials
            authority = String(decoded[decoded.index(after: decodedAt)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var method = ""
        var password = ""
        if userinfo.contains(":") {
            let pieces = userinfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            method = String(pieces[0])
            password = pieces.count > 1 ? String(pieces[1]) : ""
        } else if let decoded = Self.decodedUTF8(Self.base64Data(userinfo)),
                  let colon = decoded.firstIndex(of: ":") {
            method = String(decoded[..<colon])
            password = String(decoded[decoded.index(after: colon)...])
        } else {
            throw URIParseError.malformed("error.uri.malformed.ssMethod")
        }
        method = method.trimmingCharacters(in: .whitespaces).lowercased()
        guard !method.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.ssMethod")
        }
        guard !password.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.ssPassword")
        }

        let parsed = try splitAuthority("ss://" + authority)
        let (server, port) = try requireHostAndPort(parsed)

        // `plugin=` and other SS extension parameters have no column in the data
        // model; they are intentionally ignored by the importer.
        _ = query["plugin"]

        var profile = NodeProfile(
            id: UUID().uuidString,
            groupID: groupID,
            name: Self.displayName(fragment: fragment, server: server, port: port),
            proto: .shadowsocks,
            server: server,
            port: port
        )
        profile.ssMethod = method
        profile.password = password
        profile.rawURI = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    private func splitAuthority(_ link: String) throws -> ParsedURI {
        try splitURI(link)
    }

    private func encodeShadowsocks(_ profile: NodeProfile) -> String {
        let method = profile.ssMethod.isEmpty ? "aes-256-gcm" : profile.ssMethod
        let userinfo = Self.base64URLString("\(method):\(profile.password)")
        return "ss://\(userinfo)@\(Self.hostEncoded(profile.server)):\(profile.port)#\(Self.fragmentEncoded(profile.displayName))"
    }

    // MARK: - SOCKS5

    /// Parses `socks://` and `socks5://` links:
    /// - `socks://base64(user:pass)@host:port#name` (SIP002-style base64 userinfo)
    /// - `socks://user:pass@host:port#name` (plain userinfo)
    /// - `socks://host:port#name` (no authentication)
    ///
    /// The username lives in `NodeProfile.socksUsername`; the password reuses the
    /// shared `password` column, matching the Xray socks outbound contract.
    private func parseSOCKS(_ link: String, groupID: String) throws -> NodeProfile {
        let parsed = try splitURI(link)
        let (server, port) = try requireHostAndPort(parsed)
        let credentials = try Self.socksCredentials(fromUserInfo: parsed.userinfo)

        var profile = NodeProfile(
            id: UUID().uuidString,
            groupID: groupID,
            name: Self.displayName(fragment: parsed.fragment, server: server, port: port),
            proto: .socks,
            server: server,
            port: port
        )
        profile.socksUsername = credentials.username
        profile.password = credentials.password
        profile.rawURI = link.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    /// Username and password are either both present or both empty; Xray rejects a
    /// socks server entry with only one of them set.
    private static func socksCredentials(fromUserInfo raw: String) throws -> (username: String, password: String) {
        let userinfo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userinfo.isEmpty else { return ("", "") }

        if userinfo.contains(":") {
            let pieces = userinfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let username = String(pieces[0]).trimmingCharacters(in: .whitespaces)
            let password = pieces.count > 1 ? String(pieces[1]) : ""
            guard !username.isEmpty, !password.isEmpty else {
                throw URIParseError.malformed("error.uri.malformed.socksCredentials")
            }
            return (username, password)
        }

        guard let decoded = decodedUTF8(base64Data(userinfo)),
              let colon = decoded.firstIndex(of: ":") else {
            throw URIParseError.malformed("error.uri.malformed.socksFormat")
        }
        let username = String(decoded[..<colon]).trimmingCharacters(in: .whitespaces)
        let password = String(decoded[decoded.index(after: colon)...])
        guard !username.isEmpty, !password.isEmpty else {
            throw URIParseError.malformed("error.uri.malformed.socksCredentials")
        }
        return (username, password)
    }

    /// Canonical share form: `socks://[base64(user:pass)@]host:port#name`.
    private func encodeSOCKS(_ profile: NodeProfile) -> String {
        let username = profile.socksUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = Self.hostEncoded(profile.server)
        let fragment = Self.fragmentEncoded(profile.displayName)
        guard !username.isEmpty else {
            return "socks://\(host):\(profile.port)#\(fragment)"
        }
        let userinfo = Self.base64URLString("\(username):\(profile.password)")
        return "socks://\(userinfo)@\(host):\(profile.port)#\(fragment)"
    }

    // MARK: - Field helpers

    private static func matches(_ lhs: NodeProfile, _ rhs: NodeProfile) -> Bool {
        lhs.proto == rhs.proto
            && lhs.server.caseInsensitiveCompare(rhs.server) == .orderedSame
            && lhs.port == rhs.port
            && lhs.name == rhs.name
            && lhs.uuid.caseInsensitiveCompare(rhs.uuid) == .orderedSame
            && lhs.password == rhs.password
            && lhs.ssMethod.caseInsensitiveCompare(rhs.ssMethod) == .orderedSame
            && lhs.vmessSecurity.caseInsensitiveCompare(rhs.vmessSecurity) == .orderedSame
            && lhs.alterID == rhs.alterID
            && lhs.network == rhs.network
            && lhs.security == rhs.security
            && lhs.sni.caseInsensitiveCompare(rhs.sni) == .orderedSame
            && lhs.wsPath == rhs.wsPath
            && lhs.wsHost.caseInsensitiveCompare(rhs.wsHost) == .orderedSame
            && lhs.grpcService == rhs.grpcService
            && lhs.fingerprint.caseInsensitiveCompare(rhs.fingerprint) == .orderedSame
            && lhs.realityPublicKey == rhs.realityPublicKey
            && lhs.realityShortID.caseInsensitiveCompare(rhs.realityShortID) == .orderedSame
            && lhs.flow.caseInsensitiveCompare(rhs.flow) == .orderedSame
            && lhs.socksUsername.caseInsensitiveCompare(rhs.socksUsername) == .orderedSame
            && lhs.allowInsecure == rhs.allowInsecure
    }

    private static func displayName(fragment: String, vmessName: String = "", server: String, port: Int) -> String {
        let candidates = [fragment, vmessName]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "\(server):\(port)"
    }

    private static func transport(from raw: String) -> Transport {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "ws", "websocket": return .ws
        case "grpc", "gun": return .grpc
        case "h2", "http2": return .h2
        case "http": return .http
        default: return .tcp
        }
    }

    private static func securityLayer(from raw: String) -> SecurityLayer {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "tls", "xtls": return .tls
        case "reality": return .reality
        default: return .none
        }
    }

    private static func networkName(_ network: Transport) -> String {
        switch network {
        case .tcp: return "tcp"
        case .ws: return "ws"
        case .grpc: return "grpc"
        case .h2: return "h2"
        case .http: return "http"
        }
    }

    private static func securityName(_ security: SecurityLayer) -> String {
        switch security {
        case .none: return "none"
        case .tls: return "tls"
        case .reality: return "reality"
        }
    }

    private static func tlsName(_ security: SecurityLayer) -> String {
        switch security {
        case .none: return ""
        case .tls: return "tls"
        case .reality: return "reality"
        }
    }

    private static func transportPath(_ profile: NodeProfile) -> String {
        if profile.network == .grpc {
            return profile.grpcService.isEmpty ? profile.wsPath : profile.grpcService
        }
        return profile.wsPath
    }

    private static func hostEncoded(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":"), !trimmed.hasPrefix("[") { return "[\(trimmed)]" }
        return trimmed
    }

    private static func queryEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#;?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func fragmentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func stringValue(_ any: Any?) -> String {
        switch any {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return ""
        }
    }

    private static func intValue(_ any: Any?, default fallback: Int) -> Int {
        switch any {
        case let value as NSNumber: return value.intValue
        case let value as String: return Int(value.trimmingCharacters(in: .whitespaces)) ?? fallback
        default: return fallback
        }
    }

    private static func boolValue(_ any: Any?) -> Bool {
        switch any {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
        default: return false
        }
    }

    private static func firstNonEmpty(_ candidates: [String]) -> String {
        for candidate in candidates where !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
            return candidate
        }
        return ""
    }
}
