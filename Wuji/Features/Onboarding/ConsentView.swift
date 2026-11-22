import SwiftUI

struct ConsentView: View {
    @EnvironmentObject private var app: AppState
    @State private var agreed = false
    @State private var didConfigureDebug = false
    @State private var debugShowTerms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.t("consent.title"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    Text(L10n.t("consent.paragraph1"))
                        .padding(.top, 20)
                    Text(L10n.t("consent.noAccounts", table: "Nodes"))
                        .padding(.top, 16)
                    Text(L10n.t("consent.paragraph3", table: "Nodes"))
                        .padding(.top, 16)
                    Text(L10n.t("consent.permissions", table: "Nodes"))
                        .padding(.top, 16)

                    legalCard
                        .padding(.top, 28)

                    agreementRow
                        .padding(.top, 28)
                }
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
                .padding(.horizontal, Theme.hMargin)
                .padding(.bottom, 28)
                .wujiMacContentWidth(760)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(L10n.t("consent.navTitle"))
            .wujiInlineNavigationTitle()
            .navigationDestination(isPresented: $debugShowTerms) {
                LegalDocumentView(kind: .terms)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: L10n.t("consent.continue")) {
                    accept()
                }
                .disabled(!agreed)
                .opacity(agreed ? 1 : 0.4)
                .accessibilityIdentifier("wuji.consent.continueButton")
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Theme.background)
            }
        }
        .onAppear(perform: configureFromDebugArguments)
    }

    // MARK: - Sections

    private var legalCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LegalDocumentView(kind: .terms)
            } label: {
                linkRow(symbol: "doc.text", title: L10n.t("settings.terms"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.consent.termsLink")

            Divider()
                .padding(.leading, 52)

            NavigationLink {
                LegalDocumentView(kind: .privacy)
            } label: {
                linkRow(symbol: "hand.raised", title: L10n.t("settings.privacy"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wuji.consent.privacyLink")
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func linkRow(symbol: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.secondaryLabel)
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
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var agreementRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { agreed.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                checkbox
                Text(L10n.t("consent.agree"))
                    .font(.body)
                    .foregroundStyle(Theme.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("consent.agree"))
        .accessibilityValue(agreed ? L10n.t("consent.checked", table: "Nodes") : L10n.t("consent.unchecked", table: "Nodes"))
        .accessibilityAddTraits(agreed ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("wuji.consent.checkbox")
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(agreed ? Theme.tint : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(agreed ? Color.clear : Theme.gray3, lineWidth: 1.5)
            )
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(agreed ? 1 : 0)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func accept() {
        guard agreed else { return }
        app.settings.consentAccepted = true
        app.saveSettings()
    }

    private func configureFromDebugArguments() {
        #if DEBUG
        guard !didConfigureDebug else { return }
        didConfigureDebug = true
        guard let value = DebugScreenshotRoute.value("-WujiScreenshotPage") else { return }
        switch value {
        case "consent-agreed":
            agreed = true
        case "consent-terms":
            debugShowTerms = true
        default:
            break
        }
        #endif
    }
}
