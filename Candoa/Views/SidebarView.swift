import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: BrowserStore
    let availableUpdate: AppUpdate?
    let showsWindowControls: Bool
    let windowControlsHiddenOffset: CGFloat
    let onUpdateBannerTapped: () -> Void
    let onToggleSidebar: () -> Void

    @State private var isHoveringNewTab = false

    private let leadingInset: CGFloat = 9
    private let trailingInset: CGFloat = 9
    private let windowControlsWidth: CGFloat = 70

    /// Zen-style "Essentials" tiles: square-ish tiles that stretch to fill
    /// the row, so a few items span the full width like the reference.
    private let essentialsColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeSpaceTint: Color {
        Color(spaceHex: store.activeThemeColorHexes.first ?? "#8A8F98")
    }

    private var hasActiveThemeTint: Bool {
        !store.activeThemeColorHexes.isEmpty
    }

    private var isSetupThemePreviewActive: Bool {
        store.isSpaceSetupPresented && store.editingSpaceID == nil && hasActiveThemeTint
    }

    private var sidebarIconColor: Color {
        guard isSetupThemePreviewActive else { return CandoaChromeStyle.sidebarIcon }

        let usesDarkForeground = CandoaChromeStyle.prefersDarkForeground(
            forSpaceHex: store.activeThemeColorHexes.first ?? ""
        )
        return (usesDarkForeground ? Color.black : Color.white).opacity(0.42)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sidebarHeader
            
            if store.isSpaceSetupPresented {
                UpsertSpaceSidebarComposer(
                    store: store,
                    mode: store.isInitialSpaceSetupPresented
                        ? .initial
                        : (store.editingSpaceID != nil ? .edit : .create)
                )
                .id(store.editingSpaceID)
            } else {
                addressPill

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        essentialsSection
                        spaceLabel

                        Rectangle()
                            .fill(CandoaChromeStyle.sidebarSeparator)
                            .frame(height: 1)
                            .padding(.top, 3)
                            .padding(.bottom, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            newTabButton
                            tabsSection
                        }
                    }
                    .padding(.top, 1)
                }

                Spacer(minLength: 6)
            }

            if let availableUpdate {
                AppUpdateBanner(update: availableUpdate, action: onUpdateBannerTapped)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !store.isInitialSpaceSetupPresented {
                SpaceSwitcherView(store: store)
            }
        }
        .animation(.easeOut(duration: 0.16), value: availableUpdate)
        .animation(.easeOut(duration: 0.16), value: store.mediaControllerTabID)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 6) {
            WindowControlsView(
                isVisible: showsWindowControls,
                hiddenOffset: windowControlsHiddenOffset
            )
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
        .foregroundStyle(sidebarIconColor)
        .frame(height: 34)
    }

    private var addressPill: some View {
        Button {
            store.focusAddressBar()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLocalDevelopmentURL ? "info.circle" : "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(CandoaChromeStyle.sidebarIcon)

                Text(sidebarAddressText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(
                        isLocalDevelopmentURL
                            ? .system(size: 13, weight: .medium, design: .monospaced)
                            : .system(size: 14, weight: .semibold)
                    )
                    .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(CandoaChromeStyle.sidebarControlFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isLocalDevelopmentURL ? "Local development server" : BrowserDefaults.addressPlaceholder)
    }

    // Arc's local-dev treatment: localhost pages get an info icon and the
    // full URL — scheme, port, and path — instead of the trimmed hostname.
    private var isLocalDevelopmentURL: Bool {
        store.activeTab?.url?.isLocalDevelopment == true
    }

    private var sidebarAddressText: String {
        guard let url = store.activeTab?.url else {
            return "Search..."
        }

        if isLocalDevelopmentURL {
            return url.localDevelopmentDisplayText
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
            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: essentialsColumns, spacing: 6) {
                    ForEach(pinned) { tab in
                        essentialTile(for: tab, pinned: pinned)
                    }
                }
            }
            // Pin, unpin, and close settle the grid instead of popping; the
            // per-space identity keeps space switches an instant context cut.
            .animation(.easeOut(duration: 0.18), value: pinned.map(\.id))
            .id(store.activeSpaceID)
        }
    }

    private func essentialTile(for tab: BrowserTab, pinned: [BrowserTab]) -> some View {
        EssentialTileView(
            tab: tab,
            isActive: tab.id == store.activeTabID && !store.isNewTabPaletteActive,
            accentColor: activeSpaceTint,
            onSelect: { store.switchTab(to: tab.id) },
            onClose: { store.closeTab(tab.id) },
            onDuplicate: { store.duplicateTab(tab.id) },
            onOpenInSplit: { store.openSplitView(with: tab.id) },
            onTogglePin: { store.togglePin(tab.id) }
        )
        // The system drag image is the only visible copy while dragging; the
        // source tile leaves a gap that doubles as the insertion indicator.
        .opacity(store.draggedTabID == tab.id ? 0 : 1)
        .onDrag {
            store.beginTabDrag(tab.id)
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

    // MARK: - Tabs

    @ViewBuilder
    private var spaceLabel: some View {
        if let name = store.activeSpace?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
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
                            isActive: tab.id == store.activeTabID && !store.isNewTabPaletteActive,
                            isSplit: tab.id == store.splitTabID,
                            accentColor: activeSpaceTint,
                            mediaState: store.mediaStates[tab.id],
                            onSelect: { store.switchTab(to: tab.id) },
                            onClose: { store.closeTab(tab.id) },
                            onDuplicate: { store.duplicateTab(tab.id) },
                            onOpenInSplit: { store.openSplitView(with: tab.id) },
                            onTogglePin: { store.togglePin(tab.id) },
                            onToggleMute: { store.toggleMediaMute(tabID: tab.id) }
                        )
                        // Hide the source row while its drag session is live so
                        // the cursor ghost isn't doubled by the in-list row; the
                        // gap it leaves is the insertion indicator.
                        .opacity(store.draggedTabID == tab.id ? 0 : 1)
                        .onDrag {
                            store.beginTabDrag(tab.id)
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
                // Closing, opening, and reordering settle the list the way
                // Safari's sidebar does instead of rows popping in place; the
                // per-space identity keeps space switches an instant cut.
                .animation(.easeOut(duration: 0.18), value: tabs.map(\.id))
                .id(store.activeSpaceID)
            }
        }
    }

    private var newTabButton: some View {
        // While the ⌘T palette is open this button wears the active-tab
        // highlight — Arc's "selected without navigating" new-tab state.
        let isArmed = store.isNewTabPaletteActive

        return Button {
            store.openNewTabCommandPalette()
        } label: {
            // contentShape must live inside the label: applied outside the
            // Button it doesn't extend the clickable area, leaving only the
            // glyphs hit-testable. The layout mirrors TabRowView so the
            // button reads as one of the tab rows.
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(isArmed ? CandoaChromeStyle.sidebarText : CandoaChromeStyle.sidebarIcon)
                    .frame(width: 16, height: 16)

                Text(BrowserCommandTitles.newTab)
                    .lineLimit(1)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(isArmed ? CandoaChromeStyle.sidebarText : CandoaChromeStyle.sidebarTextSecondary)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(newTabButtonBackground(isArmed: isArmed))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHoveringNewTab = $0 }
        .overlay {
            if isHoveringNewTab && !isArmed {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CandoaChromeStyle.sidebarControlStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHoveringNewTab)
        .animation(.easeOut(duration: 0.12), value: isArmed)
    }

    private func newTabButtonBackground(isArmed: Bool) -> Color {
        if isArmed {
            return activeSpaceTint.opacity(0.18)
        }
        if isHoveringNewTab {
            return CandoaChromeStyle.sidebarControlFillHover
        }
        return Color.clear
    }
}

private struct AppUpdateBanner: View {
    let update: AppUpdate
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("Candoa \(update.version) Available")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isHovering ? CandoaChromeStyle.updateBannerFillHover : CandoaChromeStyle.updateBannerFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(CandoaChromeStyle.updateBannerStroke, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Candoa \(update.version) is available")
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
}

private struct UpsertSpaceSidebarComposer: View {
    @ObservedObject var store: BrowserStore
    let mode: SpaceComposerMode

    @State private var name = ""
    @State private var symbolName = "square.dashed"
    @State private var themeColorHex: String?
    @State private var themeAppearance = BrowserSpace.defaultThemeAppearance
    @State private var themeOpacity = 0.5
    @State private var themeTexture = 0.0
    @State private var dataMode = SpaceDataMode.isolated
    @State private var isIconPickerPresented = false
    @State private var isProfilePickerPresented = false
    @State private var isThemeEditorPresented = false
    @FocusState private var isNameFocused: Bool

