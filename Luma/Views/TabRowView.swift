import SwiftUI
import AppKit

struct TabRowView: View {
    let tab: BrowserTab
    let isActive: Bool
    let isSplit: Bool
    let accentColor: Color
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
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isActive ? LumaChromeStyle.sidebarText : LumaChromeStyle.sidebarTextSecondary)

            Spacer(minLength: 8)

            if isSplit {
                Image(systemName: "rectangle.split.1x2")
                    .font(.caption)
                    .foregroundStyle(LumaChromeStyle.sidebarIcon)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LumaChromeStyle.sidebarIcon)
            .help("Close Tab")
            .opacity(isHovering ? 1 : 0)
            .accessibilityHidden(!isHovering)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .background(rowBackground)
        .background(TabHoverTracker(isHovering: $isHovering))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", action: onTogglePin)
            Button(BrowserCommandTitles.duplicateTab, action: onDuplicate)
            Button("Open in Split View", action: onOpenInSplit)
            Button("Close Tab", action: onClose)
        }
        .overlay {
            if isHovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LumaChromeStyle.sidebarControlStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.10), value: isHovering)
    }

    private var rowBackground: Color {
        if isActive {
            return accentColor.opacity(0.18)
        }
        if isHovering {
            return LumaChromeStyle.sidebarControlFillHover
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
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(isActive ? LumaChromeStyle.sidebarText : LumaChromeStyle.sidebarIcon)
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

            // .mouseMoved matters: a row inserted under a stationary cursor
            // never gets a mouseEntered crossing, so moves inside the row are
            // the only signal that the cursor is here.
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
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

        // The first syncHoverState can run before SwiftUI has sized this
        // view (bounds still .zero), reporting "outside" for a cursor that
        // is actually over the row. Re-sync once real geometry arrives.
        override func layout() {
            super.layout()
            syncHoverState()
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange?(true)
        }

        override func mouseMoved(with event: NSEvent) {
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
