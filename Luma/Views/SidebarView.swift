import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: BrowserStore
    let availableUpdate: AppUpdate?
    let onUpdateBannerTapped: () -> Void
    let onToggleSidebar: () -> Void

    @State private var isHoveringNewTab = false

    private let leadingInset: CGFloat = 10
    private let trailingInset: CGFloat = 10
    private let windowControlsWidth: CGFloat = 82

    /// Zen-style "Essentials" tiles: square-ish tiles that stretch to fill
    /// the row, so a few items span the full width like the reference.
    private let essentialsColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeSpaceTint: Color {
        Color(spaceHex: store.activeSpace?.themeColorHex ?? "#6E8BFF")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sidebarHeader
            
            if store.isSpaceSetupPresented {
                CreateSpaceSidebarComposer(
                    store: store,
                    mode: store.isInitialSpaceSetupPresented ? .initial : .create
                )
            } else {
                addressPill

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        essentialsSection
                        spaceLabel

                        Rectangle()
                            .fill(LumaChromeStyle.sidebarSeparator)
                            .frame(height: 1)
                            .padding(.top, 3)
                            .padding(.bottom, 2)

                        newTabButton
                        tabsSection
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
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background {
            ZStack {
                LumaChromeStyle.sidebarBackground
                activeSpaceTint.opacity(store.isSpaceSetupPresented ? 0.025 : 0.055)
            }
        }
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
        .foregroundStyle(LumaChromeStyle.sidebarIcon)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            SidebarLoadingBar(progress: store.activeTab?.loadingProgress ?? 0, tint: activeSpaceTint)
                .opacity(store.activeTab?.isLoading == true ? 1 : 0)
                .offset(y: 5)
        }
    }

    private var addressPill: some View {
        Button {
            store.focusAddressBar()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(LumaChromeStyle.sidebarIcon)

                Text(sidebarAddressText)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 40)
            .background(LumaChromeStyle.sidebarControlFill)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(BrowserDefaults.addressPlaceholder)
    }

    private var sidebarAddressText: String {
        guard let url = store.activeTab?.url else {
            return "Search..."
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
                        EssentialTileView(
                            tab: tab,
                            isActive: tab.id == store.activeTabID,
                            accentColor: activeSpaceTint,
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

    @ViewBuilder
    private var spaceLabel: some View {
        if let name = store.activeSpace?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)
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
                            isActive: tab.id == store.activeTabID,
                            isSplit: tab.id == store.splitTabID,
                            accentColor: activeSpaceTint,
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
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isHoveringNewTab ? LumaChromeStyle.sidebarControlFillHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHoveringNewTab = $0 }
        .overlay {
            if isHoveringNewTab {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LumaChromeStyle.sidebarControlStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHoveringNewTab)
    }
}

private struct AppUpdateBanner: View {
    let update: AppUpdate
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("New Luma Version Available")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LumaChromeStyle.sidebarText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isHovering ? LumaChromeStyle.updateBannerFillHover : LumaChromeStyle.updateBannerFill)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(LumaChromeStyle.updateBannerStroke, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Luma \(update.version) is available")
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
}

private struct CreateSpaceSidebarComposer: View {
    @ObservedObject var store: BrowserStore
    let mode: SpaceComposerMode

    @State private var name = ""
    @State private var symbolName = "square.dashed"
    @State private var themeColorHex = "#6E8BFF"
    @State private var dataMode = SpaceDataMode.isolated
    @State private var isIconPickerPresented = false
    @State private var isProfilePickerPresented = false
    @State private var isThemeEditorPresented = false
    @FocusState private var isNameFocused: Bool

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

    init(store: BrowserStore, mode: SpaceComposerMode = .create) {
        self.store = store
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            composerHeader

            nameField

            profileRow

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
            .foregroundStyle(trimmedName.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Color(spaceHex: themeColorHex).opacity(trimmedName.isEmpty ? 0.16 : 0.36))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(trimmedName.isEmpty)

            if mode == .create {
                Button("Cancel") {
                    store.isCreateSpacePresented = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.86))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private var composerHeader: some View {
        VStack(spacing: 8) {
            Text(mode.title)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LumaChromeStyle.sidebarText)

            Text(mode.subtitle)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(LumaChromeStyle.sidebarIcon)
                .multilineTextAlignment(.center)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 32)
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            Button {
                isIconPickerPresented.toggle()
            } label: {
                SpaceIconPreview(symbolName: symbolName, themeColorHex: themeColorHex)
            }
            .buttonStyle(.plain)
            .help("Change Icon")
            .popover(isPresented: $isIconPickerPresented, arrowEdge: .leading) {
                SpaceIconPicker(
                    selectedSymbolName: $symbolName,
                    isPresented: $isIconPickerPresented
                )
            }

            TextField("Space Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .focused($isNameFocused)
                .onChange(of: name) { _, newValue in
                    let limitedName = BrowserStore.limitedSpaceNameInput(newValue)
                    if limitedName != newValue {
                        name = limitedName
                    }
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .background(LumaChromeStyle.spaceSetupControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LumaChromeStyle.spaceSetupControlStroke, lineWidth: 1)
        }
    }

    private var profileRow: some View {
        HStack(spacing: 10) {
            Text("Profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LumaChromeStyle.sidebarText)

            Spacer(minLength: 8)

            Button {
                isProfilePickerPresented.toggle()
            } label: {
                Text(dataMode.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumaChromeStyle.sidebarText)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(LumaChromeStyle.spaceSetupPillFill)
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
        .frame(height: 42)
        .background(LumaChromeStyle.spaceSetupControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LumaChromeStyle.spaceSetupControlStroke, lineWidth: 1)
        }
    }

    private var themeButton: some View {
        Button {
            isThemeEditorPresented.toggle()
        } label: {
            HStack(spacing: 9) {
                Spacer(minLength: 0)

                Circle()
                    .fill(Color(spaceHex: themeColorHex))
                    .frame(width: 10, height: 10)

                Text("Edit Theme")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumaChromeStyle.sidebarText)

                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .background(LumaChromeStyle.spaceSetupControlFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LumaChromeStyle.spaceSetupControlStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isThemeEditorPresented, arrowEdge: .trailing) {
            SpaceThemePanel(
                selectedHex: $themeColorHex,
                themeOptions: themeOptions
            )
        }
    }

    private func createSpace() {
        if mode == .initial {
            store.completeInitialSpaceSetup(
                name: trimmedName,
                symbolName: symbolName,
                themeColorHex: themeColorHex,
                dataStoreID: dataMode.dataStoreID(current: store.activeSpace?.dataStoreID)
            )
            store.focusAddressBar()
            return
        }

        store.createSpace(
            name: trimmedName,
            symbolName: symbolName,
            themeColorHex: themeColorHex,
            dataStoreID: dataMode.dataStoreID(current: store.activeSpace?.dataStoreID)
        )
        store.isCreateSpacePresented = false
        store.focusAddressBar()
    }

}

private struct SpaceIconPreview: View {
    let symbolName: String
    let themeColorHex: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LumaChromeStyle.sidebarIcon.opacity(0.78),
                    style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
                )

            if symbolName != "square.dashed" {
                if let emoji = SpaceIconOption.emoji(from: symbolName) {
                    Text(emoji)
                        .font(.system(size: 16))
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(spaceHex: themeColorHex))
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
                    .foregroundStyle(LumaChromeStyle.sidebarIcon)

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
                    .stroke(LumaChromeStyle.popoverBorder, lineWidth: 1)
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
        .background(LumaChromeStyle.popoverBackground)
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
                    .foregroundStyle(isSelected ? Color.accentColor : LumaChromeStyle.sidebarText)
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
                                .foregroundStyle(LumaChromeStyle.sidebarText)
                                .lineLimit(1)

                            Text(mode.detail)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(LumaChromeStyle.sidebarIcon)
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
        .background(LumaChromeStyle.popoverBackground)
    }
}

private struct SpaceThemePanel: View {
    @Binding var selectedHex: String
    let themeOptions: [(name: String, hex: String)]

    @State private var appearance = SpaceThemeAppearance.dark

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ForEach(SpaceThemeAppearance.allCases) { option in
                    Button {
                        appearance = option
                    } label: {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 32)
                            .foregroundStyle(LumaChromeStyle.sidebarText)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(appearance == option ? Color.primary.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(option.title)
                }
            }
            .padding(.top, 4)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(spaceHex: selectedHex).opacity(0.10))

                DotPattern()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Pick a Space color")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LumaChromeStyle.sidebarText)
            }
            .frame(height: 180)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LumaChromeStyle.popoverBorder, lineWidth: 1)
            }

            HStack(spacing: 13) {
                ForEach(themeOptions, id: \.hex) { option in
                    Button {
                        selectedHex = option.hex
                    } label: {
                        Circle()
                            .fill(Color(spaceHex: option.hex))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        selectedHex == option.hex ? LumaChromeStyle.sidebarText : Color.clear,
                                        lineWidth: 2.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(option.name)
                }
            }

            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(spaceHex: selectedHex).opacity(0.74))
                    .frame(width: 62, height: 42)

                VStack(alignment: .leading, spacing: 6) {
                    Text(appearance.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LumaChromeStyle.sidebarText)

                    Text("Theme color applies to Space controls.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(LumaChromeStyle.sidebarIcon)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(LumaChromeStyle.popoverBackground)
    }
}

private struct DotPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 8
            let dotSize: CGFloat = 2
            let color = Color.primary.opacity(0.11)

            var x: CGFloat = 6
            while x < size.width {
                var y: CGFloat = 6
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(color)
                    )
                    y += spacing
                }
                x += spacing
            }
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

    private static let emojiPrefix = "emoji:"
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

