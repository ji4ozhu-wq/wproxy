import SwiftUI

/// Custom bottom sheet with the actions for one node (design `N-node-actions`).
/// Owns a `NavigationStack` so "Edit Node" and "Share QR Code" push full-height
/// pages (the sheet expands from the action-menu detent to `.large` on push).
struct NodeActionsSheet: View {
    let profile: NodeProfile

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .height(520)
    @State private var copied = false
    @State private var copyError: String?
    @State private var showDeleteConfirm = false
    @State private var showShare = false
    @State private var showEditForm = false
    @State private var showQRShare = false
    @State private var testingLatency = false
    @State private var latencyTested = false
    @State private var latencyResult: Int?
    @State private var didConfigureDebug = false

    private enum Route: Hashable {
        case edit
        case shareQR
    }

    private var shareURI: String {
        let encoded = app.uriParser.encode(profile)
        return encoded.isEmpty ? profile.rawURI : encoded
    }

    private var isActive: Bool {
        app.settings.activeProfileID == profile.id
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .wujiHiddenNavigationBar()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .edit:
                        AddNodeFormView(editingProfile: profile,
                                        showsCancelButton: false,
                                        onSaved: { dismiss() })
                    case .shareQR:
                        QRShareView(profile: profile)
                    }
                }
        }
        .wujiPresentationDetents([.height(520), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .confirmationDialog(L10n.t("nodes.deleteConfirmTitle", table: "Nodes"),
                            isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button(L10n.t("nodes.delete", table: "Nodes"), role: .destructive) {
                app.deleteProfile(profile)
                dismiss()
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: L10n.t("nodes.deleteConfirmMessage", table: "Nodes"), profile.displayName))
        }
        .sheet(isPresented: $showEditForm) {
            NavigationStack {
                AddNodeFormView(editingProfile: profile,
                                showsCancelButton: true,
                                onSaved: {
                                    showEditForm = false
                                    dismiss()
                                })
            }
            .wujiSheetSizing(width: 560, height: 700)
        }
        .sheet(isPresented: $showQRShare) {
            NavigationStack {
                QRShareView(profile: profile)
            }
            .wujiSheetSizing(width: 560, height: 700)
        }
        .sheet(isPresented: $showShare) {
            if shareURI.isEmpty {
                Text(L10n.t("nodes.action.noURI", table: "Nodes"))
                    .padding()
                    .wujiSheetSizing(width: 380, height: 170)
            } else {
                ShareSheet(items: [shareURI])
                    .wujiSheetSizing(width: 380, height: 200)
            }
        }
        .onChange(of: path.count) { _, count in
            withAnimation(.easeInOut(duration: 0.2)) {
                detent = count > 0 ? .large : .height(520)
            }
        }
        .onAppear(perform: configureFromDebugArguments)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(Theme.label)
                    Text("\(profile.proto.shortBadge) · \(profile.endpoint)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("wuji.nodes.actions.header")

                VStack(spacing: 0) {
                    Button {
                        app.setActive(profile)
                        dismiss()
                    } label: {
                        actionRow(symbol: isActive ? "checkmark.circle.fill" : "checkmark.circle",
                                  title: L10n.t("nodes.action.setActive", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.setActive")

                    divider

                    #if os(macOS)
                    // macOS sheets render no toolbar/back button for pushed pages, so
                    // edit/QR open as proper sheets with their own action bars instead.
                    Button {
                        showEditForm = true
                    } label: {
                        actionRow(symbol: "pencil",
                                  title: L10n.t("nodes.action.edit", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.edit")
                    #else
                    NavigationLink(value: Route.edit) {
                        actionRow(symbol: "pencil",
                                  title: L10n.t("nodes.action.edit", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.edit")
                    #endif

                    divider

                    Button {
                        copyURI()
                    } label: {
                        actionRow(symbol: copied ? "checkmark" : "doc.on.doc",
                                  title: copied ? L10n.t("nodes.action.copied", table: "Nodes") : L10n.t("nodes.action.copyURI", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.copyURI")

                    divider

                    Button {
                        testLatency()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Theme.tint)
                                .frame(width: 28)
                            Text(testingLatency
                                 ? L10n.t("nodes.action.testing", table: "Nodes")
                                 : L10n.t("nodes.action.testLatency", table: "Nodes"))
                                .font(.body)
                                .foregroundStyle(Theme.label)
                            Spacer(minLength: 8)
                            if testingLatency {
                                ProgressView()
                                    .controlSize(.mini)
                            } else if latencyTested {
                                Text(latencyResultText)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Theme.secondaryLabel)
                                    .accessibilityIdentifier("wuji.nodes.actions.testResult")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .disabled(testingLatency)
                    .accessibilityIdentifier("wuji.nodes.actions.testLatency")

                    divider

                    #if os(macOS)
                    Button {
                        showQRShare = true
                    } label: {
                        actionRow(symbol: "qrcode",
                                  title: L10n.t("nodes.action.shareQR", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.shareQR")
                    #else
                    NavigationLink(value: Route.shareQR) {
                        actionRow(symbol: "qrcode",
                                  title: L10n.t("nodes.action.shareQR", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.shareQR")
                    #endif

                    divider

                    Button {
                        showShare = true
                    } label: {
                        actionRow(symbol: "square.and.arrow.up",
                                  title: L10n.t("nodes.action.share", table: "Nodes"),
                                  tint: Theme.tint)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.share")

                    divider

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        actionRow(symbol: "trash",
                                  title: L10n.t("nodes.action.delete", table: "Nodes"),
                                  tint: Theme.red)
                    }
                    .buttonStyle(SheetRowButtonStyle())
                    .accessibilityIdentifier("wuji.nodes.actions.delete")
                }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

                if let copyError {
                    Label(copyError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("wuji.nodes.actions.copyError")
                }

                Button {
                    dismiss()
                } label: {
                    Text(L10n.t("common.cancel"))
                        .font(Theme.buttonLabel)
                        .foregroundStyle(Theme.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SheetRowButtonStyle())
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .accessibilityIdentifier("wuji.nodes.actions.cancel")
            }
            .padding(.horizontal, Theme.hMargin)
            .padding(.top, 20)
            .padding(.bottom, 20)
        }
        .background(Theme.background)
    }

    private var divider: some View {
        Divider().padding(.leading, 52)
    }

    private func actionRow(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(tint == Theme.red ? Theme.red : Theme.label)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private var latencyResultText: String {
        guard let latencyResult else { return L10n.t("nodes.latency.unknown", table: "Nodes") }
        return String(format: L10n.t("unit.ms"), latencyResult)
    }

    /// Single-node latency test through `AppState.testLatencyResult`, which picks
    /// the HTTP-through-tunnel probe for the connected active node and TCP otherwise.
    private func testLatency() {
        guard !testingLatency else { return }
        testingLatency = true
        let target = profile
        Task {
            let latency = await app.testLatencyResult(for: target)
            app.updateLatency(profileID: target.id, latencyMs: latency)
            latencyResult = latency
            latencyTested = true
            testingLatency = false
        }
    }

    private func copyURI() {
        guard !shareURI.isEmpty else {
            copyError = L10n.t("nodes.action.noURI", table: "Nodes")
            return
        }
        PlatformPasteboard.setString(shareURI)
        copyError = nil
        PlatformHaptics.impact()
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.15)) { copied = false }
        }
    }

    private func configureFromDebugArguments() {
        #if DEBUG
        guard !didConfigureDebug else { return }
        didConfigureDebug = true
        switch DebugScreenshotRoute.value("-WujiScreenshotDetail") {
        case "qr":
            #if os(macOS)
            showQRShare = true
            #else
            path.append(Route.shareQR)
            #endif
        case "edit":
            #if os(macOS)
            showEditForm = true
            #else
            path.append(Route.edit)
            #endif
        default:
            break
        }
        #endif
    }
}
