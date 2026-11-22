import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// Cross-platform helpers for APIs that only exist on one Apple platform.
//
// The Wuji UI is shared between iOS/iPadOS and macOS; every helper here has a
// platform-specific implementation and the call sites in the feature views use the
// neutral wrapper instead of `#if os(...)` so the shared views stay readable.
// All iOS implementations are kept byte-for-byte equivalent to the original code
// paths so the shipping iOS app keeps its behaviour.

// MARK: - Pasteboard

enum PlatformPasteboard {
    static var string: String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #else
        return NSPasteboard.general.string(forType: .string)
        #endif
    }

    @discardableResult
    static func setString(_ value: String) -> Bool {
        #if os(iOS)
        UIPasteboard.general.string = value
        return true
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
        #endif
    }
}

// MARK: - Haptics (no-op on macOS)

enum PlatformHaptics {
    static func impact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - App lifecycle notifications

enum PlatformNotifications {
    /// Fires when the app becomes active (foreground on iOS, app/window activation on macOS).
    static var appDidBecomeActive: Notification.Name {
        #if os(iOS)
        return UIApplication.didBecomeActiveNotification
        #else
        return NSApplication.didBecomeActiveNotification
        #endif
    }
}

// MARK: - System services

enum PlatformSystem {
    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    /// URL that opens the platform's per-app privacy settings.
    static var appSettingsURL: URL? {
        #if os(iOS)
        return URL(string: UIApplication.openSettingsURLString)
        #else
        return URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
        #endif
    }

    /// Whether this process can display an in-app full screen cover. macOS uses a
    /// regular sheet instead (`wujiFullScreenCover` below).
    static var usesFullScreenCovers: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Platform image type

#if os(iOS)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    static func wujiMake(cgImage: CGImage) -> PlatformImage {
        #if os(iOS)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    var wujiCGImage: CGImage? {
        #if os(iOS)
        return cgImage
        #else
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    static func wujiDecoded(from data: Data) -> PlatformImage? {
        #if os(iOS)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }

    /// PNG representation used by the macOS "save QR image" path.
    func wujiPNGData() -> Data? {
        #if os(iOS)
        return pngData()
        #else
        guard let tiff = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

/// Renders a QR bitmap scaled without interpolation (`Image(uiImage:)` is iOS-only).
struct PlatformQRImageView: View {
    let image: PlatformImage

    var body: some View {
        #if os(iOS)
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
        #else
        Image(nsImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
        #endif
    }
}

// MARK: - Keyboard traits

enum PlatformKeyboardType {
    case `default`
    case numberPad
    case numbersAndPunctuation
    case url
    case emailAddress
}

extension View {
    @ViewBuilder
    func wujiKeyboardType(_ type: PlatformKeyboardType) -> some View {
        #if os(iOS)
        self.keyboardType(type.uiType)
        #else
        self
        #endif
    }

    @ViewBuilder
    func wujiNoAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

#if os(iOS)
private extension PlatformKeyboardType {
    var uiType: UIKeyboardType {
        switch self {
        case .default: return .default
        case .numberPad: return .numberPad
        case .numbersAndPunctuation: return .numbersAndPunctuation
        case .url: return .URL
        case .emailAddress: return .emailAddress
        }
    }
}
#endif

// MARK: - Presentation / list / toolbar shims

extension View {
    /// Navigation-link pickers are iOS-only; macOS uses a menu picker.
    @ViewBuilder
    func wujiNavigationLinkPickerStyle() -> some View {
        #if os(iOS)
        self.pickerStyle(.navigationLink)
        #else
        self.pickerStyle(.menu)
        #endif
    }

    /// Hides the iOS tab bar on a pushed detail screen; no-op on macOS.
    @ViewBuilder
    func wujiHiddenTabBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }

    /// Hides the iOS navigation bar; no-op on macOS.
    @ViewBuilder
    func wujiHiddenNavigationBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Search field attached under the navigation title on iOS; the macOS sidebar
    /// search placement is left to the system.
    @ViewBuilder
    func wujiSearchable(text: Binding<String>, prompt: Text) -> some View {
        #if os(iOS)
        self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }

    /// String-prompt variant of `wujiSearchable`.
    @ViewBuilder
    func wujiSearchable(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        self.searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        self.searchable(text: text, prompt: prompt)
        #endif
    }

    /// Lets the QR screen import a QR image file on macOS (the open panel). This is
    /// a no-op on iOS, where the photo picker is used instead.
    @ViewBuilder
    func wujiImageFileImporter(isPresented: Binding<Bool>,
                               onPick: @escaping (URL) -> Void) -> some View {
        #if os(macOS)
        self.fileImporter(isPresented: isPresented, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                onPick(url)
            }
        }
        #else
        self
        #endif
    }

    /// `.listStyle(.insetGrouped)` is iOS-only; macOS uses the inset sidebar-ish list.
    @ViewBuilder
    func wujiListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }

    /// Inline navigation bar titles only exist on iOS.
    @ViewBuilder
    func wujiInlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// `fullScreenCover` is iOS-only; macOS presents a sheet instead.
    @ViewBuilder
    func wujiFullScreenCover<Content: View>(isPresented: Binding<Bool>,
                                            onDismiss: (() -> Void)? = nil,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }

    /// Item-based variant of `wujiFullScreenCover`.
    @ViewBuilder
    func wujiFullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                               onDismiss: (() -> Void)? = nil,
                                                               @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #else
        self.sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }
}

extension View {
    /// Gives the single macOS window a sensible default and minimum size. The
    /// minimum width is deliberately below the 700pt split threshold so users can
    /// shrink the window into the iPhone (compact tab) layout. On iOS
    /// this is a no-op (the layout is driven by the device geometry).
    @ViewBuilder
    func wujiMacWindowSizing() -> some View {
        #if os(macOS)
        self.frame(minWidth: 680, idealWidth: 826, minHeight: 640, idealHeight: 780)
        #else
        self
        #endif
    }
}

// MARK: - Platform flags

enum PlatformFlags {
    static var isMacOS: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - macOS row affordances

extension View {
    /// macOS `NavigationLink` rows don't draw the disclosure chevron iOS adds, so
    /// rows made of plain text look non-interactive. On macOS render them as blue
    /// link-style rows with a trailing chevron and hover feedback.
    @ViewBuilder
    func wujiNavigationRow(chevron: Bool = true) -> some View {
        #if os(macOS)
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Theme.tint)
            .overlay(alignment: .trailing) {
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }
            .contentShape(Rectangle())
            .wujiRowHover()
        #else
        self
        #endif
    }

