import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Zen-style bottom workspace strip: a horizontal row of workspace icons
/// pinned to the bottom of the sidebar, with a trailing "add space" control.
struct SpaceSwitcherView: View {
    @ObservedObject var store: BrowserStore
    @State private var isDownloadsPresented = false
    @State private var isHoveringDownloads = false
    @State private var isActionMenuPresented = false
    @State private var isHoveringAddSpace = false
    @State private var deletingSpace: BrowserSpace?

    var body: some View {
        HStack(spacing: 8) {
            downloadsButton

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                // 22pt items + 8pt spacing keeps the same 30pt center rhythm
                // the old 16pt items had with 14pt spacing.
                HStack(spacing: 8) {
                    ForEach(store.spaces) { space in
                        workspaceButton(for: space)
                    }
                }
                .frame(minHeight: 28)
            }
            .frame(maxWidth: 150)

            Spacer(minLength: 0)

            addSpaceButton
        }
        .frame(height: 32)
        .alert("Delete Space", isPresented: isDeleteAlertPresented, presenting: deletingSpace) { space in
            Button("Delete", role: .destructive) {
                store.deleteSpace(space.id)
                deletingSpace = nil
            }

            Button("Cancel", role: .cancel) {
                deletingSpace = nil
            }
        } message: { space in
            Text("Delete \"\(space.name)\" and close its tabs?")
        }
    }

    private var downloadsButton: some View {
        Button {
            isDownloadsPresented.toggle()
        } label: {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.system(size: 15.5, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(LumaChromeStyle.sidebarIcon)
                .background(bottomButtonBackground(isActive: isDownloadsPresented, isHovering: isHoveringDownloads))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringDownloads = $0 }
        .help("Downloads")
        .popover(isPresented: $isDownloadsPresented, arrowEdge: .bottom) {
            DownloadsPopoverView {
                isDownloadsPresented = false
                openDownloadsFolder()
            }
        }
    }

    private var addSpaceButton: some View {
        Button {
            isActionMenuPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .regular))
                .frame(width: 28, height: 28)
                .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)
                .background(bottomButtonBackground(isActive: isActionMenuPresented, isHovering: isHoveringAddSpace))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringAddSpace = $0 }
        .animation(.easeOut(duration: 0.10), value: isHoveringAddSpace)
        .help("New Space")
        .popover(isPresented: $isActionMenuPresented, arrowEdge: .bottom) {
            SpaceActionMenu(
                store: store,
                isPresented: $isActionMenuPresented
            )
        }
    }

    private func bottomButtonBackground(isActive: Bool, isHovering: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isActive ? LumaChromeStyle.sidebarControlFillActive : (isHovering ? LumaChromeStyle.sidebarControlFillHover : Color.clear))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive || isHovering ? LumaChromeStyle.sidebarControlStroke : Color.clear, lineWidth: 1)
            }
    }

    private func workspaceButton(for space: BrowserSpace) -> some View {
        let isActive = space.id == store.activeSpaceID
        let themeColor = Color(spaceHex: space.themeColorHex ?? "#8A8F98")

        return Button {
            store.switchSpace(to: space.id)
        } label: {
            Group {
                if let emoji = space.iconEmoji {
                    Text(emoji)
                        .font(.system(size: 13))
                        .opacity(isActive ? 1 : 0.55)
                } else {
                    Circle()
                        .fill(isActive ? themeColor : themeColor.opacity(0.50))
                        .frame(width: isActive ? 8 : 7, height: isActive ? 8 : 7)
                        .overlay {
                            if isActive {
                                Circle()
                                    .stroke(themeColor.opacity(0.28), lineWidth: 5)
                                    .frame(width: 16, height: 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            // 22pt fits the active ring (16pt circle + 5pt stroke = 21pt) so
            // the ScrollView's clip no longer cuts it off.
            .frame(width: 22, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(space.name)
        .contextMenu {
            Button("Edit Space...") {
                store.beginSpaceEditing(space.id)
            }

            Divider()

            Button("Move Space Left") {
                store.moveSpace(space.id, by: -1)
            }
            .disabled(store.spaces.first?.id == space.id)

            Button("Move Space Right") {
                store.moveSpace(space.id, by: 1)
            }
            .disabled(store.spaces.last?.id == space.id)

            Divider()

            Button("New Space") {
                store.beginSpaceCreation()
            }

            Button("Delete Space", role: .destructive) {
                deletingSpace = space
            }
            .disabled(store.spaces.count <= 1)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _ in
            guard let draggedTabID = store.draggedTabID else { return false }
            store.moveTab(draggedTabID, toSpace: space.id)
            store.draggedTabID = nil
            return true
        }
    }

    private func openDownloadsFolder() {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return
        }

        NSWorkspace.shared.open(downloadsURL)
    }

    private var isDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { deletingSpace != nil },
            set: { isPresented in
                if !isPresented {
                    deletingSpace = nil
                }
            }
        )
    }

}

private struct DownloadsPopoverView: View {
    let onShowAllDownloads: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No downloads for this session.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

            Divider()
                .padding(.vertical, 5)

            DownloadsPopoverRow(title: "Show all downloads", action: onShowAllDownloads)
        }
        .padding(10)
        .frame(width: 240)
    }
}

private struct DownloadsPopoverRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
}

private struct SpaceActionMenu: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton(BrowserCommandTitles.createSpace, systemImage: "square.on.square") {
                store.beginSpaceCreation()
            }

            menuButton("Create Folder", systemImage: "folder") {}
                .disabled(true)

            Divider()
                .padding(.vertical, 5)

            menuButton("New Split", systemImage: "rectangle.split.2x1") {
                store.toggleSplitView()
            }

            menuButton(BrowserCommandTitles.newTab, systemImage: "plus") {
                store.openNewTabCommandPalette()
            }
        }
        .padding(10)
        .frame(width: 210)
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        SpaceActionMenuRow(title: title, systemImage: systemImage) {
            isPresented = false
            action()
        }
    }
}

private struct SpaceActionMenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovering && isEnabled ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }
}

extension Color {
    init(spaceHex: String) {
        let hex = spaceHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            self = Color(red: 0.43, green: 0.55, blue: 1.0)
            return
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
