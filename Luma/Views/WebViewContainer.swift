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
                SpaceSetupCanvas(
                    hexes: store.activeThemeColorHexes,
                    intensity: store.activeThemeIntensityMultiplier,
                    texture: store.activeThemeTexture
                )
                .padding(surfacePadding)
                .transition(.opacity)
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
            .shadow(color: Color.black.opacity(0.10), radius: 16, x: -2, y: 2)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
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

            // Whisper-level sheen when themed: anything stronger visibly
            // darkens the card against the identically-tinted chrome.
            LinearGradient(
                colors: [
                    Color.white.opacity(hexes.isEmpty ? 0.10 : 0.03),
                    Color.black.opacity(hexes.isEmpty ? 0.035 : 0.012)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            LinearGradient(
                colors: [
                    Color.white.opacity(hexes.isEmpty ? 0.10 : 0.04),
                    Color.clear,
                    Color.black.opacity(hexes.isEmpty ? 0.08 : 0.03)
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
                    .stroke(Color.black.opacity(hexes.isEmpty ? 0.08 : 0.12), lineWidth: 1)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(hexes.isEmpty ? 0.08 : 0.10), lineWidth: 1)
                    .blendMode(.overlay)
            }
        }
        .compositingGroup()
        .shadow(
            color: Color.black.opacity(hexes.isEmpty ? 0.10 : 0.18),
            radius: hexes.isEmpty ? 22 : 30,
            x: 0,
            y: hexes.isEmpty ? 8 : 10
        )
        .shadow(
            color: Color.black.opacity(hexes.isEmpty ? 0.05 : 0.10),
            radius: hexes.isEmpty ? 10 : 14,
            x: -4,
            y: 1
        )
    }

    private var canvasFill: Color {
        guard let firstHex = hexes.first else {
            return LumaChromeStyle.surfaceFill.opacity(0.88)
        }

        // The window backdrop already carries the theme color at full
        // strength; keep the card nearly transparent so chrome and canvas
        // read as one continuous surface (Zen-style).
        return Color(spaceHex: firstHex).opacity(0.08)
    }
}