    /// macOS hover feedback for interactive list rows: a tinted highlight and a
    /// pointing-hand cursor, so rows read as clickable instead of static text.
    @ViewBuilder
    func wujiRowHover() -> some View {
        #if os(macOS)
        self.modifier(WujiRowHoverModifier())
        #else
        self
        #endif
    }

    /// Conditional variant: adds hover feedback only for interactive rows.
    @ViewBuilder
    func wujiRowHover(_ active: Bool) -> some View {
        if active {
            self.wujiRowHover()
        } else {
            self
        }
    }
}

#if os(macOS)
private struct WujiRowHoverModifier: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Theme.tint.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
#endif

extension View {
    /// Interactive row title color: blue on macOS (looks like a link), unchanged on iOS.
    func wujiInteractiveTitleColor() -> Color { PlatformFlags.interactiveTitleColor }
}

extension PlatformFlags {
    static var interactiveTitleColor: Color {
        #if os(macOS)
        Theme.tint
        #else
        Theme.label
        #endif
    }
}

// MARK: - macOS window scene

extension Scene {
    /// macOS uses the iPad layout (sidebar + detail), so the window opens wide.
    @SceneBuilder
    func wujiMacWindowScene() -> some Scene {
        #if os(macOS)
        self
            .defaultSize(width: 826, height: 780)
            .windowResizability(.contentMinSize)
        #else
        self
        #endif
    }
}

// MARK: - macOS sheet presentation

extension View {
    /// iOS sheet roots fill the presentation container; macOS sheets collapse to a
    /// content sliver or clip an iOS-style `NavigationStack { List }` root. Give every
    /// macOS sheet an explicit fixed size so the whole form is visible and scrollable.
    @ViewBuilder
    func wujiSheetSizing(width: CGFloat = 560, height: CGFloat = 700) -> some View {
        #if os(macOS)
        self.frame(width: width, height: height)
        #else
        self
        #endif
    }

