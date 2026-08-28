import Testing

@testable import ExtractrKit

@Suite struct URLPolicyTests {
    @Test func acceptsHTTPS() throws {
        let url = try URLPolicy.validated("  https://example.com/watch?v=abc  ")
        #expect(url.absoluteString == "https://example.com/watch?v=abc")
    }
    @Test func rejectsHTTPAndOtherSchemes() {
        #expect(throws: URLPolicyError.insecureScheme) { try URLPolicy.validated("http://example.com/a") }
        #expect(throws: URLPolicyError.insecureScheme) { try URLPolicy.validated("ftp://example.com/a") }
    }
    @Test func rejectsEmptyAndGarbage() {
        #expect(throws: URLPolicyError.empty) { try URLPolicy.validated("   ") }
        #expect(throws: URLPolicyError.invalid) { try URLPolicy.validated("not a url") }
    }
    @Test func rejectsTooLong() {
        let long = "https://example.com/" + String(repeating: "a", count: 2100)
        #expect(throws: URLPolicyError.tooLong) { try URLPolicy.validated(long) }
    }
    @Test(arguments: [
        "https://localhost/a", "https://sub.localhost/a", "https://127.0.0.1/a",
        "https://10.1.2.3/a", "https://172.20.0.1/a", "https://192.168.1.5/a",
        "https://0.0.0.0/a", "https://2130706433/a", "https://[::1]/a",
        "https://[0:0:0:0:0:0:0:1]/a", "https://[0::1]/a", "https://[::0:1]/a",
        "https://localhost./a",
        "https://127.1/a", "https://127.0.1/a",
        "https://0177.0.0.1/a", "https://0x7f.0.0.1/a",
        "https://169.254.169.254/a", "https://[fe80::1]/a",
    ])
    func rejectsLoopbackAndPrivate(_ candidate: String) {
        #expect(throws: URLPolicyError.blockedHost) { try URLPolicy.validated(candidate) }
    }
    @Test func allowsPublicIP() throws {
        _ = try URLPolicy.validated("https://93.184.216.34/media")
    }
    @Test func allowsPublicIPv6() throws {
        _ = try URLPolicy.validated("https://[2606:4700:4700::1111]/a")
    }
    @Test func isBlockedIPv4FailsClosedOnMalformedInput() {
        #expect(URLPolicy.isBlockedIPv4([127]) == true)
    }

    /// The policy and the child process must judge the same string: `URL.host()` returns the
    /// encoded host, and whatever consumes the URL afterwards decodes it.
    @Test(arguments: [
        "https://%31%32%37.0.0.1/a",
        "https://%31%32%37.%30.%30.%31/a",
        "https://%6cocalhost/a",
        "https://%6C%6F%63%61%6C%68%6F%73%74/a",
        "https://%31%30.0.0.5/a",
        "https://%31%39%32.168.1.5/a",
        "https://%31%36%39.254.169.254/a",
        "https://%30%78%37%66.0.0.1/a",
    ])
    func rejectsPercentEncodedLoopbackAndPrivate(_ candidate: String) {
        #expect(throws: URLPolicyError.blockedHost) { try URLPolicy.validated(candidate) }
    }

    /// Unique-local addresses are the IPv6 counterpart of RFC1918 and route on a LAN.
    @Test(arguments: [
        "https://[fc00::1]/a", "https://[fd00::1]/a",
        "https://[fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]/a",
    ])
    func rejectsIPv6UniqueLocal(_ candidate: String) {
        #expect(throws: URLPolicyError.blockedHost) { try URLPolicy.validated(candidate) }
    }

    /// `inet_pton` also accepts IPv4-compatible (`::a.b.c.d`) and NAT64 (`64:ff9b::a.b.c.d`)
    /// form, so the embedded IPv4 must be judged there too, not only in IPv4-mapped form.
    @Test(arguments: [
        "https://[::127.0.0.1]/a", "https://[0:0:0:0:0:0:127.0.0.1]/a",
        "https://[::10.1.2.3]/a", "https://[::169.254.169.254]/a",
        "https://[64:ff9b::127.0.0.1]/a", "https://[64:ff9b::192.168.1.5]/a",
    ])
    func rejectsIPv6EmbeddedIPv4(_ candidate: String) {
        #expect(throws: URLPolicyError.blockedHost) { try URLPolicy.validated(candidate) }
    }

    @Test func allowsIPv6EmbeddingPublicIPv4() throws {
        _ = try URLPolicy.validated("https://[::ffff:93.184.216.34]/a")
        _ = try URLPolicy.validated("https://[64:ff9b::93.184.216.34]/a")
    }

    @Test func malformedIPv6BytesFailClosed() {
        #expect(URLPolicy.isBlockedIPv6([0, 0, 0]))
    }

    @Test func percentEncodingDoesNotBreakOrdinaryHosts() throws {
        let url = try URLPolicy.validated("https://ex%61mple.com/watch")
        #expect(url.absoluteString == "https://ex%61mple.com/watch")
    }
}
