import Foundation

/// リレーのベースURL。合言葉はここには置かない。
enum RelayEndpoint {
    static let urlDefaultsKey = "relayBaseURL"
    static let defaultBaseURL = "http://100.127.247.83:8787"

    let barcodeURL: URL
    let healthURL: URL

    static func storedBaseURL() -> String {
        let stored = UserDefaults.standard.string(forKey: urlDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        return defaultBaseURL
    }

    static func make(from raw: String?) -> Result<RelayEndpoint, RelayFailure> {
        var text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = defaultBaseURL }
        if !text.contains("://") { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              var host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased(),
              !host.isEmpty else {
            return .failure(.invalidURL)
        }
        if host.hasSuffix(".") { host.removeLast() }
        guard TailscaleHost.isAllowed(host) else { return .failure(.unsupportedHost) }

        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path == "/barcode" || path == "/health" { path = "" }
        guard path.isEmpty else { return .failure(.invalidURL) }

        components.path = "/barcode"
        guard let barcodeURL = components.url else { return .failure(.invalidURL) }
        components.path = "/health"
        guard let healthURL = components.url else { return .failure(.invalidURL) }
        return .success(RelayEndpoint(barcodeURL: barcodeURL, healthURL: healthURL))
    }
}

/// Tailscale の宛先だけを許す。ATS の例外範囲と揃えている。
enum TailscaleHost {
    /// 100.64.0.0/10（CGNAT。Tailscale の IPv4）
    static func isCGNAT(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { octet -> Int? in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isNumber),
                  let value = Int(octet), (0...255).contains(value) else { return nil }
            return value
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    /// MagicDNS は `名前.tailnet.ts.net`。`ts.net` 単体は不可。
    static func isMagicDNS(_ host: String) -> Bool {
        let host = host.lowercased()
        guard host.hasSuffix(".ts.net"), host != "ts.net", !host.contains("..") else { return false }
        return host.split(separator: ".").count >= 3
    }

    static func isAllowed(_ host: String) -> Bool {
        isCGNAT(host) || isMagicDNS(host)
    }
}
