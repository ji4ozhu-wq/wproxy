import Foundation

// MARK: - Auto-update interval

/// The auto-update choices offered by the subscription form (spec §5.7):
/// Off / 6h / 12h / 24h / 7d. Persisted as seconds in `Subscription.autoUpdateInterval`.
enum SubscriptionUpdateInterval: String, CaseIterable, Identifiable, Sendable {
    case off
    case sixHours
    case twelveHours
    case twentyFourHours
    case sevenDays

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .off: return nil
        case .sixHours: return 6 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        case .sevenDays: return 7 * 24 * 60 * 60
        }
    }

    var displayName: String {
        switch self {
        case .off: return L10n.t("subscriptions.interval.off", table: "Subscriptions")
        case .sixHours: return L10n.t("subscriptions.interval.6h", table: "Subscriptions")
        case .twelveHours: return L10n.t("subscriptions.interval.12h", table: "Subscriptions")
        case .twentyFourHours: return L10n.t("subscriptions.interval.24h", table: "Subscriptions")
        case .sevenDays: return L10n.t("subscriptions.interval.7d", table: "Subscriptions")
        }
    }

    init(seconds: TimeInterval?) {
        guard let seconds, seconds > 0 else {
            self = .off
            return
        }
        switch Int(seconds) {
        case 6 * 60 * 60: self = .sixHours
        case 24 * 60 * 60: self = .twentyFourHours
        case 7 * 24 * 60 * 60: self = .sevenDays
        case 12 * 60 * 60: self = .twelveHours
        default: self = .twelveHours
        }
    }

    init(subscription: Subscription) {
        self.init(seconds: subscription.autoUpdateInterval)
    }
}

// MARK: - Formatting helpers

enum SubscriptionFormat {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    /// "42.6 GB of 100 GB" when a quota is known, just the used amount otherwise.
    static func traffic(used: Int64?, total: Int64?) -> String? {
        guard let used else { return nil }
        let usedText = bytes(used)
        guard let total, total > 0 else { return usedText }
        return String(format: L10n.t("subscriptions.list.flow", table: "Subscriptions"), usedText, bytes(total))
    }

    static func expiry(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// "Updated 2m ago" / "Not updated yet".
    static func updated(_ date: Date?) -> String {
        guard let date else { return L10n.t("subscriptions.list.neverUpdated", table: "Subscriptions") }
        return String(format: L10n.t("subscriptions.list.updated", table: "Subscriptions"), relative(date))
    }

    static func host(_ urlString: String) -> String {
        guard var host = URL(string: urlString)?.host, !host.isEmpty else { return urlString }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}

// MARK: - Lookup helpers

@MainActor
enum SubscriptionLookup {
    static func group(for subscription: Subscription, in app: AppState) -> NodeGroup? {
        app.groups.first(where: { $0.subscriptionID == subscription.id })
    }

    static func nodes(for subscription: Subscription, in app: AppState) -> [NodeProfile] {
        guard let group = group(for: subscription, in: app) else { return [] }
        return app.nodes(in: group)
    }

    static func subscription(id: String, in app: AppState) -> Subscription? {
        app.subscriptions.first(where: { $0.id == id })
    }
}

// MARK: - Import / edit / delete

enum SubscriptionFormError: LocalizedError {
    case invalidURL
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .invalidURL: return L10n.t("subscriptions.add.invalidURL", table: "Subscriptions")
        case .insecureURL: return L10n.t("subscriptions.add.insecureURL", table: "Subscriptions")
        }
    }
}

@MainActor
enum SubscriptionImporter {
    struct AddOutcome {
        let subscription: Subscription
        let nodeCount: Int
    }

