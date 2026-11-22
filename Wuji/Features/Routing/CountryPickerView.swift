import SwiftUI

/// Multi-select country/region picker for bypass routing (spec §5.10, design reference
/// `N-country-picker`). Presented as a sheet from the routing screen; edits are applied
/// to a draft set and only committed on Done.
struct CountryPickerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Set<String> = []
    @State private var query = ""
    @State private var didLoadDraft = false

    private var allCountries: [CountryInfo] {
        app.countries.countries
    }

    private var filteredCountries: [CountryInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return allCountries }
        return allCountries.filter { country in
            country.name.localizedCaseInsensitiveContains(trimmed) ||
            country.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var selectedCountries: [CountryInfo] {
        filteredCountries.filter { draft.contains($0.code) }
    }

    private var unselectedCountries: [CountryInfo] {
        filteredCountries.filter { !draft.contains($0.code) }
    }

    private var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if allCountries.isEmpty {
                    unavailableState
                } else {
                    list
                }
            }
            .navigationTitle(L10n.t("routing.regionPickerTitle"))
            .wujiInlineNavigationTitle()
            .wujiSearchable(text: $query,
                             prompt: L10n.t("routing.searchRegions"))
            .toolbar {
                ToolbarItem(placement: .wujiLeading) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .accessibilityIdentifier("wuji.routing.picker.cancel")
                }
                ToolbarItem(placement: .wujiTrailing) {
                    Button(L10n.t("common.done")) { commit() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("wuji.routing.picker.done")
                }
            }
            .onAppear(perform: loadDraftIfNeeded)
        }
        .wujiMacSheetActions(onCancel: { dismiss() },
                             confirmTitle: L10n.t("common.done"),
                             onConfirm: { commit() })
    }

    // MARK: - List

    private var list: some View {
        WujiSettingsList {
            if hasSearchQuery && selectedCountries.isEmpty && unselectedCountries.isEmpty {
                noResultsState
            } else {
                if !selectedCountries.isEmpty {
                    Section {
                        ForEach(selectedCountries) { country in
                            countryRow(country, isSelected: true)
                        }
                    } header: {
                        sectionHeader(title: L10n.t("routing.picker.selected", table: "Routing"),
                                      count: draft.count)
                    }
                }
                if !unselectedCountries.isEmpty {
                    Section {
                        ForEach(unselectedCountries) { country in
                            countryRow(country, isSelected: false)
                        }
                    } header: {
                        allRegionsHeader
                    }
                }
            }
        }
        
        .accessibilityIdentifier("wuji.routing.picker.list")
    }

    private var allRegionsHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.t("routing.picker.all", table: "Routing"))
            Spacer(minLength: 0)
            Menu {
                Button(L10n.t("routing.picker.selectAll", table: "Routing")) {
                    draft.formUnion(allCountries.map(\.code))
                }
                .accessibilityIdentifier("wuji.routing.picker.selectAll")
                Button(L10n.t("routing.picker.clearAll", table: "Routing"), role: .destructive) {
                    draft.removeAll()
                }
                .accessibilityIdentifier("wuji.routing.picker.clearAll")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            .accessibilityIdentifier("wuji.routing.picker.menu")
        }
        .textCase(nil)
    }

    private func sectionHeader(title: String, count: Int?) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 0)
            if let count {
                Text(String(format: L10n.t("routing.picker.count", table: "Routing"), count))
            }
        }
        .textCase(nil)
    }

    private func countryRow(_ country: CountryInfo, isSelected: Bool) -> some View {
        Button {
            toggle(country.code)
        } label: {
            HStack(spacing: 16) {
                Text(country.code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 30, alignment: .leading)
                Text(country.name)
                    .font(.body)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(isSelected ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isSelected ? Theme.tint : Theme.tertiaryLabel)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wuji.routing.picker.row.\(country.code)")
        .accessibilityValue(isSelected ? "selected" : "not selected")
    }

    // MARK: - Empty / unavailable states

    private var noResultsState: some View {
        EmptyStateView(symbol: "magnifyingglass",
                       title: L10n.t("routing.picker.noResultsTitle", table: "Routing"),
                       message: L10n.t("routing.picker.noResultsMessage", table: "Routing"))
            .frame(minHeight: 320)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("wuji.routing.picker.noResults")
    }

    private var unavailableState: some View {
        EmptyStateView(symbol: "globe",
                       title: L10n.t("routing.picker.unavailableTitle", table: "Routing"),
                       message: L10n.t("routing.picker.unavailableMessage", table: "Routing"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .accessibilityIdentifier("wuji.routing.picker.unavailable")
    }

    // MARK: - Actions

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        draft = Set(app.settings.bypassCountryCodes)
    }

    private func toggle(_ code: String) {
        if draft.contains(code) {
            draft.remove(code)
        } else {
            draft.insert(code)
        }
    }

    private func commit() {
        // Keep every selected code, even when the bundled region data could not be
        // loaded (the user's existing selection must not be silently dropped).
        let sortedCodes = draft.sorted { lhs, rhs in
            regionName(for: lhs).localizedCaseInsensitiveCompare(regionName(for: rhs)) == .orderedAscending
        }
        app.settings.bypassCountryCodes = sortedCodes
        app.saveSettings()
        dismiss()
    }

    private func regionName(for code: String) -> String {
        if let country = allCountries.first(where: { $0.code == code }) {
            return country.name
        }
        return CountryDirectory.localizedName(for: code)
    }
}
