import UIKit

/// 送信前の写真の準備。
/// 向きを正立に直した画像を JPEG にして送り、表示にも同じ画像を使う。
/// こうするとサーバーが正立させた画像と表示が一致し、赤枠がずれない。
enum PhotoPreparer {
    /// 長辺がこれより大きい写真だけ縮小する（通信量を抑えるため。細かい縮小はサーバー側で行う）
    static let maxLongEdge: CGFloat = 4032
    static let jpegQuality: CGFloat = 0.9

    static func prepare(_ image: UIImage) -> (image: UIImage, jpeg: Data)? {
        // image.size は向きを反映した大きさ（ポイント）なので、ピクセルに直す
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let longEdge = max(pixelSize.width, pixelSize.height)
        let ratio = min(1, maxLongEdge / longEdge)
        let target = CGSize(width: (pixelSize.width * ratio).rounded(),
                            height: (pixelSize.height * ratio).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = upright.jpegData(compressionQuality: jpegQuality) else { return nil }
        return (upright, jpeg)
    }
}
