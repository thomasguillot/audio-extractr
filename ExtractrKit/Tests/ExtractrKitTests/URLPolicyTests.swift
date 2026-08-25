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
}
