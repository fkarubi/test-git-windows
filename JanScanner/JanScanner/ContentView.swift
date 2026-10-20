import AudioToolbox
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var store: ScanStore
    @AppStorage("allowDuplicates") private var allowDuplicates = false
    @State private var banner: String?
    @State private var showClearConfirm = false
    @State private var showRelay = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scanner
                list
            }
            .navigationTitle("JANスキャナー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Toggle("重複を許可", isOn: $allowDuplicates)
                        Button("すべて削除", role: .destructive) { showClearConfirm = true }
                            .disabled(store.records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showRelay = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .accessibilityLabel("写真で確認")
                    ShareLink(item: store.csvURL) {
                        Label("CSV共有", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.records.isEmpty)
                }
            }
            .navigationDestination(isPresented: $showRelay) {
                RelayPhotoView()
            }
            .confirmationDialog("読み取ったコードをすべて削除しますか？",
                                isPresented: $showClearConfirm,
                                titleVisibility: .visible) {
                Button("すべて削除", role: .destructive) { store.removeAll() }
            }
        }
    }

    private var scanner: some View {
        BarcodeScannerView(onScan: handleScan)
            .frame(height: 260)
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.red, lineWidth: 2)
                    .frame(width: 260, height: 110)
            }
            .overlay(alignment: .bottom) {
                if let banner {
                    Text(banner)
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
    }

    private var list: some View {
        List {
            Section {
                ForEach(Array(store.records.enumerated().reversed()), id: \.element.id) { index, record in
                    HStack {
                        Text("\(index + 1)")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(record.code)
                            .font(.body.monospacedDigit())
                        Spacer()
                        Text(store.format(record.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    // 表示は新しい順なので元のインデックスに変換する
                    let count = store.records.count
                    store.delete(at: IndexSet(offsets.map { count - 1 - $0 }))
                }
            } header: {
                Text("読み取り件数: \(store.records.count)")
            } footer: {
                Text("CSVは自動保存されます（ファイル > このiPhone内 > JANスキャナー > jan_codes.csv）")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func handleScan(_ code: String) {
        if !allowDuplicates && store.contains(code) {
            show("登録済み: \(code)")
            AudioServicesPlaySystemSound(1521) // 短い振動
            return
        }
        store.add(code)
        show("追加: \(code)")
        AudioServicesPlaySystemSound(1057) // ピッ
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func show(_ text: String) {
        withAnimation { banner = text }
        let current = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if banner == current { withAnimation { banner = nil } }
        }
    }
}
