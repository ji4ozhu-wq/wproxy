import SwiftUI

/// Subscription list (spec §5.7, design reference `N-subscriptions-list`).
/// Pushed from Settings; every card is one inset-grouped section.
struct SubscriptionListView: View {
    @EnvironmentObject private var app: AppState
    @State private var showAdd = false
    @State private var pendingDelete: Subscription?
    @State private var toast: String?
    @State private var updatingIDs: Set<String> = []

    var body: some View {
        List {
            if app.subscriptions.isEmpty {
                emptyState
            } else {
                ForEach(app.subscriptions) { subscription in
                    card(for: subscription)
                }
                Section {
                    EmptyView()
                } footer: {
                    Text(L10n.t("subscriptions.list.autoUpdateFootnote", table: "Subscriptions"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("subscriptions.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("wuji.subscriptions.addButton")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSubscriptionView()
        }
        .sheet(item: $pendingDelete) { subscription in
            ConfirmationSheet(request: deleteRequest(for: subscription))
        }
        .wujiToast($toast)
        .accessibilityIdentifier("wuji.subscriptions.list")
        .task {
            #if DEBUG
            openDeleteConfirmationForScreenshotIfNeeded()
            #endif
        }
    }

    #if DEBUG
    /// Screenshot harness: opens the delete confirmation for the first subscription.
    private func openDeleteConfirmationForScreenshotIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-WujiScreenshotRoute"),
              index + 1 < arguments.count,
              arguments[index + 1] == "subscriptions-delete-confirm",
              let first = app.subscriptions.first else { return }
        pendingDelete = first
    }
    #endif

    // MARK: - Card

    @ViewBuilder
    private func card(for subscription: Subscription) -> some View {
        let nodes = SubscriptionLookup.nodes(for: subscription, in: app)
        let used = subscription.trafficUsed
        let total = subscription.trafficTotal

        Section {
            NavigationLink {
                SubscriptionDetailView(subscriptionID: subscription.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscription.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.label)
                    Text(subtitle(for: subscription, nodeCount: nodes.count))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.vertical, 2)
            }
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deleteSwipeButton(for: subscription)
            }
            .accessibilityIdentifier("wuji.subscriptions.row.\(subscription.id)")

            if let progress = progressValue(used: used, total: total) {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: progress)
                        .tint(Theme.tint)
                        .accessibilityIdentifier("wuji.subscriptions.row.\(subscription.id).progress")
                    if let flowText = SubscriptionFormat.traffic(used: used, total: total) {
                        Text(flowText)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 2)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteSwipeButton(for: subscription)
                }
            }

            if let expireAt = subscription.expireAt {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    Text(String(format: L10n.t("subscriptions.list.expires", table: "Subscriptions"),
                                SubscriptionFormat.expiry(expireAt)))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteSwipeButton(for: subscription)
                }
            }

            if let error = subscription.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                    Text("\(L10n.t("subscriptions.list.error", table: "Subscriptions")) · \(error)")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteSwipeButton(for: subscription)
                }
            }

            updateRow(for: subscription)
        }
    }

    /// "Update" affordance on the card (B13): refetches this subscription, shows a
    /// spinner while running and reports failures without leaving the list.
    private func updateRow(for subscription: Subscription) -> some View {
        let updating = updatingIDs.contains(subscription.id)
        return HStack {
            Spacer(minLength: 0)
            Button {
                Task { await update(subscription) }
            } label: {
                HStack(spacing: 6) {
                    if updating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.footnote.weight(.semibold))
                    }
                    Text(updating
                         ? L10n.t("subscriptions.list.updating", table: "Subscriptions")
                         : L10n.t("subscriptions.list.update", table: "Subscriptions"))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(Theme.tint)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(updating)
            .accessibilityIdentifier("wuji.subscriptions.update.\(subscription.id)")
        }
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteSwipeButton(for: subscription)
        }
    }

    /// Refreshes one subscription card. A concurrent fetch of the same URL is
    /// suppressed by the service-level gate, so this stays quiet instead of
    /// surfacing a "already updating" error.
    private func update(_ subscription: Subscription) async {
        guard !updatingIDs.contains(subscription.id) else { return }
        updatingIDs.insert(subscription.id)
        defer { updatingIDs.remove(subscription.id) }
        do {
            try await app.refresh(subscription: subscription)
            toast = L10n.t("subscriptions.detail.updateSuccess", table: "Subscriptions")
        } catch {
            if let subscriptionError = error as? SubscriptionError,
               subscriptionError == .refreshInProgress { return }
            toast = "\(L10n.t("subscriptions.list.error", table: "Subscriptions")) · \(error.localizedDescription)"
        }
    }

    private func deleteSwipeButton(for subscription: Subscription) -> some View {
        Button(role: .destructive) {
            pendingDelete = subscription
        } label: {
            Label(L10n.t("subscriptions.list.delete", table: "Subscriptions"), systemImage: "trash")
        }
        .accessibilityIdentifier("wuji.subscriptions.swipeDelete.\(subscription.id)")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(symbol: "arrow.triangle.2.circlepath",
                       title: L10n.t("subscriptions.emptyTitle"),
                       message: L10n.t("subscriptions.emptyMessage"),
                       primaryTitle: L10n.t("subscriptions.add"),
                       primaryAction: { showAdd = true })
            .frame(minHeight: 420)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("wuji.subscriptions.emptyState")
    }

    // MARK: - Helpers

    private func subtitle(for subscription: Subscription, nodeCount: Int) -> String {
        let nodes = String(format: L10n.t("subscriptions.list.nodeCount", table: "Subscriptions"), nodeCount)
        return "\(nodes) · \(SubscriptionFormat.updated(subscription.lastUpdatedAt))"
    }

    private func progressValue(used: Int64?, total: Int64?) -> Double? {
        guard let used, let total, total > 0 else { return nil }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    private func deleteRequest(for subscription: Subscription) -> ConfirmationRequest {
        ConfirmationRequest(title: L10n.t("subscriptions.list.deleteTitle", table: "Subscriptions"),
                            message: String(format: L10n.t("subscriptions.list.deleteBody", table: "Subscriptions"),
                                            subscription.name),
                            confirmTitle: L10n.t("subscriptions.list.deleteConfirm", table: "Subscriptions")) {
            Task { @MainActor in
                await SubscriptionImporter.delete(app: app, subscription: subscription)
                toast = L10n.t("subscriptions.list.deletedToast", table: "Subscriptions")
            }
        }
    }
}
