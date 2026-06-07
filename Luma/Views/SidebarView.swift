import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var store: BrowserStore
    let onToggleSidebar: () -> Void

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

            SpaceSwitcherView(store: store)
        }
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
            ProgressView(value: store.activeTab?.loadingProgress ?? 0)
                .progressViewStyle(.linear)
                .opacity(store.activeTab?.isLoading == true ? 1 : 0)
                .frame(height: 2)
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
        .help("Search or enter URL")
    }

    private var sidebarAddressText: String {
        guard let url = store.activeTab?.url else {
            return "Search or enter URL"
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
                            onOpenInSplit: { store.openSplitView(with: tab.id) }
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
                            onOpenInSplit: { store.openSplitView(with: tab.id) }
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
            Label("New Tab", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
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
            Button("Duplicate Tab", action: onDuplicate)
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
