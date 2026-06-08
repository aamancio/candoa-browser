import SwiftUI
import UniformTypeIdentifiers

/// Zen-style bottom workspace strip: a horizontal row of workspace icons
/// pinned to the bottom of the sidebar, with a trailing "add space" control.
struct SpaceSwitcherView: View {
    @ObservedObject var store: BrowserStore
    @State private var isActionMenuPresented = false
    @State private var renamingSpace: BrowserSpace?
    @State private var renameDraft = ""
    @State private var deletingSpace: BrowserSpace?

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

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.spaces) { space in
                        workspaceButton(for: space)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                isActionMenuPresented.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Space")
            .popover(isPresented: $isActionMenuPresented, arrowEdge: .bottom) {
                SpaceActionMenu(
                    store: store,
                    isPresented: $isActionMenuPresented
                )
            }
        }
        .frame(height: 32)
        .alert("Rename Space", isPresented: isRenameAlertPresented) {
            TextField("Name", text: $renameDraft)

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

    private func workspaceButton(for space: BrowserSpace) -> some View {
        let isActive = space.id == store.activeSpaceID
        let themeColor = Color(spaceHex: space.themeColorHex)

        return Button {
            store.switchSpace(to: space.id)
        } label: {
            Image(systemName: space.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? themeColor : Color(nsColor: .secondaryLabelColor))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? AnyShapeStyle(themeColor.opacity(0.18)) : AnyShapeStyle(Color.clear))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isActive ? themeColor.opacity(0.28) : Color.clear, lineWidth: 1)
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
                ForEach(themeOptions, id: \.hex) { option in
                    Button {
                        store.updateSpaceTheme(space.id, colorHex: option.hex)
                    } label: {
                        Label(option.name, systemImage: option.hex == space.themeColorHex ? "checkmark" : "circle.fill")
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

private struct SpaceActionMenu: View {
    @ObservedObject var store: BrowserStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("Create Space", systemImage: "square.on.square") {
                store.beginSpaceCreation()
            }

            menuButton("Create Folder", systemImage: "folder") {}
                .disabled(true)

            Divider()
                .padding(.vertical, 5)

            menuButton("New Split", systemImage: "rectangle.split.2x1") {
                store.toggleSplitView()
            }

            menuButton("New Tab", systemImage: "plus") {
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
        Button {
            isPresented = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
