import Foundation
import Testing
@testable import BatteryGuard

struct LocalHTTPTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func getAndFragmentedPostParseWithExactByteLength() throws {
        let get = try LocalHTTPParser.parse(data("GET /v1/status?fresh=1 HTTP/1.1\r\nHost: 127.0.0.1:8767\r\nAuthorization: Bearer local\r\n\r\n"))
        #expect(get?.method == "GET")
        #expect(get?.target == "/v1/status?fresh=1")
        #expect(get?.headers["authorization"] == "Bearer local")
        #expect(get?.body.isEmpty == true)
        let header = "POST /v1/config HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\n"
        #expect(try LocalHTTPParser.parse(data(header + "ab")) == nil)
        let post = try LocalHTTPParser.parse(data(header + "abcd"))
        #expect(post?.body == data("abcd"))
        #expect(try LocalHTTPParser.parse(data("GET /v1/status HTTP/1.1\r\nHost:")) == nil)
    }

    @Test func headerAmbiguityAndTransferEncodingAreRejected() {
        let invalidHeaders = [
            "Content-Length: 0\r\ncontent-length: 0\r\n",
            "Content-Length: 0\r\nContent-Length: 1\r\n",
            "Transfer-Encoding: chunked\r\n",
            "Transfer-Encoding: identity\r\nContent-Length: 0\r\n",
            "Authorization: Bearer one\r\nAuthorization: Bearer two\r\n",
            "Content-Length : 0\r\n",
            "Content-Length: +0\r\n",
            "Content-Length: 0, 0\r\n",
            "Content-Length: -1\r\n",
            "Content-Length: 9999999999999999999999999\r\n",
            "Authorization: Bearer one\r\n two\r\n",
            "Expect: 100-continue\r\n"
        ]
        for headers in invalidHeaders {
            #expect(throws: LocalHTTPError.self) {
                try LocalHTTPParser.parse(data("POST /v1/config HTTP/1.1\r\nHost: localhost\r\n" + headers + "\r\n"))
            }
        }
    }

    @Test func requestBodyAndHeadersHaveIndependentLimits() throws {
        #expect(throws: LocalHTTPError.self) {
            try LocalHTTPParser.parse(Data(repeating: 65, count: LocalHTTPParser.maximumRequestBytes + 1))
        }
        #expect(throws: LocalHTTPError.self) {
            try LocalHTTPParser.parse(Data(repeating: 65, count: LocalHTTPParser.maximumHeaderBytes + 1))
        }
        #expect(throws: LocalHTTPError.self) {
            try LocalHTTPParser.parse(data("POST /v1/config HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(LocalHTTPParser.maximumBodyBytes + 1)\r\n\r\n"))
        }
        let header = data("POST /v1/config HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(LocalHTTPParser.maximumBodyBytes)\r\n\r\n")
        let body = Data(repeating: 65, count: LocalHTTPParser.maximumBodyBytes)
        #expect(try LocalHTTPParser.parse(header + body)?.body.count == LocalHTTPParser.maximumBodyBytes)
    }

    @Test func smugglingMalformedLinesAndUnsupportedMethodsAreRejected() {
        let inputs = [
            "GET / HTTP/1.1\r\nHost: localhost\r\n\r\nextra",
            "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1\r\n\r\nab",
            "GET / HTTP/1.1\r\nHost: localhost\r\n\r\nGET / HTTP/1.1\r\nHost: localhost\r\n\r\n",
            "GET / HTTP/1.1\r\nHost: localhost\nAuthorization: injected\r\n\r\n",
            "GET / HTTP/1.1\r\nHost: localhost\r\nBad\r\n\r\n",
            "GET / HTTP/1.1\r\nHost: localhost\r\nX: \u{0}\r\n\r\n",
            "GET / HTTP/1.1\r\n\r\n",
            "GET http://external.example/ HTTP/1.1\r\nHost: localhost\r\n\r\n",
            "GET /#fragment HTTP/1.1\r\nHost: localhost\r\n\r\n",
            "GET  / HTTP/1.1\r\nHost: localhost\r\n\r\n",
            "GET / HTTP/1.0\r\nHost: localhost\r\n\r\n",
            "DELETE / HTTP/1.1\r\nHost: localhost\r\n\r\n"
        ]
        for input in inputs {
            #expect(throws: LocalHTTPError.self) { try LocalHTTPParser.parse(data(input)) }
        }
    }

    @Test func originIsPreservedForRouterAuthorization() throws {
        let request = try LocalHTTPParser.parse(data("GET /v1/status HTTP/1.1\r\nHost: localhost\r\nOrigin: https://external.example\r\n\r\n"))
        #expect(request?.headers["origin"] == "https://external.example")
    }
}
