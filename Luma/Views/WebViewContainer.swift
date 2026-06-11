import AppKit
import SwiftUI

struct WebViewContainer: View {
    @ObservedObject var store: BrowserStore
    private let surfaceCornerRadius: CGFloat = 12
    private let surfacePadding: CGFloat = 8

    var body: some View {
        ZStack {
            if store.isSpaceSetupPresented {
                SpaceSetupCanvas(
                    hexes: store.activeThemeColorHexes,
                    intensity: store.activeThemeIntensityMultiplier,
                    texture: store.activeThemeTexture
                )
                .padding(.top, surfacePadding)
                .padding(.trailing, surfacePadding)
                .padding(.bottom, surfacePadding)
                .transition(.opacity)
            } else if let tab = store.activeTab {
                if let splitTab = store.activeSplitTab {
                    HSplitView {
                        browserSurface {
                            webPane(for: tab, title: "Primary")
                        }

                        browserSurface {
                            webPane(for: splitTab, title: "Split")
                        }
                    }
                    .padding(surfacePadding)
                } else {
                    browserSurface {
                        ActiveWebViewHost(tab: tab, store: store)
                            .background(LumaChromeStyle.surfaceFill.opacity(0.72))
                    }
                    .padding(surfacePadding)
                }
            } else {
                ContentUnavailableView(
                    "No Active Tab",
                    systemImage: "sidebar.left",
                    description: Text("Create a tab to start browsing.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if store.isFindBarPresented {
                FindBarView(store: store)
                    .padding(.top, surfacePadding + 10)
                    .padding(.trailing, surfacePadding + 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.14), value: store.isFindBarPresented)
    }

    private func browserSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                    .stroke(LumaChromeStyle.surfaceBorder, lineWidth: 1)
            }
            .background(
                RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous)
                    .fill(LumaChromeStyle.surfaceFill.opacity(0.74))
            )
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.18), radius: 14, x: -3, y: 1)
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private struct FindBarView: View {
        @ObservedObject var store: BrowserStore
        @FocusState private var isFieldFocused: Bool

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find in page", text: $store.findQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 190)
                    .focused($isFieldFocused)
                    .onSubmit { store.findNext() }

                Button {
                    store.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(store.findQuery.isEmpty)
                .help("Find Previous")

                Button {
                    store.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(store.findQuery.isEmpty)
                .help("Find Next")

                Button {
                    store.dismissFindBar()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Done")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LumaChromeStyle.popoverBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LumaChromeStyle.popoverBorder, lineWidth: 1)
            }
            .onAppear { isFieldFocused = true }
            .onExitCommand { store.dismissFindBar() }
            .onChange(of: store.findQuery) { _, _ in
                store.findNext()
            }
        }
    }

    private func webPane(for tab: BrowserTab, title: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tab.faviconSymbol)
                    .foregroundStyle(.secondary)
                Text(tab.title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if title == "Split" {
                    Button {
                        store.closeSplitView()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Close Split View")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(LumaChromeStyle.sidebarTextSecondary)
            .background(LumaChromeStyle.surfaceFill.opacity(0.72))

            ProgressView(value: tab.loadingProgress)
                .progressViewStyle(.linear)
                .opacity(tab.isLoading ? 1 : 0)
                .frame(height: 2)

            WKWebViewRepresentable(tab: tab, store: store)
                .id(tab.id)
                .background(LumaChromeStyle.surfaceFill.opacity(0.72))
        }
    }
}

private struct SpaceSetupCanvas: View {
    let hexes: [String]
    let intensity: Double
    let texture: Double

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(canvasFill)

            if !hexes.isEmpty {
                SpaceThemeBackdrop(hexes: hexes, intensity: 0.18 * intensity, texture: texture)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.black.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            LinearGradient(
                colors: [
                    Color.white.opacity(hexes.isEmpty ? 0.10 : 0.16),
                    Color.clear,
                    Color.black.opacity(hexes.isEmpty ? 0.08 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.overlay)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Image(systemName: "car.side.fill")
                .font(.system(size: 146, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary.opacity(0.052))
                .padding(.trailing, 148)
                .offset(y: 8)
                .allowsHitTesting(false)
        }
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(hexes.isEmpty ? 0.20 : 0.24), lineWidth: 1)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(hexes.isEmpty ? 0.18 : 0.20), lineWidth: 1)
                    .blendMode(.overlay)
            }
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(hexes.isEmpty ? 0.22 : 0.38),
            radius: hexes.isEmpty ? 18 : 32,
            x: 0,
            y: hexes.isEmpty ? 6 : 10
        )
        .shadow(
            color: Color.black.opacity(hexes.isEmpty ? 0.14 : 0.28),
            radius: hexes.isEmpty ? 9 : 16,
            x: -5,
            y: 1
        )
    }

    private var canvasFill: Color {
        guard let firstHex = hexes.first else {
            return LumaChromeStyle.surfaceFill.opacity(0.88)
        }

        return Color(spaceHex: firstHex).opacity(0.74)
    }
}
