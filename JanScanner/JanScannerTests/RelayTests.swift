import XCTest
@testable import JanScanner

/// 中継サーバーとのやりとりのテスト（実際の通信・写真は使わない）。
final class RelayTests: XCTestCase {

    // MARK: - 返り値の読み取り

    func testDecodesSampleResponse() throws {
        let json = """
        {"has_barcode_probability":0.99,
         "box":{"top":0.43,"bottom":0.59,"left":0.48,"right":0.69,"confidence":0.73},
         "box_px":{"top":506,"bottom":694,"left":753,"right":1082},
         "image":{"width":1568,"height":1176},
         "model":"jev-1.14.0","latency_ms":951}
        """
        let result = try JSONDecoder().decode(BarcodeResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.hasBarcodeProbability, 0.99)
        XCTAssertEqual(result.box?.confidence, 0.73)
        XCTAssertEqual(result.model, "jev-1.14.0")
        XCTAssertTrue(result.hasBarcode)
        XCTAssertEqual(result.summary, "コードあり（確率99%）")

        let rect = try XCTUnwrap(result.boxToDraw)
        XCTAssertEqual(rect.minX, 0.48, accuracy: 1e-9)
        XCTAssertEqual(rect.minY, 0.43, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 0.21, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 0.16, accuracy: 1e-9)
    }

    func testConfidenceCanBeNull() throws {
        let json = """
        {"has_barcode_probability":0.8,
         "box":{"top":0.1,"bottom":0.2,"left":0.1,"right":0.2,"confidence":null}}
        """
        let result = try JSONDecoder().decode(BarcodeResult.self, from: Data(json.utf8))
        XCTAssertNil(result.box?.confidence)
        XCTAssertNotNil(result.boxToDraw)
    }

    func testBoxCanBeNullOrMissing() throws {
        for json in [#"{"has_barcode_probability":0.1,"box":null}"#,
                     #"{"has_barcode_probability":0.1}"#] {
            let result = try JSONDecoder().decode(BarcodeResult.self, from: Data(json.utf8))
            XCTAssertNil(result.box)
            XCTAssertEqual(result.summary, "コードなし")
        }
    }

    // MARK: - しきい値

    func testThreshold() {
        let box = BarcodeBox(top: 0.1, bottom: 0.2, left: 0.1, right: 0.2, confidence: nil)
        let at = BarcodeResult(hasBarcodeProbability: RelayConfig.barcodeThreshold, box: box)
        XCTAssertTrue(at.hasBarcode)
        XCTAssertNotNil(at.boxToDraw)

        let below = BarcodeResult(hasBarcodeProbability: RelayConfig.barcodeThreshold - 0.01, box: box)
        XCTAssertFalse(below.hasBarcode)
        XCTAssertNil(below.boxToDraw, "コードなしのときは枠を描かない")
        XCTAssertEqual(below.summary, "コードなし")
    }

    func testInvalidBoxIsNotDrawn() {
        let flipped = BarcodeBox(top: 0.5, bottom: 0.4, left: 0.1, right: 0.2, confidence: nil)
        XCTAssertNil(flipped.unitRect)

        let outside = BarcodeBox(top: -0.2, bottom: 1.3, left: 0.9, right: 1.5, confidence: nil)
        let rect = outside.unitRect
        XCTAssertEqual(rect?.minX ?? -1, 0.9, accuracy: 1e-9)
        XCTAssertEqual(rect?.maxX ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(rect?.minY ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(rect?.maxY ?? -1, 1, accuracy: 1e-9)
    }

    // MARK: - エラー表示

    func testStatusErrors() {
        XCTAssertNil(RelayError.from(status: 200))
        XCTAssertEqual(RelayError.from(status: 401)?.errorDescription, "合言葉が違います")
        XCTAssertEqual(RelayError.from(status: 400)?.errorDescription, "エラー 400：画像が不正か、小さすぎます")
        XCTAssertEqual(RelayError.from(status: 413)?.errorDescription, "エラー 413：画像が大きすぎます")
        XCTAssertEqual(RelayError.from(status: 502)?.errorDescription, "エラー 502：中継サーバーの先（上流）でエラーが起きました")
    }

    func testTimeoutMessage() {
        XCTAssertEqual(RelayError.from(URLError(.timedOut)).errorDescription,
                       "つながりません。iPhoneのTailscaleがオンか確認してください")
    }

    // MARK: - 送信内容

    func testBaseURLParsing() {
        XCTAssertEqual(RelayClient(baseURLString: " http://100.127.247.83:8787/ ")?.baseURL.absoluteString,
                       "http://100.127.247.83:8787")
        XCTAssertNil(RelayClient(baseURLString: "100.127.247.83:8787"))
        XCTAssertNil(RelayClient(baseURLString: "ftp://example.com"))
    }

    func testDetectSendsBearerAndMultipart() async throws {
        let session = StubURLProtocol.session { request, body in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "http://100.127.247.83:8787/barcode")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-word")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?
                .hasPrefix("multipart/form-data; boundary=") == true)
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(text.contains(#"name="photo"; filename="photo.jpg""#))
            XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
            return (200, #"{"has_barcode_probability":0.2,"box":null}"#)
        }
        let client = try XCTUnwrap(RelayClient(baseURLString: RelayConfig.defaultBaseURL, session: session))
        // 画像の中身は確認しないので、ダミーのバイト列で十分
        let result = try await client.detect(jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), passphrase: "test-word")
        XCTAssertFalse(result.hasBarcode)
    }

    func testDetect401() async throws {
        let session = StubURLProtocol.session { _, _ in (401, #"{"error":"unauthorized"}"#) }
        let client = try XCTUnwrap(RelayClient(baseURLString: RelayConfig.defaultBaseURL, session: session))
        do {
            _ = try await client.detect(jpeg: Data([0xFF]), passphrase: "wrong")
            XCTFail("401 ならエラーになるはず")
        } catch {
            XCTAssertEqual(error as? RelayError, .unauthorized)
        }
    }

    func testDetectWithoutPassphraseDoesNotSend() async throws {
        let session = StubURLProtocol.session { _, _ in
            XCTFail("合言葉がないときは送信しない")
            return (200, "{}")
        }
        let client = try XCTUnwrap(RelayClient(baseURLString: RelayConfig.defaultBaseURL, session: session))
        do {
            _ = try await client.detect(jpeg: Data([0xFF]), passphrase: "")
            XCTFail()
        } catch {
            XCTAssertEqual(error as? RelayError, .missingPassphrase)
        }
    }

    func testHealth() async throws {
        let session = StubURLProtocol.session { request, _ in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/health")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "health は認証なし")
            return (200, #"{"ok":true}"#)
        }
        let client = try XCTUnwrap(RelayClient(baseURLString: RelayConfig.defaultBaseURL, session: session))
        try await client.health()
    }
}

/// 実際には通信せず、決まった返事を返す URLProtocol。
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest, Data) -> (Int, String)
    private static var handler: Handler?

    static func session(_ handler: @escaping Handler) -> URLSession {
        self.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let (status, json) = Self.handler?(request, body) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