private enum SpaceThemeAppearance: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var symbolName: String {
        switch self {
        case .automatic:
            return "sparkles"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

private enum SpaceComposerMode {
    case create
    case initial

    var title: String {
        "Create a Space"
    }

    var subtitle: String {
        "Spaces organize your tabs and sessions."
    }

    var primaryButtonTitle: String {
        switch self {
        case .create:
            return BrowserCommandTitles.createSpace
        case .initial:
            return BrowserCommandTitles.createSpace
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

private struct SidebarLoadingBar: View {
    let progress: Double
    let tint: Color

    private var clampedProgress: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(tint.opacity(0.70))
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
                            : AnyShapeStyle(LumaChromeStyle.sidebarControlFill)
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
                            .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)
                            .background(Circle().fill(LumaChromeStyle.sidebarBackground))
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
                            : (isHovering ? LumaChromeStyle.sidebarControlStroke : Color.clear),
                        lineWidth: 1
                    )
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
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isActive ? LumaChromeStyle.sidebarText : LumaChromeStyle.sidebarTextSecondary)
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
                    .fill(isHovering ? color : LumaChromeStyle.windowControlInactive)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(isHovering ? 0.14 : 0.08), lineWidth: 0.5)
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
            .frame(width: 29, height: 29)
            .contentShape(Rectangle())
    }
}

