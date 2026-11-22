import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

/// Real-time proxy / direct connection log (macOS only).
///
/// The tunnel extension keeps at most 1 MB of parsed Xray access-log lines in memory
/// (nothing is persisted) and the app polls it while this page is visible. The page
/// keeps its own 1 MB ring buffer so long-running sessions never grow unbounded.
struct AccessLogView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var store = AccessLogStore()

    private var visibleEntries: [AccessLogEntry] {
        guard let filter = store.filter else { return store.entries }
        return store.entries.filter { $0.route == filter }
    }

    var body: some View {
        MacGlassPage {
            VStack(alignment: .leading, spacing: 14) {
                header
                logCard
            }
            .frame(maxWidth: 900, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .task {
            store.start(tunnel: app.tunnel)
        }
        .onDisappear {
            store.stop()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L10n.t("tab.logs"))
                .font(MacGlass.titleFont)
                .foregroundStyle(Theme.label)
                .fixedSize()

            Picker("", selection: $store.filter) {
                Text(L10n.t("logs.all")).tag(String?.none)
                Text(L10n.t("logs.proxy")).tag(String?.some("proxy"))
                Text(L10n.t("logs.direct")).tag(String?.some("direct"))
                Text(L10n.t("logs.dns")).tag(String?.some("dns"))
                Text(L10n.t("logs.other")).tag(String?.some("other"))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(store.paused ? Color(nsColor: .systemOrange)
                          : (store.isLive ? Color(nsColor: .systemGreen) : Color(nsColor: .tertiaryLabelColor)))
                    .frame(width: 7, height: 7)
                Text(store.paused ? L10n.t("logs.paused") : (store.isLive ? L10n.t("logs.live") : "—"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryLabel)
                    .fixedSize()
            }

            Button(L10n.t("logs.save")) {
                saveDisplayedLogs()
            }
            .disabled(visibleEntries.isEmpty)

            Button(store.paused ? L10n.t("logs.resume") : L10n.t("logs.pause")) {
                store.setPaused(!store.paused)
            }

            Button(L10n.t("logs.clear")) {
                store.clear()
            }
        }
        .padding(.horizontal, 4)
    }

    /// Exports the currently visible (filtered, newest-first) entries as a plain text file.
    private func saveDisplayedLogs() {
        let entries = visibleEntries
        guard !entries.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let lines = entries.map { entry in
            let route = L10n.t(routeLabelKey(for: entry.route))
            return "\(formatter.string(from: entry.timestamp))\t\(route)\t\(entry.host)\t\(entry.destination)\t\(entry.detour)"
        }
        let text = lines.joined(separator: "\n") + "\n"

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = L10n.t("logs.save")
        panel.nameFieldStringValue = "Wuji-logs-\(stamp.string(from: Date())).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func routeLabelKey(for route: String) -> String {
        switch route {
        case "proxy": return "logs.proxy"
        case "direct": return "logs.direct"
        case "dns": return "logs.dns"
        default: return "logs.other"
        }
    }

    private var logCard: some View {
        MacGlassCard {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleEntries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text(L10n.t("logs.empty"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 120)
                    } else {
                        ForEach(visibleEntries) { entry in
                            row(entry)
                            MacGlassDivider()
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ entry: AccessLogEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 62, alignment: .leading)

            Text(L10n.t(labelKey(for: entry.route)))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint(for: entry.route))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint(for: entry.route).opacity(0.14), in: Capsule())
                .frame(width: 46)

            Text(entry.host)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.destination)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func labelKey(for route: String) -> String {
        switch route {
        case "proxy": return "logs.proxy"
        case "direct": return "logs.direct"
        case "dns": return "logs.dns"
        default: return "logs.other"
        }
    }

    private func tint(for route: String) -> Color {
        switch route {
        case "proxy": return Color(nsColor: .systemBlue)
        case "direct": return Color(nsColor: .systemGreen)
        case "dns": return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .secondaryLabelColor)
        }
    }
}

@MainActor
final class AccessLogStore: ObservableObject {
    private static let maxBytes = 1_000_000

    /// Newest first: index 0 is the most recent connection.
    @Published private(set) var entries: [AccessLogEntry] = []
    @Published var paused = false
    @Published var filter: String?
    @Published private(set) var isLive = false

    private weak var tunnel: TunnelController?
    private var timer: Timer?
    private var nextSeq = 0
    private var bytes = 0
    private var fetching = false

    func start(tunnel: TunnelController) {
        self.tunnel = tunnel
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setPaused(_ value: Bool) {
        paused = value
        if !value { refresh() }
    }

    func clear() {
        entries.removeAll()
        bytes = 0
        nextSeq = 0
        Task { [weak self] in
            await self?.tunnel?.clearAccessLog()
            self?.refresh()
        }
    }

    private func refresh() {
        guard !paused, !fetching, let tunnel else { return }
        fetching = true
        let after = nextSeq
        Task { [weak self] in
            guard let self else { return }
            let batch = await tunnel.requestAccessLogs(after: after)
            await MainActor.run {
                self.fetching = false
                guard let batch else {
                    self.isLive = false
                    return
                }
                self.isLive = true
                if entryAppend(batch.entries) {
                    self.nextSeq = max(self.nextSeq, batch.next)
                    self.trimToBudget()
                }
            }
        }
    }

    private func entryAppend(_ newEntries: [AccessLogEntry]) -> Bool {
        guard !newEntries.isEmpty else { return true }
        let existing = Set(entries.map(\.seq))
        let fresh = newEntries.filter { !existing.contains($0.seq) }
        guard !fresh.isEmpty else { return true }
        // Extension sends oldest -> newest; keep the UI newest -> oldest.
        entries.insert(contentsOf: fresh.reversed(), at: 0)
        for entry in fresh {
            bytes += entry.host.utf8.count + entry.destination.utf8.count + entry.detour.utf8.count + 96
        }
        return true
    }

    private func trimToBudget() {
        // Newest entries stay at the front; drop the oldest from the tail of the
        // in-memory ring buffer once the 1 MB budget is exceeded.
        while bytes > Self.maxBytes, !entries.isEmpty {
            let removed = entries.removeLast()
            bytes -= removed.host.utf8.count + removed.destination.utf8.count + removed.detour.utf8.count + 96
        }
        if bytes < 0 { bytes = 0 }
    }
}

#endif
