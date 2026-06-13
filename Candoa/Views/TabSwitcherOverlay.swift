import AppKit
import SwiftUI

struct TabSwitcherOverlay: View {
    @ObservedObject var store: BrowserStore
    @State private var snapshots: [UUID: NSImage] = [:]

    var body: some View {
        if !store.tabSwitcherTabs.isEmpty {
            panel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .onAppear(perform: refreshSnapshots)
                .onChange(of: store.tabSwitcherTabs.map(\.id)) { _, _ in
                    refreshSnapshots()
                }
        }
    }

    private var panel: some View {
        HStack(spacing: TabSwitcherMetrics.columnSpacing) {
            ForEach(store.tabSwitcherTabs) { tab in
                TabSwitcherPreviewCard(
                    tab: tab,
                    snapshot: snapshots[tab.id],
                    isSelected: tab.id == store.tabSwitcherSelectedTabID
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CandoaChromeStyle.popoverBorder, lineWidth: 1)
        }
        .shadow(color: Color(nsColor: .shadowColor).opacity(0.24), radius: 26, y: 14)
    }

    private func refreshSnapshots() {
        let visibleIDs = Set(store.tabSwitcherTabs.map(\.id))
        snapshots = snapshots.filter { visibleIDs.contains($0.key) }

        for tab in store.tabSwitcherTabs where snapshots[tab.id] == nil {
            store.webCoordinator.snapshotImage(for: tab.id, width: TabSwitcherMetrics.snapshotWidth) { image in
                guard let image else { return }
                snapshots[tab.id] = image
            }
        }
    }
}

private enum TabSwitcherMetrics {
    static let cardWidth: CGFloat = 142
    static let columnSpacing: CGFloat = 10
    static let snapshotWidth: CGFloat = 260
    static let titleBarHeight: CGFloat = 14
    static let previewHeight: CGFloat = 84
    static let miniatureWindowHeight = titleBarHeight + previewHeight
}

private struct TabSwitcherPreviewCard: View {
    let tab: BrowserTab
    let snapshot: NSImage?
    let isSelected: Bool

    private var hostText: String {
        tab.url?.host(percentEncoded: false) ?? tab.url?.absoluteString ?? BrowserDefaults.newTabTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            miniatureWindow

            HStack(spacing: 6) {
                favicon

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(hostText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .frame(width: TabSwitcherMetrics.cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.20) : CandoaChromeStyle.surfaceFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.92) : CandoaChromeStyle.surfaceBorder, lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isSelected ? 1.035 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var miniatureWindow: some View {
        let windowShape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return GeometryReader { proxy in
            VStack(spacing: 0) {
                titleBar
                previewSurface(width: proxy.size.width)
            }
            .frame(
                width: proxy.size.width,
                height: TabSwitcherMetrics.miniatureWindowHeight,
                alignment: .top
            )
        }
        .frame(height: TabSwitcherMetrics.miniatureWindowHeight)
        .frame(maxWidth: .infinity)
        .clipShape(windowShape)
        .overlay {
            windowShape.stroke(CandoaChromeStyle.surfaceBorder, lineWidth: 1)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.red.opacity(0.78)).frame(width: 4, height: 4)
            Circle().fill(Color.yellow.opacity(0.78)).frame(width: 4, height: 4)
            Circle().fill(Color.green.opacity(0.78)).frame(width: 4, height: 4)

            Spacer(minLength: 4)

            Text(hostText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 74, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: TabSwitcherMetrics.titleBarHeight)
        .background(CandoaChromeStyle.sidebarControlFill)
    }

    private func previewSurface(width: CGFloat) -> some View {
        let boundedWidth = max(width, 1)

        return ZStack {
            if let snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: boundedWidth, height: TabSwitcherMetrics.previewHeight)
                    .clipped()
            } else {
                fallbackPreview
                    .frame(width: boundedWidth, height: TabSwitcherMetrics.previewHeight)
            }
        }
        .frame(width: boundedWidth, height: TabSwitcherMetrics.previewHeight)
        .clipped()
    }

    private var fallbackPreview: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 7) {
                favicon
                    .font(.system(size: 20))

                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 100)
            }
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: tab.faviconSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }
}
