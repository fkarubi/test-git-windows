import CoreGraphics
import Foundation

/// 中継サーバーが返すバーコードの位置。0〜1の割合で、左上が原点。
struct BarcodeBox: Decodable, Equatable {
    let top: Double
    let bottom: Double
    let left: Double
    let right: Double
    /// サーバーが null を返すこともある
    let confidence: Double?

    /// 0〜1に収めた枠。幅か高さがないときは nil。
    var unitRect: CGRect? {
        let l = min(max(left, 0), 1), r = min(max(right, 0), 1)
        let t = min(max(top, 0), 1), b = min(max(bottom, 0), 1)
        guard r > l, b > t else { return nil }
        return CGRect(x: l, y: t, width: r - l, height: b - t)
    }
}

/// POST /barcode の返り値。box_px と image は表示に使わないので読まない。
struct BarcodeResult: Decodable, Equatable {
    let hasBarcodeProbability: Double
    let box: BarcodeBox?
    let model: String?
    let latencyMs: Double?

    enum CodingKeys: String, CodingKey {
        case hasBarcodeProbability = "has_barcode_probability"
        case box
        case model
        case latencyMs = "latency_ms"
    }

    init(hasBarcodeProbability: Double, box: BarcodeBox?, model: String? = nil, latencyMs: Double? = nil) {
        self.hasBarcodeProbability = hasBarcodeProbability
        self.box = box
        self.model = model
        self.latencyMs = latencyMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasBarcodeProbability = try c.decode(Double.self, forKey: .hasBarcodeProbability)
        // box が null・欠けている・形が違う場合も、判定結果だけは表示できるようにする
        box = try? c.decodeIfPresent(BarcodeBox.self, forKey: .box)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        latencyMs = try? c.decodeIfPresent(Double.self, forKey: .latencyMs)
    }

    var hasBarcode: Bool {
        hasBarcodeProbability >= RelayConfig.barcodeThreshold
    }

    /// 赤枠を描く位置。「コードなし」のときは描かない。
    var boxToDraw: CGRect? {
        hasBarcode ? box?.unitRect : nil
    }

    var summary: String {
        if hasBarcode {
            let percent = Int((hasBarcodeProbability * 100).rounded())
            return "コードあり（確率\(percent)%）"
        }
        return "コードなし"
    }
}

/// 中継サーバーとの通信エラー。表示する文言は日本語。
enum RelayError: LocalizedError, Equatable {
    case missingPassphrase
    case invalidURL
    case unreachable
    case blockedByATS
    case unauthorized
    case http(Int)
    case badResponse
    case invalidImage
    case other(String)

    var errorDescription: String? {
        switch self {
        case .missingPassphrase:
            return "設定画面で合言葉を保存してください"
        case .invalidURL:
            return "中継URLが正しくありません（例: http://100.127.247.83:8787）"
        case .unreachable:
            return "つながりません。iPhoneのTailscaleがオンか確認してください"
        case .blockedByATS:
            return "iOSの通信設定（ATS）で止められました。中継URLのホストが許可されているか確認してください"
        case .unauthorized:
            return "合言葉が違います"
        case .http(let code):
            return "エラー \(code)：\(Self.describe(status: code))"
        case .badResponse:
            return "サーバーの返事を読み取れませんでした"
        case .invalidImage:
            return "写真を読み込めませんでした"
        case .other(let message):
            return message
        }
    }

    private static func describe(status: Int) -> String {
        switch status {
        case 400: return "画像が不正か、小さすぎます"
        case 404: return "中継URLが違う可能性があります"
        case 413: return "画像が大きすぎます"
        case 500...599: return "中継サーバーの先（上流）でエラーが起きました"
        default: return "サーバーがエラーを返しました"
        }
    }

    /// HTTPステータスからエラーを作る。成功（2xx）なら nil。
    static func from(status: Int) -> RelayError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        default: return .http(status)
        }
    }

    /// URLSession のエラーを表示用に変換する。
    static func from(_ error: Error) -> RelayError {
        if let relay = error as? RelayError { return relay }
        guard let urlError = error as? URLError else {
            return .other(error.localizedDescription)
        }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed:
            return .unreachable
        case .appTransportSecurityRequiresSecureConnection:
            return .blockedByATS
        default:
            return .other("通信エラー（\(urlError.code.rawValue)）")
        }
    }
}