    /// Adds a bottom action bar to a macOS sheet root. macOS sheets don't render
    /// SwiftUI `.toolbar` items, so forms that rely on toolbar Cancel/Save buttons
    /// on iOS would otherwise have no visible way to submit or dismiss.
    @ViewBuilder
    func wujiMacSheetActions(cancelTitle: String = L10n.t("common.cancel"),
                             onCancel: (() -> Void)? = nil,
                             confirmTitle: String? = nil,
                             confirmDisabled: Bool = false,
                             onConfirm: (() -> Void)? = nil,
                             isEnabled: Bool = true) -> some View {
        #if os(macOS)
        if isEnabled {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if let onCancel {
                    Button(cancelTitle, action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                }
                Spacer()
                if let confirmTitle, let onConfirm {
                    Button(confirmTitle, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.tint)
                        .controlSize(.large)
                        .disabled(confirmDisabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Sheet detents only exist on iOS; on macOS the explicit sheet size above wins.
    @ViewBuilder
    func wujiPresentationDetents(_ detents: Set<PresentationDetent>) -> some View {
        #if os(iOS)
        self.presentationDetents(detents)
        #else
        self
        #endif
    }

    /// Detent variant with a selection binding used by the node actions sheet.
    @ViewBuilder
    func wujiPresentationDetents(_ detents: Set<PresentationDetent>,
                                 selection: Binding<PresentationDetent>) -> some View {
        #if os(iOS)
        self.presentationDetents(detents, selection: selection)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing bar button: `.topBarTrailing` on iOS, `.primaryAction` on macOS.
    static var wujiTrailing: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    /// Leading bar button: `.topBarLeading` on iOS, navigation area on macOS.
    static var wujiLeading: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarLeading
        #else
        return .navigation
        #endif
    }
}

// MARK: - List background

extension View {
    /// iOS lists get a custom page background; macOS grouped Forms must keep the
    /// system grouped background or the white row cards disappear.
    @ViewBuilder
    func wujiListBackground() -> some View {
        #if os(macOS)
        self
        #else
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
        #endif
    }
}

// MARK: - macOS content width

extension View {
    /// macOS windows are much wider than phones; keep reading content in a centered
    /// column instead of stretching phone/tablet layouts edge to edge. No-op on iOS.
    @ViewBuilder
    func wujiMacContentWidth(_ width: CGFloat = 720) -> some View {
        #if os(macOS)
        self
            .frame(maxWidth: width)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}

// MARK: - macOS settings container

/// iOS keeps the grouped `List` design; macOS uses the native grouped `Form`
/// (System Settings style: rounded cards on a gray window background).
struct WujiSettingsList<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        #if os(macOS)
        Form {
            content
        }
        .formStyle(.grouped)
        #else
        List {
            content
        }
        .listStyle(.insetGrouped)
        #endif
    }
}


// MARK: - macOS Liquid Glass design system (iOS 26 style)

#if os(macOS)
/// Tokens for the chosen "iOS 26 Liquid Glass" macOS skin: soft page gradient,
/// translucent cards, tinted SF Symbol chips, blue gradient pill buttons.
enum MacGlass {
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.00)
    static let purple = Color(red: 0.69, green: 0.32, blue: 0.87)
    static let teal = Color(red: 0.19, green: 0.69, blue: 0.78)
    static let gray = Color(red: 0.56, green: 0.56, blue: 0.58)
    static let red = Color(red: 1.00, green: 0.23, blue: 0.19)

    static let cardRadius: CGFloat = 20
    static let rowHeight: CGFloat = 44
    static let iconSize: CGFloat = 30

    static let pageTop = Color(red: 0.949, green: 0.953, blue: 0.965)
    static let pageBottom = Color(red: 0.949, green: 0.953, blue: 0.965)
    /// Flat (non-gradient) page background requested for the macOS window.
    static let flatPage = Color(red: 0.949, green: 0.953, blue: 0.965)

    static let titleFont = Font.system(size: 28, weight: .bold)
    static let sectionFont = Font.system(size: 13, weight: .semibold)
    static let rowFont = Font.system(size: 16)
    static let subFont = Font.system(size: 13)
    static let metricFont = Font.system(size: 22, weight: .semibold)
}

struct MacGlassPageBackground: View {
    var body: some View {
        MacGlass.flatPage
            .ignoresSafeArea()
    }
}

struct MacGlassPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            MacGlassPageBackground()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct MacGlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MacGlass.cardRadius, style: .continuous)
        content
            .background(.ultraThinMaterial, in: shape)
            .background(Color.white.opacity(0.56), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 0.5))
            .clipShape(shape)
            .shadow(color: Color(red: 0.12, green: 0.20, blue: 0.40).opacity(0.10),
                    radius: 14, x: 0, y: 10)
    }
}

struct MacGlassIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = MacGlass.iconSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tint.opacity(0.16))
            )
    }
}

struct MacGlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.35))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }
}

struct MacGlassRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var value: String?
    var showsChevron = true
    var titleColor: Color = Theme.label
    var valueColor: Color = Theme.secondaryLabel

    var body: some View {
        HStack(spacing: 12) {
            MacGlassIcon(symbol: symbol, tint: tint)
            Text(title)
                .font(MacGlass.rowFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(MacGlass.rowFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: MacGlass.rowHeight)
        .contentShape(Rectangle())
    }
}

struct MacGlassMetric: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                MacGlassIcon(symbol: symbol, tint: tint, size: 24)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text(value)
                .font(MacGlass.metricFont)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct MacGlassCompactMetric: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct MacGlassPrimaryButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [Color(red: 0.30, green: 0.55, blue: 1.0), MacGlass.blue],
                                   startPoint: .top, endPoint: .bottom)
                )
            )
            .shadow(color: MacGlass.blue.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct MacGlassSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(MacGlass.sectionFont)
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.leading, 4)
    }
}

struct MacGlassFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.secondaryLabel)
            .padding(.leading, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

extension View {
    /// Flat window background so titlebar / toolbar gaps match the page colour.
    @ViewBuilder
    func wujiGlassWindowBackground() -> some View {
        #if os(macOS)
        self.background(MacGlass.flatPage)
        #else
        self
        #endif
    }
}

extension View {
    /// iOS keeps its flat page background; macOS uses a flat neutral page colour.
    @ViewBuilder
    func wujiGlassPageBackground() -> some View {
        #if os(macOS)
        self.background(MacGlassPageBackground())
        #else
        self.background(Theme.background)
        #endif
    }
}


extension Notification.Name {
    /// Posted by the macOS menu bar extra to jump to a tab in the main window
    /// ("connect" / "nodes" / "settings"). No-op on iOS.
    static let wujiSelectTab = Notification.Name("wuji.selectTab")
}
