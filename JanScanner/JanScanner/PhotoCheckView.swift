import PhotosUI
import SwiftUI

/// 「写真で確認」モード：写真を中継サーバーに送り、バーコードの有無と位置を表示する。
struct PhotoCheckView: View {
    @StateObject private var model = PhotoCheckModel()
    @AppStorage(RelayConfig.baseURLKey) private var baseURL = RelayConfig.defaultBaseURL
    @State private var libraryItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoArea
                    resultArea
                    buttons
                }
                .padding()
            }
            .navigationTitle("写真で確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("設定", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                RelaySettingsView()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    model.check(image, baseURLString: baseURL)
                }
                .ignoresSafeArea()
            }
            .onChange(of: libraryItem) { item in
                guard let item else { return }
                libraryItem = nil
                Task { @MainActor in
                    let data = try? await item.loadTransferable(type: Data.self)
                    model.check(imageData: data, baseURLString: baseURL)
                }
            }
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let photo = model.photo {
            AnnotatedPhoto(image: photo, unitBox: model.result?.boxToDraw)
                .frame(maxHeight: 420)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 240)
                .overlay {
                    if model.status == .sending {
                        ProgressView("写真を準備しています…")
                    } else {
                        Text("写真を撮るか、ライブラリから選んでください")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .sending:
            if model.photo != nil {
                ProgressView("確認しています…")
            }
        case .done(let result):
            VStack(spacing: 4) {
                Text(result.summary)
                    .font(.title2.bold())
                    .foregroundStyle(result.hasBarcode ? Color.red : Color.primary)
                if let modelName = result.model {
                    Text(modelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                showCamera = true
            } label: {
                Label("写真を撮る", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!CameraPicker.isAvailable)

            PhotosPicker(selection: $libraryItem, matching: .images) {
                Label("ライブラリ", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .disabled(model.status == .sending)
        .controlSize(.large)
    }
}

/// 正立させた写真の上に、0〜1の割合で指定された位置に赤枠を重ねる。
struct AnnotatedPhoto: View {
    let image: UIImage
    let unitBox: CGRect?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                // overlay の大きさ ＝ 画面に表示されている写真の大きさ
                GeometryReader { geo in
                    if let box = unitBox {
                        Rectangle()
                            .stroke(Color.red, lineWidth: 3)
                            .frame(width: box.width * geo.size.width,
                                   height: box.height * geo.size.height)
                            .position(x: box.midX * geo.size.width,
                                      y: box.midY * geo.size.height)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
