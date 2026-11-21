import SwiftUI
import UIKit

/// Modal destinations owned by the Nodes feature.
enum NodeFlow: Identifiable {
    case menu
    case addNode
    case edit(NodeProfile)
    case actions(NodeProfile)
    case paste
    case addSubscription
    case scan

    var id: String {
        switch self {
        case .menu: return "menu"
        case .addNode: return "addNode"
        case .edit(let profile): return "edit-\(profile.id)"
        case .actions(let profile): return "actions-\(profile.id)"
        case .paste: return "paste"
        case .addSubscription: return "addSubscription"
        case .scan: return "scan"
        }
    }
}

struct NodeListView: View {
    @EnvironmentObject private var app: AppState

    @State private var searchText = ""
    @State private var activeFlow: NodeFlow?
    @State private var debugFullScreenFlow: NodeFlow?
    @State private var pendingFlow: NodeFlow?
    @State private var showScan = false
    @State private var testingAll = false
    @State private var testingIDs: Set<String> = []
    @State private var refreshingSubscriptionIDs: Set<String> = []
    @State private var toast: String?
    @State private var deleteCandidate: NodeProfile?
    @State private var didHandleDebug = false

    var body: some View {
        NavigationStack {
            List {
                listContent
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(L10n.t("nodes.search")))
            .navigationTitle(L10n.t("tab.nodes"))
            .toolbar { toolbarContent }
            .refreshable { await testAllNodes() }
            .wujiToast($toast)
            .sheet(item: $activeFlow, onDismiss: presentPendingFlow) { flow in
                sheetContent(for: flow)
            }
            .fullScreenCover(isPresented: $showScan, onDismiss: presentPendingFlow) {
                ScanQRView()
            }
            .fullScreenCover(item: $debugFullScreenFlow) { flow in
                sheetContent(for: flow)
            }
            .confirmationDialog(deleteDialogTitle,
                                isPresented: deleteDialogBinding,
                                presenting: deleteCandidate) { profile in
                Button(L10n.t("nodes.delete", table: "Nodes"), role: .destructive) {
                    app.deleteProfile(profile)
                    deleteCandidate = nil
                }
                Button(L10n.t("common.cancel"), role: .cancel) {
                    deleteCandidate = nil
                }
            } message: { profile in
                Text(String(format: L10n.t("nodes.deleteConfirmMessage", table: "Nodes"), profile.displayName))
            }
            .onAppear(perform: handleDebugArguments)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !app.nodes.isEmpty {
                sortMenu
                    .accessibilityIdentifier("wuji.nodes.sortMenu")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !app.nodes.isEmpty {
                Button {
                    Task { await testAllNodes() }
                } label: {
                    if testingAll {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt")
                    }
                }
                .disabled(testingAll)
                .accessibilityLabel(L10n.t("nodes.testAll", table: "Nodes"))
                .accessibilityIdentifier("wuji.nodes.testAllButton")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                open(.menu)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(L10n.t("nodes.addNode"))
            .accessibilityIdentifier("wuji.nodes.addButton")
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker(L10n.t("nodes.sortBy", table: "Nodes"), selection: sortFieldBinding) {
                Text(L10n.t("nodes.sort.name", table: "Nodes")).tag("name")
                Text(L10n.t("nodes.sort.latency", table: "Nodes")).tag("latency")
                Text(L10n.t("nodes.sort.added", table: "Nodes")).tag("added")
            }
            Divider()
            Button {
                setSortAscending(true)
            } label: {
                Label(L10n.t("nodes.sort.ascending", table: "Nodes"),
                      systemImage: app.settings.sortAscending ? "checkmark" : "circle")
            }
            Button {
                setSortAscending(false)
            } label: {
                Label(L10n.t("nodes.sort.descending", table: "Nodes"),
                      systemImage: app.settings.sortAscending ? "circle" : "checkmark")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(L10n.t("nodes.sort", table: "Nodes"))
    }

    private var sortFieldBinding: Binding<String> {
        Binding(
            get: { validSortField },
            set: { newValue in
                app.settings.sortField = newValue
                app.saveSettings()
            }
        )
    }

    private var validSortField: String {
        switch app.settings.sortField {
        case "name", "latency", "added": return app.settings.sortField
        default: return "latency"
        }
    }

    private func setSortAscending(_ ascending: Bool) {
        app.settings.sortAscending = ascending
        app.saveSettings()
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        if app.nodes.isEmpty {
            emptyState
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else if displayGroups.isEmpty {
            noResultsState
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        } else {
            ForEach(displayGroups) { group in
                Section {
                    ForEach(sortedNodes(in: group)) { profile in
                        nodeRow(profile)
                    }
                } header: {
                    sectionHeader(for: group)
                }
            }
        }
    }

    private var displayGroups: [NodeGroup] {
        app.groups
            .filter { !nodes(in: $0).isEmpty }
            .sorted { lhs, rhs in
                let lhsManual = lhs.kind == .manual
                let rhsManual = rhs.kind == .manual
                if lhsManual != rhsManual { return lhsManual }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func sectionHeader(for group: NodeGroup) -> some View {
        let count = nodes(in: group).count
        return HStack(spacing: 6) {
            Text(groupTitle(group))
                .textCase(.uppercase)
            Spacer(minLength: 8)
            if let subscription = subscription(for: group) {
                if subscription.lastError != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(L10n.t("nodes.updateFailed", table: "Nodes"))
                    }
                    .foregroundStyle(Theme.red)
                } else if let updated = subscription.lastUpdatedAt {
                    Text("\(count) · \(Self.relative(updated))")
                } else {
                    Text(countText(count))
                }
                refreshButton(for: subscription, groupID: group.id)
            } else {
                Text(countText(count))
            }
        }
    }

    /// Per-subscription "update" affordance in the group header (B13). Refreshing
    /// keeps the old nodes until the new list arrives; failures land in a toast and
    /// in the red "Update failed" label of the header.
    private func refreshButton(for subscription: Subscription, groupID: String) -> some View {
        let refreshing = refreshingSubscriptionIDs.contains(subscription.id)
        return Button {
            Task { await refresh(subscription) }
        } label: {
            Group {
                if refreshing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(refreshing)
        .accessibilityLabel(L10n.t("nodes.group.update", table: "Nodes"))
        .accessibilityIdentifier("wuji.nodes.group.\(groupID).update")
    }

    private func groupTitle(_ group: NodeGroup) -> String {
        if group.kind == .manual {
            return L10n.t("nodes.group.manual", table: "Nodes")
        }
        return group.name
    }

    private func subscription(for group: NodeGroup) -> Subscription? {
        guard group.kind == .subscription, let id = group.subscriptionID else { return nil }
        return app.subscriptions.first { $0.id == id }
    }

    private func countText(_ count: Int) -> String {
        if count == 1 { return L10n.t("nodes.count.one", table: "Nodes") }
        return String(format: L10n.t("nodes.count.many", table: "Nodes"), count)
    }

    private func nodeRow(_ profile: NodeProfile) -> some View {
        HStack(spacing: 6) {
            Button {
                select(profile)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                        Text("\(profile.proto.shortBadge) · \(profile.endpoint)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryLabel)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    latencyView(profile)
                    if app.settings.activeProfileID == profile.id {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.tint)
                            .accessibilityLabel(L10n.t("nodes.active", table: "Nodes"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(profile.displayName), \(profile.proto.shortBadge), \(profile.endpoint)")
            .accessibilityIdentifier("wuji.nodes.row.\(profile.id)")

            Button {
                activeFlow = .actions(profile)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.t("nodes.rowMenu", table: "Nodes"))
            .accessibilityIdentifier("wuji.nodes.rowMenu.\(profile.id)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteCandidate = profile
            } label: {
                Label(L10n.t("nodes.delete", table: "Nodes"), systemImage: "trash")
            }
            .accessibilityIdentifier("wuji.nodes.swipeDelete.\(profile.id)")
            Button {
                activeFlow = .edit(profile)
            } label: {
                Label(L10n.t("nodes.action.edit", table: "Nodes"), systemImage: "pencil")
            }
            .tint(Theme.tint)
            .accessibilityIdentifier("wuji.nodes.swipeEdit.\(profile.id)")
        }
        .swipeActions(edge: .leading) {
            Button {
                select(profile)
            } label: {
                Label(L10n.t("nodes.action.setActive", table: "Nodes"), systemImage: "checkmark.circle")
            }
            .tint(Theme.tint)
            .accessibilityIdentifier("wuji.nodes.swipeSetActive.\(profile.id)")
        }
    }

    @ViewBuilder
    private func latencyView(_ profile: NodeProfile) -> some View {
        if testingIDs.contains(profile.id) {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 58)
        } else if let latency = profile.latencyMs {
            Text(String(format: L10n.t("unit.ms"), latency))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(latencyColor(latency))
                .accessibilityIdentifier("wuji.nodes.latency.\(profile.id)")
        } else {
            Text(L10n.t("nodes.latency.unknown", table: "Nodes"))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.tertiaryLabel)
                .accessibilityIdentifier("wuji.nodes.latency.\(profile.id)")
        }
    }

    private func latencyColor(_ latency: Int) -> Color {
        if latency < 100 { return Theme.green }
        if latency < 200 { return Theme.orange }
        return Theme.red
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 88, height: 88)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
            Text(L10n.t("nodes.emptyTitle"))
                .font(.title3.bold())
                .foregroundStyle(Theme.label)
            Text(L10n.t("nodes.emptyMessage"))
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            PrimaryButton(title: L10n.t("nodes.addNode")) {
                open(.menu)
            }
            .accessibilityIdentifier("wuji.nodes.empty.addButton")
            .padding(.top, 4)
            Button {
                open(.addSubscription)
            } label: {
                Text(L10n.t("nodes.addSubscription"))
                    .font(Theme.buttonLabel)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.hMargin)
            .accessibilityIdentifier("wuji.nodes.empty.addSubscriptionButton")
            Button {
                open(.scan)
            } label: {
                Text(L10n.t("nodes.addMenu.scan", table: "Nodes"))
                    .font(Theme.buttonLabel)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.hMargin)
            .accessibilityIdentifier("wuji.nodes.empty.scanButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.bottom, 48)
    }

    private var noResultsState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.tertiaryLabel)
            Text(L10n.t("nodes.noResultsTitle", table: "Nodes"))
                .font(.headline)
                .foregroundStyle(Theme.label)
            Text(L10n.t("nodes.noResultsMessage", table: "Nodes"))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    // MARK: - Search, sorting, filtering

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func nodes(in group: NodeGroup) -> [NodeProfile] {
        var result = app.nodes.filter { $0.groupID == group.id }
        if isSearching {
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            result = result.filter { profile in
                profile.displayName.lowercased().contains(query)
                    || profile.server.lowercased().contains(query)
                    || profile.proto.shortBadge.lowercased().contains(query)
                    || profile.endpoint.lowercased().contains(query)
            }
        }
        return sortedNodes(result)
    }

    private func sortedNodes(in group: NodeGroup) -> [NodeProfile] {
        nodes(in: group)
    }

    private func sortedNodes(_ profiles: [NodeProfile]) -> [NodeProfile] {
        let ascending = app.settings.sortAscending
        return profiles.sorted { lhs, rhs in
            var result: ComparisonResult
            switch validSortField {
            case "name":
                result = lhs.displayName.localizedStandardCompare(rhs.displayName)
            case "added":
                result = lhs.createdAt.compare(rhs.createdAt)
            default:
                switch (lhs.latencyMs, rhs.latencyMs) {
                case let (left?, right?):
                    result = left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
                case (nil, nil):
                    result = lhs.displayName.localizedStandardCompare(rhs.displayName)
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
            if result == .orderedSame {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    // MARK: - Actions

    private func select(_ profile: NodeProfile) {
        app.setActive(profile)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func testAllNodes() async {
        guard !testingAll, !app.nodes.isEmpty else { return }
        testingAll = true
        let targets = app.nodes
        testingIDs = Set(targets.map(\.id))
        // Single source of truth for the probe: `AppState.testLatencyResult`
        // measures the active node with an HTTP request through the tunnel while
        // connected, and falls back to the direct TCP handshake for everything else.
        // Results arrive in small batches so a long subscription does not open
        // hundreds of sockets at once.
        let concurrency = LatencyTester.defaultConcurrency
        var index = 0
        while index < targets.count {
            let end = min(index + concurrency, targets.count)
            let batch = Array(targets[index..<end])
            await withTaskGroup(of: (String, Int?).self) { group in
                for profile in batch {
                    let profileID = profile.id
                    group.addTask { (profileID, await self.app.testLatencyResult(for: profile)) }
                }
                for await (profileID, latency) in group {
                    app.updateLatency(profileID: profileID, latencyMs: latency)
                    testingIDs.remove(profileID)
                }
            }
            index = end
        }
        app.reload()
        testingIDs.removeAll()
        testingAll = false
    }

    /// Refreshes one subscription from its group header (B13). Concurrent refreshes
    /// of the same subscription are suppressed by the service-level fetch gate.
    private func refresh(_ subscription: Subscription) async {
        guard !refreshingSubscriptionIDs.contains(subscription.id) else { return }
        refreshingSubscriptionIDs.insert(subscription.id)
        defer { refreshingSubscriptionIDs.remove(subscription.id) }
        do {
            try await app.refresh(subscription: subscription)
            toast = String(format: L10n.t("nodes.updated", table: "Nodes"), Self.relative(Date()))
        } catch {
            if let subscriptionError = error as? SubscriptionError,
               subscriptionError == .refreshInProgress { return }
            toast = "\(L10n.t("nodes.updateFailed", table: "Nodes")) · \(error.localizedDescription)"
        }
    }

    private var deleteDialogTitle: String {
        L10n.t("nodes.deleteConfirmTitle", table: "Nodes")
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { deleteCandidate != nil },
            set: { presented in
                if !presented { deleteCandidate = nil }
            }
        )
    }

    // MARK: - Presentation

    private func open(_ flow: NodeFlow) {
        if activeFlow != nil || showScan {
            pendingFlow = flow
            activeFlow = nil
            showScan = false
        } else {
            present(flow)
        }
    }

    private func present(_ flow: NodeFlow) {
        switch flow {
        case .scan:
            showScan = true
        default:
            activeFlow = flow
        }
    }

    private func presentPendingFlow() {
        guard let next = pendingFlow else { return }
        pendingFlow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            present(next)
        }
    }

    @ViewBuilder
    private func sheetContent(for flow: NodeFlow) -> some View {
        switch flow {
        case .menu:
            AddNodeMenuSheet { selection in
                open(selection)
            }
        case .addNode:
            NavigationStack {
                AddNodeFormView(initialProtocol: debugAddFormProtocol,
                                onClose: { activeFlow = nil })
            }
        case .edit(let profile):
            NavigationStack {
                AddNodeFormView(editingProfile: profile,
                                onClose: { activeFlow = nil })
            }
        case .actions(let profile):
            NodeActionsSheet(profile: profile)
        case .paste:
            NavigationStack {
                PasteImportView(initialText: debugPasteInitialText, onImport: { summary in
                    toast = summary.message
                })
            }
        case .addSubscription:
            AddSubscriptionView()
        case .scan:
            EmptyView()
        }
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Debug screenshot harness

    private func handleDebugArguments() {
        #if DEBUG
        guard !didHandleDebug else { return }
        didHandleDebug = true
        if let search = DebugScreenshotRoute.value("-WujiScreenshotSearch") {
            searchText = search
        }
        if DebugScreenshotRoute.value("-WujiScreenshotPage") == "nodes-add-vless-full" {
            debugFullScreenFlow = .addNode
            return
        }
        if let page = DebugScreenshotRoute.value("-WujiScreenshotPage") {
            switch page {
            case "nodes-menu":
                activeFlow = .menu
            case "nodes-add", "nodes-add-vless", "nodes-add-trojan", "nodes-add-ss", "nodes-add-socks", "nodes-add-invalid":
                activeFlow = .addNode
            case "nodes-scan", "nodes-scan-preview":
                showScan = true
            case "nodes-paste", "nodes-paste-data", "nodes-paste-socks":
                activeFlow = .paste
            case "nodes-actions":
                if let profile = app.nodes.first {
                    activeFlow = .actions(profile)
                }
            case "nodes-add-subscription":
                activeFlow = .addSubscription
            default:
                break
            }
        }
        switch DebugScreenshotRoute.value("-WujiScreenshotAction") {
        case "test":
            Task { await testAllNodes() }
        case "sort-name":
            app.settings.sortField = "name"
            app.settings.sortAscending = true
            app.saveSettings()
        case "sort-latency-desc":
            app.settings.sortField = "latency"
            app.settings.sortAscending = false
            app.saveSettings()
        default:
            break
        }
        #endif
    }

    /// Protocol shown by the debug-launched add form. Read straight from the launch
    /// arguments so the sheet content is built with the right value on first render.
    private var debugAddFormProtocol: ProxyProtocol {
        #if DEBUG
        switch DebugScreenshotRoute.value("-WujiScreenshotPage") {
        case "nodes-add-vless", "nodes-add-vless-full": return .vless
        case "nodes-add-trojan": return .trojan
        case "nodes-add-ss": return .shadowsocks
        case "nodes-add-socks": return .socks
        default: return .vmess
        }
        #else
        return .vmess
        #endif
    }

    /// Pre-filled links for the debug-launched paste page (read at sheet creation time).
    private var debugPasteInitialText: String? {
        #if DEBUG
        switch DebugScreenshotRoute.value("-WujiScreenshotPage") {
        case "nodes-paste-data": return Self.debugSampleLinks
        case "nodes-paste-socks": return Self.debugSocksLinks
        default: return nil
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    static let debugSampleLinks = """
    vless://b9d3f7e2-6a4c-4f5d-8e91-2c7a0e4b9f3d@203.0.113.24:443?type=ws&security=tls&sni=example.com&path=%2Fws#Tokyo-01
    vmess://eyJ2IjoiMiIsInBzIjoiU2VvdWwtMDIiLCJhZGQiOiIyMDMuMC4xMTMuMjUiLCJwb3J0IjoiNDQzIiwiaWQiOiJiOWQzZjdlMi02YTRjLTRmNWQtOGU5MS0yYzdhMGU0YjlmM2QiLCJhaWQiOiIwIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJzZW91bC5leGFtcGxlIiwicGF0aCI6Ii93cyIsInRscyI6InRscyJ9
    trojan://demo-password@trojan.example:443?security=tls&sni=trojan.example#Frankfurt
    ss://YWVzLTI1Ni1nY206ZGVtby1wYXNzd29yZA==@198.51.100.10:8388#Singapore
    """

    /// SOCKS5 links for the screenshot harness: base64 userinfo, plain userinfo, no auth.
    static let debugSocksLinks = """
    socks://c29ja3MtdXNlcjpzb2Nrcy1wYXNz@203.0.113.31:1080#Socks%20Base64
    socks://plain-user:plain-pass@203.0.113.32:1080#Socks%20Plain
    socks5://203.0.113.33:1080#Socks%20NoAuth
    """
    #endif
}

// MARK: - Add menu

struct AddNodeMenuSheet: View {
    let onSelect: (NodeFlow) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                menuRow(symbol: "square.and.pencil",
                        title: L10n.t("nodes.addMenu.manual", table: "Nodes"),
                        identifier: "wuji.nodes.addMenu.manual") {
                    onSelect(.addNode)
                }
                sheetDivider
                menuRow(symbol: "qrcode.viewfinder",
                        title: L10n.t("nodes.addMenu.scan", table: "Nodes"),
                        identifier: "wuji.nodes.addMenu.scan") {
                    onSelect(.scan)
                }
                sheetDivider
                menuRow(symbol: "doc.on.clipboard",
                        title: L10n.t("nodes.addMenu.paste", table: "Nodes"),
                        identifier: "wuji.nodes.addMenu.paste") {
                    onSelect(.paste)
                }
                sheetDivider
                menuRow(symbol: "link",
                        title: L10n.t("nodes.addMenu.subscription", table: "Nodes"),
                        identifier: "wuji.nodes.addMenu.subscription") {
                    onSelect(.addSubscription)
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

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
            .buttonStyle(SheetRowButtonStyle(cornerRadius: Theme.cardRadius))
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityIdentifier("wuji.nodes.addMenu.cancel")
        }
        .padding(.horizontal, Theme.hMargin)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var sheetDivider: some View {
        Divider().padding(.leading, 52)
    }

    private func menuRow(symbol: String, title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.tint)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(SheetRowButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// Native-looking pressed highlight for custom sheet rows (matches list selection gray).
struct SheetRowButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color(.systemGray4).opacity(0.6) : Color.clear)
            )
    }
}
