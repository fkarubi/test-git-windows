import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RelayPhotoView: View {
    @StateObject private var model = RelayPhotoModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 16) {
            preview
            status
            buttons
            Text("TailscaleでMacに接続している必要があります。URLと合言葉は右上の設定から入れます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .navigationTitle("写真で確認")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("リレー設定")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                RelaySettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $model.showLibrary) {
            LibraryPicker(isPresented: $model.showLibrary) { image, data in
                model.submit(image: image, fileData: data)
            }
        }
        .sheet(isPresented: $model.showCamera) {
            CameraPicker(isPresented: $model.showCamera) { image in
                model.submit(image: image, fileData: nil)
            }
        }
        .onDisappear {
            // 設定や写真選択のシートでは送受信を止めない。画面を閉じたときだけ止める。
            if !showSettings && !model.showCamera && !model.showLibrary {
                model.cancel()
            }
        }
    }

    private var preview: some View {
        Color.black
            .overlay {
                if let image = model.image {
                    GeometryReader { geo in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.width, height: geo.size.height)
                            if let box = model.boxToDraw,
                               let rect = BoxOverlay.rect(box: box, imageSize: image.size, in: geo.size) {
                                Rectangle()
                                    .stroke(.red, lineWidth: 2)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                } else {
                    Text("写真を撮るか、ライブラリから選んでください")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .overlay {
                if model.phase == .sending {
                    ProgressView("送信中…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(height: 360)
            .clipped()
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .sending:
            EmptyView()
        case .success(let check):
            VStack(spacing: 4) {
                Text(check.verdict.title)
                    .font(.headline)
                Text(check.verdict.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let meta = metaLine(check) {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        case .failure(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            actionButtons
            if !model.cameraAvailable {
                Text("この端末にはカメラがありません。写真を選んでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.openCamera()
            } label: {
                Label("写真を撮る", systemImage: "camera")
            }
            .disabled(!model.cameraAvailable || model.phase == .sending)

            Button {
                model.showLibrary = true
            } label: {
                Label("写真を選ぶ", systemImage: "photo.on.rectangle")
            }
            .disabled(model.phase == .sending)
        }
        .buttonStyle(.borderedProminent)
    }

    private func metaLine(_ check: RelayCheck) -> String? {
        let name = check.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelName = name.isEmpty ? nil : name
        switch (modelName, check.latencyMs) {
        case let (name?, latency?):
            return "\(name) · \(latency) ms"
        case let (name?, nil):
            return name
        case let (nil, latency?):
            return "\(latency) ms"
        case (nil, nil):
            return nil
        }
    }
}

@MainActor
final class RelayPhotoModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case sending
        case success(RelayCheck)
        case failure(String)
    }

    @Published var image: UIImage?
    @Published var phase: Phase = .idle
    @Published var showCamera = false
    @Published var showLibrary = false

    var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var boxToDraw: DrawableBox? {
        if case .success(let check) = phase { return check.verdict.boxToDraw }
        return nil
    }

    private let client: RelayClient
    private var task: Task<Void, Never>?

    init(client: RelayClient = RelayClient()) {
        self.client = client
    }

    func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.showCamera = true
                    } else {
                        self.phase = .failure(Self.cameraDenied)
                    }
                }
            }
        case .denied, .restricted:
            phase = .failure(Self.cameraDenied)
        @unknown default:
            phase = .failure(Self.cameraDenied)
        }
    }

    func submit(image: UIImage?, fileData: Data?) {
        guard let image else {
            self.image = nil
            phase = .failure("この写真は読み取れませんでした。別の写真を選んでください。")
            return
        }
        self.image = RelayImageEncoding.scaledForDisplay(image)
        switch RelayImageEncoding.prepare(uiImage: image, fileData: fileData) {
        case .ready(let payload):
            send(payload)
        case .tooLarge:
            phase = .failure(RelayFailure.tooLarge.message)
        case .unreadable:
            phase = .failure("この写真は読み取れませんでした。JPEG、PNG、HEICを選んでください。")
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func send(_ payload: RelayImageEncoding.Payload) {
        task?.cancel()
        phase = .sending
        task = Task {
            do {
                let check = try await client.detect(image: payload.data, mime: payload.mime, filename: payload.filename)
                if Task.isCancelled { return }
                phase = .success(check)
            } catch is CancellationError {
                return
            } catch let failure as RelayFailure {
                if Task.isCancelled { return }
                phase = .failure(failure.message)
            } catch {
                if Task.isCancelled { return }
                phase = .failure(RelayFailure.network.message)
            }
        }
    }

    private static let cameraDenied = "カメラへのアクセスが許可されていません。「設定」>「JANスキャナー」でカメラをオンにしてください。"
}

struct LibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage?, Data?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        @Binding var isPresented: Bool
        var onPick: (UIImage?, Data?) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (UIImage?, Data?) -> Void) {
            _isPresented = isPresented
            self.onPick = onPick
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                isPresented = false
                return
            }
            let finish: (UIImage?, Data?) -> Void = { image, data in
                Task { @MainActor in
                    self.onPick(image, data)
                    self.isPresented = false
                }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    let image = data.flatMap { UIImage(data: $0) }
                    finish(image, data)
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    finish(object as? UIImage, nil)
                }
            } else {
                finish(nil, nil)
            }
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        @Binding var isPresented: Bool
        var onPick: (UIImage?) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (UIImage?) -> Void) {
            _isPresented = isPresented
            self.onPick = onPick
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onPick(image)
            isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented = false
        }
    }
}
