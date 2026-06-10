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
    let onTogglePin: () -> Void

    @State private var isHovering = false

    var body: some View {
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

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close Tab")
            .opacity(isHovering ? 1 : 0)
            .accessibilityHidden(!isHovering)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(rowBackground)
        .background(TabHoverTracker(isHovering: $isHovering))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", action: onTogglePin)
            Button(BrowserCommandTitles.duplicateTab, action: onDuplicate)
            Button("Open in Split View", action: onOpenInSplit)
            Button("Close Tab", action: onClose)
        }
        .overlay {
            if isHovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHovering)
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

private struct TabHoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChange = { isHovering = $0 }
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHoverChange = { isHovering = $0 }
        view.syncHoverState()
    }

    final class TrackingView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea

            super.updateTrackingAreas()
            syncHoverState()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.syncHoverState()
            }
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseExited(with event: NSEvent) {
            syncHoverState()
        }

        func syncHoverState() {
            guard let window else {
                onHoverChange?(false)
                return
            }

            let windowLocation = window.mouseLocationOutsideOfEventStream
            let localLocation = convert(windowLocation, from: nil)
            onHoverChange?(bounds.contains(localLocation))
        }
    }
}
