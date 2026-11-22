import SwiftUI

/// Manual node form (spec §5.4 / §5.8). One protocol segment drives the visible fields.
/// Presented inside a `NavigationStack` (as a sheet for add, pushed for edit).
struct AddNodeFormView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let editingProfile: NodeProfile?
    let showsCancelButton: Bool
    var onSaved: (() -> Void)?
    /// Explicit dismissal route for sheet presentations. `@Environment(\.dismiss)`
    /// can silently fail when the form pushed a navigation destination first
    /// (e.g. the security picker), leaving the save button on screen after saving.
    var onClose: (() -> Void)?

    @State private var proto: ProxyProtocol
    @State private var name: String
    @State private var server: String
    @State private var port: String
    @State private var uuid: String
    @State private var alterID: String
    @State private var vmessSecurity: String
    @State private var flow: String
    @State private var password: String
    @State private var socksUsername: String
    @State private var ssMethod: String
    @State private var network: Transport
    @State private var security: SecurityLayer
    @State private var sni: String
    @State private var wsPath: String
    @State private var wsHost: String
    @State private var grpcService: String
    @State private var fingerprint: String
    @State private var allowInsecure: Bool
    @State private var realityPublicKey: String
    @State private var realityShortID: String
    @State private var errors: [String: String] = [:]
    @State private var saveError: String?
    @State private var saving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, address, port, uuid, alterID, password, socksUsername, sni, wsPath, wsHost, grpcService, realityPublicKey, realityShortID
    }

    private static let vmessSecurityOptions = ["auto", "aes-128-gcm", "chacha20-poly1305", "none"]
    private static let shadowsocksMethods = [
        "aes-256-gcm", "aes-128-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305"
    ]
    private static let fingerprintOptions = ["", "chrome", "firefox", "safari", "ios", "android", "edge", "randomized"]

    private static func fingerprintLabel(_ value: String) -> String {
        switch value {
        case "ios": return "iOS"
        case "edge": return "Edge"
        case "randomized": return "Randomized"
        default: return value.capitalized
        }
    }

    init(editingProfile: NodeProfile? = nil,
         initialProtocol: ProxyProtocol = .vmess,
         showsCancelButton: Bool = true,
         onSaved: (() -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        self.editingProfile = editingProfile
        self.showsCancelButton = showsCancelButton
        self.onSaved = onSaved
        self.onClose = onClose
        let profile = editingProfile
        _proto = State(initialValue: profile?.proto ?? initialProtocol)
        _name = State(initialValue: profile?.name ?? "")
        _server = State(initialValue: profile?.server ?? "")
        _port = State(initialValue: profile.map { String($0.port) } ?? "")
        _uuid = State(initialValue: profile?.uuid ?? "")
        _alterID = State(initialValue: profile.map { String($0.alterID) } ?? "")
        _vmessSecurity = State(initialValue: profile?.vmessSecurity ?? "auto")
        _flow = State(initialValue: profile?.flow ?? "")
        _password = State(initialValue: profile?.password ?? "")
        _socksUsername = State(initialValue: profile?.socksUsername ?? "")
        _ssMethod = State(initialValue: profile.map { $0.ssMethod.isEmpty ? "aes-256-gcm" : $0.ssMethod } ?? "aes-256-gcm")
        _network = State(initialValue: profile?.network ?? .tcp)
        _security = State(initialValue: profile?.security ?? .none)
        _sni = State(initialValue: profile?.sni ?? "")
        _wsPath = State(initialValue: profile?.wsPath ?? "")
        _wsHost = State(initialValue: profile?.wsHost ?? "")
        _grpcService = State(initialValue: profile?.grpcService ?? "")
        _fingerprint = State(initialValue: profile?.fingerprint ?? "")
        _allowInsecure = State(initialValue: profile?.allowInsecure ?? false)
        _realityPublicKey = State(initialValue: profile?.realityPublicKey ?? "")
        _realityShortID = State(initialValue: profile?.realityShortID ?? "")
    }

    private var isEditing: Bool { editingProfile != nil }

    private var title: String {
        isEditing ? L10n.t("nodes.form.editTitle", table: "Nodes") : L10n.t("nodes.form.title", table: "Nodes")
    }

    private var networkOptions: [Transport] {
        switch proto {
        case .vmess, .vless: return [.tcp, .ws, .grpc, .h2]
        case .trojan: return [.tcp, .ws, .grpc]
        case .shadowsocks, .socks: return [.tcp]
        }
    }

    var body: some View {
        Form {
            protocolSection
            if let saveError {
                Section {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .accessibilityIdentifier("wuji.nodes.form.saveError")
                }
            }
            serverSection
            credentialsSection
            if proto != .shadowsocks && proto != .socks {
                transportSection
            }
            if proto != .shadowsocks && proto != .socks {
                advancedSection
            }
            if proto == .vless && security == .reality {
                realitySection
            }
        }
        #if os(macOS)
        // macOS `Form` defaults to the two-column inspector style, which fights the
        // custom label/field rows (labels get pushed around, fields overflow). The
        // grouped style renders the same rows as a native settings list.
        .formStyle(.grouped)
        #endif
        .wujiListBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .wujiInlineNavigationTitle()
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .wujiLeading) {
                    Button(L10n.t("common.cancel")) { close() }
                        .accessibilityIdentifier("wuji.nodes.form.cancelButton")
                }
            }
            ToolbarItem(placement: .wujiTrailing) {
                Button {
                    save()
                } label: {
                    if saving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.t("common.save"))
                            .fontWeight(.semibold)
                    }
                }
                .disabled(saving)
                .accessibilityLabel(L10n.t("common.save"))
                .accessibilityIdentifier("wuji.nodes.form.saveButton")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.t("common.done")) {
                    focusedField = nil
                }
                .accessibilityIdentifier("wuji.nodes.form.keyboardDone")
            }
        }
        .onAppear(perform: configureFromDebugArguments)
        .onChange(of: proto) { _, newValue in
            applyProtocolDefaults(for: newValue)
        }
        .onChange(of: security) { _, newValue in
            if newValue == .none {
                allowInsecure = false
            }
        }
        // macOS sheets don't render SwiftUI toolbar items, so the form gets a
        // visible bottom Cancel/Save bar there (iOS keeps its toolbar buttons).
        .wujiMacSheetActions(onCancel: { close() },
                             confirmTitle: L10n.t("common.save"),
                             confirmDisabled: saving,
                             onConfirm: { save() })
    }

    // MARK: - Sections

    private var protocolSection: some View {
        Section {
            #if os(macOS)
            // macOS does not compress a segmented control to the available width, so
            // the five protocol segments overflow the sheet and the last one is clipped.
            // Use the native menu picker there.
            Picker(L10n.t("nodes.form.section.protocol", table: "Nodes"), selection: $proto) {
                ForEach(ProxyProtocol.allCases, id: \.self) { value in
                    Text(value == .shadowsocks ? value.shortBadge : value.displayName).tag(value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier("wuji.nodes.form.protocolPicker")
            #else
            Picker("", selection: $proto) {
                ForEach(ProxyProtocol.allCases, id: \.self) { value in
                    Text(value == .shadowsocks ? value.shortBadge : value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("wuji.nodes.form.protocolPicker")
            #endif
        } header: {
            Text(L10n.t("nodes.form.section.protocol", table: "Nodes"))
        }
    }

    private var serverSection: some View {
        Section {
            fieldRow(label: L10n.t("nodes.form.name", table: "Nodes"),
                     placeholder: L10n.t("nodes.form.namePlaceholder", table: "Nodes"),
                     text: $name, field: .name,
                     identifier: "wuji.nodes.form.name")
            fieldRow(label: L10n.t("nodes.form.address", table: "Nodes"),
                     placeholder: "example.com",
                     text: $server, field: .address,
                     keyboard: .url,
                     identifier: "wuji.nodes.form.address")
            errorRow("server")
            fieldRow(label: L10n.t("nodes.form.port", table: "Nodes"),
                     placeholder: "443",
                     text: $port, field: .port,
                     keyboard: .numberPad,
                     identifier: "wuji.nodes.form.port")
            errorRow("port")
            errorRow("duplicate")
        } header: {
            Text(L10n.t("nodes.form.section.server", table: "Nodes"))
        }
    }

    @ViewBuilder
    private var credentialsSection: some View {
        Section {
            switch proto {
            case .vmess:
                fieldRow(label: L10n.t("nodes.form.uuid", table: "Nodes"),
                         text: $uuid, field: .uuid,
                         identifier: "wuji.nodes.form.uuid")
                errorRow("uuid")
                fieldRow(label: L10n.t("nodes.form.alterID", table: "Nodes"),
                         placeholder: "0",
                         text: $alterID, field: .alterID,
                         keyboard: .numberPad,
                         identifier: "wuji.nodes.form.alterID")
                Picker(L10n.t("nodes.form.encryption", table: "Nodes"), selection: $vmessSecurity) {
                    ForEach(Self.vmessSecurityOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .wujiNavigationLinkPickerStyle()
                .accessibilityIdentifier("wuji.nodes.form.encryption")
            case .vless:
                fieldRow(label: L10n.t("nodes.form.uuid", table: "Nodes"),
                         text: $uuid, field: .uuid,
                         identifier: "wuji.nodes.form.uuid")
                errorRow("uuid")
                Picker(L10n.t("nodes.form.flow", table: "Nodes"), selection: $flow) {
                    Text(L10n.t("nodes.form.none", table: "Nodes")).tag("")
                    Text("xtls-rprx-vision").tag("xtls-rprx-vision")
                }
                .wujiNavigationLinkPickerStyle()
                .accessibilityIdentifier("wuji.nodes.form.flow")
            case .trojan:
                fieldRow(label: L10n.t("nodes.form.password", table: "Nodes"),
                         text: $password, field: .password,
                         identifier: "wuji.nodes.form.password")
                errorRow("password")
            case .shadowsocks:
                Picker(L10n.t("nodes.form.method", table: "Nodes"), selection: $ssMethod) {
                    ForEach(Self.shadowsocksMethods, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .wujiNavigationLinkPickerStyle()
                .accessibilityIdentifier("wuji.nodes.form.method")
                fieldRow(label: L10n.t("nodes.form.password", table: "Nodes"),
                         text: $password, field: .password,
                         identifier: "wuji.nodes.form.password")
                errorRow("password")
            case .socks:
                fieldRow(label: L10n.t("nodes.form.username", table: "Nodes"),
                         placeholder: L10n.t("nodes.form.namePlaceholder", table: "Nodes"),
                         text: $socksUsername, field: .socksUsername,
                         identifier: "wuji.nodes.form.socksUsername")
                errorRow("socksUsername")
                fieldRow(label: L10n.t("nodes.form.password", table: "Nodes"),
                         text: $password, field: .password,
                         identifier: "wuji.nodes.form.password")
                errorRow("password")
                errorRow("socksCredentials")
            }
        } header: {
            Text(L10n.t("nodes.form.section.credentials", table: "Nodes"))
        }
    }

    private var transportSection: some View {
        Section {
            Picker(L10n.t("nodes.form.network", table: "Nodes"), selection: $network) {
                ForEach(networkOptions, id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .wujiNavigationLinkPickerStyle()
            .accessibilityIdentifier("wuji.nodes.form.network")

            if proto == .vless {
                Picker(L10n.t("nodes.form.security", table: "Nodes"), selection: $security) {
                    Text(L10n.t("nodes.form.none", table: "Nodes")).tag(SecurityLayer.none)
                    Text("TLS").tag(SecurityLayer.tls)
                    Text("REALITY").tag(SecurityLayer.reality)
                }
                .wujiNavigationLinkPickerStyle()
                .accessibilityIdentifier("wuji.nodes.form.security")
            } else {
                Toggle(L10n.t("nodes.form.tls", table: "Nodes"),
                       isOn: Binding(get: { security == .tls },
                                     set: { security = $0 ? .tls : .none }))
                    .tint(Theme.green)
                    .accessibilityIdentifier("wuji.nodes.form.tls")
            }

            if security != .none || proto == .trojan {
                fieldRow(label: L10n.t("nodes.form.sni", table: "Nodes"),
                         placeholder: server,
                         text: $sni, field: .sni,
                         identifier: "wuji.nodes.form.sni")
            }

            if network == .ws {
                fieldRow(label: L10n.t("nodes.form.path", table: "Nodes"),
                         placeholder: "/",
                         text: $wsPath, field: .wsPath,
                         identifier: "wuji.nodes.form.path")
                fieldRow(label: L10n.t("nodes.form.host", table: "Nodes"),
                         text: $wsHost, field: .wsHost,
                         identifier: "wuji.nodes.form.host")
            } else if network == .grpc {
                fieldRow(label: L10n.t("nodes.form.grpcService", table: "Nodes"),
                         text: $grpcService, field: .grpcService,
                         identifier: "wuji.nodes.form.grpcService")
            }
        } header: {
            Text(L10n.t("nodes.form.section.transport", table: "Nodes"))
        }
    }

    private var advancedSection: some View {
        Section {
            Picker(L10n.t("nodes.form.fingerprint", table: "Nodes"), selection: $fingerprint) {
                Text(L10n.t("nodes.form.none", table: "Nodes")).tag("")
                ForEach(Self.fingerprintOptions.dropFirst(), id: \.self) { value in
                    Text(Self.fingerprintLabel(value)).tag(value)
                }
            }
            .wujiNavigationLinkPickerStyle()
            .accessibilityIdentifier("wuji.nodes.form.fingerprint")

            if security != .none {
                Toggle(L10n.t("nodes.form.allowInsecure", table: "Nodes"), isOn: $allowInsecure)
                    .tint(Theme.green)
                    .accessibilityIdentifier("wuji.nodes.form.allowInsecure")
            }
        } header: {
            Text(L10n.t("nodes.form.section.advanced", table: "Nodes"))
        }
    }

    private var realitySection: some View {
        Section {
            fieldRow(label: L10n.t("nodes.form.realityPublicKey", table: "Nodes"),
                     text: $realityPublicKey, field: .realityPublicKey,
                     identifier: "wuji.nodes.form.realityPublicKey")
            errorRow("realityPublicKey")
            fieldRow(label: L10n.t("nodes.form.realityShortID", table: "Nodes"),
                     text: $realityShortID, field: .realityShortID,
                     identifier: "wuji.nodes.form.realityShortID")
            errorRow("realityShortID")
        } header: {
            Text(L10n.t("nodes.form.section.reality", table: "Nodes"))
        }
    }

    // MARK: - Row helpers

    private func fieldRow(label: String,
                          placeholder: String = "",
                          text: Binding<String>,
                          field: Field,
                          keyboard: PlatformKeyboardType = .default,
                          identifier: String) -> some View {
        #if os(macOS)
        // macOS text fields have a large intrinsic minimum width; the iOS trailing
        // layout overflows the sheet and cuts controls off. Use a fixed label column
        // and a constrained field that always fits the row.
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.label)
                .frame(width: 92, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(identifier)
        }
        #else
        HStack(spacing: 12) {
            Text(label)
                .font(.body)
                .foregroundStyle(Theme.label)
            Spacer(minLength: 8)
            TextField(placeholder, text: text)
                .font(.body)
                .foregroundStyle(Theme.secondaryLabel)
                .multilineTextAlignment(.trailing)
                .wujiKeyboardType(keyboard)
                .wujiNoAutocapitalization()
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .accessibilityIdentifier(identifier)
        }
        #endif
    }

    @ViewBuilder
    private func errorRow(_ key: String) -> some View {
        if let message = errors[key] {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wuji.nodes.form.error.\(key)")
        }
    }

    // MARK: - Protocol switching

    private func applyProtocolDefaults(for value: ProxyProtocol) {
        if !networkOptions.contains(network) {
            network = networkOptions.first ?? .tcp
        }
        switch value {
        case .shadowsocks, .socks:
            security = .none
            network = .tcp
        case .trojan:
            if network == .h2 { network = .tcp }
            if security == .reality { security = .none }
        default:
            break
        }
    }

    // MARK: - Debug screenshot harness

    private func configureFromDebugArguments() {
        #if DEBUG
        switch DebugScreenshotRoute.value("-WujiScreenshotAction") {
        case "invalid":
            _ = validate()
        case "autosave":
            // Headless-screenshot smoke test: exercise the real save pipeline end to end.
            server = "203.0.113.99"
            name = "Smoke Test Node"
            port = "443"
            uuid = "11111111-2222-3333-4444-555555555555"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { save() }
        default:
            break
        }
        #endif
    }

    // MARK: - Validation & save

    private func validate() -> Bool {
        var newErrors: [String: String] = [:]
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedServer.isEmpty {
            newErrors["server"] = L10n.t("nodes.form.error.addressRequired", table: "Nodes")
        } else if trimmedServer.contains(" ") || trimmedServer.contains("/") {
            newErrors["server"] = L10n.t("nodes.form.error.addressInvalid", table: "Nodes")
        }

        // Empty means "use the placeholder default" (443); only reject values
        // that were actually typed and are out of range/non-numeric.
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPort.isEmpty {
            if let portValue = Int(trimmedPort), (1...65535).contains(portValue) {
                // valid
            } else {
                newErrors["port"] = L10n.t("nodes.form.error.portInvalid", table: "Nodes")
            }
        }

        switch proto {
        case .vmess, .vless:
            if UUID(uuidString: uuid.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                newErrors["uuid"] = L10n.t("nodes.form.error.uuidInvalid", table: "Nodes")
            }
        case .trojan, .shadowsocks:
            if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newErrors["password"] = L10n.t("nodes.form.error.passwordRequired", table: "Nodes")
            }
        case .socks:
            // The Xray socks outbound needs both credentials or neither, so a
            // half-filled pair is rejected here exactly like the config builder does.
            let trimmedUsername = socksUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUsername.isEmpty != trimmedPassword.isEmpty {
                newErrors["socksCredentials"] = L10n.t("nodes.form.error.socksCredentials", table: "Nodes")
            }
        }

        if proto == .vless && security == .reality {
            if realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newErrors["realityPublicKey"] = L10n.t("nodes.form.error.realityKeyRequired", table: "Nodes")
            }
            let shortID = realityShortID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !shortID.isEmpty && !shortID.allSatisfy({ $0.isHexDigit }) {
                newErrors["realityShortID"] = L10n.t("nodes.form.error.shortIDInvalid", table: "Nodes")
            }
        }

        if !newErrors.isEmpty {
            errors = newErrors
            return false
        }

        if let duplicate = duplicateNode(trimmedServer: trimmedServer) {
            errors = ["duplicate": String(format: L10n.t("nodes.form.error.duplicate", table: "Nodes"), duplicate.displayName)]
            return false
        }

        errors = [:]
        return true
    }

    private func duplicateNode(trimmedServer: String) -> NodeProfile? {
        let portValue = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { (1...65535).contains($0) ? $0 : nil } ?? 443
        let trimmedUUID = uuid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSocksUsername = socksUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.nodes.first { existing in
            guard existing.id != editingProfile?.id else { return false }
            guard existing.proto == proto, existing.server == trimmedServer, existing.port == portValue else { return false }
            switch proto {
            case .vmess, .vless:
                return existing.uuid.lowercased() == trimmedUUID
            case .trojan, .shadowsocks:
                return existing.password == trimmedPassword
            case .socks:
                return existing.socksUsername == trimmedSocksUsername && existing.password == trimmedPassword
            }
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func save() {
        guard validate() else { return }
        saving = true
        saveError = nil
        let profile = buildProfile()
        do {
            try app.profileStore.upsert(profile: profile)
            app.reload()
            if editingProfile == nil {
                app.setActive(profile)
            }
            app.scheduleLatencyTests(for: [profile])
            saving = false
            if let onSaved {
                onSaved()
            } else {
                close()
            }
        } catch {
            saving = false
            saveError = L10n.t("nodes.form.saveFailed", table: "Nodes")
        }
    }

    private func buildProfile() -> NodeProfile {
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portValue = Int(trimmedPort) ?? 443
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var profile = editingProfile ?? NodeProfile(
            id: UUID().uuidString,
            groupID: ProfileStore.manualGroupID,
            name: trimmedName,
            proto: proto,
            server: trimmedServer,
            port: portValue
        )
        profile.proto = proto
        profile.server = trimmedServer
        profile.port = portValue
        profile.name = trimmedName.isEmpty ? "\(trimmedServer):\(portValue)" : trimmedName
        profile.uuid = (proto == .vmess || proto == .vless) ? uuid.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.alterID = proto == .vmess ? (Int(alterID.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) : 0
        profile.vmessSecurity = proto == .vmess ? vmessSecurity : "auto"
        profile.flow = proto == .vless ? flow : ""
        let usesPassword = proto == .trojan || proto == .shadowsocks || proto == .socks
        profile.password = usesPassword ? password.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.socksUsername = proto == .socks ? socksUsername.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.ssMethod = proto == .shadowsocks ? ssMethod : ""
        let usesPlainTransport = proto == .shadowsocks || proto == .socks
        profile.network = usesPlainTransport ? .tcp : network
        profile.security = usesPlainTransport ? .none : security
        profile.sni = proto == .socks ? "" : sni.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.wsPath = network == .ws ? wsPath.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.wsHost = network == .ws ? wsHost.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.grpcService = network == .grpc ? grpcService.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.fingerprint = proto == .socks ? "" : fingerprint
        profile.allowInsecure = security != .none ? allowInsecure : false
        profile.realityPublicKey = (proto == .vless && security == .reality) ? realityPublicKey.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.realityShortID = (proto == .vless && security == .reality) ? realityShortID.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        profile.updatedAt = Date()
        return profile
    }
}
