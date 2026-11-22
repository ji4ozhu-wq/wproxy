import SwiftUI
import CoreImage

#if os(iOS)
import Photos
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Renders a node share link as a white-on-black QR code (spec §5.9).
/// Pushed from the node actions sheet, so it expects an enclosing `NavigationStack`.
struct QRShareView: View {
    let profile: NodeProfile

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: PlatformImage?
    @State private var saveSaving = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showShare = false

    private var shareURI: String {
        let encoded = app.uriParser.encode(profile)
        return encoded.isEmpty ? profile.rawURI : encoded
    }

    private var hasURI: Bool { !shareURI.isEmpty }

    /// iOS saves the QR image to the photo library; macOS exports a PNG file
    /// through a save panel (there is no Photos-library write path in a sandboxed
    /// Mac App Store app).
    private var saveButtonTitle: String {
        #if os(iOS)
        return L10n.t("nodes.qr.saveToPhotos", table: "Nodes")
        #else
        return L10n.t("nodes.qr.saveToFile", table: "Nodes")
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card
                    .padding(.horizontal, Theme.hMargin)

                PrimaryButton(title: saveButtonTitle,
                              isLoading: saveSaving) {
                    saveImage()
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

                #if os(macOS)
                // macOS sheets don't render the toolbar share button; expose the
                // native share menu inline instead.
                ShareLink(item: shareURI) {
                    Text(L10n.t("nodes.qr.share", table: "Nodes"))
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
                .accessibilityIdentifier("wuji.nodes.qr.shareButton")
                #endif

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
        .wujiInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .wujiTrailing) {
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
                .wujiSheetSizing(width: 380, height: 200)
        }
        .onAppear(perform: generateQRIfNeeded)
        .wujiMacSheetActions(confirmTitle: L10n.t("common.done"),
                             onConfirm: { dismiss() })
    }

    private var card: some View {
        VStack(spacing: 12) {
            Text(profile.displayName)
                .font(.title2.bold())
                .foregroundStyle(Theme.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let qrImage {
                PlatformQRImageView(image: qrImage)
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
        PlatformPasteboard.setString(shareURI)
        PlatformHaptics.impact()
        showStatus(L10n.t("nodes.qr.copied", table: "Nodes"), isError: false)
    }

    private func saveImage() {
        #if os(iOS)
        saveToPhotos()
        #else
        saveToFile()
        #endif
    }

    #if os(iOS)
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
                    PlatformHaptics.success()
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
    #else
    private func saveToFile() {
        guard let qrImage, hasURI, let png = qrImage.wujiPNGData() else {
            statusMessage = L10n.t("nodes.qr.noURI", table: "Nodes")
            statusIsError = true
            return
        }
        saveSaving = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.fileName(for: profile)
        let response = panel.runModal()
        saveSaving = false
        guard response == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url, options: .atomic)
            showStatus(L10n.t("nodes.qr.saved", table: "Nodes"), isError: false)
        } catch {
            showStatus(L10n.t("nodes.qr.saveFailed", table: "Nodes"), isError: true)
        }
    }

    /// File name safe for a save panel (no path separators or colons).
    private static func fileName(for profile: NodeProfile) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let base = profile.displayName
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let name = base.isEmpty ? "wuji-node" : base
        return "\(name)-qr.png"
    }
    #endif

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
    static func image(for text: String) -> PlatformImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return PlatformImage.wujiMake(cgImage: cgImage)
    }
}

// MARK: - System share sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
/// macOS has no `UIActivityViewController`; present a small sheet with SwiftUI's
/// native `ShareLink`, which opens the macOS share menu (Mail, Messages, AirDrop…).
struct ShareSheet: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss

    private var text: String { items.compactMap { $0 as? String }.first ?? "" }

    var body: some View {
        VStack(spacing: 18) {
            ShareLink(item: text) {
                Label(L10n.t("nodes.qr.share", table: "Nodes"), systemImage: "square.and.arrow.up")
                    .font(Theme.buttonLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.buttonHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.tint)

            Button(L10n.t("common.cancel")) {
                dismiss()
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(minWidth: 320)
    }
}
#endif
