import SwiftUI

struct FirstConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAllow: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Scrolls instead of clipping when the system font is turned up.
            ScrollView {
                VStack(spacing: 16) {
                    Text(L10n.t("firstConnect.title"))
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t("firstConnect.body"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 0) {
                PrimaryButton(title: L10n.t("common.allow")) { onAllow() }
                    .accessibilityIdentifier("wuji.home.firstConnect.allow")
                PlainActionButton(title: L10n.t("common.notNow"), color: Theme.secondaryLabel) { onCancel() }
                    .accessibilityIdentifier("wuji.home.firstConnect.notNow")
            }
            .padding(.bottom, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .background(Theme.card)
    }
}
