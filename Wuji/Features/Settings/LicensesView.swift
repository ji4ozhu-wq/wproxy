import SwiftUI

// MARK: - Licenses

/// Open source licenses with expandable full texts (spec §5.12).
struct LicensesView: View {
    @State private var expanded: Set<String> = []

    var body: some View {
        WujiSettingsList {
            Section {
                ForEach(LicensesCatalog.components) { component in
                    DisclosureGroup(isExpanded: isExpandedBinding(for: component.id)) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(component.summary)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(component.body)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(component.name)
                                .font(.body)
                                .foregroundStyle(Theme.label)
                            Text(component.license)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryLabel)
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("wuji.settings.licenses.\(component.id)")
                }
            } footer: {
                Text(L10n.t("about.builtWith"))
            }
        }
        .navigationTitle(L10n.t("about.licenses"))
        .wujiInlineNavigationTitle()
        .wujiHiddenTabBar()
    }

    private func isExpandedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expanded.insert(id)
                } else {
                    expanded.remove(id)
                }
            }
        )
    }
}
