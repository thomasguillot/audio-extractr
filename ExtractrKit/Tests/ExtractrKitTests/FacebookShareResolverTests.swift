import Foundation
import Testing

@testable import ExtractrKit

private struct ScriptedTracer: RedirectTracing {
    var hops: [String] = []
    var failure: (any Error)?

    func hops(from url: URL) async throws -> [URL] {
        if let failure { throw failure }
        return [url] + hops.map { URL(string: $0)! }
    }
}

@Suite struct FacebookShareResolverTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test(arguments: [
        "https://www.facebook.com/share/v/1BiCaWHnK5/",
        "https://facebook.com/share/v/1BiCaWHnK5",
        "https://m.facebook.com/share/r/1BGqFNXqYQ/",
        "https://web.facebook.com/share/v/1BiCaWHnK5/?mibextid=wwXIfr",
        "https://WWW.Facebook.com/share/v/1BiCaWHnK5/",
        "https://fb.watch/myD_fzCU8q/",
        "https://fb.watch/myD-Ai3tPr",
    ])
    func recognizesShareLinks(_ link: String) {
        #expect(FacebookShareResolver.isShareLink(url(link)))
    }

    @Test(arguments: [
        "https://www.facebook.com/reel/1195289147628387",
        "https://www.facebook.com/watch/?v=647537299265662",
        "https://www.facebook.com/share/p/1BiCaWHnK5/",
        "https://www.facebook.com/share/v/",
        "https://www.facebook.com/share/v/abc/extra",
        "https://www.facebook.com//share/v/abc",
        "https://evil.facebook.com.example/share/v/abc/",
        "https://notfacebook.com/share/v/abc/",
        "https://l.facebook.com/share/v/abc/",
        "https://www.fb.watch/abc/",
        "https://fb.watch/",
        "https://fb.watch/abc/def",
        "http://fb.watch/abc/",
        "https://www.youtube.com/share/v/abc/",
    ])
    func leavesEverythingElseAlone(_ link: String) {
        #expect(!FacebookShareResolver.isShareLink(url(link)))
    }

    @Test func nonShareLinksPassThroughWithoutARequest() async throws {
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(failure: URLError(.notConnectedToInternet)))
        let link = url("https://www.facebook.com/reel/1195289147628387")
        #expect(try await resolver.resolve(link) == link)
    }

    @Test(arguments: [
        ("https://www.facebook.com/reel/1195289147628387?mibextid=abc&rdid=x",
         "https://www.facebook.com/reel/1195289147628387"),
        ("https://m.facebook.com/watch/?v=647537299265662&rdid=x&share_url=y",
         "https://m.facebook.com/watch/?v=647537299265662"),
        ("https://www.facebook.com/cnn/videos/10155529876156509/?mibextid=abc",
         "https://www.facebook.com/cnn/videos/10155529876156509/"),
        ("https://www.facebook.com/videos/10155529876156509/",
         "https://www.facebook.com/watch/?v=10155529876156509"),
        ("https://web.facebook.com/gov.sg/videos/10154383743583686#comments",
         "https://web.facebook.com/gov.sg/videos/10154383743583686/"),
    ])
    func resolvesToACleanSupportedURL(_ final: String, _ expected: String) async throws {
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(hops: [final]))
        let resolved = try await resolver.resolve(url("https://www.facebook.com/share/v/1BiCaWHnK5/"))
        #expect(resolved.absoluteString == expected)
    }

    @Test func followsSeveralHops() async throws {
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(hops: [
            "https://www.facebook.com/share/v/1BiCaWHnK5/?_rdr",
            "https://www.facebook.com/watch/?v=647537299265662",
        ]))
        let resolved = try await resolver.resolve(url("https://fb.watch/myD_fzCU8q/"))
        #expect(resolved.absoluteString == "https://www.facebook.com/watch/?v=647537299265662")
    }

    @Test(arguments: [
        "https://www.facebook.com/login/?next=https%3A%2F%2Fwww.facebook.com%2Fshare%2Fv%2Fabc%2F",
        "https://www.fb.watch/login/?next=https%3A%2F%2Ffb.watch%2FvxemEFv5az%2F",
        "https://m.facebook.com/login.php?next=x",
        "https://www.facebook.com/checkpoint/block/?next=x",
    ])
    func loginRedirectAsksForAPublicVideo(_ final: String) async {
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(hops: [final]))
        await #expect(throws: FacebookShareError.loginRequired) {
            try await resolver.resolve(url("https://fb.watch/vxemEFv5az/"))
        }
    }

    @Test(arguments: [
        [String](),
        ["https://www.facebook.com/"],
        ["https://www.facebook.com/watch/?v=notdigits"],
        ["https://www.facebook.com/watch/"],
        ["https://www.facebook.com/reel/"],
        ["https://www.facebook.com/cnn/posts/10153664894881749"],
        ["https://evil.example/reel/1195289147628387"],
        ["https://facebook.com.evil.example/reel/1195289147628387"],
        ["http://www.facebook.com/reel/1195289147628387"],
        ["http://www.facebook.com/x", "https://www.facebook.com/reel/1195289147628387"],
        ["https://127.0.0.1/reel/1195289147628387"],
        ["http://www.facebook.com/x", "https://www.facebook.com/login/"],
    ])
    func keepsTheShareLinkWhenTheDestinationIsNotUsable(_ hops: [String]) async throws {
        let link = url("https://www.facebook.com/share/v/1BiCaWHnK5/")
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(hops: hops))
        #expect(try await resolver.resolve(link) == link)
    }

    @Test func keepsTheShareLinkAfterALongRedirectChain() async throws {
        let chain = (0..<FacebookShareResolver.maxRedirects).map { "https://www.facebook.com/hop/\($0)" }
            + ["https://www.facebook.com/reel/1195289147628387"]
        let link = url("https://fb.watch/myD_fzCU8q/")
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(hops: chain))
        #expect(try await resolver.resolve(link) == link)
    }

    @Test func keepsTheShareLinkWhenTheRequestFails() async throws {
        let link = url("https://fb.watch/myD_fzCU8q/")
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(failure: URLError(.timedOut)))
        #expect(try await resolver.resolve(link) == link)
    }

    @Test func cancellationStaysCancellation() async {
        let resolver = FacebookShareResolver(tracer: ScriptedTracer(failure: URLError(.cancelled)))
        await #expect(throws: CancellationError.self) {
            try await resolver.resolve(url("https://fb.watch/myD_fzCU8q/"))
        }
    }

    @Test func tracerStopsAtTheFirstHopThatSettlesIt() {
        #expect(FacebookShareResolver.settles(url("https://www.facebook.com/reel/1195289147628387")))
        #expect(FacebookShareResolver.settles(url("https://www.fb.watch/login/?next=x")))
        #expect(FacebookShareResolver.settles(url("http://www.facebook.com/share/v/abc/")))
        #expect(FacebookShareResolver.settles(url("https://evil.example/share/v/abc/")))
        #expect(!FacebookShareResolver.settles(url("https://www.facebook.com/share/v/abc/?_rdr")))
    }
}

@Suite struct FacebookFailureTests {
    @Test func recognizesLoginRequired() {
        let stderr = """
            [facebook] Extracting URL: https://www.facebook.com/watch/?v=1
            ERROR: [facebook] 1: This video is only available for registered users. Use --cookies-from-browser or --cookies for the authentication. See  https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp  for how to manually pass cookies
            """
        #expect(FacebookFailure.classify(stderr) == .loginRequired)
    }

    @Test func recognizesCannotParseData() {
        let stderr = "ERROR: [facebook] 10155529876156509: Cannot parse data; please report this issue on  https://github.com/yt-dlp/yt-dlp/issues"
        #expect(FacebookFailure.classify(stderr) == .unreadable)
    }

    @Test func ignoresOtherSitesAndOtherErrors() {
        #expect(FacebookFailure.classify("ERROR: [youtube] abc: Cannot parse data") == nil)
        #expect(FacebookFailure.classify("ERROR: [facebook] 1: HTTP Error 404: Not Found") == nil)
        #expect(FacebookFailure.classify("") == nil)
    }
}
