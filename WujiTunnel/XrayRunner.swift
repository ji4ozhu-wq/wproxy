import Foundation
import LibXray
import os.log

/// Thin Swift wrapper around the forked libXray JSON API (`apiVersion` 3).
///
/// Every call goes through `CGoInvoke`; the response string is allocated by Go and
/// must be released with `CGoFree`. Xray itself runs on a Go runtime and blocks the
/// calling thread while a configuration is parsed, so callers should use a
/// background queue (the packet tunnel provider owns `xrayQueue` for this).
enum XrayRunner {
    enum InvocationError: LocalizedError {
        case requestEncodingFailed
        case requestTooLarge(bytes: Int, limit: Int)
        case emptyResponse
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .requestEncodingFailed:
                return "Failed to encode the Xray request."
            case .requestTooLarge(let bytes, let limit):
                return "The Xray configuration is \(bytes / 1024) KB, over the \(limit / 1024) KB kernel limit."
            case .emptyResponse:
                return "The Xray kernel returned an empty response."
            case .rejected(let message):
                return message
            }
        }
    }

    struct TrafficSample {
        var uplinkBytes: Int64
        var downlinkBytes: Int64
    }

    /// libXray rejects Invoke request/response envelopes larger than 16 MiB.
    static let maxRequestBytes = 15 * 1024 * 1024

    private static let apiVersion = 3
    private static let log = Logger(subsystem: "com.juejin.ios.wuji.tunnel-ext", category: "XrayRunner")

    // MARK: - Kernel lifecycle

    /// Injects the utun fd into the config root `env` object and starts the core.
    static func run(configJSON: String, tunFileDescriptor: Int32) throws {
        guard tunFileDescriptor >= 3 else {
            throw InvocationError.rejected("The tunnel file descriptor is invalid (\(tunFileDescriptor)).")
        }
        let prepared = try injectTunFileDescriptor(into: configJSON, fd: tunFileDescriptor)
        try invokeChecked(method: "runXray", payload: ["xrayJson": prepared])
    }

    static func stop() {
        do {
            try invokeChecked(method: "stopXray", payload: nil)
        } catch {
            // If the kernel was never started, stopXray is a no-op; anything else
            // is only diagnosable while the extension is being torn down anyway.
            log.error("stopXray failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func isRunning() -> Bool {
        guard let data = try? invoke(method: "getXrayState", payload: nil),
              let running = data["running"] as? Bool else { return false }
        return running
    }

    static func version() -> String? {
        guard let data = try? invoke(method: "xrayVersion", payload: nil) else { return nil }
        return data["version"] as? String
    }

    // MARK: - Traffic statistics (libXray fork)

    /// Cumulative bytes counted by the Xray `tun-in` inbound. Requires the forked
    /// libXray method `getTrafficStats` (tools/libxray-patch/wuji-traffic-stats.patch).
    static func trafficSample(inboundTag: String = XrayConfigBuilder.tunInboundTag) throws -> TrafficSample {
        let data = try invoke(method: "getTrafficStats", payload: ["inboundTag": inboundTag])
        guard let uplink = (data["uplink"] as? NSNumber)?.int64Value,
              let downlink = (data["downlink"] as? NSNumber)?.int64Value else {
            throw InvocationError.emptyResponse
        }
        return TrafficSample(uplinkBytes: uplink, downlinkBytes: downlink)
    }

    // MARK: - Config preparation

    /// Adds (or replaces) `env["xray.tun.fd"]` in the config the app generated and
    /// returns the JSON text handed to `runXray`.
    static func injectTunFileDescriptor(into configJSON: String, fd: Int32) throws -> String {
        guard let data = configJSON.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InvocationError.rejected("The tunnel configuration is not valid JSON.")
        }
        var env = root["env"] as? [String: String] ?? [:]
        env["xray.tun.fd"] = String(fd)
        root["env"] = env
        guard let updated = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
              let text = String(data: updated, encoding: .utf8) else {
            throw InvocationError.requestEncodingFailed
        }
        return text
    }

    // MARK: - Invoke plumbing

    @discardableResult
    private static func invokeChecked(method: String, payload: [String: Any]?) throws -> [String: Any] {
        try invoke(method: method, payload: payload)
    }

    private static func invoke(method: String, payload: [String: Any]?) throws -> [String: Any] {
        var request: [String: Any] = [
            "apiVersion": apiVersion,
            "method": method
        ]
        if let payload {
            request["payload"] = payload
        }
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else {
            throw InvocationError.requestEncodingFailed
        }
        guard requestData.count <= maxRequestBytes else {
            throw InvocationError.requestTooLarge(bytes: requestData.count, limit: maxRequestBytes)
        }
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            throw InvocationError.requestEncodingFailed
        }

        let response: String? = requestText.withCString { cString in
            guard let pointer = CGoInvoke(UnsafeMutablePointer(mutating: cString)) else { return nil }
            defer { CGoFree(pointer) }
            return String(cString: pointer)
        }
        guard let response, let responseData = response.data(using: .utf8) else {
            throw InvocationError.emptyResponse
        }
        guard let envelope = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] else {
            log.error("Unreadable libXray response for \(method, privacy: .public)")
            throw InvocationError.rejected("The Xray kernel returned an unreadable response.")
        }
        let success = envelope["success"] as? Bool ?? false
        if !success {
            let message = (envelope["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "The Xray kernel rejected \(method)."
            log.error("libXray \(method, privacy: .public) failed: \(message, privacy: .public)")
            throw InvocationError.rejected(message)
        }
        return envelope["data"] as? [String: Any] ?? [:]
    }
}
