import SwiftUI

// MARK: - Confirmation sheet
//
// The project uses its own confirmation surfaces instead of the system alert style
// (docs/app-build-rules.md §3). This sheet follows the native visual language used by
// the add menu sheet in `N-add-menu`: grabber, title, message, a white card with the
// destructive action and cancel.

struct ConfirmationRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive: Bool = true
    let onConfirm: () -> Void
}

struct ConfirmationSheet: View {
    let request: ConfirmationRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 18)
            // Long messages (small screens, accessibility text sizes) scroll instead of
            // being clipped by a fixed-height detent.
            ScrollView {
                VStack(spacing: 6) {
                    Text(request.title)
                        .font(.headline)
                        .foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wuji.confirmation.title")
                    Text(request.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryLabel)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wuji.confirmation.message")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 0) {
                Button {
                    dismiss()
                    DispatchQueue.main.async { request.onConfirm() }
                } label: {
                    Text(request.confirmTitle)
                        .font(Theme.buttonLabel)
                        .foregroundStyle(request.isDestructive ? Theme.red : Theme.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wuji.confirmation.confirm")
                Divider()
                    .padding(.leading, 16)
                Button {
                    dismiss()
                } label: {
                    Text(L10n.t("common.cancel"))
                        .font(Theme.buttonLabel)
                        .foregroundStyle(Theme.tint)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wuji.confirmation.cancel")
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, Theme.hMargin)
            .padding(.bottom, 12)
        }
        .background(Theme.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Lightweight toast

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.black.opacity(0.78))
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        // Informational only: let taps pass through to the content below.
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("wuji.toast")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard newValue != nil else { return }
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_200_000_000)
                    guard !Task.isCancelled else { return }
                    self.message = nil
                }
            }
    }
}

extension View {
    func wujiToast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - Reusable grouped row

/// Plain label/value row used by the settings and subscription screens, matching the
/// native inset-grouped list rows in the approved design references.
struct ValueRow: View {
    let title: String
    var value: String?
    var showsChevron = false
    var valueColor: Color = Theme.secondaryLabel

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.label)
            Spacer(minLength: 12)
            if let value {
                Text(value)
                    .font(Theme.body)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .frame(minHeight: 24)
        .contentShape(Rectangle())
    }
}

/// Inset-grouped section header that always renders uppercase, matching the approved
/// design references (English). Chinese strings are unaffected by uppercasing.
struct UppercaseSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .textCase(.uppercase)
    }
}