    private let themeOptions: [(name: String, hex: String)] = [
        ("Neutral", "#F0EAE1"),
        ("Green", "#74E0AA"),
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

    private var isThemePreviewActive: Bool {
        mode != .edit && themeColorHex != nil
    }

    private var usesDarkForeground: Bool {
        guard let themeColorHex else { return false }
        return CandoaChromeStyle.prefersDarkForeground(forSpaceHex: themeColorHex)
    }

    private var foregroundBase: Color {
        usesDarkForeground ? Color.black : Color.white
    }

    private var primaryButtonTintHex: String {
        themeColorHex ?? BrowserSpace.defaultThemeColorHex
    }

    private var primaryButtonUsesDarkForeground: Bool {
        CandoaChromeStyle.prefersDarkForeground(forSpaceHex: primaryButtonTintHex)
    }

    private var primaryButtonForegroundBase: Color {
        primaryButtonUsesDarkForeground ? Color.black : Color.white
    }

    private var textColor: Color {
        isThemePreviewActive ? foregroundBase.opacity(usesDarkForeground ? 0.82 : 0.88) : CandoaChromeStyle.sidebarText
    }

    private var secondaryTextColor: Color {
        isThemePreviewActive ? foregroundBase.opacity(usesDarkForeground ? 0.55 : 0.58) : CandoaChromeStyle.sidebarTextSecondary
    }

    private var iconColor: Color {
        isThemePreviewActive ? foregroundBase.opacity(0.42) : CandoaChromeStyle.sidebarIcon
    }

    private var controlFill: Color {
        isThemePreviewActive ? foregroundBase.opacity(usesDarkForeground ? 0.06 : 0.075) : CandoaChromeStyle.spaceSetupControlFill
    }

    private var controlStroke: Color {
        isThemePreviewActive ? foregroundBase.opacity(0.08) : CandoaChromeStyle.spaceSetupControlStroke
    }

    private var pillFill: Color {
        isThemePreviewActive ? foregroundBase.opacity(usesDarkForeground ? 0.08 : 0.10) : CandoaChromeStyle.spaceSetupPillFill
    }

    private var createButtonTextColor: Color {
        if trimmedName.isEmpty {
            return primaryButtonForegroundBase.opacity(primaryButtonUsesDarkForeground ? 0.38 : 0.42)
        }

        return primaryButtonForegroundBase.opacity(primaryButtonUsesDarkForeground ? 0.82 : 0.92)
    }

    private var themeAppearanceSelection: Binding<SpaceThemeAppearance> {
        Binding {
            themeAppearance
        } set: { newAppearance in
            themeAppearance = newAppearance
            store.previewSpaceThemeAppearance(newAppearance)
        }
    }

    private var createButtonBackground: Color {
        Color(spaceHex: primaryButtonTintHex)
            .opacity(trimmedName.isEmpty ? 0.52 : 0.86)
    }

    init(store: BrowserStore, mode: SpaceComposerMode = .create) {
        self.store = store
        self.mode = mode
        _name = State(initialValue: mode.defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            composerHeader

            nameField

            // Edit keeps the space's existing profile; switching a live
            // space's data store means migrating its web views.
            if mode != .edit {
                profileRow
            }

            themeButton

            Spacer(minLength: 0)

            Button {
                createSpace()
            } label: {
                Text(mode.primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(createButtonTextColor)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(createButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(trimmedName.isEmpty)

            if mode != .initial {
                Button("Cancel") {
                    store.clearSpaceThemePreview()
                    if mode == .edit {
                        store.editingSpaceID = nil
                    } else {
                        store.isCreateSpacePresented = false
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isThemePreviewActive ? foregroundBase.opacity(usesDarkForeground ? 0.78 : 0.82) : Color.primary.opacity(0.86))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .onAppear {
            if mode == .edit, let space = store.editingSpace {
                name = space.name
                symbolName = space.symbolName
                themeColorHex = space.themeColorHex
                themeAppearance = space.themeAppearance
                themeOpacity = space.themeOpacity
                themeTexture = space.themeTexture
            } else {
                isNameFocused = true
            }
            publishCurrentThemePreview()
        }
        .onDisappear {
            store.clearSpaceThemePreview()
        }
    }

    private var composerHeader: some View {
        VStack(spacing: 8) {
            Text(mode.title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(textColor)

            Text(mode.subtitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(iconColor)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 34)
        .padding(.bottom, 32)
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            Button {
                isIconPickerPresented.toggle()
            } label: {
                SpaceIconPreview(
                    symbolName: symbolName,
                    themeColorHex: themeColorHex,
                    strokeColor: isThemePreviewActive
                        ? foregroundBase.opacity(0.46)
                        : CandoaChromeStyle.sidebarIcon.opacity(0.78)
                )
            }
            .buttonStyle(.plain)
            .help("Change Icon")
            .popover(isPresented: $isIconPickerPresented, arrowEdge: .leading) {
                SpaceIconPicker(
                    selectedSymbolName: $symbolName,
                    isPresented: $isIconPickerPresented
                )
            }

            TextField("", text: $name, prompt: Text(verbatim: ""))
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .focused($isNameFocused)
                .accessibilityLabel("Space Name")
                .overlay(alignment: .leading) {
                    if name.isEmpty {
                        // Manual placeholder: the system prompt ignores custom
                        // colors on macOS and stays scheme-colored, which reads
                        // white on light theme surfaces.
                        Text("Space Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: name) { _, newValue in
                    let limitedName = BrowserStore.limitedSpaceNameInput(newValue)
                    if limitedName != newValue {
                        name = limitedName
                    }
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(controlFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(controlStroke, lineWidth: 1)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 10) {
            Text("Profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(textColor)

            Spacer(minLength: 8)

            Button {
                isProfilePickerPresented.toggle()
            } label: {
                Text(dataMode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(pillFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isProfilePickerPresented, arrowEdge: .trailing) {
                SpaceProfilePicker(
                    selectedMode: $dataMode,
                    isPresented: $isProfilePickerPresented
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(controlFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(controlStroke, lineWidth: 1)
        }
    }

    private var themeButton: some View {
        Button {
            isThemeEditorPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                Spacer(minLength: 0)

                if let themeColorHex {
                    Circle()
                        .fill(Color(spaceHex: themeColorHex))
                        .frame(width: 10, height: 10)
                }

                Text("Edit Theme")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(textColor)

                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .background(controlFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(controlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isThemeEditorPresented, arrowEdge: .trailing) {
            SpaceThemePanel(
                selectedHex: $themeColorHex,
                selectedAppearance: themeAppearanceSelection,
                selectedOpacity: $themeOpacity,
                selectedTexture: $themeTexture,
                themeOptions: themeOptions,
                onThemePreviewChange: { hexes, opacity, texture in
                    store.previewSpaceThemeColors(
                        primaryHex: hexes.first,
                        auxiliaryHexes: Array(hexes.dropFirst())
                    )
                    store.previewSpaceThemeControls(opacity: opacity, texture: texture)
                }
            )
        }
    }

    private func publishCurrentThemePreview() {
        store.previewSpaceThemeAppearance(themeAppearance)
        store.previewSpaceThemeColors(primaryHex: themeColorHex)
        store.previewSpaceThemeControls(opacity: themeOpacity, texture: themeTexture)
    }

    private func createSpace() {
        if mode == .edit {
            if let editingSpaceID = store.editingSpaceID {
                store.updateSpace(
                    editingSpaceID,
                    name: trimmedName,
                    symbolName: symbolName,
                    themeColorHex: themeColorHex,
                    themeAppearance: themeAppearance,
                    themeOpacity: themeOpacity,
                    themeTexture: themeTexture
                )
            }
            store.clearSpaceThemePreview()
            return
        }

        if mode == .initial {
            store.completeInitialSpaceSetup(
                name: trimmedName,
                symbolName: symbolName,
                themeColorHex: themeColorHex,
                themeAppearance: themeAppearance,
                themeOpacity: themeOpacity,
                themeTexture: themeTexture,
                dataStoreID: dataMode.dataStoreID(current: store.activeSpace?.dataStoreID)
            )
            store.clearSpaceThemePreview()
            store.openNewTabCommandPalette()
            return
        }

        store.createSpace(
            name: trimmedName,
            symbolName: symbolName,
            themeColorHex: themeColorHex,
            themeAppearance: themeAppearance,
            themeOpacity: themeOpacity,
            themeTexture: themeTexture,
            dataStoreID: dataMode.dataStoreID(current: store.activeSpace?.dataStoreID)
        )
        store.clearSpaceThemePreview()
        store.isCreateSpacePresented = false
        store.openNewTabCommandPalette()
    }

}

private struct SpaceIconPreview: View {
    let symbolName: String
    let themeColorHex: String?
    var strokeColor: Color = CandoaChromeStyle.sidebarIcon.opacity(0.78)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
                )

            if symbolName != "square.dashed" {
                if let emoji = SpaceIconOption.emoji(from: symbolName) {
                    Text(emoji)
                        .font(.system(size: 16))
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(spaceHex: themeColorHex ?? "#A8ADB7"))
                }
            }
        }
        .frame(width: 26, height: 26)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SpaceIconPicker: View {
    @Binding var selectedSymbolName: String
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var mode = SpaceIconPickerMode.emojis

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 6)
    private let symbolOptions = [
        SpaceIconOption(symbolName: "sparkle", title: "Sparkle"),
        SpaceIconOption(symbolName: "sparkles", title: "Sparkles"),
        SpaceIconOption(symbolName: "circle.grid.2x2", title: "Grid"),
        SpaceIconOption(symbolName: "square.grid.2x2", title: "Squares"),
        SpaceIconOption(symbolName: "circle", title: "Circle"),
        SpaceIconOption(symbolName: "square", title: "Square"),
        SpaceIconOption(symbolName: "triangle", title: "Triangle"),
        SpaceIconOption(symbolName: "diamond", title: "Diamond"),
        SpaceIconOption(symbolName: "star", title: "Star"),
        SpaceIconOption(symbolName: "star.fill", title: "Filled Star"),
        SpaceIconOption(symbolName: "moon.stars", title: "Night"),
        SpaceIconOption(symbolName: "moon", title: "Moon"),
        SpaceIconOption(symbolName: "sun.max", title: "Day"),
        SpaceIconOption(symbolName: "cloud", title: "Cloud"),
        SpaceIconOption(symbolName: "cloud.sun", title: "Weather"),
        SpaceIconOption(symbolName: "bolt", title: "Fast"),
        SpaceIconOption(symbolName: "leaf", title: "Leaf"),
        SpaceIconOption(symbolName: "tree", title: "Tree"),
        SpaceIconOption(symbolName: "flame", title: "Focus"),
        SpaceIconOption(symbolName: "drop", title: "Drop"),
        SpaceIconOption(symbolName: "heart", title: "Heart"),
        SpaceIconOption(symbolName: "flag", title: "Flag"),
        SpaceIconOption(symbolName: "bookmark", title: "Bookmark"),
        SpaceIconOption(symbolName: "tag", title: "Tag"),
        SpaceIconOption(symbolName: "pin", title: "Pin"),
        SpaceIconOption(symbolName: "location", title: "Location"),
        SpaceIconOption(symbolName: "shield", title: "Shield"),
        SpaceIconOption(symbolName: "lock", title: "Lock"),
        SpaceIconOption(symbolName: "key", title: "Key"),
        SpaceIconOption(symbolName: "circle.hexagongrid", title: "Network"),
        SpaceIconOption(symbolName: "wand.and.stars", title: "Magic"),
        SpaceIconOption(symbolName: "lightbulb", title: "Idea"),
        SpaceIconOption(symbolName: "scope", title: "Scope"),
        SpaceIconOption(symbolName: "target", title: "Target"),
        SpaceIconOption(symbolName: "checkmark.circle", title: "Check"),
        SpaceIconOption(symbolName: "plus.circle", title: "Plus"),
        SpaceIconOption(symbolName: "minus.circle", title: "Minus"),
        SpaceIconOption(symbolName: "xmark.circle", title: "Close")
    ]
    private let iconOptions = [
        SpaceIconOption(symbolName: "house", title: "Home"),
        SpaceIconOption(symbolName: "building.2", title: "Office"),
        SpaceIconOption(symbolName: "briefcase", title: "Work"),
        SpaceIconOption(symbolName: "laptopcomputer", title: "Laptop"),
        SpaceIconOption(symbolName: "desktopcomputer", title: "Desktop"),
        SpaceIconOption(symbolName: "graduationcap", title: "Study"),
        SpaceIconOption(symbolName: "paintpalette", title: "Creative"),
        SpaceIconOption(symbolName: "terminal", title: "Code"),
        SpaceIconOption(symbolName: "keyboard", title: "Keyboard"),
        SpaceIconOption(symbolName: "book.closed", title: "Reading"),
        SpaceIconOption(symbolName: "pencil", title: "Writing"),
        SpaceIconOption(symbolName: "calendar", title: "Calendar"),
        SpaceIconOption(symbolName: "clock", title: "Clock"),
        SpaceIconOption(symbolName: "alarm", title: "Alarm"),
        SpaceIconOption(symbolName: "envelope", title: "Mail"),
        SpaceIconOption(symbolName: "message", title: "Messages"),
        SpaceIconOption(symbolName: "phone", title: "Phone"),
        SpaceIconOption(symbolName: "music.note", title: "Music"),
        SpaceIconOption(symbolName: "headphones", title: "Audio"),
        SpaceIconOption(symbolName: "film", title: "Video"),
        SpaceIconOption(symbolName: "cart", title: "Shopping"),
        SpaceIconOption(symbolName: "bag", title: "Bag"),
        SpaceIconOption(symbolName: "creditcard", title: "Banking"),
        SpaceIconOption(symbolName: "dollarsign.circle", title: "Money"),
        SpaceIconOption(symbolName: "chart.bar", title: "Charts"),
        SpaceIconOption(symbolName: "chart.pie", title: "Analytics"),
        SpaceIconOption(symbolName: "airplane", title: "Travel"),
        SpaceIconOption(symbolName: "car", title: "Car"),
        SpaceIconOption(symbolName: "bicycle", title: "Bike"),
        SpaceIconOption(symbolName: "figure.walk", title: "Walking"),
        SpaceIconOption(symbolName: "fork.knife", title: "Food"),
        SpaceIconOption(symbolName: "cup.and.saucer", title: "Coffee"),
        SpaceIconOption(symbolName: "gift", title: "Gift"),
        SpaceIconOption(symbolName: "shippingbox", title: "Package"),
        SpaceIconOption(symbolName: "camera", title: "Photos"),
        SpaceIconOption(symbolName: "photo", title: "Gallery"),
        SpaceIconOption(symbolName: "lock", title: "Private"),
        SpaceIconOption(symbolName: "hammer", title: "Build"),
        SpaceIconOption(symbolName: "wrench.and.screwdriver", title: "Tools"),
        SpaceIconOption(symbolName: "gearshape", title: "Settings"),
        SpaceIconOption(symbolName: "gamecontroller", title: "Games"),
        SpaceIconOption(symbolName: "folder", title: "Folder"),
        SpaceIconOption(symbolName: "doc.text", title: "Documents"),
        SpaceIconOption(symbolName: "tray", title: "Inbox"),
        SpaceIconOption(symbolName: "paperplane", title: "Send"),
        SpaceIconOption(symbolName: "globe", title: "Web"),
        SpaceIconOption(symbolName: "person", title: "Person"),
        SpaceIconOption(symbolName: "person.2", title: "People"),
        SpaceIconOption(symbolName: "link", title: "Link"),
        SpaceIconOption(symbolName: "eye", title: "Watch")
    ]
    private let emojiOptions = [
        SpaceIconOption(emoji: "😀", title: "Smile"),
        SpaceIconOption(emoji: "😄", title: "Happy"),
        SpaceIconOption(emoji: "😎", title: "Cool"),
        SpaceIconOption(emoji: "🤓", title: "Study"),
        SpaceIconOption(emoji: "🥳", title: "Celebrate"),
        SpaceIconOption(emoji: "🤫", title: "Quiet"),
        SpaceIconOption(emoji: "🧠", title: "Thinking"),
        SpaceIconOption(emoji: "👀", title: "Watch"),
        SpaceIconOption(emoji: "💼", title: "Work"),
        SpaceIconOption(emoji: "🏠", title: "Home"),
        SpaceIconOption(emoji: "🏦", title: "Banking"),
        SpaceIconOption(emoji: "🛒", title: "Shopping"),
        SpaceIconOption(emoji: "🎓", title: "School"),
        SpaceIconOption(emoji: "🎨", title: "Creative"),
        SpaceIconOption(emoji: "📚", title: "Reading"),
        SpaceIconOption(emoji: "🧪", title: "Research"),
        SpaceIconOption(emoji: "💻", title: "Computer"),
        SpaceIconOption(emoji: "⌨️", title: "Keyboard"),
        SpaceIconOption(emoji: "📱", title: "Phone"),
        SpaceIconOption(emoji: "📷", title: "Camera"),
        SpaceIconOption(emoji: "🎵", title: "Music"),
        SpaceIconOption(emoji: "🎮", title: "Games"),
        SpaceIconOption(emoji: "✈️", title: "Travel"),
        SpaceIconOption(emoji: "🚗", title: "Car"),
        SpaceIconOption(emoji: "☕️", title: "Coffee"),
        SpaceIconOption(emoji: "🍽️", title: "Food"),
        SpaceIconOption(emoji: "🏋️", title: "Fitness"),
        SpaceIconOption(emoji: "🧘", title: "Calm"),
        SpaceIconOption(emoji: "🌱", title: "Growth"),
        SpaceIconOption(emoji: "🔥", title: "Focus"),
        SpaceIconOption(emoji: "⚡️", title: "Fast"),
        SpaceIconOption(emoji: "🌙", title: "Night"),
        SpaceIconOption(emoji: "☀️", title: "Day"),
        SpaceIconOption(emoji: "⭐️", title: "Star"),
        SpaceIconOption(emoji: "💎", title: "Diamond"),
        SpaceIconOption(emoji: "❤️", title: "Heart"),
        SpaceIconOption(emoji: "🔒", title: "Private"),
        SpaceIconOption(emoji: "🔑", title: "Key"),
        SpaceIconOption(emoji: "🧰", title: "Tools"),
        SpaceIconOption(emoji: "📦", title: "Package"),
        SpaceIconOption(emoji: "📈", title: "Growth Chart"),
        SpaceIconOption(emoji: "💸", title: "Money"),
        SpaceIconOption(emoji: "🧾", title: "Receipts"),
        SpaceIconOption(emoji: "📝", title: "Notes"),
        SpaceIconOption(emoji: "✅", title: "Done"),
        SpaceIconOption(emoji: "🚀", title: "Launch"),
        SpaceIconOption(emoji: "🧭", title: "Navigate"),
        SpaceIconOption(emoji: "🌍", title: "World")
    ]

    private var filteredOptions: [SpaceIconOption] {
        let options: [SpaceIconOption]
        switch mode {
        case .emojis:
            options = emojiOptions
        case .symbols:
            options = symbolOptions
        case .icons:
            options = iconOptions
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return options }
        return options.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.symbolName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Icon Type", selection: $mode) {
                    ForEach(SpaceIconPickerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 216)

                Spacer()

                Button {
                    selectedSymbolName = "square.dashed"
                    isPresented = false
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Clear Icon")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CandoaChromeStyle.sidebarIcon)

                TextField(mode.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CandoaChromeStyle.popoverBorder, lineWidth: 1)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filteredOptions) { option in
                        Button {
                            selectedSymbolName = option.symbolName
                            isPresented = false
                        } label: {
                            SpaceIconOptionView(
                                option: option,
                                isSelected: selectedSymbolName == option.symbolName
                            )
                        }
                        .buttonStyle(.plain)
                        .help(option.title)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(width: 304, height: 340)
        .background(CandoaChromeStyle.popoverBackground)
    }
}

private struct SpaceIconOptionView: View {
    let option: SpaceIconOption
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)

            if let emoji = option.emoji {
                Text(emoji)
                    .font(.system(size: 19))
            } else {
                Image(systemName: option.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : CandoaChromeStyle.sidebarText)
            }
        }
        .frame(width: 34, height: 34)
    }
}

private struct SpaceProfilePicker: View {
    @Binding var selectedMode: SpaceDataMode
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(SpaceDataMode.allCases) { mode in
                Button {
                    selectedMode = mode
                    isPresented = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(mode.tint)
                            .frame(width: 21)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CandoaChromeStyle.sidebarText)
                                .lineLimit(1)

                            Text(mode.detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CandoaChromeStyle.sidebarIcon)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if selectedMode == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selectedMode == mode ? Color.primary.opacity(0.07) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(CandoaChromeStyle.popoverBackground)
    }
}

private struct SpaceThemePanel: View {
    @Binding var selectedHex: String?
    @Binding var selectedAppearance: SpaceThemeAppearance
    @Binding var selectedOpacity: Double
    @Binding var selectedTexture: Double
    let themeOptions: [(name: String, hex: String)]
    let onThemePreviewChange: ([String], Double, Double) -> Void

    @State private var auxiliaryHexes: [String] = []
    @State private var palettePage = 0
    @State private var palettePageDirection = 1
    @State private var usesHarmony = true
    @State private var dotPositions = [ThemeDotPosition(x: 0.57, y: 0.55)]
    @State private var didInitializeDotPositions = false

    private var paletteOptions: [(name: String, hex: String)] {
        themeOptions + [
            ("Mist", "#C8D3E8"),
            ("Mint", "#8BE0C2"),
            ("Amber", "#F0C36D"),
            ("Coral", "#F18A7A"),
            ("Lavender", "#C9A7E8"),
            ("Sky", "#82C4EA"),
            ("Rose", "#E4A4C3"),
            ("Graphite", "#8F96A8")
        ]
    }

    private var visiblePaletteOptions: [(name: String, hex: String)] {
        let pageSize = 8
        let currentPage = min(max(0, palettePage), pageCount - 1)
        let start = min(currentPage * pageSize, max(0, paletteOptions.count - pageSize))
        let end = min(start + pageSize, paletteOptions.count)
        return Array(paletteOptions[start..<end])
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(paletteOptions.count) / 8.0)))
    }

    private var canPagePaletteBackward: Bool {
        palettePage > 0
    }

    private var canPagePaletteForward: Bool {
        palettePage < pageCount - 1
    }

    private var activeHexes: [String] {
        selectedHex.map { [$0] + auxiliaryHexes } ?? []
    }

    private var normalizedOpacity: Double {
        (min(0.9, max(0.3, selectedOpacity)) - 0.3) / 0.6
    }

    private var hasSelectedThemeColor: Bool {
        selectedHex != nil
    }

    private var themeControlAccentHex: String {
        selectedHex ?? "#A8ADB7"
    }

    var body: some View {
        VStack(spacing: 0) {
            themeField

            paletteRow
                .padding(.top, 10)

            lowerControls
                .padding(.top, 12)
        }
        .padding(10)
        .frame(width: 372)
        .onAppear {
            initializeDotPositionsIfNeeded()
            publishThemePreview()
        }
        .onChange(of: selectedHex) { _, _ in
            publishThemePreview()
        }
        .onChange(of: auxiliaryHexes) { _, _ in
            publishThemePreview()
        }
        .onChange(of: selectedOpacity) { _, _ in
            publishThemePreview()
        }
        .onChange(of: selectedTexture) { _, _ in
            publishThemePreview()
        }
    }

    private var themeField: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.045))

            ThemeColorFieldBackground(
                hexes: activeHexes,
                positions: dotPositions,
                intensity: 0.20 + normalizedOpacity * 0.62
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            DotPattern(opacity: 0.09 + selectedTexture * 0.22, spacing: 6, dotSize: 1.7)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            ThemeColorFieldDots(
                hexes: activeHexes,
                positions: dotPositions,
                onDrag: updateDotPosition
            )

            VStack(spacing: 0) {
                appearanceControls
                    .padding(.top, 12)

                Spacer(minLength: 0)

                fieldActionControls
                    .padding(.bottom, 15)
            }
        }
        .frame(height: 352)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CandoaChromeStyle.popoverBorder, lineWidth: 1)
        }
    }

    private var appearanceControls: some View {
        HStack(spacing: 18) {
            ForEach(SpaceThemeAppearance.allCases) { option in
                Button {
                    selectedAppearance = option
                } label: {
                    Image(systemName: option.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 32)
                        .foregroundStyle(CandoaChromeStyle.sidebarText)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(selectedAppearance == option ? Color.primary.opacity(0.13) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(option.title)
            }
        }
    }

    private var fieldActionControls: some View {
        HStack(spacing: 28) {
            ThemeIconButton(systemName: "plus", help: "Add Color") {
                addAuxiliaryColor()
            }
            .disabled(auxiliaryHexes.count >= 2)

            ThemeIconButton(systemName: "minus", help: "Remove Color") {
                removeAuxiliaryColor()
            }
            .disabled(selectedHex == nil && auxiliaryHexes.isEmpty)

            ThemeHarmonyButton(isActive: usesHarmony, isEnabled: activeHexes.count > 1) {
                usesHarmony.toggle()

                // Snap immediately so the toggle gives visible feedback
                // instead of only applying on the next dot drag.
                if usesHarmony, let primary = dotPositions.first, !auxiliaryHexes.isEmpty {
                    withAnimation(.easeOut(duration: 0.22)) {
                        harmonizeAuxiliaryDots(around: primary)
                    }
                    publishThemePreview()
                }
            }
        }
    }

    private var paletteRow: some View {
        HStack(spacing: 9) {
            ThemeIconButton(systemName: "chevron.left", help: "Previous Colors") {
                pagePalette(by: -1)
            }
            .disabled(!canPagePaletteBackward)

            ZStack {
                paletteColorPage
                    .id(palettePage)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: palettePageDirection > 0 ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: palettePageDirection > 0 ? .leading : .trailing)
                                .combined(with: .opacity)
                        )
                    )
            }
            .frame(width: 287, height: 32)
            .clipped()

            ThemeIconButton(systemName: "chevron.right", help: "More Colors") {
                pagePalette(by: 1)
            }
            .disabled(!canPagePaletteForward)
        }
        .frame(height: 32)
    }

    private var paletteColorPage: some View {
        HStack(spacing: 9) {
            ForEach(visiblePaletteOptions, id: \.hex) { option in
                Button {
                    selectPaletteColor(option.hex)
                } label: {
                    Circle()
                        .fill(Color(spaceHex: option.hex))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedHex == option.hex ? Color.white : Color.clear,
                                    lineWidth: 3
                                )
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    selectedHex == option.hex ? CandoaChromeStyle.sidebarText.opacity(0.68) : Color.clear,
                                    lineWidth: 1
                                )
                                .padding(-1)
                        }
                }
                .buttonStyle(.plain)
                .help(option.name)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 287, height: 32, alignment: .leading)
    }

    private var lowerControls: some View {
        HStack(spacing: 18) {
            ThemeWaveSlider(
                value: $selectedOpacity,
                accentHex: themeControlAccentHex,
                isEnabled: hasSelectedThemeColor
            )
                .frame(width: 218, height: 58)

            Spacer(minLength: 0)

            ThemeTextureDial(
                value: $selectedTexture,
                accentHex: themeControlAccentHex,
                isEnabled: hasSelectedThemeColor
            )
                .frame(width: 62, height: 62)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 2)
    }

    private func addAuxiliaryColor() {
        guard auxiliaryHexes.count < 2 else { return }
        let hexes = paletteOptions.map(\.hex)
        guard let firstHex = hexes.first else { return }

        if selectedHex == nil {
            selectedHex = firstHex
            ensureDotPositionCount()
            dotPositions[0] = Self.position(forHex: firstHex)
            publishThemePreview()
            return
        }

        let referenceHex = auxiliaryHexes.last ?? selectedHex ?? firstHex
        let referenceIndex = hexes.firstIndex(of: referenceHex) ?? 0

        for offset in 1...hexes.count {
            let candidate = hexes[(referenceIndex + offset) % hexes.count]
            if candidate != selectedHex, !auxiliaryHexes.contains(candidate) {
                auxiliaryHexes.append(candidate)
                ensureDotPositionCount()
                dotPositions[auxiliaryHexes.count] = suggestedAuxiliaryPosition(at: auxiliaryHexes.count)
                publishThemePreview()
                return
            }
        }
    }

    private func removeAuxiliaryColor() {
        if !auxiliaryHexes.isEmpty {
            auxiliaryHexes.removeLast()
        } else if selectedHex != nil {
            selectedHex = nil
        } else {
            return
        }

        if dotPositions.count > activeHexes.count {
            dotPositions.removeLast(dotPositions.count - activeHexes.count)
        }
        publishThemePreview()
    }

    private func initializeDotPositionsIfNeeded() {
        guard !didInitializeDotPositions else { return }
        didInitializeDotPositions = true
        dotPositions = selectedHex.map { [Self.position(forHex: $0)] } ?? []
        ensureDotPositionCount()
    }

    private func ensureDotPositionCount() {
        while dotPositions.count < activeHexes.count {
            dotPositions.append(suggestedAuxiliaryPosition(at: dotPositions.count))
        }

        if dotPositions.count > activeHexes.count {
            dotPositions.removeLast(dotPositions.count - activeHexes.count)
        }
    }

    private func selectPaletteColor(_ hex: String) {
        selectedHex = hex
        ensureDotPositionCount()
        dotPositions[0] = Self.position(forHex: hex)
        publishThemePreview()
    }

    private func pagePalette(by delta: Int) {
        let nextPage = min(max(0, palettePage + delta), pageCount - 1)
        guard nextPage != palettePage else { return }

        palettePageDirection = delta >= 0 ? 1 : -1
        withAnimation(.easeOut(duration: 0.18)) {
            palettePage = nextPage
        }
    }

    private func updateDotPosition(index: Int, position: ThemeDotPosition) {
        ensureDotPositionCount()
        guard dotPositions.indices.contains(index) else { return }

        dotPositions[index] = position

        if index == 0 {
            selectedHex = Self.hex(for: position)
            if usesHarmony, auxiliaryHexes.count > 0 {
                harmonizeAuxiliaryDots(around: position)
            }
        } else {
            let auxiliaryIndex = index - 1
            if auxiliaryHexes.indices.contains(auxiliaryIndex) {
                auxiliaryHexes[auxiliaryIndex] = Self.hex(for: position)
            }
        }

        publishThemePreview()
    }

    private func harmonizeAuxiliaryDots(around primaryPosition: ThemeDotPosition) {
        let dx = primaryPosition.x - 0.5
        let dy = primaryPosition.y - 0.5
        let primaryAngle = atan2(dy, dx)
        let radius = min(0.38, max(0.18, hypot(dx, dy)))

        for auxiliaryIndex in auxiliaryHexes.indices {
            let dotIndex = auxiliaryIndex + 1
            let offset = auxiliaryIndex == 0 ? 2.12 : -2.12
            let angle = primaryAngle + offset
            let position = ThemeDotPosition(
                x: 0.5 + cos(angle) * radius,
                y: 0.5 + sin(angle) * radius
            ).clampedToUnitCircle()

            dotPositions[dotIndex] = position
            auxiliaryHexes[auxiliaryIndex] = Self.hex(for: position)
        }
    }

    private func publishThemePreview() {
        onThemePreviewChange(activeHexes, selectedOpacity, selectedTexture)
    }

    private func suggestedAuxiliaryPosition(at index: Int) -> ThemeDotPosition {
        let primary = dotPositions.first ?? ThemeDotPosition(x: 0.57, y: 0.55)
        let dx = primary.x - 0.5
        let dy = primary.y - 0.5
        let primaryAngle = atan2(dy, dx)
        let radius = min(0.38, max(0.22, hypot(dx, dy)))
        let offset = index == 1 ? 2.12 : -2.12

        return ThemeDotPosition(
            x: 0.5 + cos(primaryAngle + offset) * radius,
            y: 0.5 + sin(primaryAngle + offset) * radius
        ).clampedToUnitCircle()
    }

    private static func position(forHex hex: String) -> ThemeDotPosition {
        guard let components = rgbComponents(from: hex) else {
            return ThemeDotPosition(x: 0.57, y: 0.55)
        }

        let color = NSColor(
            calibratedRed: components.red,
            green: components.green,
            blue: components.blue,
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let radius = min(0.40, max(0.16, saturation * 0.40))
        let angle = hue * .pi * 2
        return ThemeDotPosition(
            x: 0.5 + cos(angle) * radius,
            y: 0.5 + sin(angle) * radius
        ).clampedToUnitCircle()
    }

    private static func hex(for position: ThemeDotPosition) -> String {
        let dx = position.x - 0.5
        let dy = position.y - 0.5
        var hue = atan2(dy, dx) / (.pi * 2)
        if hue < 0 {
            hue += 1
        }

        let distance = min(1, hypot(dx, dy) / 0.42)
        let saturation = min(0.96, max(0.34, distance))
        let brightness = min(0.98, max(0.46, 1.04 - position.y * 0.56))

        let color = NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return "#6E8BFF"
        }

        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func rgbComponents(from hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }

        return (
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0
        )
    }
}

private struct ThemeDotPosition: Equatable {
    var x: CGFloat
    var y: CGFloat

    func point(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func clampedToUnitCircle() -> ThemeDotPosition {
        let dx = x - 0.5
        let dy = y - 0.5
        let radius = hypot(dx, dy)
        guard radius > 0.42 else {
            return ThemeDotPosition(
                x: min(0.92, max(0.08, x)),
                y: min(0.92, max(0.08, y))
            )
        }

        let scale = 0.42 / radius
        return ThemeDotPosition(
            x: min(0.92, max(0.08, 0.5 + dx * scale)),
            y: min(0.92, max(0.08, 0.5 + dy * scale))
        )
    }

    static func clamped(from point: CGPoint, in size: CGSize) -> ThemeDotPosition {
        let safeWidth = max(1, size.width)
        let safeHeight = max(1, size.height)
        let center = CGPoint(x: safeWidth / 2, y: safeHeight / 2)
        let fieldRadius = min(safeWidth, safeHeight) * 0.42
        var clampedPoint = point

        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        if distance > fieldRadius {
            let scale = fieldRadius / distance
            clampedPoint = CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
        }

        return ThemeDotPosition(
            x: min(0.92, max(0.08, clampedPoint.x / safeWidth)),
            y: min(0.92, max(0.08, clampedPoint.y / safeHeight))
        )
    }
}

private struct ThemeColorFieldBackground: View {
    let hexes: [String]
    let positions: [ThemeDotPosition]
    let intensity: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(hexes.enumerated()), id: \.offset) { index, hex in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(spaceHex: hex).opacity(intensity),
                                    Color(spaceHex: hex).opacity(intensity * 0.30),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 8,
                                endRadius: 125
                            )
                        )
                        .frame(width: 260, height: 260)
                        .position(position(for: index, in: proxy.size))
                        .blur(radius: 14)
                }

                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.08),
                        Color.primary.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func position(for index: Int, in size: CGSize) -> CGPoint {
        guard positions.indices.contains(index) else {
            return CGPoint(x: size.width * 0.57, y: size.height * 0.55)
        }

        return positions[index].point(in: size)
    }
}

private struct ThemeColorFieldDots: View {
    let hexes: [String]
    let positions: [ThemeDotPosition]
    let onDrag: (Int, ThemeDotPosition) -> Void

