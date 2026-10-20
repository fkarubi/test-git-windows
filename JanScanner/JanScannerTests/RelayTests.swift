import UIKit
import XCTest
@testable import JanScanner

/// 合成のバイト列と JSON だけを使う。店や人の写真は置かない。
final class RelayTests: XCTestCase {
    private let token = "unit-test-token-ok"

    override func tearDown() {
        RelayURLStub.handler = nil
        RelayURLStub.reset()
        super.tearDown()
    }

    func testThresholdConstantAndBoundary() {
        XCTAssertEqual(RelayVerdict.presenceThreshold, 0.5)
        let box = DrawableBox(top: 0.1, bottom: 0.2, left: 0.3, right: 0.4, confidence: nil)
        let present = RelayVerdict(probability: 0.5, box: box)
        XCTAssertEqual(present.boxToDraw, box)
        XCTAssertEqual(present.title, "バーコードあり（50.0%）")

        let absent = RelayVerdict(probability: 0.499, box: box)
        XCTAssertNil(absent.boxToDraw)
        XCTAssertEqual(absent.title, "バーコードなし（49.9%）")
        XCTAssertEqual(absent.detail, "50.0%未満なので、枠は表示していません。")
    }

    func testUndrawableBoxIsDroppedWhenPresent() {
        let box = RelayBox(top: 0.4, bottom: 0.4, left: 0.1, right: 0.2, confidence: 0.9)
        XCTAssertNil(box.drawable)
        let verdict = RelayVerdict(probability: 0.8, box: box.drawable)
        XCTAssertEqual(verdict, .present(probability: 0.8, box: nil))
        XCTAssertNil(verdict.boxToDraw)
        XCTAssertEqual(verdict.detail, "位置を示す枠は返りませんでした。")
    }

    func testBoxBounds() {
        XCTAssertNotNil(RelayBox(top: 0, bottom: 1, left: 0, right: 1, confidence: nil).drawable)
        XCTAssertNil(RelayBox(top: -0.01, bottom: 0.5, left: 0, right: 1, confidence: nil).drawable)
        XCTAssertNil(RelayBox(top: 0, bottom: 0.5, left: 0, right: 1.01, confidence: nil).drawable)
        XCTAssertNil(RelayBox(top: 0.2, bottom: nil, left: 0, right: 1, confidence: nil).drawable)
    }

    func testOverlayAspectFit() throws {
        let box = DrawableBox(top: 0, bottom: 1, left: 0.25, right: 0.75, confidence: nil)
        let rect = try XCTUnwrap(BoxOverlay.rect(
            box: box,
            imageSize: CGSize(width: 100, height: 50),
            in: CGSize(width: 200, height: 200)
        ))
        XCTAssertEqual(rect.origin.x, 50, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 50, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.height, 100, accuracy: 0.001)
        XCTAssertNil(BoxOverlay.rect(box: box, imageSize: .zero, in: CGSize(width: 10, height: 10)))
    }

    func testDecodesRelayJSON() throws {
        let json = """
        {"has_barcode_probability":0.99,
         "box":{"top":0.43,"bottom":0.59,"left":0.49,"right":0.68,"confidence":null},
         "box_px":{"top":506,"bottom":694,"left":768,"right":1066},
         "image":{"width":1568,"height":1176},
         "model":"jev-1.14.0","latency_ms":173}
        """.data(using: .utf8)!
        let result = try RelayJSON.decoder.decode(RelayBarcodeResult.self, from: json)
        XCTAssertEqual(result.hasBarcodeProbability ?? -1, 0.99, accuracy: 0.000001)
        XCTAssertEqual(result.latencyMs, 173)
        XCTAssertEqual(result.model, "jev-1.14.0")
        let box = try XCTUnwrap(result.box?.drawable)
        XCTAssertEqual(box.top, 0.43, accuracy: 0.000001)
        XCTAssertNil(box.confidence)
    }

