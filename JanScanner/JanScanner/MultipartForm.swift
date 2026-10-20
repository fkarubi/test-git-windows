import Foundation

/// multipart/form-data の本文を組み立てる。
struct MultipartForm {
    let boundary = "JanScanner-\(UUID().uuidString)"

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    func body(fieldName: String, filename: String, mimeType: String, data: Data) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