private extension View {
    func toolbarIconButton() -> some View {
        modifier(ToolbarIconButtonModifier())
    }
}

// MARK: - Shared chrome styling

enum LumaChromeStyle {
    static let sidebarWidth: CGFloat = 300
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let workspaceBackground = Color(nsColor: .controlBackgroundColor)
    static let sidebarBackground = Color(nsColor: .windowBackgroundColor).opacity(0.86)
    static let sidebarBorder = Color(nsColor: .separatorColor).opacity(0.70)
    static let sidebarSeparator = Color(nsColor: .separatorColor).opacity(0.60)
    static let sidebarControlFill = Color.primary.opacity(0.055)
    static let sidebarControlFillHover = Color.primary.opacity(0.085)
    static let sidebarControlFillActive = Color.accentColor.opacity(0.16)
    static let sidebarControlStroke = Color(nsColor: .separatorColor).opacity(0.75)
    static let spaceSetupControlFill = Color.primary.opacity(0.075)
    static let spaceSetupControlStroke = Color.primary.opacity(0.035)
    static let spaceSetupPillFill = Color.primary.opacity(0.13)
    static let updateBannerFill = Color.primary.opacity(0.075)
    static let updateBannerFillHover = Color.primary.opacity(0.105)
    static let updateBannerStroke = Color.primary.opacity(0.20)
    static let sidebarText = Color.primary.opacity(0.92)
    static let sidebarTextSecondary = Color(nsColor: .secondaryLabelColor)
    static let sidebarIcon = Color(nsColor: .tertiaryLabelColor)
    static let windowControlInactive = Color.primary.opacity(0.14)
    static let surfaceFill = Color(nsColor: .controlBackgroundColor)
    static let surfaceBorder = Color(nsColor: .separatorColor).opacity(0.75)
    static let popoverBackground = Color(nsColor: .windowBackgroundColor)
    static let popoverBorder = Color(nsColor: .separatorColor).opacity(0.85)
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