    private static let coordinateSpaceName = "CandoaThemeColorField"

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(hexes.enumerated()), id: \.offset) { index, hex in
                    Circle()
                        .fill(Color(spaceHex: hex))
                        .frame(width: index == 0 ? 40 : 22, height: index == 0 ? 40 : 22)
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(index == 0 ? 0.95 : 0.86), lineWidth: index == 0 ? 5 : 3)
                        }
                        .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                        .scaleEffect(positions.indices.contains(index) ? 1 : 0.001)
                        .position(position(for: index, in: proxy.size))
                        .contentShape(Circle())
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
                                .onChanged { gesture in
                                    onDrag(
                                        index,
                                        ThemeDotPosition.clamped(from: gesture.location, in: proxy.size)
                                    )
                                }
                        )
                        .help(index == 0 ? "Drag to change Space color" : "Drag to adjust theme color")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .coordinateSpace(name: Self.coordinateSpaceName)
        }
    }

    private func position(for index: Int, in size: CGSize) -> CGPoint {
        guard positions.indices.contains(index) else {
            return CGPoint(x: size.width * 0.57, y: size.height * 0.55)
        }

        return positions[index].point(in: size)
    }
}

private struct ThemeIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CandoaChromeStyle.sidebarText.opacity(isEnabled ? 0.92 : 0.34))
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ThemeHarmonyButton: View {
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false
    @State private var didPushNotAllowedCursor = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CandoaChromeStyle.sidebarText.opacity(isEnabled ? (isActive ? 0.94 : 0.54) : 0.30))
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive && isEnabled ? Color.primary.opacity(0.13) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isEnabled ? "Auto-arrange colors" : "Add another color to use harmony")
        .onHover { hovering in
            isHovering = hovering
            updateCursor()
        }
        .onChange(of: isEnabled) { _, _ in
            updateCursor()
        }
        .onDisappear {
            popNotAllowedCursorIfNeeded()
        }
    }

    private func updateCursor() {
        guard isHovering, !isEnabled else {
            popNotAllowedCursorIfNeeded()
            return
        }

        guard !didPushNotAllowedCursor else { return }
        NSCursor.operationNotAllowed.push()
        didPushNotAllowedCursor = true
    }

    private func popNotAllowedCursorIfNeeded() {
        guard didPushNotAllowedCursor else { return }
        NSCursor.pop()
        didPushNotAllowedCursor = false
    }
}

