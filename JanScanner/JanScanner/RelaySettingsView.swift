import SwiftUI

/// URL は UserDefaults、合言葉はキーチェーン。合言葉は表示しない。
struct RelaySettingsView: View {
    @AppStorage(RelayEndpoint.urlDefaultsKey) private var baseURL = RelayEndpoint.defaultBaseURL
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var notice: String?

    var body: some View {
        Form {
            Section {
                TextField("http://100.x.x.x:8787", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("リレーのURL")
            } footer: {
                Text("初期値はMacのTailscaleアドレスです。MagicDNS（http://名前.tailnet.ts.net:8787）も使えます。末尾の /barcode は付けなくて構いません。")
            }

            Section {
                SecureField("新しい合言葉", text: $tokenDraft)
                Button("合言葉を保存") { saveToken() }
                    .disabled(RelayKeychain.normalize(tokenDraft).isEmpty)
                if hasToken {
                    Button("合言葉を削除", role: .destructive) { deleteToken() }
                }
            } header: {
                Text("合言葉")
            } footer: {
                Text(hasToken
                     ? "キーチェーンに保存済みです。変えるときだけ入力してください。保存した合言葉は再表示しません。"
                     : "未設定です。Macのキーチェーンに入れた合言葉を貼り付けて保存してください。")
            }

            if let notice {
                Section {
                    Text(notice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("リレー設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasToken = RelayKeychain.token() != nil
            let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                baseURL = RelayEndpoint.defaultBaseURL
            }
        }
        .onDisappear {
            let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = trimmed.isEmpty ? RelayEndpoint.defaultBaseURL : trimmed
        }
    }

    private func saveToken() {
        do {
            try RelayKeychain.save(tokenDraft)
            tokenDraft = ""
            hasToken = true
            notice = "キーチェーンに保存しました。"
        } catch let error as RelayKeychainError {
            notice = error.message
        } catch {
            notice = RelayKeychainError.failed.message
        }
    }

    private func deleteToken() {
        RelayKeychain.delete()
        tokenDraft = ""
        hasToken = false
        notice = "合言葉を削除しました。"
    }
}
