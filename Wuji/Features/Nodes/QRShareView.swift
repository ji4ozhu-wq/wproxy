import SwiftUI
import UIKit
import Photos
import CoreImage

/// Renders a node share link as a white-on-black QR code (spec §5.9).
/// Pushed from the node actions sheet, so it expects an enclosing `NavigationStack`.
struct QRShareView: View {
    let profile: NodeProfile

    @EnvironmentObject private var app: AppState
    @State private var qrImage: UIImage?
    @State private var saveSaving = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showShare = false

    private var shareURI: String {
        let encoded = app.uriParser.encode(profile)
        return encoded.isEmpty ? profile.rawURI : encoded
    }

    private var hasURI: Bool { !shareURI.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card
                    .padding(.horizontal, Theme.hMargin)

                PrimaryButton(title: L10n.t("nodes.qr.saveToPhotos", table: "Nodes"),
                              isLoading: saveSaving) {
                    saveToPhotos()
                }
                .disabled(!hasURI || saveSaving)
                .opacity(hasURI ? 1 : 0.4)
                .accessibilityIdentifier("wuji.nodes.qr.saveButton")

                Button {
                    copyURI()
                } label: {
                    Text(L10n.t("nodes.qr.copyURI", table: "Nodes"))
                        .font(Theme.buttonLabel)
                        .foregroundStyle(hasURI ? Theme.tint : Theme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.buttonHeight)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.hMargin)
                .disabled(!hasURI)
                .accessibilityIdentifier("wuji.nodes.qr.copyButton")

                if let statusMessage {
                    Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? Theme.red : Theme.green)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, Theme.hMargin)
                        .accessibilityIdentifier("wuji.nodes.qr.status")
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .navigationTitle(L10n.t("nodes.qr.title", table: "Nodes"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShare = true
                } label: {
                    Label(L10n.t("nodes.qr.share", table: "Nodes"), systemImage: "square.and.arrow.up")
                }
                .disabled(!hasURI)
                .accessibilityLabel(L10n.t("nodes.qr.share", table: "Nodes"))
                .accessibilityIdentifier("wuji.nodes.qr.shareButton")
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareURI])
        }
        .onAppear(perform: generateQRIfNeeded)
    }

    private var card: some View {
        VStack(spacing: 12) {
            Text(profile.displayName)
                .font(.title2.bold())
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let qrImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 188)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityLabel(String(format: L10n.t("nodes.qr.imageLabel", table: "Nodes"), profile.displayName))
                    .accessibilityIdentifier("wuji.nodes.qr.image")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.tertiaryLabel)
                    Text(L10n.t("nodes.qr.noURI", table: "Nodes"))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("wuji.nodes.qr.emptyState")
            }

            Text("\(profile.proto.shortBadge) · \(profile.endpoint)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func generateQRIfNeeded() {
        guard qrImage == nil, hasURI else { return }
        qrImage = QRCodeRenderer.image(for: shareURI)
    }

    private func copyURI() {
        guard hasURI else {
            statusMessage = L10n.t("nodes.qr.noURI", table: "Nodes")
            statusIsError = true
            return
        }
        UIPasteboard.general.string = shareURI
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showStatus(L10n.t("nodes.qr.copied", table: "Nodes"), isError: false)
    }

    private func saveToPhotos() {
        guard let qrImage, hasURI else {
            statusMessage = L10n.t("nodes.qr.noURI", table: "Nodes")
            statusIsError = true
            return
        }
        saveSaving = true
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                await MainActor.run {
                    saveSaving = false
                    showStatus(L10n.t("nodes.qr.saveFailed", table: "Nodes"), isError: true)
                }
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: qrImage)
                }
                await MainActor.run {
                    saveSaving = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showStatus(L10n.t("nodes.qr.saved", table: "Nodes"), isError: false)
                }
            } catch {
                await MainActor.run {
                    saveSaving = false
                    showStatus(L10n.t("nodes.qr.saveFailed", table: "Nodes"), isError: true)
                }
            }
        }
    }

    private func showStatus(_ message: String, isError: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            statusMessage = message
            statusIsError = isError
        }
        if !isError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if statusMessage == message { statusMessage = nil }
                }
            }
        }
    }
}

// MARK: - QR generation

enum QRCodeRenderer {
    static func image(for text: String) -> UIImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - System share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