private struct ThemeWaveSlider: View {
    @Binding var value: Double
    let accentHex: String
    let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var handleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private let range = 0.3...0.9

    private var normalizedValue: Double {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let progress = normalizedValue
            let handleX = CGFloat(progress) * max(1, size.width - 26) + 13
            let handleWidth = CGFloat(14 + progress * 10)
            let handleHeight = CGFloat(42 + progress * 12)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? 0.09 : 0.05))
                    .frame(height: 16)
                    .padding(.horizontal, 1)

                ThemeWaveShape(progress: progress)
                    .stroke(Color.primary.opacity(isEnabled ? 0.28 : 0.16), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    .frame(height: 32)
                    .padding(.horizontal, 1)

                ThemeWaveShape(progress: progress)
                    .trim(from: 0, to: progress)
                    .stroke(
                        isEnabled
                            ? Color(spaceHex: accentHex).opacity(0.38 + progress * 0.46)
                            : Color.primary.opacity(0.12),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                    .frame(height: 32)
                    .padding(.horizontal, 1)

                Capsule(style: .continuous)
                    .fill(handleColor.opacity(isEnabled ? 1 : 0.28))
                    .frame(width: handleWidth, height: handleHeight)
                    .shadow(color: Color.black.opacity(isEnabled ? 0.22 : 0), radius: 6, x: 0, y: 3)
                    .position(x: handleX, y: size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let progress = min(1, max(0, gesture.location.x / max(1, size.width)))
                        value = range.lowerBound + progress * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}

private struct ThemeWaveShape: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude = rect.height * (0.18 + CGFloat(progress) * 0.20)
        let midY = rect.midY
        let wavelength = max(34, rect.width / 5.5)

        path.move(to: CGPoint(x: rect.minX, y: midY))

        var x = rect.minX
        while x <= rect.maxX {
            let normalized = (x - rect.minX) / wavelength
            let y = midY + sin(normalized * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }

        return path
    }
}

private struct ThemeTextureDial: View {
    @Binding var value: Double
    let accentHex: String
    let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragValue: Double?

    private var handleColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private let textureStepCount = 16
    private var maxTextureStep: Int {
        textureStepCount - 1
    }

    private var clampedValue: Double {
        min(1, max(0, value))
    }

    private var displayedValue: Double {
        dragValue ?? clampedValue
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let radius = side * 0.35
            let activeValue = displayedValue
            let activeStep = textureStep(for: activeValue)

            ZStack {
                ForEach(0..<textureStepCount, id: \.self) { index in
                    let isActive = isEnabled && activeValue > 0 && index <= activeStep
                    Circle()
                        .fill(isActive ? Color(spaceHex: accentHex).opacity(0.74) : Color.primary.opacity(index % 4 == 0 ? 0.30 : 0.20))
                        .frame(width: index % 4 == 0 ? 5 : 4, height: index % 4 == 0 ? 5 : 4)
                        .position(point(forStep: index, radius: radius, in: proxy.size))
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(spaceHex: accentHex).opacity(isEnabled ? 0.28 : 0.04),
                                Color.primary.opacity(isEnabled ? 0.10 : 0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        DotPattern(
                            opacity: isEnabled ? 0.03 + activeValue * 0.20 : 0.035,
                            spacing: 4,
                            dotSize: 1.1
                        )
                        .clipShape(Circle())
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                    }
                    .frame(width: side * 0.64, height: side * 0.64)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                Capsule(style: .continuous)
                    .fill(handleColor.opacity(isEnabled ? 1 : 0.34))
                    .frame(width: 7, height: 18)
                    .rotationEffect(.degrees(rotationDegrees(forStep: activeStep)))
                    .position(point(forStep: activeStep, radius: radius, in: proxy.size))
                    .shadow(color: Color.black.opacity(isEnabled ? 0.18 : 0), radius: 3, x: 0, y: 1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        let nextValue = steppedValue(for: dialValue(for: gesture.location, in: proxy.size))
                        if textureStep(for: displayedValue) != textureStep(for: nextValue) {
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        setValueWithoutAnimation(nextValue)
                    }
                    .onEnded { _ in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            dragValue = nil
                        }
                    }
            )
        }
    }

    private func point(forStep step: Int, radius: CGFloat, in size: CGSize) -> CGPoint {
        let angle = angle(forStep: step)
        return CGPoint(
            x: size.width / 2 + sin(angle) * radius,
            y: size.height / 2 - cos(angle) * radius
        )
    }

    private func dialValue(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let angle = normalizedAngle(atan2(location.y - center.y, location.x - center.x) + (.pi / 2))
        return Double(angle / (.pi * 2))
    }

    private func angle(forStep step: Int) -> CGFloat {
        CGFloat(min(maxTextureStep, max(0, step))) / CGFloat(textureStepCount) * .pi * 2
    }

    private func rotationDegrees(forStep step: Int) -> Double {
        Double(min(maxTextureStep, max(0, step))) / Double(textureStepCount) * 360
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        positiveModulo(angle, .pi * 2)
    }

    private func positiveModulo(_ value: CGFloat, _ modulus: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private func steppedValue(for value: Double) -> Double {
        Double(textureStep(for: value)) / Double(maxTextureStep)
    }

    private func textureStep(for value: Double) -> Int {
        min(maxTextureStep, max(0, Int((min(1, max(0, value)) * Double(maxTextureStep)).rounded())))
    }

    private func setValueWithoutAnimation(_ nextValue: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragValue = nextValue
            value = nextValue
        }
    }
}

private struct DotPattern: View {
    var opacity: Double = 0.11
    var spacing: CGFloat = 8
    var dotSize: CGFloat = 2

    var body: some View {
        let clampedOpacity = min(1, max(0, opacity))

        if clampedOpacity > 0 {
            DotPatternCanvas(spacing: spacing, dotSize: dotSize)
                .equatable()
                .opacity(clampedOpacity)
        }
    }
}

private struct DotPatternCanvas: View, Equatable {
    var spacing: CGFloat
    var dotSize: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            guard spacing > 0, dotSize > 0 else { return }

            var dots = Path()
            var x: CGFloat = 6
            while x < size.width {
                var y: CGFloat = 6
                while y < size.height {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
                    y += spacing
                }
                x += spacing
            }

            context.fill(dots, with: .color(Color.primary))
        }
    }
}

