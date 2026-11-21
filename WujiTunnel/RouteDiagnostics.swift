import Darwin
import Foundation

/// DEBUG-only route/interface snapshot. The tunnel can receive DNS packets while
/// app TCP silently bypasses the utun; comparing the installed default routes
/// against the utun interface makes that visible without Console access.
private struct RTMetrics {
    var locks: UInt32 = 0
    var mtu: UInt32 = 0
    var hopcount: UInt32 = 0
    var expire: Int32 = 0
    var recvpipe: UInt32 = 0
    var sendpipe: UInt32 = 0
    var ssthresh: UInt32 = 0
    var rtt: UInt32 = 0
    var rttvar: UInt32 = 0
    var pksent: UInt32 = 0
    var filler: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
}

/// Mirrors `struct rt_msghdr` from <net/route.h>; Swift on iOS does not import it.
private struct RTMessageHeader {
    var msglen: UInt16 = 0
    var version: UInt8 = 0
    var type: UInt8 = 0
    var index: UInt16 = 0
    private var padding: UInt16 = 0
    var flags: Int32 = 0
    var addrs: Int32 = 0
    var pid: Int32 = 0
    var seq: Int32 = 0
    var err: Int32 = 0
    var use: Int32 = 0
    var inits: UInt32 = 0
    var metrics: RTMetrics = RTMetrics()
}

enum RouteDiagnostics {
    private static let rtaDst: Int32 = 0x1
    private static let rtaGateway: Int32 = 0x2
    private static let rtaNetmask: Int32 = 0x4
    private static let rtaMax = 8

    static func write(context: String) {
        #if DEBUG
        guard let directory = AppGroup.containerURL else { return }
        let text = "context=\(context) at=\(ISO8601DateFormatter().string(from: Date()))\n" + snapshot()
        try? Data(text.utf8).write(to: directory.appendingPathComponent("route_diag.txt"), options: .atomic)
        #endif
    }

    static func snapshot() -> String {
        var lines: [String] = []
        lines.append(contentsOf: interfaceLines())
        lines.append(contentsOf: routeLines())
        return lines.joined(separator: "\n")
    }

    private static func interfaceLines() -> [String] {
        var lines: [String] = ["interfaces:"]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, head != nil else {
            return lines + ["  getifaddrs failed errno=\(errno)"]
        }
        defer { freeifaddrs(head) }
        var pointer = head
        while let current = pointer {
            let name = String(cString: current.pointee.ifa_name)
            if name.hasPrefix("utun") || name == "en0" || name == "pdp_ip0" {
                guard let address = current.pointee.ifa_addr else {
                    pointer = current.pointee.ifa_next
                    continue
                }
                let family = Int32(address.pointee.sa_family)
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(address, socklen_t(address.pointee.sa_len),
                                         &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                if result == 0 {
                    lines.append("  \(name) family=\(family) addr=\(String(cString: buffer)) flags=0x\(String(current.pointee.ifa_flags, radix: 16))")
                }
            }
            pointer = current.pointee.ifa_next
        }
        return lines
    }

    private static func routeLines() -> [String] {
        var lines: [String] = ["default routes:"]
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_DUMP, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
            return lines + ["  sysctl size failed errno=\(errno)"]
        }
        var buffer = [UInt8](repeating: 0, count: length)
        let result = buffer.withUnsafeMutableBytes {
            sysctl(&mib, 6, $0.baseAddress, &length, nil, 0)
        }
        guard result == 0 else {
            return lines + ["  sysctl dump failed errno=\(errno)"]
        }
        let headerSize = MemoryLayout<RTMessageHeader>.size
        lines.append("  headerSize=\(headerSize)")
        buffer.withUnsafeBytes { raw in
            var offset = 0
            var total = 0
            var defaults = 0
            while offset + headerSize <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: RTMessageHeader.self)
                let messageLength = Int(header.msglen)
                guard messageLength > 0, offset + messageLength <= length else { break }
                total += 1
                var cursor = offset + headerSize
                let mask = header.addrs
                var destination: String?
                var gateway: String?
                var netmask: String?
                var family: Int32 = 0
                for index in 0..<rtaMax {
                    let flag = Int32(1) << Int32(index)
                    guard mask & flag != 0 else { continue }
                    let address = readSockaddr(raw, at: cursor)
                    if flag == rtaDst { destination = address.text; family = address.family }
                    if flag == rtaGateway { gateway = address.text }
                    if flag == rtaNetmask { netmask = address.text }
                    let size = address.length > 0 ? address.length : MemoryLayout<sockaddr>.size
                    cursor += (size + 3) & ~3
                }
                if let destination,
                   (destination == "0.0.0.0" || destination == "::"),
                   netmask == nil || netmask == "0.0.0.0" || netmask == "::" {
                    defaults += 1
                    lines.append("  if=\(interfaceName(index: header.index)) family=\(family) gw=\(gateway ?? "-") dst=\(destination) mask=\(netmask ?? "-") flags=0x\(String(header.flags, radix: 16))")
                }
                offset += messageLength
            }
            lines.append("  total=\(total) defaultCount=\(defaults)")
        }
        return lines
    }

    private static func readSockaddr(_ raw: UnsafeRawBufferPointer, at offset: Int) -> (length: Int, family: Int32, text: String?) {
        guard offset + 2 <= raw.count else { return (0, 0, nil) }
        let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
        let family = Int32(raw.loadUnaligned(fromByteOffset: offset + 1, as: UInt8.self))
        guard length >= 2, offset + length <= raw.count else { return (length, family, nil) }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        if family == AF_INET {
            var address = raw.loadUnaligned(fromByteOffset: offset, as: sockaddr_in.self).sin_addr
            guard inet_ntop(AF_INET, &address, &text, socklen_t(text.count)) != nil else { return (length, family, nil) }
            return (length, family, String(cString: text))
        }
        if family == AF_INET6 {
            var address = raw.loadUnaligned(fromByteOffset: offset, as: sockaddr_in6.self).sin6_addr
            guard inet_ntop(AF_INET6, &address, &text, socklen_t(text.count)) != nil else { return (length, family, nil) }
            return (length, family, String(cString: text))
        }
        return (length, family, nil)
    }

    private static func interfaceName(index: UInt16) -> String {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        if if_indextoname(UInt32(index), &buffer) != nil {
            return String(cString: buffer)
        }
        return "\(index)"
    }
}
