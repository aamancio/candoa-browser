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
    @State private var renamingSpace: BrowserSpace?
    @State private var renameDraft = ""
    @State private var deletingSpace: BrowserSpace?

    private let themeOptions: [(name: String, hex: String)] = [
        ("Blue", "#6E8BFF"),
        ("Green", "#74E0AA"),
        ("Gold", "#E0A84F"),
        ("Red", "#DA6A72"),
        ("Violet", "#9B7BE5"),
        ("Cyan", "#5CA8D8"),
        ("Pink", "#D17FB3"),
        ("Olive", "#8E9A5B")
    ]

    var body: some View {
        HStack(spacing: 8) {
            downloadsButton

            Spacer(minLength: 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
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
        .overlay(alignment: .bottomLeading) {
            if isDownloadsPresented {
                DownloadsPopoverView {
                    isDownloadsPresented = false
                    openDownloadsFolder()
                }
                .frame(width: 520)
                .offset(x: 1, y: -43)
                .transition(.scale(scale: 0.98, anchor: .bottomLeading).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .zIndex(isDownloadsPresented ? 30 : 0)
        .animation(.easeOut(duration: 0.14), value: isDownloadsPresented)
        .alert("Rename Space", isPresented: isRenameAlertPresented) {
            TextField("Name", text: $renameDraft)
                .onChange(of: renameDraft) { _, newValue in
                    let limitedName = BrowserStore.limitedSpaceNameInput(newValue)
                    if limitedName != newValue {
                        renameDraft = limitedName
                    }
                }

            Button("Rename") {
                guard let renamingSpace else { return }
                store.renameSpace(renamingSpace.id, to: renameDraft)
                self.renamingSpace = nil
            }

            Button("Cancel", role: .cancel) {
                renamingSpace = nil
            }
        }
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
            Circle()
                .fill(isActive ? themeColor : themeColor.opacity(0.50))
                .frame(width: isActive ? 8 : 7, height: isActive ? 8 : 7)
                .frame(width: 16, height: 28)
                .overlay {
                    if isActive {
                        Circle()
                            .stroke(themeColor.opacity(0.28), lineWidth: 5)
                            .frame(width: 16, height: 16)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(space.name)
        .contextMenu {
            Button("Rename Space...") {
                beginRenaming(space)
            }

            Button("Change Space Icon") {
                store.cycleSpaceIcon(space.id)
            }

            Menu("Edit Theme Color") {
                Button {
                    store.updateSpaceTheme(space.id, colorHex: nil)
                } label: {
                    Label("Standard", systemImage: space.themeColorHex == nil ? "checkmark" : "circle")
                }

                Divider()

                ForEach(themeOptions, id: \.hex) { option in
                    Button {
                        store.updateSpaceTheme(space.id, colorHex: option.hex)
                    } label: {
                        Label(option.name, systemImage: option.hex == space.themeColorHex ? "checkmark" : "circle.fill")
                    }
                }
            }

            Menu("Appearance") {
                ForEach(SpaceThemeAppearance.allCases) { option in
                    Button {
                        store.updateSpaceThemeAppearance(space.id, appearance: option)
                    } label: {
                        Label(option.title, systemImage: option == space.themeAppearance ? "checkmark" : option.symbolName)
                    }
                }
            }

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

    private var isRenameAlertPresented: Binding<Bool> {
        Binding(
            get: { renamingSpace != nil },
            set: { isPresented in
                if !isPresented {
                    renamingSpace = nil
                }
            }
        )
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

    private func beginRenaming(_ space: BrowserSpace) {
        renamingSpace = space
        renameDraft = space.name
    }
}

private struct DownloadsPopoverView: View {
    let onShowAllDownloads: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("No downloads for this session.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.top, 25)
                .padding(.bottom, 28)

            Rectangle()
                .fill(LumaChromeStyle.popoverBorder)
                .frame(height: 1)
                .padding(.horizontal, 24)

            Button(action: onShowAllDownloads) {
                Text("Show all downloads")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(LumaChromeStyle.popoverBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(LumaChromeStyle.popoverBorder, lineWidth: 1)
        }
        .overlay(alignment: .bottomLeading) {
            DownloadsPopoverTail()
                .fill(LumaChromeStyle.popoverBackground)
                .frame(width: 34, height: 24)
                .overlay {
                    DownloadsPopoverTail()
                        .stroke(LumaChromeStyle.popoverBorder, lineWidth: 1)
                }
                .offset(x: 13, y: 15)
        }
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.24), radius: 18, x: 0, y: 10)
    }
}

private struct DownloadsPopoverTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 4, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - 1, y: rect.maxY - 1),
            control: CGPoint(x: rect.minX + 7, y: rect.maxY * 0.70)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - 3, y: rect.minY),
            control: CGPoint(x: rect.midX + 6, y: rect.maxY * 0.70)
        )
        path.closeSubpath()
        return path
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
                store.newTab()
                store.focusAddressBar()
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
