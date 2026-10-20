import Foundation

/// 写真をリレーへ送り、判定 JSON を返す。合言葉はヘッダ以外に出さない。
final class RelayClient {
    private let healthSession: URLSession
    private let uploadSession: URLSession
    private let ownsSessions: Bool
    /// URLSession が delegate を保持するが、セッションを分けるのでこちらでも持っておく。
    private let delegates: [RedirectStopper]

    init(session: URLSession? = nil) {
        if let session {
            healthSession = session
            uploadSession = session
            ownsSessions = false
            delegates = []
            return
        }
        let healthStopper = RedirectStopper()
        let uploadStopper = RedirectStopper()
        delegates = [healthStopper, uploadStopper]
        healthSession = Self.makeSession(timeout: 10, delegate: healthStopper)
        uploadSession = Self.makeSession(timeout: 120, delegate: uploadStopper)
        ownsSessions = true
    }

    deinit {
        if ownsSessions {
            healthSession.invalidateAndCancel()
            uploadSession.invalidateAndCancel()
        }
        withExtendedLifetime(delegates) {}
    }

    /// 先に認証なしの /health を短い制限時間で叩き、届かなければ写真は送らない。
    func detect(image: Data, mime: String, filename: String,
                baseURL: String? = nil, token explicitToken: String? = nil) async throws -> RelayCheck {
        let token = explicitToken ?? RelayKeychain.token()
        guard let token, !token.isEmpty else { throw RelayFailure.missingToken }
        let endpoint = try RelayEndpoint.make(from: baseURL ?? RelayEndpoint.storedBaseURL()).get()

        try await ping(endpoint.healthURL)
        try Task.checkCancellation()
        let result = try await upload(image, mime: mime, filename: filename,
                                      url: endpoint.barcodeURL, token: token)
        guard let probability = result.hasBarcodeProbability,
              probability.isFinite,
              (0...1).contains(probability) else {
            throw RelayFailure.badResponse
        }
        return RelayCheck(
            verdict: RelayVerdict(probability: probability, box: result.box?.drawable),
            latencyMs: result.latencyMs,
            model: result.model
        )
    }

    private func ping(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        let (data, response) = try await send(request, session: healthSession, stage: .health)
        guard let http = response as? HTTPURLResponse else { throw RelayFailure.badResponse }
        guard http.statusCode == 200 else {
            throw RelayHTTP.failure(status: http.statusCode, data: data, stage: .health)
        }
        struct Health: Decodable { var ok: Bool? }
        guard (try? JSONDecoder().decode(Health.self, from: data))?.ok == true else {
            throw RelayFailure.badResponse
        }
    }

    private func upload(_ image: Data, mime: String, filename: String, url: URL, token: String) async throws -> RelayBarcodeResult {
        let boundary = "JanScanner-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = RelayMultipart.body(image: image, filename: filename, mime: mime, boundary: boundary)

        let (data, response) = try await send(request, session: uploadSession, stage: .upload)
        guard let http = response as? HTTPURLResponse else { throw RelayFailure.badResponse }
        guard http.statusCode == 200 else {
            throw RelayHTTP.failure(status: http.statusCode, data: data, stage: .upload)
        }
        guard let result = try? RelayJSON.decoder.decode(RelayBarcodeResult.self, from: data) else {
            throw RelayFailure.badResponse
        }
        return result
    }

    private func send(_ request: URLRequest, session: URLSession, stage: RequestStage) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw RelayHTTP.map(error, stage: stage)
        } catch let failure as RelayFailure {
            throw failure
        }
    }

    private static func makeSession(timeout: TimeInterval, delegate: URLSessionTaskDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

/// リダイレクト先へ合言葉を送らない。
final class RedirectStopper: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
