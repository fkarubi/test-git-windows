import UIKit

/// 送信用の画像。店やお客様の写真はテストに使わない。
enum RelayImageEncoding {
    static let maxBytes = 15 * 1024 * 1024

    struct Payload: Equatable {
        var data: Data
        var mime: String
        var filename: String
    }

    enum Prepare: Equatable {
        case ready(Payload)
        case tooLarge
        case unreadable
    }

    static func prepare(uiImage: UIImage, fileData: Data?) -> Prepare {
        if let fileData, fileData.count <= maxBytes, let kind = ImageKind(data: fileData) {
            return .ready(Payload(data: fileData, mime: kind.mime, filename: kind.filename))
        }
        guard let jpeg = compressedJPEG(uiImage) else {
            return fileData.map { $0.count > maxBytes } == true ? .tooLarge : .unreadable
        }
        if jpeg.count > maxBytes { return .tooLarge }
        return .ready(Payload(data: jpeg, mime: "image/jpeg", filename: "photo.jpg"))
    }

    /// 表示用。向きをピクセルに焼き、長辺を揃える。枠の比率は変わらない。
    static func scaledForDisplay(_ image: UIImage, maxPixel: CGFloat = 2048) -> UIImage {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        guard longest > maxPixel, longest > 0 else { return image }
        let ratio = maxPixel / longest
        let newSize = CGSize(width: max(1, floor(pixelW * ratio)), height: max(1, floor(pixelH * ratio)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let original = max(pixelW, pixelH)
        guard original > 0 else { return nil }
        var sides: [CGFloat] = []
        if original <= 4096 { sides.append(original) }
        for candidate in [CGFloat(2048), 1600, 1280, 1024] where candidate < original - 0.5 {
            sides.append(candidate)
        }
        if sides.isEmpty { sides = [2048] }
        for side in sides {
            let scaled = scaledForDisplay(image, maxPixel: side)
            for quality in [CGFloat(0.85), 0.7, 0.55] {
                if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes {
                    return data
                }
            }
        }
        return nil
    }
}

enum ImageKind: Equatable {
    case jpeg
    case png
    case heic

    var mime: String {
        switch self {
        case .jpeg: return "image/jpeg"
        case .png: return "image/png"
        case .heic: return "image/heic"
        }
    }

    var filename: String {
        switch self {
        case .jpeg: return "photo.jpg"
        case .png: return "photo.png"
        case .heic: return "photo.heic"
        }
    }

    init?(data: Data) {
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
            return
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            self = .png
            return
        }
        if Self.isHEIC(data) {
            self = .heic
            return
        }
        return nil
    }

    private static func isHEIC(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        guard String(data: data.subdata(in: 4..<8), encoding: .ascii) == "ftyp" else { return false }
        let brand = String(data: data.subdata(in: 8..<12), encoding: .ascii) ?? ""
        return ["heic", "heix", "hevc", "hevx", "heim", "heis", "heif", "mif1", "msf1"].contains(brand)
    }
}
