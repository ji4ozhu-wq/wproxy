import SwiftUI
import AVFoundation
import PhotosUI
import UIKit
import CoreImage

/// Camera / photo-library QR import (spec §5.5).
/// Presented as a full-screen cover with a dark camera backdrop; falls back to the
/// photo picker or clipboard import when the camera is unavailable or denied.
struct ScanQRView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var scanner = QRScannerController()
    @State private var cameraState: CameraState = .checking
    @State private var previewProfile: NodeProfile?
    @State private var previewWarning: String?
    @State private var previewError: String?
    @State private var invalidMessage: String?
    @State private var lastHandledCode: String?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPasteFallback = false
    @State private var didConfigureDebug = false

    private enum CameraState {
        case checking, running, denied, unavailable
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraState == .running {
                CameraPreviewView(session: scanner.session)
                    .ignoresSafeArea()
            }
            content
            if let previewProfile {
                previewOverlay(profile: previewProfile)
            }
        }
        .preferredColorScheme(.dark)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onAppear(perform: configureCamera)
        .onDisappear { scanner.stop() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            loadPhoto(item)
        }
        .onChange(of: scenePhase) { _, phase in
            guard cameraState == .running else { return }
            if phase == .active {
                scanner.start()
            } else {
                scanner.stop()
            }
        }
        .onReceive(scanner.$code.compactMap { $0 }) { code in
            handleScannedCode(code)
        }
        .sheet(isPresented: $showPasteFallback) {
            NavigationStack {
                PasteImportView()
            }
        }
    }

    // MARK: - Layout

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            if cameraState == .denied {
                Spacer()
                permissionPanel
                Spacer()
                pasteFallbackButton
                    .padding(.bottom, 8)
            } else {
                Spacer()
                if cameraState != .checking {
                    Text(L10n.t("nodes.scan.hint", table: "Nodes"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                viewfinder
                    .frame(width: 260, height: 260)
                    .padding(.top, 26)
                statusCaption
                Spacer()
            }

            if let invalidMessage {
                Text(invalidMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier("wuji.nodes.scan.error")
            }

            bottomControls
                .padding(.bottom, 24)
        }
    }

    /// Caption under the viewfinder: camera start progress, or the reason there is no feed.
    @ViewBuilder
    private var statusCaption: some View {
        if cameraState == .checking {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text(L10n.t("nodes.scan.starting", table: "Nodes"))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 18)
        } else if cameraState == .unavailable {
            Text(L10n.t("nodes.scan.noCamera", table: "Nodes"))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 18)
                .accessibilityIdentifier("wuji.nodes.scan.unavailableMessage")
        }
    }

    private var closeButton: some View {
        Button {
            scanner.stop()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
        }
        .accessibilityLabel(L10n.t("nodes.scan.close", table: "Nodes"))
        .accessibilityIdentifier("wuji.nodes.scan.closeButton")
    }

    private var viewfinder: some View {
        ViewfinderCorners()
            .accessibilityHidden(true)
    }

    private var permissionPanel: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.8))
            Text(L10n.t("nodes.scan.permissionTitle", table: "Nodes"))
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(L10n.t("nodes.scan.permissionMessage", table: "Nodes"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L10n.t("nodes.scan.openSettings", table: "Nodes"))
                    .font(Theme.buttonLabel)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            .accessibilityIdentifier("wuji.nodes.scan.openSettingsButton")
        }
    }

    private var pasteFallbackButton: some View {
        Button {
            showPasteFallback = true
        } label: {
            Text(L10n.t("nodes.scan.pasteInstead", table: "Nodes"))
                .font(Theme.buttonLabel)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 40)
        .padding(.top, 4)
        .accessibilityIdentifier("wuji.nodes.scan.pasteButton")
    }

    private var bottomControls: some View {
        Button {
            showPhotoPicker = true
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "camera")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Theme.tint)
                    .frame(width: 64, height: 64)
                    .background(Color.white)
                    .clipShape(Circle())
                Text(L10n.t("nodes.scan.choosePhoto", table: "Nodes"))
                    .font(.body)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("nodes.scan.choosePhoto", table: "Nodes"))
        .accessibilityIdentifier("wuji.nodes.scan.choosePhotoButton")
    }

    private func previewOverlay(profile: NodeProfile) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {}
            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t("nodes.scan.recognizedTitle", table: "Nodes"))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                        Text(profile.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.label)
                            .lineLimit(2)
                        Text("\(profile.proto.shortBadge) · \(profile.endpoint)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                        if let previewWarning {
                            Label(previewWarning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("wuji.nodes.scan.warning")
                        }
                        if let previewError {
                            Text(previewError)
                                .font(.caption)
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("wuji.nodes.scan.previewError")
                        }
                    }
                    HStack(spacing: 12) {
                        Button {
                            cancelPreview()
                        } label: {
                            Text(L10n.t("common.cancel"))
                                .font(Theme.buttonLabel)
                                .foregroundStyle(Theme.tint)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wuji.nodes.scan.cancelSaveButton")

                        Button {
                            savePreview(profile)
                        } label: {
                            Text(L10n.t("nodes.scan.save", table: "Nodes"))
                                .font(Theme.buttonLabel)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Theme.tint)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wuji.nodes.scan.saveButton")
                    }
                }
                .padding(20)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, Theme.hMargin)
                .padding(.bottom, 28)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("wuji.nodes.scan.previewCard")
            }
        }
    }

    // MARK: - Camera lifecycle

    private func configureCamera() {
        #if DEBUG
        if !didConfigureDebug {
            didConfigureDebug = true
            if DebugScreenshotRoute.value("-WujiScreenshotPage") == "nodes-scan-preview" {
                cameraState = .unavailable
                previewProfile = Self.debugPreviewProfile(basedOn: app.nodes.first)
                scanner.stop()
                return
            }
        }
        #endif
        guard AVCaptureDevice.default(for: .video) != nil else {
            cameraState = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        startCamera()
                    } else {
                        cameraState = .denied
                    }
                }
            }
        default:
            cameraState = .denied
        }
    }

    private func startCamera() {
        scanner.configureIfNeeded()
        scanner.start()
        cameraState = .running
    }

    // MARK: - Handling results

    private func handleScannedCode(_ code: String) {
        guard previewProfile == nil, code != lastHandledCode else { return }
        lastHandledCode = code
        do {
            let profile = try app.uriParser.parseLink(code, groupID: ProfileStore.manualGroupID)
            let parameters = app.uriParser.unsupportedParameters(in: code)
            previewWarning = parameters.isEmpty
                ? nil
                : String(format: L10n.t("nodes.import.warning", table: "Nodes"),
                         parameters.joined(separator: ", "))
            previewError = nil
            previewProfile = profile
            scanner.stop()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            invalidMessage = L10n.t("nodes.scan.invalidQR", table: "Nodes")
            scanner.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    invalidMessage = nil
                }
                lastHandledCode = nil
            }
        }
    }

    private func cancelPreview() {
        previewProfile = nil
        previewWarning = nil
        previewError = nil
        scanner.reset()
        lastHandledCode = nil
        if cameraState == .running {
            scanner.start()
        }
    }

    private func savePreview(_ profile: NodeProfile) {
        // Importing must not create a second copy of a node the app already has.
        if app.nodes.contains(where: { app.uriParser.isDuplicate(profile, of: $0) }) {
            previewError = L10n.t("nodes.scan.alreadyAdded", table: "Nodes")
            return
        }
        app.addProfiles([profile], groupID: ProfileStore.manualGroupID)
        app.setActive(profile)
        scanner.stop()
        dismiss()
    }

    #if DEBUG
    /// Screenshot harness: a synthetic, never-existing node so saving the preview
    /// card really appends one node (the old version reused an existing id and the
    /// upsert silently updated it instead).
    private static func debugPreviewProfile(basedOn base: NodeProfile?) -> NodeProfile {
        var profile = base ?? NodeProfile(id: UUID().uuidString,
                                          groupID: ProfileStore.manualGroupID,
                                          name: "Scanned Node",
                                          proto: .vless,
                                          server: "198.51.100.77",
                                          port: 443)
        profile.id = UUID().uuidString
        profile.groupID = ProfileStore.manualGroupID
        profile.name = "\(profile.name) (Scanned)"
        profile.server = "198.51.100.77"
        profile.rawURI = ""
        switch profile.proto {
        case .vmess, .vless:
            profile.uuid = UUID().uuidString
        case .trojan, .shadowsocks:
            profile.password = "scanned-\(UUID().uuidString)"
        case .socks:
            profile.socksUsername = "scanned-user"
            profile.password = "scanned-\(UUID().uuidString)"
        }
        return profile
    }
    #endif

    private func loadPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { photoItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let code = QRImageDecoder.decode(data: data) else {
                await MainActor.run {
                    invalidMessage = L10n.t("nodes.scan.photoError", table: "Nodes")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { invalidMessage = nil }
                    }
                }
                return
            }
            await MainActor.run {
                handleScannedCode(code)
            }
        }
    }
}

