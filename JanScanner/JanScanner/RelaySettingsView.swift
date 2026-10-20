import SwiftUI

/// 中継サーバーの設定。合言葉はキーチェーンにだけ保存し、保存後は表示しない。
struct RelaySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(RelayConfig.baseURLKey) private var baseURL = RelayConfig.defaultBaseURL
    @State private var newPassphrase = ""
    @State private var isSaved = PassphraseKeychain.isSaved
    @State private var saveMessage: String?
    @State private var testMessage: String?
    @State private var testOK = false
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(RelayConfig.defaultBaseURL, text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("初期値に戻す") { baseURL = RelayConfig.defaultBaseURL }
                        .disabled(baseURL == RelayConfig.defaultBaseURL)
                } header: {
                    Text("中継URL")
                }

                Section {
                    LabeledContent("状態", value: isSaved ? "保存済み" : "未設定")
                    SecureField(isSaved ? "変更するときだけ入力" : "合言葉", text: $newPassphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存") { save() }
                        .disabled(newPassphrase.isEmpty)
                    if isSaved {
                        Button("合言葉を削除", role: .destructive) {
                            PassphraseKeychain.delete()
                            isSaved = PassphraseKeychain.isSaved
                            saveMessage = "削除しました"
                        }
                    }
                    if let saveMessage {
                        Text(saveMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("合言葉")
                } footer: {
                    Text("合言葉はこのiPhoneのキーチェーンにだけ保存され、保存後は表示されません。")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("接続テスト")
                            if testing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testing)
                    if let testMessage {
                        Label(testMessage,
                              systemImage: testOK ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(testOK ? Color.green : Color.orange)
                    }
                } footer: {
                    Text("/health に接続できるかを確かめます（合言葉は確認しません）。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let value = newPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        newPassphrase = ""
        guard !value.isEmpty else { return }
        do {
            try PassphraseKeychain.save(value)
            saveMessage = "保存しました"
        } catch {
            saveMessage = error.localizedDescription
        }
        isSaved = PassphraseKeychain.isSaved
    }

    @MainActor
    private func testConnection() async {
        testing = true
        defer { testing = false }
        testMessage = nil
        guard let client = RelayClient(baseURLString: baseURL) else {
            testOK = false
            testMessage = RelayError.invalidURL.localizedDescription
            return
        }
        do {
            try await client.health()
            testOK = true
            testMessage = "接続できました"
        } catch {
            testOK = false
            testMessage = RelayError.from(error).localizedDescription
        }
    }
}