private struct SpaceIconOption: Identifiable {
    let symbolName: String
    let title: String

    init(symbolName: String, title: String) {
        self.symbolName = symbolName
        self.title = title
    }

    init(emoji: String, title: String) {
        self.symbolName = Self.emojiPrefix + emoji
        self.title = title
    }

    var id: String { symbolName }

    var emoji: String? {
        Self.emoji(from: symbolName)
    }

    static func emoji(from symbolName: String) -> String? {
        guard symbolName.hasPrefix(emojiPrefix) else { return nil }
        return String(symbolName.dropFirst(emojiPrefix.count))
    }

    private static let emojiPrefix = BrowserSpace.emojiSymbolPrefix
}

private enum SpaceIconPickerMode: String, CaseIterable, Identifiable {
    case emojis
    case symbols
    case icons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .emojis:
            return "Emojis"
        case .symbols:
            return "Symbols"
        case .icons:
            return "Icons"
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .emojis:
            return "Search emojis"
        case .symbols, .icons:
            return "Search icons"
        }
    }
}

private enum SpaceComposerMode {
    case create
    case initial
    case edit

    var defaultName: String {
        switch self {
        case .initial:
            return "Personal"
        case .create, .edit:
            return ""
        }
    }

    var title: String {
        switch self {
        case .create, .initial:
            return "Create a Space"
        case .edit:
            return "Edit Space"
        }
    }

