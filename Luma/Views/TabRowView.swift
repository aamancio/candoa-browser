import SwiftUI
import AppKit

struct TabRowView: View {
    let tab: BrowserTab
    let isActive: Bool
    let isSplit: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onOpenInSplit: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                ZStack {
                    faviconImage
                        .opacity(tab.isLoading ? 0 : 1)

                    if tab.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                    }
                }
                .frame(width: 16, height: 16)

                Text(tab.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12.5, weight: .medium))

                Spacer(minLength: 8)

                if isSplit {
                    Image(systemName: "rectangle.split.1x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Close Tab")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Duplicate Tab", action: onDuplicate)
            Button("Open in Split View", action: onOpenInSplit)
            Button("Close Tab", action: onClose)
        }
    }

    private var rowBackground: Color {
        if isActive {
            return Color.primary.opacity(0.10)
        }
        if isHovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
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
        }
    }
}
