import SwiftUI
import os

/// Add / edit subscription form (spec §5.7, design reference `N-subscription-add`).
/// Presented as its own sheet: it owns a `NavigationStack` so it can push the
/// auto-update interval picker. Callers should present it directly:
/// `.sheet { AddSubscriptionView() }`.
struct AddSubscriptionView: View {
    private static let log = Logger(subsystem: "com.juejin.ios.wuji", category: "AddSubscription")
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// `nil` = add a new subscription; non-nil = edit that subscription.
    private let editingSubscription: Subscription?

    @State private var url: String
    @State private var name: String
    @State private var interval: SubscriptionUpdateInterval
    @State private var isLoading = false
    @State private var formError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case url
        case name
    }

    init(editing subscription: Subscription? = nil) {
        self.editingSubscription = subscription
        _url = State(initialValue: subscription?.url ?? "")
        _name = State(initialValue: subscription?.name ?? "")
        _interval = State(initialValue: subscription.map(SubscriptionUpdateInterval.init(subscription:)) ?? .twelveHours)
    }

    private var isEditing: Bool { editingSubscription != nil }

    private var titleText: String {
        isEditing
            ? L10n.t("subscriptions.edit.title", table: "Subscriptions")
            : L10n.t("subscriptionAdd.title")
    }

    private var submitTitle: String {
        isEditing
            ? L10n.t("common.save")
            : L10n.t("subscriptions.add.action", table: "Subscriptions")
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isLoading && !trimmedURL.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L10n.t("subscriptions.add.urlPlaceholder", table: "Subscriptions"), text: $url)
                        .focused($focusedField, equals: .url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .disabled(isLoading)
                        .accessibilityIdentifier("wuji.subscriptions.add.urlField")
                } header: {
                    UppercaseSectionHeader(title: L10n.t("subscriptionAdd.urlSection"))
                }

                Section {
                    HStack(spacing: 12) {
                        Text(L10n.t("subscriptionAdd.name"))
                            .foregroundStyle(Theme.label)
                        TextField("", text: $name)
                            .focused($focusedField, equals: .name)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .disabled(isLoading)
                            .accessibilityIdentifier("wuji.subscriptions.add.nameField")
                    }
                    NavigationLink {
                        intervalPicker
                    } label: {
                        ValueRow(title: L10n.t("subscriptions.add.autoUpdate", table: "Subscriptions"),
                                 value: interval.displayName)
                    }
                    .disabled(isLoading)
                    .accessibilityIdentifier("wuji.subscriptions.add.autoUpdate")
                } header: {
                    UppercaseSectionHeader(title: L10n.t("subscriptionAdd.details"))
                } footer: {
                    Text(L10n.t("subscriptions.add.footnote", table: "Subscriptions"))
                }

                if let formError {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.red)
                            Text(formError)
                                .font(.footnote)
                                .foregroundStyle(Theme.label)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("wuji.subscriptions.form.error")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .environment(\.defaultMinListRowHeight, 44)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .disabled(isLoading)
                        .accessibilityIdentifier("wuji.subscriptions.add.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.save")) { Task { await submit() } }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("wuji.subscriptions.add.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.t("common.done")) { focusedField = nil }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    PrimaryButton(title: submitTitle, isLoading: isLoading) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("wuji.subscriptions.add.submit")
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                .background(Theme.background)
            }
        }
    }

    // MARK: - Interval picker

    private var intervalPicker: some View {
        List {
            ForEach(SubscriptionUpdateInterval.allCases) { option in
                Button {
                    interval = option
                } label: {
                    HStack {
                        Text(option.displayName)
                            .foregroundStyle(Theme.label)
                        Spacer()
                        if interval == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wuji.subscriptions.add.interval.\(option.rawValue)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("subscriptions.add.autoUpdate", table: "Subscriptions"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Submit

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        formError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            if let editingSubscription {
                try await SubscriptionImporter.saveMetadata(app: app,
                                                            subscription: editingSubscription,
                                                            rawURL: url,
                                                            rawName: name,
                                                            interval: interval)
            } else {
                _ = try await SubscriptionImporter.add(app: app,
                                                       rawURL: url,
                                                       rawName: name,
                                                       interval: interval)
            }
            dismiss()
        } catch {
            Self.log.error("Adding the subscription failed: \(error.localizedDescription, privacy: .private)")
            formError = error.localizedDescription
        }
    }
}
