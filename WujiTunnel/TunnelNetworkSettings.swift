import Foundation
import NetworkExtension

/// Builds the `NEPacketTunnelNetworkSettings` the packet tunnel provider installs
/// before Xray takes over the utun socket.
///
/// The tun owns the default routes (0.0.0.0/0 + ::/0) so every packet of the
/// device is handed to Xray through the utun fd. The proxy server addresses are
/// always excluded to rule out a routing loop, and the LAN ranges are excluded only
/// while the "bypass LAN" setting is on (audit B1): when it is off, LAN destinations
/// enter the tunnel like any other traffic and follow the Xray routing rules.
enum TunnelNetworkSettingsFactory {
    static let ipv4Address = "198.18.0.1"
    static let ipv4SubnetMask = "255.255.0.0"
    static let ipv6Address = "fd00:1234::1"
    static let ipv6NetworkPrefixLength = 64
    static let mtu = 1380

    /// DNS endpoints advertised to the system. Both live inside the tunnel
    /// subnets; their :53 traffic is captured by the port 53 routing rule and
    /// answered by the Xray dns app (DoH through the proxy, no leak).
    static var dnsServers: [String] {
        // IPv4-only: the proxy endpoint and the tunnel routes are IPv4. Advertising
        // AAAA answers made iOS pick IPv6 first; those packets then failed (Google,
        // Baidu) while DNS itself still worked through the tunnel.
        [XrayConfigBuilder.tunnelDNSv4Address]
    }

    /// IPv4 ranges that must stay outside the tunnel regardless of the LAN setting:
    /// link-local, loopback, carrier-grade NAT, multicast and limited broadcast.
    static let alwaysExcludedIPv4Ranges: [(destination: String, mask: String)] = [
        ("169.254.0.0", "255.255.0.0"),
        ("127.0.0.0", "255.0.0.0"),
        ("100.64.0.0", "255.192.0.0"),
        ("224.0.0.0", "240.0.0.0"),
        ("255.255.255.255", "255.255.255.255")
    ]

    /// RFC1918 ranges, excluded only when the user keeps the "bypass LAN" setting on.
    static let lanIPv4Ranges: [(destination: String, mask: String)] = [
        ("10.0.0.0", "255.0.0.0"),
        ("172.16.0.0", "255.240.0.0"),
        ("192.168.0.0", "255.255.0.0")
    ]

    /// IPv6 ranges that must stay outside the tunnel regardless of the LAN setting:
    /// loopback, link-local and multicast.
    static let alwaysExcludedIPv6Ranges: [(destination: String, prefix: Int)] = [
        ("::1", 128),
        ("fe80::", 10),
        ("ff00::", 8)
    ]

    /// Unique-local IPv6 addresses are the IPv6 equivalent of RFC1918, so they follow
    /// the same "bypass LAN" switch.
    static let lanIPv6Ranges: [(destination: String, prefix: Int)] = [
        ("fc00::", 7)
    ]

    /// - Parameters:
    ///   - serverHost: the proxy server address shown in the system VPN dialog.
    ///   - excludedServerAddresses: resolved proxy server IPv4 literals. They are
    ///     excluded from the tun routes so the tunnel's own transport stays direct.
    ///   - bypassLAN: `true` keeps LAN (RFC1918 / IPv6 ULA) traffic outside the tunnel.
    static func make(serverHost: String,
                     excludedServerAddresses: [String],
                     bypassLAN: Bool) -> NEPacketTunnelNetworkSettings {
        let remoteAddress = serverHost.isEmpty ? "127.0.0.1" : serverHost
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteAddress)
        settings.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: [ipv4Address], subnetMasks: [ipv4SubnetMask])
        var ipv4Excluded = alwaysExcludedIPv4Ranges.map {
            NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
        }
        if bypassLAN {
            ipv4Excluded.append(contentsOf: lanIPv4Ranges.map {
                NEIPv4Route(destinationAddress: $0.destination, subnetMask: $0.mask)
            })
        }
        for address in excludedServerAddresses where isIPv4Literal(address) {
            ipv4Excluded.append(NEIPv4Route(destinationAddress: address, subnetMask: "255.255.255.255"))
        }
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = ipv4Excluded
        settings.ipv4Settings = ipv4

        // No IPv6 settings: see `dnsServers` above. The tunnel is IPv4-only until
        // the proxy path is verified end-to-end for IPv6.

        let dns = NEDNSSettings(servers: dnsServers)
        // Empty match domain = the default resolver for the whole system.
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        return settings
    }

    /// Resolves the proxy host to IPv4 literals so the provider can keep the
    /// proxy endpoint outside the tunnel routes. Blocks; call off the main queue.
    static func resolveIPv4Addresses(for host: String) -> [String] {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if isIPv4Literal(trimmed) { return [trimmed] }
        // A literal IPv6 server needs no IPv4 exclude route.
        if trimmed.contains(":") { return [] }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = trimmed.withCString { name in
            getaddrinfo(name, nil, &hints, &result)
        }
        guard status == 0, let first = result else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ai_next }
            guard let sockaddrPointer = current.pointee.ai_addr,
                  sockaddrPointer.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let address = UnsafeRawPointer(sockaddrPointer)
                .assumingMemoryBound(to: sockaddr_in.self)
                .pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var rawAddress = address
            guard inet_ntop(AF_INET, &rawAddress, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let text = String(cString: buffer)
            if !addresses.contains(text) { addresses.append(text) }
        }
        return addresses
    }

    static func isIPv4Literal(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }
}