    func testDefaultURLAndAllowlist() throws {
        XCTAssertEqual(RelayEndpoint.defaultBaseURL, "http://100.127.247.83:8787")
        let endpoint = try RelayEndpoint.make(from: nil).get()
        XCTAssertEqual(endpoint.barcodeURL.absoluteString, "http://100.127.247.83:8787/barcode")
        XCTAssertEqual(endpoint.healthURL.absoluteString, "http://100.127.247.83:8787/health")

        let bare = try RelayEndpoint.make(from: "100.64.0.1:8787/barcode/").get()
        XCTAssertEqual(bare.barcodeURL.absoluteString, "http://100.64.0.1:8787/barcode")

        let magic = try RelayEndpoint.make(from: "HTTP://My-Mac.Tail-Name.ts.net:8787/health").get()
        XCTAssertEqual(magic.healthURL.absoluteString, "http://my-mac.tail-name.ts.net:8787/health")

        XCTAssertTrue(TailscaleHost.isCGNAT("100.64.0.0"))
        XCTAssertTrue(TailscaleHost.isCGNAT("100.127.255.255"))
        XCTAssertFalse(TailscaleHost.isCGNAT("100.63.255.255"))
        XCTAssertFalse(TailscaleHost.isCGNAT("100.128.0.1"))
        XCTAssertFalse(TailscaleHost.isCGNAT("10.0.0.1"))
        XCTAssertFalse(TailscaleHost.isMagicDNS("ts.net"))
        XCTAssertFalse(TailscaleHost.isMagicDNS("notts.net"))
        XCTAssertFalse(TailscaleHost.isAllowed("example.com"))

        expectFailure("http://example.com:8787", .unsupportedHost)
        expectFailure("http://user:secret@100.127.247.83:8787", .invalidURL)
        expectFailure("ftp://100.127.247.83:8787", .invalidURL)
        expectFailure("http://my-mac.tail.ts.net:8787/extra", .invalidURL)
    }

    func testErrorCopy() {
        XCTAssertEqual(
            RelayFailure.timedOut.message,
            "接続がタイムアウトしました。iPhoneのTailscaleがオフ、または未接続の可能性があります。"
        )
        XCTAssertEqual(
            RelayFailure.barcodeTimedOut.message,
            "リレーには届きましたが、判定が時間内に返りませんでした。もう一度試してください。"
        )
        XCTAssertEqual(
            RelayFailure.unauthorized.message,
            "合言葉が違います（401）。設定のトークンを確認してください。"
        )
        XCTAssertFalse(RelayFailure.unauthorized.message.contains(token))
        XCTAssertEqual(
            RelayHTTP.map(URLError(.timedOut), stage: .health) as? RelayFailure,
            .timedOut
        )
        XCTAssertEqual(
            RelayHTTP.map(URLError(.timedOut), stage: .upload) as? RelayFailure,
            .barcodeTimedOut
        )
        XCTAssertEqual(
            RelayHTTP.map(URLError(.appTransportSecurityRequiresSecureConnection), stage: .health) as? RelayFailure,
            .transportSecurity
        )
        let bad = #"{"error":"画像が小さすぎます"}"#.data(using: .utf8)!
        XCTAssertEqual(RelayHTTP.failure(status: 400, data: bad, stage: .upload), .badImage("画像が小さすぎます"))
        let leaked = #"{"error":"token leaked"}"#.data(using: .utf8)!
        XCTAssertEqual(RelayHTTP.failure(status: 400, data: leaked, stage: .upload), .badImage(""))
        XCTAssertEqual(RelayHTTP.failure(status: 401, data: leaked, stage: .upload), .unauthorized)
        XCTAssertEqual(RelayHTTP.failure(status: 413, data: Data(), stage: .upload), .tooLarge)
        XCTAssertEqual(RelayHTTP.failure(status: 502, data: Data(), stage: .upload), .upstream)
    }

    func testMultipartOmitsToken() {
        let image = Data([0x01, 0x02, 0x03, 0x04])
        let body = RelayMultipart.body(image: image, filename: "a\r\nb.jpg", mime: "image/jpeg", boundary: "BOUND")
        XCTAssertNotNil(body.range(of: Data("name=\"photo\"".utf8)))
        XCTAssertNotNil(body.range(of: image))
        XCTAssertNil(body.range(of: Data(token.utf8)))
        XCTAssertNil(body.range(of: Data("\r\nb".utf8)))
        XCTAssertNotNil(body.range(of: Data("filename=\"ab.jpg\"".utf8)))
    }

