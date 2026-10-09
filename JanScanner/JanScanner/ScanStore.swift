import Foundation

struct ScanRecord: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let date: Date
}

/// 読み取り結果を保持し、Documents/jan_codes.csv に自動保存する。
@MainActor
final class ScanStore: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []

    /// 「ファイル」アプリからも見える場所（このiPhone内/JANスキャナー）
    let csvURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("jan_codes.csv")

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    init() {
        load()
    }

    func add(_ code: String) {
        records.append(ScanRecord(code: code, date: Date()))
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    func removeAll() {
        records.removeAll()
        save()
    }

    func contains(_ code: String) -> Bool {
        records.contains { $0.code == code }
    }

    func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    // MARK: - CSV

    private func save() {
        var csv = "No,JANコード,読取日時\r\n"
        for (i, r) in records.enumerated() {
            csv += "\(i + 1),\(r.code),\(formatter.string(from: r.date))\r\n"
        }
        // Excel で文字化けしないよう UTF-8 BOM を付ける
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(csv.utf8))
        do {
            try data.write(to: csvURL, options: .atomic)
        } catch {
            print("CSV保存に失敗しました: \(error)")
        }
    }

    private func load() {
        guard let text = try? String(contentsOf: csvURL, encoding: .utf8) else { return }
        let lines = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .components(separatedBy: .newlines)
            .dropFirst() // ヘッダー行
        records = lines.compactMap { line in
            let cols = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 3 else { return nil }
            return ScanRecord(code: cols[1], date: formatter.date(from: cols[2]) ?? Date())
        }
    }
}
