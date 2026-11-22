import SwiftUI

#if DEBUG
/// DEBUG-only launch-argument helper used by the headless simulator screenshot
/// harness (the Simulator on the build machine has no GUI window to tap).
/// Example: `xcrun simctl launch <udid> com.juejin.ios.wuji -WujiScreenshotPage onboarding2`.
enum DebugScreenshotRoute {
    static func value(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        return value.hasPrefix("-") ? nil : value
    }
}
#endif

struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var page = 0
    @State private var didConfigureDebug = false

    private enum IllustrationLayout {
        case cluster, row, single
    }

    private struct Page {
        let layout: IllustrationLayout
        let symbols: [String]
        let titleKey: String
        let bodyKey: String
    }

    private let pages: [Page] = [
        Page(layout: .cluster,
             symbols: ["power", "server.rack", "arrow.triangle.branch"],
             titleKey: "onboarding.1.title",
             bodyKey: "onboarding.1.body"),
        Page(layout: .row,
             symbols: ["qrcode.viewfinder", "doc.on.clipboard", "link"],
             titleKey: "onboarding.2.title",
             bodyKey: "onboarding.2.body"),
        Page(layout: .single,
             symbols: ["arrow.triangle.branch"],
             titleKey: "onboarding.3.title",
             bodyKey: "onboarding.3.body")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(L10n.t("common.skip")) { finish() }
                    .font(.body)
                    .foregroundStyle(Theme.tint)
                    .accessibilityIdentifier("wuji.onboarding.skipButton")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            #if os(iOS)
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("wuji.onboarding.pager")
            #else
            // macOS has no paged TabView; show the current page and let the
            // "Continue" button (or the page indicator) switch pages.
            pageView(pages[min(page, pages.count - 1)])
                .accessibilityIdentifier("wuji.onboarding.pager")
            #endif

            pageIndicator
                .padding(.bottom, 26)

            PrimaryButton(title: page == pages.count - 1 ? L10n.t("onboarding.getStarted") : L10n.t("common.continue")) {
                advance()
            }
            .accessibilityIdentifier("wuji.onboarding.primaryButton")
            .padding(.bottom, 18)
        }
        .background(Theme.background)
        .onAppear(perform: configureFromDebugArguments)
    }

    // MARK: - Page content

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        // Scrollable so small screens (SE) and accessibility text sizes never clip
        // the title/body; `minHeight` keeps the illustration centered when it fits.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    illustration(page)
                    Spacer().frame(height: 40)
                    Text(L10n.t(page.titleKey))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    Spacer().frame(height: 18)
                    Text(L10n.t(page.bodyKey))
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .wujiMacContentWidth(640)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func illustration(_ page: Page) -> some View {
        switch page.layout {
        case .cluster:
            VStack(spacing: 18) {
                symbolCircle(page.symbols[0], diameter: 88, symbolSize: 42)
                HStack(spacing: 22) {
                    if page.symbols.count > 1 { symbolCircle(page.symbols[1], diameter: 88, symbolSize: 36) }
                    if page.symbols.count > 2 { symbolCircle(page.symbols[2], diameter: 88, symbolSize: 38) }
                }
            }
        case .row:
            HStack(spacing: 20) {
                ForEach(page.symbols.prefix(3), id: \.self) { symbol in
                    symbolCircle(symbol, diameter: 88, symbolSize: 38)
                }
            }
        case .single:
            symbolCircle(page.symbols[0], diameter: 128, symbolSize: 54)
        }
    }

    private func symbolCircle(_ symbol: String, diameter: CGFloat, symbolSize: CGFloat) -> some View {
        Circle()
            .fill(Theme.tint.opacity(0.12))
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: symbolSize, weight: .regular))
                    .foregroundStyle(Theme.tint)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Indicator & actions

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.tint : Theme.gray4)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.t("onboarding.pageIndicator", table: "Nodes"), page + 1, pages.count))
        .accessibilityIdentifier("wuji.onboarding.pageIndicator")
    }

    private func advance() {
        if page < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        app.settings.onboardingDone = true
        app.saveSettings()
    }

    private func configureFromDebugArguments() {
        #if DEBUG
        guard !didConfigureDebug else { return }
        didConfigureDebug = true
        if let value = DebugScreenshotRoute.value("-WujiScreenshotPage") {
            switch value {
            case "onboarding2":
                page = 1
            case "onboarding3":
                page = 2
            case "consent-unchecked", "consent-agreed", "consent-terms":
                // Screenshot harness: skip onboarding so the consent gate is visible.
                finish()
            default:
                page = 0
            }
        }
        #endif
    }
}