// MARK: - Camera preview

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

// MARK: - Capture session

final class QRScannerController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    @Published var code: String?

    private var configured = false
    private let sessionQueue = DispatchQueue(label: "com.juejin.ios.wuji.qr-session")

    func configureIfNeeded() {
        guard !configured, let device = AVCaptureDevice.default(for: .video) else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }
        session.commitConfiguration()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func reset() {
        code = nil
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard code == nil,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        code = value
    }
}

// MARK: - Viewfinder & photo decoding

private struct ViewfinderCorners: View {
    var body: some View {
        GeometryReader { proxy in
            let length: CGFloat = 38
            let radius: CGFloat = 22
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                // Top left
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: radius))
                path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))
                // Top right
                path.move(to: CGPoint(x: width - length, y: 0))
                path.addLine(to: CGPoint(x: width - radius, y: 0))
                path.addQuadCurve(to: CGPoint(x: width, y: radius), control: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: length))
                // Bottom left
                path.move(to: CGPoint(x: 0, y: height - length))
                path.addLine(to: CGPoint(x: 0, y: height - radius))
                path.addQuadCurve(to: CGPoint(x: radius, y: height), control: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: length, y: height))
                // Bottom right
                path.move(to: CGPoint(x: width - length, y: height))
                path.addLine(to: CGPoint(x: width - radius, y: height))
                path.addQuadCurve(to: CGPoint(x: width, y: height - radius), control: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: width, y: height - length))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }
}

enum QRImageDecoder {
    static func decode(data: Data) -> String? {
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        guard let features = detector?.features(in: ciImage) else { return nil }
        for feature in features {
            if let qr = feature as? CIQRCodeFeature, let message = qr.messageString, !message.isEmpty {
                return message
            }
        }
        return nil
    }
}
