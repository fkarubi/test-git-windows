import Foundation

/// Mac で動いている中継サーバーとの通信。
/// 合言葉は呼び出しごとに受け取り、保持・ログ出力はしない。
struct RelayClient {
    let baseURL: URL
    var session: URLSession = .shared

    /// 入力された文字列から作る。http/https とホストがなければ nil。
    init?(baseURLString: String, session: URLSession = .shared) {
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        self.baseURL = url
        self.session = session
    }

    /// POST /barcode に JPEG を送り、判定結果を返す。
    func detect(jpeg: Data, passphrase: String) async throws -> BarcodeResult {
        guard !passphrase.isEmpty else { throw RelayError.missingPassphrase }

        let form = MultipartForm()
        var request = URLRequest(url: baseURL.appendingPathComponent("barcode"))
        request.httpMethod = "POST"
        request.timeoutInterval = RelayConfig.detectTimeout
        request.setValue("Bearer \(passphrase)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = form.body(fieldName: "photo", filename: "photo.jpg", mimeType: "image/jpeg", data: jpeg)

        let data = try await send(request)
        do {
            return try JSONDecoder().decode(BarcodeResult.self, from: data)
        } catch {
            throw RelayError.badResponse
        }
    }

    /// GET /health（認証なし）。{"ok":true} なら成功。
    func health() async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = RelayConfig.healthTimeout
        let data = try await send(request)

        struct Health: Decodable { let ok: Bool }
        guard (try? JSONDecoder().decode(Health.self, from: data))?.ok == true else {
            throw RelayError.badResponse
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RelayError.from(error)
        }
        guard let http = response as? HTTPURLResponse else { throw RelayError.badResponse }
        if let error = RelayError.from(status: http.statusCode) { throw error }
        return data
    }
}