    var subtitle: String {
        switch self {
        case .create, .initial:
            return "Spaces organize your tabs and sessions."
        case .edit:
            return "Update this Space's name, icon, and theme."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .create, .initial:
            return BrowserCommandTitles.createSpace
        case .edit:
            return "Save Changes"
        }
    }
}

private enum SpaceDataMode: String, CaseIterable, Identifiable {
    case isolated
    case shareCurrent
    case personal
    case work
    case banking
    case shopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isolated:
            return "Default"
        case .shareCurrent:
            return "Current"
        case .personal:
            return "Personal"
        case .work:
            return "Work"
        case .banking:
            return "Banking"
        case .shopping:
            return "Shopping"
        }
    }

    var detail: String {
        switch self {
        case .isolated:
            return "Separate browsing session"
        case .shareCurrent:
            return "Share active Space session"
        case .personal:
            return "Shared personal profile"
        case .work:
            return "Shared work profile"
        case .banking:
            return "Shared finance profile"
        case .shopping:
            return "Shared shopping profile"
        }
    }

    var symbolName: String {
        switch self {
        case .isolated:
            return "person.crop.circle"
        case .shareCurrent:
            return "link"
        case .personal:
            return "person.crop.circle.fill"
        case .work:
            return "briefcase.fill"
        case .banking:
            return "dollarsign.circle.fill"
        case .shopping:
            return "cart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .isolated:
            return .blue
        case .shareCurrent:
            return .green
        case .personal:
            return .cyan
        case .work:
            return .orange
        case .banking:
            return Color(red: 0.39, green: 0.82, blue: 0.18)
        case .shopping:
            return .pink
        }
    }

    func dataStoreID(current: UUID?) -> UUID {
        switch self {
        case .isolated:
            return UUID()
        case .shareCurrent:
            return current ?? UUID()
        case .personal:
            return UUID(uuidString: "69E60654-3E84-4761-87DA-B13A2C7195E3")!
        case .work:
            return UUID(uuidString: "3ED24A8B-6573-46BE-9059-8E8E331F0143")!
        case .banking:
            return UUID(uuidString: "28166B44-6387-4216-9EAE-39A569C6014D")!
        case .shopping:
            return UUID(uuidString: "72BC27D2-3D02-459A-A0AF-98036B15CF13")!
        }
    }
}

