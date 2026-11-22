import Darwin
import Foundation
import os.log

/// Locates the utun file descriptor owned by the Network Extension process.
///
/// The packet tunnel provider never receives the utun fd directly, but the
/// system creates the utun kernel-control socket inside our process when
/// `setTunnelNetworkSettings` completes. We find it with plain POSIX calls:
///
///  1. walk the process file descriptor table,
///  2. keep fds whose peer address family is `AF_SYSTEM` (32) — a kernel control socket,
///  3. ask the UTUN kernel control (`com.apple.net.utun_control`) for its control id
///     with `ioctl(CTLIOCGINFO)` and compare it with the socket's peer `sc_id`,
///  4. optionally narrow to the fd whose interface (via `UTUN_OPT_IFNAME`) owns the
///     tunnel address configured by the provider.
///
/// No KVC, no private APIs: only `getpeername`, `ioctl`, `getsockopt` and
/// `getifaddrs`, all of which are part of the public POSIX/Darwin surface.
enum TunFdResolver {
    /// AF_SYSTEM / AF_SYS_CONTROL / SYSPROTO_CONTROL / UTUN_OPT_IFNAME from <sys/socket.h>
    /// and <sys/kern_control.h>; that header is not exposed to Swift, so the stable
    /// ABI values are declared here.
    private static let afSystem: sa_family_t = 32
    private static let sysprotoControl: Int32 = 2
    private static let utunOptIfname: Int32 = 2
    /// _IOWR('N', 3, struct ctl_info): 4-byte id + 96-byte name.
    private static let ctlIOCGInfo: UInt = 0xC064_4E03
    private static let ctlInfoSize = 4 + 96
    private static let utunControlName = "com.apple.net.utun_control"
    private static let maximumFD: Int32 = 1024

    private static let log = Logger(subsystem: "com.juejin.ios.wuji.tunnel-ext", category: "TunFdResolver")

    struct TunDescriptor: Equatable {
        let fd: Int32
        let unit: UInt32
        let interfaceName: String?
    }

    /// Returns the utun fd, preferring the descriptor whose interface holds
    /// `expectedInterfaceAddress` (the tunnel IPv4 address the provider configured).
    static func utunFileDescriptor(expectedInterfaceAddress: String? = nil) -> Int32? {
        let descriptors = utunDescriptors()
        if descriptors.isEmpty {
            // Some NetworkExtension builds (notably macOS app extensions) don't
            // expose the utun kernel-control peer through `getpeername`, so the
            // sysaddr/sc_id probe above finds nothing. Fall back to identifying
            // the socket by its UTUN_OPT_IFNAME and matching the interface that
            // owns the tunnel address the provider just configured.
            if let fallback = utunFileDescriptorByInterfaceName(expectedInterfaceAddress: expectedInterfaceAddress) {
                log.info("Resolved utun fd \(fallback) via interface-name fallback")
                return fallback
            }
            log.error("No utun kernel-control socket found in this process")
            return nil
        }
        if let address = expectedInterfaceAddress,
           let interfaceName = interfaceName(owningAddress: address),
           let match = descriptors.first(where: { $0.interfaceName == interfaceName }) {
            log.info("Resolved utun fd \(match.fd) for interface \(interfaceName, privacy: .public)")
            return match.fd
        }
        // The provider process owns a single tunnel; if several sockets exist
        // (re-created tunnel), the newest one has the highest unit number.
        let newest = descriptors.max(by: { $0.unit < $1.unit })
        if descriptors.count > 1 {
            log.warning("Multiple utun sockets found (\(descriptors.count, privacy: .public)); using the highest unit")
        }
        if let newest {
            log.info("Resolved utun fd \(newest.fd) (unit \(newest.unit, privacy: .public))")
        }
        return newest?.fd
    }

    /// All utun kernel-control sockets of the current process, ordered by fd.
    static func utunDescriptors() -> [TunDescriptor] {
        guard let controlID = utunControlID() else { return [] }
        var result: [TunDescriptor] = []
        for fd in Int32(0)...maximumFD {
            guard peerControlID(of: fd) == controlID else { continue }
            let unit = peerControlUnit(of: fd) ?? 0
            result.append(TunDescriptor(fd: fd, unit: unit, interfaceName: socketInterfaceName(fd: fd)))
        }
        return result
    }