    static func normalizeURL(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            throw SubscriptionFormError.invalidURL
        }
        // The form rejects cleartext HTTP the same way the fetcher does, so the user
        // gets a readable message instead of an ATS error. Loopback stays allowed for
        // the local fixture server used by the DEBUG/UI-test harness.
        if scheme == "http", !SubscriptionService.isLoopbackHost(host) {
            throw SubscriptionFormError.insecureURL
        }
        return url.absoluteString
    }

    static func resolvedName(_ raw: String, urlString: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = URL(string: urlString)?.host, !host.isEmpty { return host }
        return L10n.t("subscriptions.defaultName")
    }

    /// Fetches the subscription, then creates the subscription row, its group and its nodes.
    /// The caller surfaces any thrown error in the form and keeps the entered values.
    static func add(app: AppState,
                    rawURL: String,
                    rawName: String,
                    interval: SubscriptionUpdateInterval) async throws -> AddOutcome {
        let urlString = try normalizeURL(rawURL)
        let name = resolvedName(rawName, urlString: urlString)
        let subscriptionID = UUID().uuidString
        let groupID = "subscription-\(subscriptionID)"
        let sortOrder = (app.groups.map(\.sortOrder).max() ?? 0) + 1

        do {
            let result = try await app.subscriptionService.fetch(url: urlString, groupID: groupID, name: name)
            try app.profileStore.upsert(group: NodeGroup(id: groupID,
                                                        name: name,
                                                        kind: .subscription,
                                                        subscriptionID: subscriptionID,
                                                        sortOrder: sortOrder))
            for node in result.nodes {
                try app.profileStore.upsert(profile: node)
            }
            let subscription = Subscription(id: subscriptionID,
                                            url: urlString,
                                            name: name,
                                            autoUpdateInterval: interval.seconds,
                                            lastUpdatedAt: result.updatedAt,
                                            trafficUpload: result.trafficUpload,
                                            trafficDownload: result.trafficDownload,
                                            trafficTotal: result.trafficTotal,
                                            expireAt: result.expireAt,
                                            lastError: nil,
                                            createdAt: Date())
            try app.subscriptionStore.upsert(subscription)
            app.reload()
            app.scheduleLatencyTests(for: result.nodes)
            return AddOutcome(subscription: subscription, nodeCount: result.nodes.count)
        } catch {
            try? app.profileStore.deleteProfiles(inGroup: groupID)
            try? app.profileStore.delete(groupID: groupID)
            throw error
        }
    }

    /// Saves the form values. When the URL changed the node list is refreshed; a failed
    /// refresh keeps the previous nodes and records `lastError` (spec §5.7) before throwing.
    @discardableResult
    static func saveMetadata(app: AppState,
                             subscription: Subscription,
                             rawURL: String,
                             rawName: String,
                             interval: SubscriptionUpdateInterval) async throws -> Subscription {
        let urlString = try normalizeURL(rawURL)
        let name = resolvedName(rawName, urlString: urlString)
        let urlChanged = urlString != subscription.url

        var updated = subscription
        updated.url = urlString
        updated.name = name
        updated.autoUpdateInterval = interval.seconds
        try app.subscriptionStore.upsert(updated)

        if var group = SubscriptionLookup.group(for: updated, in: app) {
            group.name = name
            try app.profileStore.upsert(group: group)
        }
        app.reload()

        if urlChanged {
            // Refresh in the background so the edit form can close immediately. A failed
            // refresh keeps the previous nodes and records `lastError` in the list.
            Task { @MainActor in
                _ = try? await app.refresh(subscription: updated)
            }
        }
        return updated
    }

    /// Deletes the subscription together with its group and nodes. When the running
    /// node belongs to that group the tunnel is disconnected first (B7/G4), so the
    /// kernel never keeps a tunnel whose node row is already gone.
    @discardableResult
    static func delete(app: AppState, subscription: Subscription) async -> Bool {
        if let group = SubscriptionLookup.group(for: subscription, in: app) {
            await app.prepareForRemoval(ofGroup: group.id)
            if let activeID = app.settings.activeProfileID,
               app.nodes(in: group).contains(where: { $0.id == activeID }) {
                app.setActive(nil)
            }
            try? app.profileStore.deleteProfiles(inGroup: group.id)
            try? app.profileStore.delete(groupID: group.id)
        }
        try? app.subscriptionStore.delete(subscription.id)
        app.reload()
        return true
    }
}
