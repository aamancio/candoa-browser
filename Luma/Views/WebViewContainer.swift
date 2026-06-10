import AppKit
import SwiftUI

struct WebViewContainer: View {
    @ObservedObject var store: BrowserStore
    private let surfaceCornerRadius: CGFloat = 16
    private let surfacePadding: CGFloat = 8

    var body: some View {
        ZStack {
            if let tab = store.activeTab {
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
                            .background(LumaChromeStyle.surfaceFill)
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
        .background(LumaChromeStyle.workspaceBackground)
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
                    .fill(LumaChromeStyle.surfaceFill)
            )
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.20), radius: 18, x: 0, y: 6)
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
            .background(LumaChromeStyle.surfaceFill)

            ProgressView(value: tab.loadingProgress)
                .progressViewStyle(.linear)
                .opacity(tab.isLoading ? 1 : 0)
                .frame(height: 2)

            WKWebViewRepresentable(tab: tab, store: store)
                .id(tab.id)
                .background(LumaChromeStyle.surfaceFill)
        }
    }
}
