import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum URLPolicyError: Error, Equatable {
    case empty
    case tooLong
    case invalid
    case insecureScheme
    case blockedHost
}

/// Single acceptance point for remote URLs: https-only, loopback/private hosts rejected.
public enum URLPolicy {
    public static let maxLength = 2048

    public static func validated(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLPolicyError.empty }
        guard trimmed.count <= maxLength else { throw URLPolicyError.tooLong }
        // percentEncoded: false — the default leaves the host encoded, so "%31%32%37.0.0.1"
        // would reach isBlockedHost intact while yt-dlp decodes it and reaches 127.0.0.1.
        guard let url = URL(string: trimmed), let host = url.host(percentEncoded: false),
            !host.isEmpty
        else {
            throw URLPolicyError.invalid
        }
        guard isHTTPS(url) else { throw URLPolicyError.insecureScheme }
        guard !isBlockedHost(host) else { throw URLPolicyError.blockedHost }
        return url
    }

    public static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// https-only parse for URLs that arrive from the update API rather than from the user.
    /// The host denylist deliberately does not apply: these are public release hosts, and
    /// `validated(_:)` stays the gate for anything a person typed.
    public static func httpsURL(_ string: String) -> URL? {
        guard let url = URL(string: string), isHTTPS(url) else { return nil }
        return url
    }

    static func isBlockedHost(_ host: String) -> Bool {
        var h = host.lowercased()
        // FQDNs may carry a single trailing "." (root label); normalize it away.
        if h.hasSuffix(".") { h.removeLast() }

        if h == "localhost" || h.hasSuffix(".localhost") { return true }
        if let ipv4 = parseIPv4(h) { return isBlockedIPv4(ipv4) }
        if let ipv6 = parseIPv6(h) { return isBlockedIPv6(ipv6) }
        return false
    }

    /// Parses any form `inet_aton` accepts: dotted-quad, shorthand 1-3 part forms,
    /// octal (`0177...`) and hex (`0x7f...`) octets, and bare 32-bit integers.
    private static func parseIPv4(_ s: String) -> [UInt8]? {
        guard !s.isEmpty else { return nil }
        var addr = in_addr()
        let ok = s.withCString { inet_aton($0, &addr) }
        guard ok != 0 else { return nil }
        let value = UInt32(bigEndian: addr.s_addr)
        return [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    static func isBlockedIPv4(_ ip: [UInt8]) -> Bool {
        // A malformed byte array must block, not allow — fail closed.
        guard ip.count == 4 else { return true }
        let (a, b, c, d) = (ip[0], ip[1], ip[2], ip[3])
        if a == 127 { return true } // loopback 127.0.0.0/8
        if a == 10 { return true } // private 10.0.0.0/8
        if a == 172, (16...31).contains(b) { return true } // private 172.16.0.0/12
        if a == 192, b == 168 { return true } // private 192.168.0.0/16
        if a == 169, b == 254 { return true } // link-local / cloud metadata 169.254.0.0/16
        if a == 0, b == 0, c == 0, d == 0 { return true } // unspecified
        return false
    }

    /// Parses any textual IPv6 form `inet_pton` accepts, including embedded IPv4
    /// (`::ffff:a.b.c.d`). Returns the 16 raw address bytes.
    private static func parseIPv6(_ s: String) -> [UInt8]? {
        guard !s.isEmpty else { return nil }
        var addr = in6_addr()
        let ok = s.withCString { inet_pton(AF_INET6, $0, &addr) }
        guard ok == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        // A malformed byte array must block, not allow — fail closed.
        guard bytes.count == 16 else { return true }

        // Loopback ::1
        if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 { return true }
        // Unspecified ::
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        // Link-local fe80::/10 (top 10 bits: 1111111010)
        if bytes[0] == 0xfe, (bytes[1] & 0xc0) == 0x80 { return true }
        // Unique-local fc00::/7 — the IPv6 counterpart of RFC1918
        if (bytes[0] & 0xfe) == 0xfc { return true }

        // Every form inet_pton accepts that carries an IPv4 address: mapped
        // ::ffff:a.b.c.d, compatible ::a.b.c.d, and NAT64 64:ff9b::a.b.c.d.
        let embedded = [bytes[12], bytes[13], bytes[14], bytes[15]]
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return isBlockedIPv4(embedded)
        }
        if bytes[0..<12].allSatisfy({ $0 == 0 }) { return isBlockedIPv4(embedded) }
        if bytes[0] == 0, bytes[1] == 0x64, bytes[2] == 0xff, bytes[3] == 0x9b,
            bytes[4..<12].allSatisfy({ $0 == 0 })
        {
            return isBlockedIPv4(embedded)
        }
        return false
    }
}
