import SwiftUI
import UIKit

/// 「写真で確認」モードの状態。写真の準備・送信・結果を持つ。
@MainActor
final class PhotoCheckModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case sending
        case done(BarcodeResult)
        case failed(String)
    }

    @Published private(set) var photo: UIImage?
    @Published private(set) var status: Status = .idle

    private var task: Task<Void, Never>?

    var result: BarcodeResult? {
        if case .done(let result) = status { return result }
        return nil
    }

    func check(_ original: UIImage, baseURLString: String) {
        task?.cancel()
        photo = nil
        status = .sending

        task = Task {
            // 正立化と JPEG 変換は重いのでメインスレッド以外で行う
            let prepared = await Task.detached(priority: .userInitiated) {
                PhotoPreparer.prepare(original)
            }.value
            guard !Task.isCancelled else { return }
            guard let prepared else {
                status = .failed(RelayError.invalidImage.localizedDescription)
                return
            }
            photo = prepared.image

            do {
                guard let client = RelayClient(baseURLString: baseURLString) else {
                    throw RelayError.invalidURL
                }
                guard let passphrase = PassphraseKeychain.load(), !passphrase.isEmpty else {
                    throw RelayError.missingPassphrase
                }
                let result = try await client.detect(jpeg: prepared.jpeg, passphrase: passphrase)
                guard !Task.isCancelled else { return }
                status = .done(result)
            } catch {
                guard !Task.isCancelled else { return }
                status = .failed(RelayError.from(error).localizedDescription)
            }
        }
    }

    /// ライブラリで選んだ写真のデータから確認する
    func check(imageData: Data?, baseURLString: String) {
        guard let imageData, let image = UIImage(data: imageData) else {
            task?.cancel()
            photo = nil
            status = .failed(RelayError.invalidImage.localizedDescription)
            return
        }
        check(image, baseURLString: baseURLString)
    }
}