    func testTokenNormalizationDoesNotUseUserDefaults() throws {
        XCTAssertEqual(RelayKeychain.normalize("  Bearer \(token)  "), token)
        XCTAssertThrowsError(try RelayKeychain.save("short-token", account: testAccount)) { error in
            XCTAssertEqual(error as? RelayKeychainError, .tooShort)
        }
        XCTAssertThrowsError(try RelayKeychain.save("bad token value here", account: testAccount)) { error in
            XCTAssertEqual(error as? RelayKeychainError, .invalid)
        }

        let account = testAccount
        XCTAssertNotEqual(account, RelayKeychain.account)
        defer { RelayKeychain.delete(account: account) }
        try RelayKeychain.save("Bearer \(token)", account: account)
        XCTAssertEqual(RelayKeychain.token(account: account), token)
        for value in UserDefaults.standard.dictionaryRepresentation().values {
            if let string = value as? String {
                XCTAssertFalse(string.contains(token))
            }
        }
    }

    func testImageKindAndSyntheticPayload() {
        XCTAssertEqual(ImageKind(data: Data([0xFF, 0xD8, 0xFF, 0x00])), .jpeg)
        XCTAssertEqual(ImageKind(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D])), .png)
        XCTAssertEqual(ImageKind(data: ftyp("heic")), .heic)
        XCTAssertEqual(ImageKind(data: ftyp("mif1")), .heic)
        XCTAssertNil(ImageKind(data: ftyp("avif")))

        let heic = ftyp("heic")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let prepared = RelayImageEncoding.prepare(uiImage: image, fileData: heic)
        guard case .ready(let payload) = prepared else {
            return XCTFail("expected original bytes")
        }
        XCTAssertEqual(payload.data, heic)
        XCTAssertEqual(payload.mime, "image/heic")
        XCTAssertEqual(payload.filename, "photo.heic")
        XCTAssertEqual(RelayImageEncoding.prepare(uiImage: UIImage(), fileData: nil), .unreadable)
    }

    func testDoesNotSendTokenOffTailscale() async {
        RelayURLStub.handler = { _ in
            XCTFail("example.com には送らない")
            return (500, Data())
        }
        let client = makeClient()
        do {
            _ = try await client.detect(image: Data([1]), mime: "image/jpeg", filename: "photo.jpg",
                                        baseURL: "http://example.com", token: token)
            XCTFail("should throw")
        } catch let failure as RelayFailure {
            XCTAssertEqual(failure, .unsupportedHost)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(RelayURLStub.calls.isEmpty)
    }

    func testHealthTimeoutDoesNotUpload() async {
        RelayURLStub.handler = { _ in throw URLError(.timedOut) }
        let client = makeClient()
        do {
            _ = try await client.detect(image: Data([1]), mime: "image/jpeg", filename: "photo.jpg",
                                        baseURL: RelayEndpoint.defaultBaseURL, token: token)
            XCTFail("should throw")
        } catch let failure as RelayFailure {
            XCTAssertEqual(failure, .timedOut)
            XCTAssertTrue(failure.message.contains("Tailscale"))
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(RelayURLStub.calls.map(\.path), ["/health"])
    }

    func testUploadTimeoutAfterHealth() async throws {
        RelayURLStub.handler = { request in
            if request.url?.path == "/health" {
                return (200, Data("{\"ok\":true}".utf8))
            }
            throw URLError(.timedOut)
        }
        let client = makeClient()
        do {
            _ = try await client.detect(image: Data([1]), mime: "image/jpeg", filename: "photo.jpg",
                                        baseURL: RelayEndpoint.defaultBaseURL, token: token)
            XCTFail("should throw")
        } catch let failure as RelayFailure {
            XCTAssertEqual(failure, .barcodeTimedOut)
            XCTAssertFalse(failure.message.contains("オフ"))
        }
    }

    func testUnauthorizedAndSuccess() async throws {
        let image = Data([0x10, 0x20, 0x30, 0x40])
        RelayURLStub.handler = { request in
            if request.url?.path == "/health" {
                return (200, Data("{\"ok\":true}".utf8))
            }
            return (401, Data("{\"error\":\"unauthorized\"}".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.detect(image: image, mime: "image/jpeg", filename: "photo.jpg",
                                        baseURL: RelayEndpoint.defaultBaseURL, token: token)
            XCTFail("should throw")
        } catch let failure as RelayFailure {
            XCTAssertEqual(failure, .unauthorized)
        }
        let barcode = try XCTUnwrap(RelayURLStub.calls.first { $0.path == "/barcode" })
        XCTAssertEqual(barcode.authorization, "Bearer \(token)")
        XCTAssertNil(RelayURLStub.calls.first { $0.path == "/health" }?.authorization)
        let body = try XCTUnwrap(barcode.body)
        XCTAssertNotNil(body.range(of: Data("name=\"photo\"".utf8)))
        XCTAssertNotNil(body.range(of: image))
        XCTAssertNil(body.range(of: Data(token.utf8)))

        RelayURLStub.reset()
        RelayURLStub.handler = { request in
            if request.url?.path == "/health" {
                return (200, Data("{\"ok\":true}".utf8))
            }
            let json = """
            {"has_barcode_probability":0.49,"box":{"top":0.1,"bottom":0.2,"left":0.3,"right":0.4,"confidence":0.7},
             "model":"jev-1.14.0","latency_ms":12}
            """
            return (200, Data(json.utf8))
        }
        let low = try await makeClient().detect(image: image, mime: "image/jpeg", filename: "photo.jpg",
                                                 baseURL: "http://100.127.247.83:8787", token: token)
        XCTAssertNil(low.verdict.boxToDraw)
        XCTAssertEqual(low.latencyMs, 12)

        RelayURLStub.reset()
        RelayURLStub.handler = { request in
            if request.url?.path == "/health" {
                return (200, Data("{\"ok\":true}".utf8))
            }
            let json = """
            {"has_barcode_probability":0.5,"box":{"top":0.1,"bottom":0.4,"left":0.2,"right":0.8,"confidence":null},
             "model":"jev-1.14.0","latency_ms":20}
            """
            return (200, Data(json.utf8))
        }
        let high = try await makeClient().detect(image: image, mime: "image/jpeg", filename: "photo.jpg",
                                                  baseURL: RelayEndpoint.defaultBaseURL, token: token)
        let drawn = try XCTUnwrap(high.verdict.boxToDraw)
        XCTAssertEqual(drawn.left, 0.2, accuracy: 0.000001)
        XCTAssertEqual(high.verdict.title, "バーコードあり（50.0%）")
    }

    private func expectFailure(_ raw: String, _ expected: RelayFailure,
                               file: StaticString = #filePath, line: UInt = #line) {
        switch RelayEndpoint.make(from: raw) {
        case .failure(let error):
            XCTAssertEqual(error, expected, file: file, line: line)
        case .success:
            XCTFail("失敗するURLです: \(raw)", file: file, line: line)
        }
    }

    func testMissingTokenDoesNotCallNetwork() async {
        RelayURLStub.handler = { _ in
            XCTFail("token が無いときは送らない")
            return (500, Data())
        }
        do {
            _ = try await makeClient().detect(image: Data([1]), mime: "image/jpeg", filename: "photo.jpg",
                                              baseURL: RelayEndpoint.defaultBaseURL, token: "")
            XCTFail("should throw")
        } catch let failure as RelayFailure {
            XCTAssertEqual(failure, .missingToken)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private var testAccount: String { "relay-token-unit-test" }

    private func makeClient() -> RelayClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayURLStub.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return RelayClient(session: URLSession(configuration: config))
    }

    private func ftyp(_ brand: String) -> Data {
        var data = Data(repeating: 0, count: 12)
        data.replaceSubrange(4..<8, with: Data("ftyp".utf8))
        data.replaceSubrange(8..<12, with: Data(brand.utf8))
        return data
    }
}

final class RelayURLStub: URLProtocol {
    struct Call {
        var path: String
        var authorization: String?
        var body: Data?
    }

    static var handler: ((URLRequest) throws -> (Int, Data))?
    private static let lock = NSLock()
    private static var recorded: [Call] = []
    static var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func reset() {
        lock.lock()
        recorded = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let call = Call(
            path: request.url?.path ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: Self.body(of: request)
        )
        Self.lock.lock()
        Self.recorded.append(call)
        Self.lock.unlock()

        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://100.127.247.83/")!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 2048)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
