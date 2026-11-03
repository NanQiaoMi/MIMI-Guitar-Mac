import MIMICore
import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    private var queryIsEmpty: Bool {
        model.commandQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            domainPicker
            Divider().overlay(MIMITheme.softBorder)
            results
            footer
        }
        .background(MIMITheme.paperWhite)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { searchFocused = true }
        }
        .onExitCommand(perform: close)
    }

    private var searchHeader: some View {
        HStack(spacing: 13) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(MIMITheme.darkGold)
            TextField("搜索曲谱、歌手或文章…", text: $model.commandQuery)
                .font(MIMITheme.displayFont(size: 19, weight: .medium))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onChange(of: model.commandQuery) { _ in model.commandQueryDidChange() }
                .onSubmit { model.submitCommandSearch() }
                .accessibilityLabel("搜索曲谱、歌手或文章")
            if !queryIsEmpty {
                Button {
                    model.commandQuery = ""
                    model.commandQueryDidChange()
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .frame(width: 26, height: 26)
                    .background(MIMITheme.paper, in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭搜索面板")
        }
        .padding(.horizontal, 23)
        .padding(.vertical, 19)
    }

    private var domainPicker: some View {
        HStack(spacing: 7) {
            ForEach(SearchDomain.allCases) { domain in
                Button {
                    model.commandDomain = domain
                    model.commandDomainDidChange()
                    searchFocused = true
                } label: {
                    Text(domain.title)
                        .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                        .foregroundStyle(model.commandDomain == domain ? Color.white : MIMITheme.bodyInk)
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .background(model.commandDomain == domain ? MIMITheme.ink : MIMITheme.paper, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if !queryIsEmpty {
                Text("按回车查看全部结果")
                    .font(.system(size: 10))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
        }
        .padding(.horizontal, 23)
        .padding(.bottom, 15)
    }

    @ViewBuilder
    private var results: some View {
        if queryIsEmpty {
            recentSearches
        } else if model.commandIsLoading && model.commandItems.isEmpty && model.commandArticles.isEmpty {
            VStack(spacing: 11) {
                ProgressView().controlSize(.regular)
                Text("正在搜索本地曲库与文章…")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.commandItems.isEmpty && model.commandArticles.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.commandError == nil ? "magnifyingglass" : "exclamationmark.triangle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(model.commandError == nil ? MIMITheme.warmGold : MIMITheme.terracotta)
                Text(model.commandError == nil ? "没有找到相关内容" : "搜索暂时失败")
                    .font(MIMITheme.displayFont(size: 14, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                Text(model.commandError ?? "换个关键词，或按回车查看完整搜索结果。")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                if model.commandError != nil {
                    Button("重试搜索") { model.commandQueryDidChange() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.commandItems.isEmpty {
                        resultSection(title: "曲谱", count: model.commandItems.count) {
                            ForEach(model.commandItems) { item in scoreResult(item) }
                        }
                    }
                    if !model.commandArticles.isEmpty {
                        resultSection(title: "文章", count: model.commandArticles.count) {
                            ForEach(model.commandArticles) { article in articleResult(article) }
                        }
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近搜索")
                    .font(MIMITheme.displayFont(size: 12, weight: .semibold))
                    .foregroundStyle(MIMITheme.mutedInk)
                Spacer()
                if !model.recentSearches.isEmpty {
                    Button("清除全部") { model.clearRecentSearches() }
                        .font(MIMITheme.bodyFont(size: 10))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .buttonStyle(.plain)
                }
            }
            if model.recentSearches.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 25, weight: .light))
                        .foregroundStyle(MIMITheme.warmGold)
                    Text("搜索曲名、歌手，或查找文章")
                        .font(MIMITheme.bodyFont(size: 12))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(model.recentSearches, id: \.self) { query in
                    HStack(spacing: 10) {
                        Button {
                            model.useRecentSearch(query)
                            model.submitCommandSearch()
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .font(MIMITheme.bodyFont(size: 12))
                                .foregroundStyle(MIMITheme.bodyInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { model.removeRecentSearch(query) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(MIMITheme.mutedInk)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("移除最近搜索")
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 37)
                    .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resultSection<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(MIMITheme.displayFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.mutedInk)
                Text("\(count)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            content()
        }
    }

    private func scoreResult(_ item: CatalogItem) -> some View {
        Button {
            model.openCatalogItem(item)
            close()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .foregroundStyle(MIMITheme.darkGold)
                    .frame(width: 32, height: 32)
                    .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(MIMITheme.displayFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                    Text(item.artist ?? "未知歌手").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                }
                Spacer()
                Text(item.category == "ukulele" ? "尤克里里" : "吉他谱")
                    .font(MIMITheme.bodyFont(size: 9, weight: .medium))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(MIMITheme.paper, in: Capsule())
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandResultButtonStyle())
    }

    private func articleResult(_ article: CatalogArticle) -> some View {
        Button {
            model.navigate(.article(id: article.id))
            close()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(MIMITheme.terracotta)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xF7E8E0), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(article.title).font(MIMITheme.displayFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                    Text(article.category ?? "文章")
                        .font(MIMITheme.bodyFont(size: 10))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandResultButtonStyle())
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("Tab 选择结果", systemImage: "rectangle.and.pencil.and.ellipsis")
            Label("↵ 查看全部", systemImage: "return")
            Spacer()
            Text("⌘ K")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 5))
            Text("关闭")
                .font(.system(size: 10))
                .foregroundStyle(MIMITheme.mutedInk)
            Text("esc")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 5))
        }
        .font(.system(size: 10))
        .foregroundStyle(MIMITheme.mutedInk)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(MIMITheme.paperWhite)
        .overlay(alignment: .top) { Rectangle().fill(MIMITheme.softBorder).frame(height: 1) }
    }

    private func close() {
        model.isCommandPalettePresented = false
        dismiss()
    }
}

private struct CommandResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? MIMITheme.paper : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
