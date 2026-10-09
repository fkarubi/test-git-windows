import Foundation

/// JAN（EAN-13 / EAN-8）コードのチェックデジット検証。
enum JANCode {
    static func isValid(_ code: String) -> Bool {
        guard code.count == 13 || code.count == 8,
              code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }

        let digits = code.compactMap { $0.wholeNumberValue }
        let body = digits.dropLast()
        // 右端（チェックデジットの左隣）から奇数桁に3、偶数桁に1を掛ける
        var sum = 0
        for (i, d) in body.reversed().enumerated() {
            sum += d * (i % 2 == 0 ? 3 : 1)
        }
        let check = (10 - sum % 10) % 10
        return check == digits.last
    }
}
