import SwiftUI

/// Zen-style bottom workspace strip: a horizontal row of workspace icons
/// pinned to the bottom of the sidebar, with a trailing "add space" control.
struct SpaceSwitcherView: View {
    @ObservedObject var store: BrowserStore

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
                store.createSpace()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Space")
        }
        .frame(height: 32)
    }

    private func workspaceButton(for space: BrowserSpace) -> some View {
        let isActive = space.id == store.activeSpaceID

        return Button {
            store.switchSpace(to: space.id)
        } label: {
            Image(systemName: space.symbolName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? Color.primary : Color(nsColor: .secondaryLabelColor))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? AnyShapeStyle(Color.primary.opacity(0.10)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(space.name)
    }
}
