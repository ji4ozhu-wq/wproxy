import SwiftUI

struct SectionHeader: View {
    let title: String
    var body: some View {
        // C7 (audit): Chinese has no case; uppercasing would only mangle Latin words
        // embedded in a localized Chinese title. Keep the translated string as-is there.
        Text(Self.uppercased(title))
            .font(Theme.sectionHeader)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.horizontal, Theme.hMargin)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func uppercased(_ title: String) -> String {
        guard Locale.preferredLanguages.first?.hasPrefix("zh") != true else { return title }
        return title.uppercased()
    }
}

struct CardContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .padding(.horizontal, Theme.hMargin)
    }
}

struct PrimaryButton: View {
    let title: String
    var isDestructive = false
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(Theme.buttonLabel)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.buttonHeight)
            .background(isDestructive ? Theme.red : Theme.tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isLoading)
        .padding(.horizontal, Theme.hMargin)
    }
}

struct PlainActionButton: View {
    let title: String
    var color: Color = Theme.tint
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.buttonLabel)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .wujiRowHover()
        }
    }
}

struct DataRowView: View {
    let symbol: String
    let title: String
    var value: String?
    var showsChevron = false
    var titleColor: Color = Theme.label
    var symbolColor: Color = Theme.secondaryLabel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(symbolColor)
                .frame(width: 24)
            Text(title)
                .font(Theme.body)
                .foregroundStyle(showsChevron ? PlatformFlags.interactiveTitleColor : titleColor)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Theme.body)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .padding(.horizontal, Theme.hMargin)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .wujiRowHover(showsChevron)
    }
}

struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 52)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 88, height: 88)
                .background(Theme.fillTertiary)
                .clipShape(Circle())
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Theme.label)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let primaryTitle, let primaryAction {
                PrimaryButton(title: primaryTitle, action: primaryAction)
                    .padding(.top, 6)
            }
            if let secondaryTitle, let secondaryAction {
                PlainActionButton(title: secondaryTitle, action: secondaryAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

struct ConnectionButton: View {
    let state: TunnelState
    var action: () -> Void

    private var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isConnected {
                    Circle()
                        .fill(Theme.tint.opacity(0.12))
                        .frame(width: Theme.connectButtonSize + 24, height: Theme.connectButtonSize + 24)
                }
                Circle()
                    .fill(isConnected ? Theme.tint : Theme.card)
                    .overlay(
                        Circle().strokeBorder(isConnected ? Color.clear : Theme.separator, lineWidth: 1)
                    )
                    .frame(width: Theme.connectButtonSize, height: Theme.connectButtonSize)
                if state.isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.4)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 62, weight: .light))
                        .foregroundStyle(isConnected ? .white : Theme.secondaryLabel)
                }
            }
        }
        .buttonStyle(.plain)
        // B6 (audit): while the tunnel is connecting/disconnecting a further tap must
        // not start a concurrent connect or turn into an unintended disconnect.
        .disabled(state.isBusy)
        .accessibilityIdentifier("wuji.home.connectButton")
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, Theme.hMargin)
    }
}