    /// Fallback resolver: walks the fd table and asks the kernel control for the
    /// `UTUN_OPT_IFNAME` of every socket, keeping the ones whose interface is a
    /// `utun*` device. Prefers the interface that owns `expectedInterfaceAddress`,
    /// otherwise the highest fd (the newest tunnel).
    private static func utunFileDescriptorByInterfaceName(expectedInterfaceAddress: String?) -> Int32? {
        let expectedInterface = expectedInterfaceAddress.flatMap(interfaceName(owningAddress:))
        var candidates: [(fd: Int32, name: String)] = []
        for fd in Int32(3)...maximumFD {
            guard let name = socketInterfaceName(fd: fd), name.hasPrefix("utun") else { continue }
            candidates.append((fd, name))
            if let expectedInterface, name == expectedInterface {
                return fd
            }
        }
        return candidates.max(by: { $0.fd < $1.fd })?.fd
    }

    // MARK: - Kernel control helpers

    /// Control id of `com.apple.net.utun_control`, resolved once per call from a
    /// throwaway AF_SYSTEM socket. Returns nil when the platform has no utun
    /// control (e.g. the iOS simulator).
    private static func utunControlID() -> UInt32? {
        let fd = socket(Int32(afSystem), SOCK_DGRAM, sysprotoControl)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return controlID(for: fd)
    }

    private static func controlID(for fd: Int32) -> UInt32? {
        var buffer = ctlInfoBuffer()
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return ioctl(fd, ctlIOCGInfo, base)
        }
        guard result == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        }
    }

    private static func ctlInfoBuffer() -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: ctlInfoSize)
        let name = Array(utunControlName.utf8)
        buffer.replaceSubrange(4..<(4 + name.count), with: name)
        return buffer
    }

    /// `sc_id` of the peer address; only valid for AF_SYSTEM sockets.
    private static func peerControlID(of fd: Int32) -> UInt32? {
        guard let peer = peerSockaddrControl(fd), peer.family == afSystem else { return nil }
        return peer.controlID
    }

    private static func peerControlUnit(of fd: Int32) -> UInt32? {
        guard let peer = peerSockaddrControl(fd), peer.family == afSystem else { return nil }
        return peer.unit
    }

    private struct PeerSystemAddress {
        let family: sa_family_t
        let controlID: UInt32
        let unit: UInt32
    }

    /// Reads `struct sockaddr_ctl { u_char sc_len; sa_family_t sc_family;
    /// u_int16_t ss_sysaddr; u_int32_t sc_id; u_int32_t sc_unit; ... }` from the
    /// peer name without depending on the (non-public) Swift type.
    private static func peerSockaddrControl(_ fd: Int32) -> PeerSystemAddress? {
        var address = sockaddr()
        var length = socklen_t(MemoryLayout<sockaddr>.size)
        guard getpeername(fd, &address, &length) == 0 else { return nil }
        guard address.sa_family == afSystem else { return nil }
        var controlID: UInt32 = 0
        var unit: UInt32 = 0
        withUnsafeBytes(of: address) { raw in
            guard raw.count >= 12 else { return }
            controlID = raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            unit = raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
        }
        return PeerSystemAddress(family: address.sa_family, controlID: controlID, unit: unit)
    }

    private static func socketInterfaceName(fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        var size = socklen_t(buffer.count)
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return getsockopt(fd, sysprotoControl, utunOptIfname, base, &size)
        }
        guard result == 0, size > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Interface lookup

    /// Name of the interface that currently owns `address`, e.g. "utun3" for
    /// the 198.18.0.1 address the packet tunnel provider assigned.
    private static func interfaceName(owningAddress address: String) -> String? {
        var expected = in_addr()
        guard address.withCString({ inet_pton(AF_INET, $0, &expected) }) == 1 else { return nil }

        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let sockaddrPointer = current.pointee.ifa_addr,
                  sockaddrPointer.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let found = UnsafeRawPointer(sockaddrPointer)
                .assumingMemoryBound(to: sockaddr_in.self)
                .pointee.sin_addr
            if found.s_addr == expected.s_addr {
                return String(cString: current.pointee.ifa_name)
            }
        }
        return nil
    }
}
