import Foundation

/// 「写真で確認」モードの設定値。
enum RelayConfig {
    /// has_barcode_probability がこの値以上なら「コードあり」と判定する
    static let barcodeThreshold = 0.5

    /// 中継サーバーの初期URL（合言葉はここに書かない。キーチェーンだけに保存する）
    static let defaultBaseURL = "http://100.127.247.83:8787"

    /// 中継URLを保存する UserDefaults のキー（URLは秘密情報ではない）
    static let baseURLKey = "relayBaseURL"

    /// 写真送信の待ち時間（秒）
    static let detectTimeout: TimeInterval = 20

    /// 接続テストの待ち時間（秒）
    static let healthTimeout: TimeInterval = 5
}
