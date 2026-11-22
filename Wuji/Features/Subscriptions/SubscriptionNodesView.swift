import SwiftUI

// MARK: - All nodes sheet

/// "View All N Nodes" destination: every node of the subscription, tap to select it.
struct SubscriptionNodesView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let subscriptionID: String

    private var subscription: Subscription? {
        SubscriptionLookup.subscription(id: subscriptionID, in: app)
    }

    private var nodes: [NodeProfile] {
        guard let subscription else { return [] }
        return SubscriptionLookup.nodes(for: subscription, in: app)
    }

    var body: some View {
        NavigationStack {
            WujiSettingsList {
                if nodes.isEmpty {
                    EmptyStateView(symbol: "server.rack",
                                   title: L10n.t("subscriptions.detail.nodesTitle", table: "Subscriptions"),
                                   message: L10n.t("subscriptions.detail.noNodes", table: "Subscriptions"))
                        .frame(minHeight: 320)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(nodes) { node in
                            Button {
                                app.setActive(node)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(node.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(Theme.label)
                                        Text("\(node.proto.shortBadge) · \(node.endpoint)")
                                            .font(.footnote)
                                            .foregroundStyle(Theme.secondaryLabel)
                                    }
                                    Spacer(minLength: 8)
                                    if app.settings.activeProfileID == node.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.tint)
                                    }
                                    Text(node.latencyMs.map { String(format: L10n.t("unit.ms"), $0) } ?? L10n.t("nodes.latency.unknown", table: "Nodes"))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(Theme.secondaryLabel)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wuji.subscriptions.nodes.row.\(node.id)")
                        }
                    }
                }
            }
            .wujiListStyle()
            .navigationTitle(L10n.t("subscriptions.detail.nodesTitle", table: "Subscriptions"))
            .wujiInlineNavigationTitle()
            .wujiHiddenTabBar()
            .toolbar {
                ToolbarItem(placement: .wujiTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                        .accessibilityIdentifier("wuji.subscriptions.nodes.done")
                }
            }
        }
        .wujiMacSheetActions(confirmTitle: L10n.t("common.done"),
                             onConfirm: { dismiss() })
    }
}
