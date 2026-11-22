import SwiftUI

/// Subscription detail (spec §5.7, design reference `N-subscription-detail`).
/// Pushed from the subscription list; shows usage, metadata, a node preview, and the
/// update / edit / delete actions.
struct SubscriptionDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let subscriptionID: String

    @State private var editingSubscription: Subscription?
    @State private var deleteConfirmation: ConfirmationRequest?
    @State private var showAllNodes = false
    @State private var isUpdating = false
    @State private var updateError: String?
    @State private var toast: String?

    private var subscription: Subscription? {
        SubscriptionLookup.subscription(id: subscriptionID, in: app)
    }

    var body: some View {
        Group {
            if let subscription {
                content(for: subscription)
            } else {
                notFoundState
            }
        }
        .navigationTitle(subscription?.name ?? L10n.t("subscriptions.title"))
        .wujiInlineNavigationTitle()
        .wujiHiddenTabBar()
        .toolbar {
            if let subscription {
                ToolbarItem(placement: .wujiTrailing) {
                    Button(L10n.t("common.edit", table: "Settings")) {
                        editingSubscription = subscription
                    }
                    .accessibilityIdentifier("wuji.subscriptions.detail.edit")
                }
            }
        }
        .sheet(item: $editingSubscription) { subscription in
            AddSubscriptionView(editing: subscription)
                .wujiSheetSizing(width: 520, height: 620)
        }
        .sheet(item: $deleteConfirmation) { request in
            ConfirmationSheet(request: request)
                .wujiSheetSizing(width: 420, height: 240)
        }
        .sheet(isPresented: $showAllNodes) {
            SubscriptionNodesView(subscriptionID: subscriptionID)
                .wujiSheetSizing(width: 560, height: 640)
        }
        .wujiToast($toast)
        .task {
            #if DEBUG
            await openSheetsForScreenshotIfNeeded()
            #endif
        }
    }

    #if DEBUG
    /// Screenshot harness: `-WujiScreenshotRoute subscription-nodes|subscription-edit`
    /// opens the corresponding sheet on this page.
    private func openSheetsForScreenshotIfNeeded() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WujiScreenshotRoute"),
              index + 1 < arguments.count else { return }
        let route = arguments[index + 1]
        guard route == "subscription-nodes" || route == "subscription-edit" else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard let subscription else { return }
        if route == "subscription-nodes" {
            showAllNodes = true
        } else {
            editingSubscription = subscription
        }
    }
    #endif

    // MARK: - Content

    private func content(for subscription: Subscription) -> some View {
        let nodes = SubscriptionLookup.nodes(for: subscription, in: app)
        return WujiSettingsList {
            statsSection(subscription: subscription, nodes: nodes)
            infoSection(subscription: subscription)
            if let message = updateError ?? subscription.lastError {
                errorSection(message)
            }
            nodesSection(subscription: subscription, nodes: nodes)
            actionsSection(subscription: subscription)
        }
        
        .accessibilityIdentifier("wuji.subscriptions.detail.list")
    }

    private func statsSection(subscription: Subscription, nodes: [NodeProfile]) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 0) {
                    statColumn(label: L10n.t("subscriptions.detail.nodes", table: "Subscriptions"),
                               value: "\(nodes.count)",
                               identifier: "nodes")
                    statDivider
                    statColumn(label: L10n.t("subscriptions.detail.used", table: "Subscriptions"),
                               value: usedText(subscription),
                               identifier: "used")
                    statDivider
                    statColumn(label: L10n.t("subscriptions.detail.expires", table: "Subscriptions"),
                               value: expiryText(subscription),
                               identifier: "expires")
                }
                if let progress = progressValue(subscription) {
                    ProgressView(value: progress)
                        .tint(Theme.tint)
                        .accessibilityIdentifier("wuji.subscriptions.detail.progress")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func infoSection(subscription: Subscription) -> some View {
        Section {
            ValueRow(title: L10n.t("subscriptions.detail.lastUpdated", table: "Subscriptions"),
                     value: subscription.lastUpdatedAt.map { SubscriptionFormat.relative($0) }
                        ?? L10n.t("subscriptions.detail.never", table: "Subscriptions"))
            ValueRow(title: L10n.t("subscriptions.detail.autoUpdate", table: "Subscriptions"),
                     value: SubscriptionUpdateInterval(subscription: subscription).displayName)
            Button {
                PlatformPasteboard.setString(subscription.url)
                toast = L10n.t("subscriptions.detail.urlCopied", table: "Subscriptions")
            } label: {
                ValueRow(title: L10n.t("subscriptions.detail.url", table: "Subscriptions"),
                         value: SubscriptionFormat.host(subscription.url),
                         interactive: true,
                         showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.subscriptions.detail.url")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("subscriptions.detail.updateFailed", table: "Subscriptions"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.red)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("wuji.subscriptions.detail.error")
        }
    }

    @ViewBuilder
    private func nodesSection(subscription: Subscription, nodes: [NodeProfile]) -> some View {
        Section {
            if nodes.isEmpty {
                Text(L10n.t("subscriptions.detail.noNodes", table: "Subscriptions"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("wuji.subscriptions.detail.nodesEmpty")
            } else {
                ForEach(nodes.prefix(3)) { node in
                    nodeRow(node)
                }
                Button {
                    showAllNodes = true
                } label: {
                    Text(String(format: L10n.t("subscriptions.detail.viewAll", table: "Subscriptions"), nodes.count))
                        .font(Theme.body)
                        .foregroundStyle(Theme.tint)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wuji.subscriptions.detail.viewAllNodes")
            }
        }
    }

    private func nodeRow(_ node: NodeProfile) -> some View {
        Button {
            app.setActive(node)
            toast = String(format: L10n.t("subscriptions.detail.selectedNode", table: "Subscriptions"), node.displayName)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.label)
                    Text("\(node.proto.shortBadge) · \(node.server)")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                Spacer(minLength: 8)
                if app.settings.activeProfileID == node.id {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tint)
                }
                Text(node.latencyMs.map { String(format: L10n.t("unit.ms"), $0) } ?? L10n.t("nodes.latency.unknown", table: "Nodes"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wuji.subscriptions.detail.node.\(node.id)")
    }

    private func actionsSection(subscription: Subscription) -> some View {
        Section {
            VStack(spacing: 6) {
                PrimaryButton(title: L10n.t("subscriptions.detail.updateNow", table: "Subscriptions"),
                              isLoading: isUpdating) {
                    Task { await updateNow(subscription) }
                }
                .disabled(isUpdating)
                .accessibilityIdentifier("wuji.subscriptions.detail.updateNow")

                Button {
                    deleteConfirmation = deleteRequest(for: subscription)
                } label: {
                    Text(L10n.t("subscriptions.detail.delete", table: "Subscriptions"))
                        .font(Theme.body)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isUpdating)
                .accessibilityIdentifier("wuji.subscriptions.detail.delete")
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
        }
    }

    private var notFoundState: some View {
        EmptyStateView(symbol: "questionmark.folder",
                       title: L10n.t("subscriptions.detail.notFound", table: "Subscriptions"),
                       message: L10n.t("subscriptions.detail.notFoundMessage", table: "Subscriptions"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .accessibilityIdentifier("wuji.subscriptions.detail.notFound")
    }

    // MARK: - Actions

    private func updateNow(_ subscription: Subscription) async {
        guard !isUpdating else { return }
        isUpdating = true
        updateError = nil
        defer { isUpdating = false }
        do {
            try await app.refresh(subscription: subscription)
            toast = L10n.t("subscriptions.detail.updateSuccess", table: "Subscriptions")
        } catch {
            if let subscriptionError = error as? SubscriptionError,
               subscriptionError == .refreshInProgress { return }
            updateError = error.localizedDescription
        }
    }

    private func deleteRequest(for subscription: Subscription) -> ConfirmationRequest {
        ConfirmationRequest(title: L10n.t("subscriptions.list.deleteTitle", table: "Subscriptions"),
                            message: String(format: L10n.t("subscriptions.list.deleteBody", table: "Subscriptions"),
                                            subscription.name),
                            confirmTitle: L10n.t("subscriptions.list.deleteConfirm", table: "Subscriptions")) {
            Task { @MainActor in
                await SubscriptionImporter.delete(app: app, subscription: subscription)
                dismiss()
            }
        }
    }

    // MARK: - Formatting

    private func usedText(_ subscription: Subscription) -> String {
        subscription.trafficUsed.map { SubscriptionFormat.bytes($0) } ?? "—"
    }

    private func expiryText(_ subscription: Subscription) -> String {
        subscription.expireAt.map { SubscriptionFormat.expiry($0) } ?? "—"
    }

    private func progressValue(_ subscription: Subscription) -> Double? {
        guard let used = subscription.trafficUsed,
              let total = subscription.trafficTotal,
              total > 0 else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 42)
            .padding(.horizontal, 10)
    }

    private func statColumn(label: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("wuji.subscriptions.detail.stat.\(identifier)")
    }
}