// MARK: - Essential tile

private struct EssentialTileView: View {
    let tab: BrowserTab
    let isActive: Bool
    let accentColor: Color
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onOpenInSplit: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(accentColor.opacity(0.18))
                            : AnyShapeStyle(CandoaChromeStyle.sidebarControlFill)
                    )

                faviconImage
                    .frame(width: 18, height: 18)
            }
            .frame(height: 44)
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(CandoaChromeStyle.sidebarTextSecondary)
                            .background(Circle().fill(CandoaChromeStyle.sidebarBackground))
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                    .padding(4)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isActive
                            ? accentColor.opacity(0.34)
                            : (isHovering ? CandoaChromeStyle.sidebarControlStroke : Color.clear),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isActive)
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? CandoaChromeStyle.sidebarText : CandoaChromeStyle.sidebarTextSecondary)
        }
    }
}

// MARK: - Window controls

private struct WindowControlsView: View {
    let isVisible: Bool
    let hiddenOffset: CGFloat

    var body: some View {
        NativeWindowControlsView(
            isVisible: isVisible,
            hiddenOffset: hiddenOffset
        )
    }
}

private struct NativeWindowControlsView: NSViewRepresentable {
    let isVisible: Bool
    let hiddenOffset: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NativeWindowControlsHost()
        view.configure(isVisible: isVisible, hiddenOffset: hiddenOffset, animated: false)
        DispatchQueue.main.async {
            view.attachWindowControls(animated: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? NativeWindowControlsHost)?
            .configure(isVisible: isVisible, hiddenOffset: hiddenOffset, animated: true)
        DispatchQueue.main.async {
            (nsView as? NativeWindowControlsHost)?.attachWindowControls(animated: true)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? NativeWindowControlsHost)?.restoreWindowControls()
    }
}

private final class NativeWindowControlsHost: NSView {
    private static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]
    private static let centerSpacing: CGFloat = 20
    private static let fallbackButtonSize = NSSize(width: 14, height: 14)
    private static let transitionDuration: TimeInterval = 0.18

    private weak var attachedWindow: NSWindow?
    private var originalFrames: [Int: NSRect] = [:]
    private var originalHiddenStates: [Int: Bool] = [:]
    private var lastVisibleHostFrameBySuperview: [ObjectIdentifier: NSRect] = [:]
    private var isControlsVisible = true
    private var hiddenOffset: CGFloat = 0
    private var shouldAnimateNextLayout = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: 60, height: 24)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachWindowControls(animated: false)
    }

    func configure(isVisible: Bool, hiddenOffset: CGFloat, animated: Bool) {
        let visibilityChanged = isControlsVisible != isVisible
        let offsetChanged = self.hiddenOffset != hiddenOffset
        isControlsVisible = isVisible
        self.hiddenOffset = hiddenOffset
        shouldAnimateNextLayout = animated && (visibilityChanged || offsetChanged)
    }

    func attachWindowControls(animated: Bool) {
        guard let window else { return }

        if let attachedWindow, attachedWindow !== window {
            restoreWindowControls()
        }

        attachedWindow = window

        for buttonType in Self.buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            let key = Int(buttonType.rawValue)

            if originalFrames[key] == nil {
                originalFrames[key] = button.frame
                originalHiddenStates[key] = button.isHidden
            }

            button.isHidden = false
        }

        layoutWindowControls(animated: animated || shouldAnimateNextLayout)
        shouldAnimateNextLayout = false
    }

    func restoreWindowControls() {
        guard let attachedWindow else { return }

        for buttonType in Self.buttonTypes {
            guard let button = attachedWindow.standardWindowButton(buttonType) else { continue }
            let key = Int(buttonType.rawValue)

            if let originalFrame = originalFrames[key] {
                button.frame = originalFrame
            }

            if let wasHidden = originalHiddenStates[key] {
                button.isHidden = wasHidden
            }
        }

        originalFrames.removeAll()
        originalHiddenStates.removeAll()
        lastVisibleHostFrameBySuperview.removeAll()
        self.attachedWindow = nil
    }

    override func layout() {
        super.layout()
        layoutWindowControls(animated: false)
    }

    private func layoutWindowControls(animated: Bool) {
        guard let attachedWindow else { return }

        for (index, buttonType) in Self.buttonTypes.enumerated() {
            guard
                let button = attachedWindow.standardWindowButton(buttonType),
                let buttonSuperview = button.superview
            else { continue }

            let currentSize = button.frame.size
            let buttonSize = currentSize.width > 0 && currentSize.height > 0
                ? currentSize
                : Self.fallbackButtonSize
            button.isHidden = false

            let hostFrameInWindow = convert(bounds, to: nil)
            let superviewID = ObjectIdentifier(buttonSuperview)
            let hostFrameInButtonSuperview = buttonSuperview.convert(hostFrameInWindow, from: nil)
            let isHostOnscreen = hostFrameInWindow.maxX > 0
                && hostFrameInWindow.minX < attachedWindow.frame.width

            let resolvedHostFrame: NSRect
            if isHostOnscreen {
                lastVisibleHostFrameBySuperview[superviewID] = hostFrameInButtonSuperview
                resolvedHostFrame = hostFrameInButtonSuperview
            } else if let lastVisibleHostFrame = lastVisibleHostFrameBySuperview[superviewID] {
                resolvedHostFrame = lastVisibleHostFrame
            } else {
                resolvedHostFrame = hostFrameInButtonSuperview
            }

            let x = resolvedHostFrame.minX
                + (isControlsVisible ? 0 : hiddenOffset)
                + CGFloat(index) * Self.centerSpacing
            let y = floor(resolvedHostFrame.midY - buttonSize.height / 2)
            let nextFrame = NSRect(origin: CGPoint(x: x, y: y), size: buttonSize)

            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.transitionDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    button.animator().frame = nextFrame
                }
            } else {
                button.frame = nextFrame
            }
        }
    }
}

