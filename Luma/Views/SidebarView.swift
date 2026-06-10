import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: BrowserStore
    let onToggleSidebar: () -> Void

    @State private var isHoveringNewTab = false

    private let leadingInset: CGFloat = 12
    private let trailingInset: CGFloat = 10
    private let windowControlsWidth: CGFloat = 74

    /// Zen-style "Essentials" tiles: square-ish tiles that stretch to fill
    /// the row, so a few items span the full width like the reference.
    private let essentialsColumns = [
        GridItem(.adaptive(minimum: 54, maximum: .infinity), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarHeader
            
            if store.isCreateSpacePresented {
                CreateSpaceSidebarComposer(store: store)
            } else {
                addressPill

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        essentialsSection
                        spaceLabel

                        Divider()
                            .padding(.vertical, 2)

                        newTabButton
                        tabsSection
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 6)
            }

            if let mediaTab = store.mediaControllerTab, let mediaState = store.mediaControllerState {
                MediaControllerView(store: store, tab: mediaTab, state: mediaState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            SpaceSwitcherView(store: store)
        }
        .animation(.easeOut(duration: 0.16), value: store.mediaControllerTabID)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 7) {
            WindowControlsView()
                .frame(width: windowControlsWidth, height: 24)

            Button {
                onToggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .toolbarIconButton()
            .help("Hide Sidebar")

            Spacer(minLength: 8)

            Button(action: store.goBack) {
                Image(systemName: "arrow.left")
            }
            .disabled(!store.canGoBack)
            .toolbarIconButton()
            .help("Back")

            Button(action: store.goForward) {
                Image(systemName: "arrow.right")
            }
            .disabled(!store.canGoForward)
            .toolbarIconButton()
            .help("Forward")

            if store.activeTab?.isLoading == true {
                Button(action: store.stopLoadingActiveTab) {
                    Image(systemName: "xmark")
                }
                .toolbarIconButton()
                .help("Stop")
            } else {
                Button(action: store.reloadActiveTab) {
                    Image(systemName: "arrow.clockwise")
                }
                .toolbarIconButton()
                .help("Reload")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            SidebarLoadingBar(progress: store.activeTab?.loadingProgress ?? 0)
                .opacity(store.activeTab?.isLoading == true ? 1 : 0)
                .offset(y: 5)
        }
    }

    private var addressPill: some View {
        Button {
            store.focusAddressBar()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: store.activeTab?.faviconSymbol ?? "globe")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)

                Text(sidebarAddressText)
                    .lineLimit(1)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.quaternary.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(BrowserDefaults.addressPlaceholder)
    }

    private var sidebarAddressText: String {
        guard let url = store.activeTab?.url else {
            return BrowserDefaults.addressPlaceholder
        }

        if let host = url.host(percentEncoded: false) {
            return host.replacingOccurrences(of: "www.", with: "")
        }

        return url.absoluteString
    }

    // MARK: - Essentials (pinned tiles)

    @ViewBuilder
    private var essentialsSection: some View {
        let pinned = store.pinnedTabsForActiveSpace

        if !pinned.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: essentialsColumns, spacing: 8) {
                    ForEach(pinned) { tab in
                        EssentialTileView(
                            tab: tab,
                            isActive: tab.id == store.activeTabID,
                            onSelect: { store.switchTab(to: tab.id) },
                            onClose: { store.closeTab(tab.id) },
                            onDuplicate: { store.duplicateTab(tab.id) },
                            onOpenInSplit: { store.openSplitView(with: tab.id) },
                            onTogglePin: { store.togglePin(tab.id) }
                        )
                        .onDrag {
                            store.draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabReorderDropDelegate(
                                targetTab: tab,
                                tabs: pinned,
                                pinned: true,
                                store: store
                            )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Tabs

    private var spaceLabel: some View {
        Text(store.activeSpace?.name ?? "Space")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var tabsSection: some View {
        let tabs = store.regularTabsForActiveSpace

        VStack(alignment: .leading, spacing: 2) {
            if tabs.isEmpty {
                Text("No tabs")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        TabRowView(
                            tab: tab,
                            isActive: tab.id == store.activeTabID,
                            isSplit: tab.id == store.splitTabID,
                            onSelect: { store.switchTab(to: tab.id) },
                            onClose: { store.closeTab(tab.id) },
                            onDuplicate: { store.duplicateTab(tab.id) },
                            onOpenInSplit: { store.openSplitView(with: tab.id) },
                            onTogglePin: { store.togglePin(tab.id) }
                        )
                        .onDrag {
                            store.draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: TabReorderDropDelegate(
                                targetTab: tab,
                                tabs: tabs,
                                pinned: false,
                                store: store
                            )
                        )
                    }
                }
            }
        }
    }

    private var newTabButton: some View {
        Button {
            store.newTab()
            store.focusAddressBar()
        } label: {
            Label(BrowserCommandTitles.newTab, systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(isHoveringNewTab ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHoveringNewTab = $0 }
        .overlay {
            if isHoveringNewTab {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHoveringNewTab)
    }
}

private struct CreateSpaceSidebarComposer: View {
    @ObservedObject var store: BrowserStore

    @State private var name = ""
    @State private var symbolName = "sparkle"
    @State private var themeColorHex = "#6E8BFF"
    @State private var dataMode = SpaceDataMode.isolated
    @State private var isThemeEditorPresented = false

    private let symbols = [
        "sparkle",
        "briefcase",
        "house",
        "paintpalette",
        "graduationcap",
        "bolt",
        "leaf",
        "terminal"
    ]

    private let themeOptions: [(name: String, hex: String)] = [
        ("Blue", "#6E8BFF"),
        ("Green", "#66BFA3"),
        ("Gold", "#E0A84F"),
        ("Red", "#DA6A72"),
        ("Violet", "#9B7BE5"),
        ("Cyan", "#5CA8D8"),
        ("Pink", "#D17FB3"),
        ("Olive", "#8E9A5B")
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .center, spacing: 5) {
                Text("Create a Space")
                    .font(.system(size: 14, weight: .semibold))

                Text("Spaces organize tabs and sessions.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 26)

            HStack(spacing: 7) {
                Button {
                    cycleSymbol()
                } label: {
                    Image(systemName: symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color(spaceHex: themeColorHex))
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(spaceHex: themeColorHex).opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .help("Change Icon")

                TextField("Space Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: 8) {
                Text("Profile")
                    .font(.system(size: 11.5, weight: .medium))

                Spacer()

                Picker("Profile", selection: $dataMode) {
                    ForEach(SpaceDataMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 106)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    isThemeEditorPresented.toggle()
                }
            } label: {
                HStack {
                    Circle()
                        .fill(Color(spaceHex: themeColorHex))
                        .frame(width: 12, height: 12)

                    Text("Edit Theme")
                        .font(.system(size: 11.5, weight: .medium))

                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)

            if isThemeEditorPresented {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(21), spacing: 7), count: 6), spacing: 7) {
                    ForEach(themeOptions, id: \.hex) { option in
                        Button {
                            themeColorHex = option.hex
                        } label: {
                            Circle()
                                .fill(Color(spaceHex: option.hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(themeColorHex == option.hex ? 0.58 : 0), lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)

            Button {
                createSpace()
            } label: {
                Text(BrowserCommandTitles.createSpace)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.primary)
            .frame(height: 26)
            .background(Color.primary.opacity(trimmedName.isEmpty ? 0.08 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .disabled(trimmedName.isEmpty)

            Button("Cancel") {
                store.isCreateSpacePresented = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
        }
    }

    private func createSpace() {
        let dataStoreID: UUID
        switch dataMode {
        case .isolated:
            dataStoreID = UUID()
        case .shareCurrent:
            dataStoreID = store.activeSpace?.dataStoreID ?? UUID()
        }

        store.createSpace(
            name: trimmedName,
            symbolName: symbolName,
            themeColorHex: themeColorHex,
            dataStoreID: dataStoreID
        )
        store.isCreateSpacePresented = false
        store.focusAddressBar()
    }

    private func cycleSymbol() {
        guard let index = symbols.firstIndex(of: symbolName) else {
            symbolName = symbols[0]
            return
        }

        symbolName = symbols[(index + 1) % symbols.count]
    }
}

private enum SpaceDataMode: String, CaseIterable, Identifiable {
    case isolated
    case shareCurrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isolated:
            return "New"
        case .shareCurrent:
            return "Current"
        }
    }
}

private struct SidebarLoadingBar: View {
    let progress: Double

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Color.accentColor.opacity(0.58))
                .frame(width: proxy.size.width * clampedProgress, height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 1)
        .allowsHitTesting(false)
    }
}

// MARK: - Essential tile

private struct EssentialTileView: View {
    let tab: BrowserTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onOpenInSplit: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(Color.primary.opacity(0.12))
                            : AnyShapeStyle(Color.primary.opacity(0.05))
                    )

                faviconImage
                    .frame(width: 20, height: 20)
            }
            .frame(height: 54)
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .background(Circle().fill(.background))
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                    .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tab.title)
        .contextMenu {
            Button("Unpin Tab", action: onTogglePin)
            Button(BrowserCommandTitles.duplicateTab, action: onDuplicate)
            Button("Open in Split View", action: onOpenInSplit)
            Button("Close Tab", action: onClose)
        }
    }

    @ViewBuilder
    private var faviconImage: some View {
        if
            let data = tab.faviconData,
            let nsImage = NSImage(data: data)
        {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: tab.faviconSymbol)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - Window controls

private struct WindowControlsView: View {
    @State private var window: NSWindow?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            WindowControlButton(
                color: Color(red: 1.0, green: 0.27, blue: 0.29),
                symbolName: "xmark",
                accessibilityLabel: "Close",
                isHovering: isHovering
            ) {
                window?.performClose(nil)
            }

            WindowControlButton(
                color: Color(red: 1.0, green: 0.78, blue: 0.16),
                symbolName: "minus",
                accessibilityLabel: "Minimize",
                isHovering: isHovering
            ) {
                window?.miniaturize(nil)
            }

            WindowControlButton(
                color: Color(red: 0.20, green: 0.80, blue: 0.28),
                symbolName: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "Zoom",
                isHovering: isHovering
            ) {
                window?.zoom(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowReader(window: $window))
        .onHover { isHovering = $0 }
    }
}

private struct WindowControlButton: View {
    let color: Color
    let symbolName: String
    let accessibilityLabel: String
    let isHovering: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.14), lineWidth: 0.5)
                    }

                Image(systemName: symbolName)
                    .font(.system(size: 6.2, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.58))
                    .opacity(isHovering ? 1 : 0)
            }
            .frame(width: 13, height: 13)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.system(size: 17, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

private extension View {
    func toolbarIconButton() -> some View {
        modifier(ToolbarIconButtonModifier())
    }
}

// MARK: - Drag reordering

private struct TabReorderDropDelegate: DropDelegate {
    let targetTab: BrowserTab
    let tabs: [BrowserTab]
    let pinned: Bool
    let store: BrowserStore

    func dropEntered(info: DropInfo) {
        guard
            let draggedID = store.draggedTabID,
            draggedID != targetTab.id,
            let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }),
            let toIndex = tabs.firstIndex(where: { $0.id == targetTab.id })
        else {
            return
        }

        var orderedIDs = tabs.map(\.id)
        let movedID = orderedIDs.remove(at: fromIndex)
        orderedIDs.insert(movedID, at: toIndex)
        store.reorderTabs(orderedIDs, pinned: pinned)
    }

    func performDrop(info: DropInfo) -> Bool {
        store.draggedTabID = nil
        return true
    }
}

/// Arc/Zen-style now-playing bar pinned to the bottom of the sidebar, just
/// above the space switcher, controlling whichever tab owns media playback.
private struct MediaControllerView: View {
    @ObservedObject var store: BrowserStore
    let tab: BrowserTab
    let state: TabMediaState

    var body: some View {
        HStack(spacing: 0) {
            MediaControlButton(help: tab.title) {
                store.focusMediaTab()
            } label: {
                favicon
            }

            MediaControlButton(systemImage: "backward.end.fill", help: "Previous") {
                store.skipMediaTrack(forward: false)
            }

            MediaControlButton(
                systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                help: state.isPlaying ? "Pause" : "Play"
            ) {
                store.toggleMediaPlayback()
            }

            MediaControlButton(systemImage: "forward.end.fill", help: "Next") {
                store.skipMediaTrack(forward: true)
            }

            MediaControlButton(
                systemImage: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: state.isMuted ? "Unmute" : "Mute"
            ) {
                store.toggleMediaMute()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: tab.faviconSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MediaControlButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovering = false

    init(
        help: String,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.help = help
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.07) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
        .help(help)
    }
}

extension MediaControlButton where Label == Image {
    init(systemImage: String, help: String, action: @escaping () -> Void) {
        self.init(help: help, action: action) {
            Image(systemName: systemImage)
        }
    }
}
