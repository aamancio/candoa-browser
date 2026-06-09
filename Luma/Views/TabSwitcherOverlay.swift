import AppKit
import SwiftUI

struct TabSwitcherOverlay: View {
    @ObservedObject var store: BrowserStore
    @State private var snapshots: [UUID: NSImage] = [:]

    private let columns = Array(
        repeating: GridItem(.fixed(TabSwitcherMetrics.cardWidth), spacing: TabSwitcherMetrics.columnSpacing),
        count: 5
    )

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
        LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
            ForEach(store.tabSwitcherTabs.prefix(10)) { tab in
                TabSwitcherPreviewCard(
                    tab: tab,
                    snapshot: snapshots[tab.id],
                    isSelected: tab.id == store.tabSwitcherSelectedTabID
                )
            }
        }
        .frame(width: TabSwitcherMetrics.gridWidth)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 26, y: 14)
    }

    private func refreshSnapshots() {
        let visibleIDs = Set(store.tabSwitcherTabs.prefix(10).map(\.id))
        snapshots = snapshots.filter { visibleIDs.contains($0.key) }

        for tab in store.tabSwitcherTabs.prefix(10) where snapshots[tab.id] == nil {
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
    static let gridWidth: CGFloat = cardWidth * 5 + columnSpacing * 4
    static let snapshotWidth: CGFloat = 260
    static let previewHeight: CGFloat = 84
}

private struct TabSwitcherPreviewCard: View {
    let tab: BrowserTab
    let snapshot: NSImage?
    let isSelected: Bool

    private var hostText: String {
        tab.url?.host(percentEncoded: false) ?? tab.url?.absoluteString ?? "New Tab"
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
                .fill(isSelected ? Color.accentColor.opacity(0.20) : Color.black.opacity(0.24))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.92) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
        .scaleEffect(isSelected ? 1.035 : 1)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var miniatureWindow: some View {
        VStack(spacing: 0) {
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
            .frame(height: 14)
            .background(Color.black.opacity(0.32))

            ZStack {
                if let snapshot {
                    Image(nsImage: snapshot)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackPreview
                }
            }
            .frame(height: TabSwitcherMetrics.previewHeight)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
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