// MARK: - Toolbar icon button

private struct ToolbarIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 25, height: 25)
            .offset(y: -2)
            .contentShape(Rectangle())
    }
}

private extension View {
    func toolbarIconButton() -> some View {
        modifier(ToolbarIconButtonModifier())
    }
}

// MARK: - Shared chrome styling

enum CandoaChromeStyle {
    static let sidebarWidth: CGFloat = 234
    static let setupNeutralTint = Color.primary.opacity(0.10)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let workspaceBackground = Color(nsColor: .controlBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor).opacity(0.90)
    static let sidebarBorder = Color.primary.opacity(0.12)
    static let sidebarSeparator = Color.primary.opacity(0.08)
    static let sidebarControlFill = Color.primary.opacity(0.055)
    static let sidebarControlFillHover = Color.primary.opacity(0.080)
    static let sidebarControlFillActive = Color.accentColor.opacity(0.16)
    static let sidebarControlStroke = Color.primary.opacity(0.08)
    static let spaceSetupControlFill = Color.primary.opacity(0.060)
    static let spaceSetupControlStroke = Color.primary.opacity(0.08)
    static let spaceSetupPillFill = Color.primary.opacity(0.075)
    static let updateBannerFill = Color.primary.opacity(0.075)
    static let updateBannerFillHover = Color.primary.opacity(0.105)
    static let updateBannerStroke = Color.primary.opacity(0.20)
    static let sidebarText = Color.primary.opacity(0.88)
    static let sidebarTextSecondary = Color.primary.opacity(0.62)
    static let sidebarIcon = Color.primary.opacity(0.38)
    static let windowControlInactive = Color.primary.opacity(0.14)
    static let surfaceFill = Color(nsColor: .controlBackgroundColor)
    static let surfaceBorder = Color.primary.opacity(0.12)
    static let popoverBackground = Color(nsColor: .windowBackgroundColor)
    static let popoverBorder = Color(nsColor: .separatorColor).opacity(0.85)

    /// Whether chrome text needs to be dark to stay legible on the themed
    /// surface. At preview strength the theme color dominates the chrome
    /// (0.74 tint), so the color's own perceived luminance decides: light
    /// colors (mint, gold, pink…) wash out white text.
    static func prefersDarkForeground(forSpaceHex hex: String) -> Bool {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return false }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.60
    }
}

/// The single chrome surface painted across the entire window (Zen-style):
/// sidebar, title-bar strip, and the gutter around the web view all share it,
/// so the theme tint reads as one continuous backdrop.
struct CandoaWindowBackdrop: View {
    @ObservedObject var store: BrowserStore

    private var hasThemeTint: Bool {
        !store.activeThemeColorHexes.isEmpty
    }

    private var isSetupThemePreviewActive: Bool {
        store.isSpaceSetupPresented && store.editingSpaceID == nil && hasThemeTint
    }

    private var usesSetupChrome: Bool {
        store.isSpaceSetupPresented && store.editingSpaceID == nil
    }

    private var backdropIntensity: Double {
        if usesSetupChrome {
            // Near-flat during preview: the gradient's brightened leading
            // blob sits under the sidebar and visibly whitens it otherwise.
            return isSetupThemePreviewActive ? 0.04 : 0.08
        }

        return 0.16
    }

    // During create/initial setup theme preview the chrome mirrors
    // SpaceSetupCanvas's fill so sidebar, title bar, and canvas read as one
    // continuous color. Editing keeps normal browsing chrome so preview and
    // saved state match.
    private var spaceTintOpacity: Double {
        guard hasThemeTint else { return 0 }
        return usesSetupChrome ? 0.74 : 0.050
    }

    var body: some View {
        ZStack {
            CandoaChromeStyle.windowBackground
            Color(spaceHex: store.activeThemeColorHexes.first ?? "#8A8F98")
                .opacity(spaceTintOpacity)
            SpaceThemeBackdrop(
                hexes: store.activeThemeColorHexes,
                intensity: backdropIntensity * store.activeThemeIntensityMultiplier,
                texture: store.activeThemeTexture
            )
            CandoaChromeStyle.setupNeutralTint.opacity(usesSetupChrome && !isSetupThemePreviewActive ? 0.18 : 0)
        }
    }
}

struct SpaceThemeBackdrop: View {
    let hexes: [String]
    var intensity: Double = 1
    var texture: Double = 0

    private var palette: [String]? {
        SpaceThemePalette.resolvedHexes(from: hexes)
    }

    private var clampedTexture: Double {
        min(1, max(0, texture))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let longestSide = max(size.width, size.height)

            if let palette {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(spaceHex: palette[0]).opacity(0.34 * intensity),
                            Color(spaceHex: palette[1]).opacity(0.30 * intensity),
                            Color(spaceHex: palette[2]).opacity(0.42 * intensity)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )

                    radialColor(hex: palette[0], opacity: 0.50 * intensity, endRadius: longestSide * 0.48)
                        .frame(width: longestSide * 0.95, height: longestSide * 0.95)
                        .position(x: size.width * 0.08, y: size.height * 0.18)
                        .blur(radius: 34)

                    radialColor(hex: palette[1], opacity: 0.38 * intensity, endRadius: longestSide * 0.54)
                        .frame(width: longestSide, height: longestSide)
                        .position(x: size.width * 0.52, y: size.height * 0.38)
                        .blur(radius: 42)

                    radialColor(hex: palette[2], opacity: 0.54 * intensity, endRadius: longestSide * 0.56)
                        .frame(width: longestSide * 1.05, height: longestSide * 1.05)
                        .position(x: size.width * 0.96, y: size.height * 0.52)
                        .blur(radius: 48)

                    if clampedTexture > 0 {
                        DotPattern(
                            opacity: 0.025 + clampedTexture * 0.12,
                            spacing: 5,
                            dotSize: 1.2
                        )
                        .blendMode(.overlay)
                    }
                }
            }
        }
        .compositingGroup()
    }

    private func radialColor(hex: String, opacity: Double, endRadius: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(spaceHex: hex).opacity(opacity),
                        Color(spaceHex: hex).opacity(opacity * 0.28),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 12,
                    endRadius: endRadius
                )
            )
    }
}

private enum SpaceThemePalette {
    static func resolvedHexes(from hexes: [String]) -> [String]? {
        let cleaned = hexes.filter { !$0.isEmpty }
        guard let primary = cleaned.first else { return nil }

        if cleaned.count >= 3 {
            return Array(cleaned.prefix(3))
        }

        if cleaned.count == 2 {
            return [cleaned[0], shiftedHex(from: cleaned[0], hueOffset: 0.10, saturationScale: 0.72, brightnessScale: 1.08), cleaned[1]]
        }

        return [
            shiftedHex(from: primary, hueOffset: -0.015, saturationScale: 1.08, brightnessScale: 1.08),
            primary,
            shiftedHex(from: primary, hueOffset: 0.045, saturationScale: 0.72, brightnessScale: 0.92)
        ]
    }

    private static func shiftedHex(
        from hex: String,
        hueOffset: CGFloat,
        saturationScale: CGFloat,
        brightnessScale: CGFloat
    ) -> String {
        guard let color = nsColor(from: hex) else {
            return "#6E8BFF"
        }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let shiftedHue = (hue + hueOffset).truncatingRemainder(dividingBy: 1)
        let normalizedHue = shiftedHue < 0 ? shiftedHue + 1 : shiftedHue
        let shiftedColor = NSColor(
            calibratedHue: normalizedHue,
            saturation: min(0.94, max(0.16, saturation * saturationScale)),
            brightness: min(0.98, max(0.24, brightness * brightnessScale)),
            alpha: 1
        )

        guard let rgbColor = shiftedColor.usingColorSpace(.sRGB) else {
            return hex
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(rgbColor.redComponent * 255)),
            Int(round(rgbColor.greenComponent * 255)),
            Int(round(rgbColor.blueComponent * 255))
        )
    }

    private static func nsColor(from hex: String) -> NSColor? {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return nil
        }

        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1
        )
    }
}

// MARK: - Drag reordering

private struct TabReorderDropDelegate: DropDelegate {
    let targetTab: BrowserTab
    let tabs: [BrowserTab]
    let pinned: Bool
    let store: BrowserStore

    // Only tab drags reorder the list; text dragged off a web page also
    // matches UTType.text and must fall through.
    func validateDrop(info: DropInfo) -> Bool {
        store.draggedTabID != nil
    }

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
