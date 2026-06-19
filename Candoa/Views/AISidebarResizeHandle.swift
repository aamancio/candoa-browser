import AppKit
import SwiftUI

enum AISidebarLayout {
    static let minWidth: CGFloat = 360
    static let maxWidth: CGFloat = 720
    static let resizeHandleHitWidth: CGFloat = 12
}

struct AISidebarResizeHandle: View {
    let isResizing: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(CandoaChromeStyle.sidebarTextSecondary.opacity(isActive ? 0.64 : 0.28))
                .frame(width: isActive ? 3 : 1)
                .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .candoaAISidebarCursor(AISidebarResizeCursor.horizontal)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Resize Ask Sidebar")
    }

    private var isActive: Bool {
        isHovering || isResizing
    }
}

enum AISidebarResizeCursor {
    static var horizontal: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.columnResize(directions: .all)
        }
        return .resizeLeftRight
    }
}

struct AISidebarCursorHoverModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .background(AISidebarCursorRectView(cursor: cursor))
            .onContinuousHover { phase in
                if case .active = phase {
                    cursor.set()
                }
            }
            .onHover { isHovering in
                if isHovering {
                    cursor.set()
                }
            }
    }
}

struct AISidebarCursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> AISidebarCursorRectNSView {
        let view = AISidebarCursorRectNSView(frame: .zero)
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: AISidebarCursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

final class AISidebarCursorRectNSView: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

extension View {
    func candoaAISidebarCursor(_ cursor: NSCursor) -> some View {
        modifier(AISidebarCursorHoverModifier(cursor: cursor))
    }
}
