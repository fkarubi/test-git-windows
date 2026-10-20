import CoreGraphics
import Foundation

/// これ以上を「バーコードあり」とみなす。枠を描くかどうかもこの値だけで決める。
enum RelayVerdict: Equatable {
    static let presenceThreshold = 0.5

    case present(probability: Double, box: DrawableBox?)
    case absent(probability: Double)

    init(probability: Double, box: DrawableBox?) {
        if probability >= Self.presenceThreshold {
            self = .present(probability: probability, box: box)
        } else {
            self = .absent(probability: probability)
        }
    }

    var probability: Double {
        switch self {
        case .present(let probability, _), .absent(let probability):
            return probability
        }
    }

    /// 「あり」のときだけ枠を返す。「なし」では箱が来ても描かない。
    var boxToDraw: DrawableBox? {
        if case .present(_, let box) = self { return box }
        return nil
    }

    var title: String {
        switch self {
        case .present(let probability, _):
            return "バーコードあり（\(Self.percent(probability))）"
        case .absent(let probability):
            return "バーコードなし（\(Self.percent(probability))）"
        }
    }

    var detail: String {
        switch self {
        case .present(_, let box) where box == nil:
            return "位置を示す枠は返りませんでした。"
        case .present:
            return "赤い枠がバーコードの位置です。"
        case .absent:
            return "\(Self.percent(Self.presenceThreshold))未満なので、枠は表示していません。"
        }
    }

    static func percent(_ probability: Double) -> String {
        String(format: "%.1f%%", locale: Locale(identifier: "en_US_POSIX"), probability * 100)
    }
}

struct DrawableBox: Equatable {
    var top: Double
    var bottom: Double
    var left: Double
    var right: Double
    var confidence: Double?
}

struct RelayCheck: Equatable {
    var verdict: RelayVerdict
    var latencyMs: Int?
    var model: String?
}

struct RelayBarcodeResult: Decodable, Equatable {
    var hasBarcodeProbability: Double?
    var box: RelayBox?
    var model: String?
    var latencyMs: Int?
}

struct RelayBox: Decodable, Equatable {
    var top: Double?
    var bottom: Double?
    var left: Double?
    var right: Double?
    var confidence: Double?

    var drawable: DrawableBox? {
        guard let top, let bottom, let left, let right,
              [top, bottom, left, right].allSatisfy(\.isFinite),
              (0...1).contains(top), (0...1).contains(bottom),
              (0...1).contains(left), (0...1).contains(right),
              bottom > top, right > left else { return nil }
        return DrawableBox(top: top, bottom: bottom, left: left, right: right, confidence: confidence)
    }
}

enum RelayFailure: Error, Equatable {
    case missingToken
    case invalidURL
    case unsupportedHost
    case timedOut
    case barcodeTimedOut
    case unreachable
    case dns
    case unauthorized
    case badImage(String)
    case tooLarge
    case upstream
    case badResponse
    case transportSecurity
    case network

    var message: String {
        switch self {
        case .missingToken:
            return "合言葉が未設定です。右上の設定から入力して保存してください。"
        case .invalidURL:
            return "リレーのURLが正しくありません。http://100.x.x.x:8787 の形で入力してください。"
        case .unsupportedHost:
            return "このURLには送れません。Tailscaleのアドレス（100.64.0.0〜100.127.255.255）か、MagicDNS名（名前.tailnet.ts.net）を使ってください。"
        case .timedOut:
            return "接続がタイムアウトしました。iPhoneのTailscaleがオフ、または未接続の可能性があります。"
        case .barcodeTimedOut:
            return "リレーには届きましたが、判定が時間内に返りませんでした。もう一度試してください。"
        case .unreachable:
            return "リレーに接続できません。iPhoneのTailscaleが接続中か確認してください。"
        case .dns:
            return "URLのホスト名を解決できません。MagicDNS名の綴りと、Tailscaleの接続を確認してください。"
        case .unauthorized:
            return "合言葉が違います（401）。設定のトークンを確認してください。"
        case .badImage(let detail):
            if detail.isEmpty {
                return "写真を送れませんでした（400）。JPEG、PNG、HEICを選んでください。"
            }
            return "写真を送れませんでした（400）。\(detail)"
        case .tooLarge:
            return "写真が大きすぎます（413）。16MB以下の写真にしてください。"
        case .upstream:
            return "リレーの先でエラーになりました。時間をおいてもう一度試してください。"
        case .badResponse:
            return "リレーの応答を読み取れませんでした。"
        case .transportSecurity:
            return "iOSがこのHTTP接続をブロックしました。URLはTailscaleの100.xアドレスか、MagicDNS名（….ts.net）にしてください。"
        case .network:
            return "通信に失敗しました。iPhoneのTailscaleが接続中か確認してください。"
        }
    }
}

enum BoxOverlay {
    /// 画像全体をコンテナへ aspect-fit したときの、左上原点 0...1 の枠。
    static func rect(box: DrawableBox, imageSize: CGSize, in container: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return nil }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (container.width - fitted.width) / 2,
            y: (container.height - fitted.height) / 2
        )
        return CGRect(
            x: origin.x + fitted.width * box.left,
            y: origin.y + fitted.height * box.top,
            width: fitted.width * (box.right - box.left),
            height: fitted.height * (box.bottom - box.top)
        )
    }
}

enum RelayMultipart {
    static func body(image: Data, filename: String, mime: String, boundary: String) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        let safeName = filename.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        let name = safeName.isEmpty ? "photo.jpg" : safeName
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(name)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(image)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}

enum RelayHTTP {
    static func failure(status: Int, data: Data, stage: RequestStage) -> RelayFailure {
        switch status {
        case 401:
            return .unauthorized
        case 400:
            return .badImage(serverText(data))
        case 413:
            return .tooLarge
        case 200:
            return .badResponse
        default:
            return stage == .health ? .badResponse : .upstream
        }
    }

    /// 400 の本文はサーバーが日本語で返す。トークンや長い詳細は出さない。
    static func serverText(_ data: Data) -> String {
        struct Body: Decodable { var error: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let error = body.error else { return "" }
        if error == "unauthorized" || error == "typesafe_error" { return "" }
        let lowered = error.lowercased()
        if lowered.contains("bearer") || lowered.contains("token") || lowered.contains("api") {
            return ""
        }
        guard error.count <= 180 else { return "" }
        return error
    }

    static func map(_ error: URLError, stage: RequestStage) -> Error {
        if error.code == .cancelled { return CancellationError() }
        if error.code == .appTransportSecurityRequiresSecureConnection {
            return RelayFailure.transportSecurity
        }
        switch error.code {
        case .timedOut:
            return stage == .health ? RelayFailure.timedOut : RelayFailure.barcodeTimedOut
        case .cannotFindHost, .dnsLookupFailed:
            return RelayFailure.dns
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
             .dataNotAllowed, .internationalRoamingOff:
            return RelayFailure.unreachable
        default:
            return RelayFailure.network
        }
    }
}

enum RequestStage {
    case health
    case upload
}

enum RelayJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
