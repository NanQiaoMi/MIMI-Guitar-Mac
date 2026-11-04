import MIMICore
import SwiftUI

private enum CommandPaletteEntry: Identifiable, Equatable {
    case recent(String)
    case score(CatalogItem)
    case article(CatalogArticle)

    var id: String {
        switch self {
        case .recent(let query): return "recent:\(query)"
        case .score(let item): return "score:\(item.id)"
        case .article(let art): return "article:\(art.id)"
        }
    }
}

@MainActor
private final class CommandPaletteNavigationState: ObservableObject {
    @Published var selectedIndex: Int = -1
}

struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @StateObject private var navState = CommandPaletteNavigationState()
    @State private var keyMonitor: Any?

    private var queryIsEmpty: Bool {
        model.commandQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectableEntries: [CommandPaletteEntry] {
        if queryIsEmpty {
            return model.recentSearches.map { .recent($0) }
        } else {
            var list: [CommandPaletteEntry] = []
            list.append(contentsOf: model.commandItems.map { .score($0) })
            list.append(contentsOf: model.commandArticles.map { .article($0) })
            return list
        }
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
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onExitCommand(perform: close)
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let entries = self.selectableEntries
            let count = entries.count

            if event.keyCode == 125 { // Down Arrow
                if count > 0 {
                    DispatchQueue.main.async {
                        self.navState.selectedIndex = min(count - 1, max(0, self.navState.selectedIndex + 1))
                    }
                    return nil
                }
            } else if event.keyCode == 126 { // Up Arrow
                if count > 0 {
                    DispatchQueue.main.async {
                        if self.navState.selectedIndex > 0 {
                            self.navState.selectedIndex -= 1
                        } else if self.navState.selectedIndex == 0 {
                            self.navState.selectedIndex = -1
                        }
                    }
                    return nil
                }
            } else if event.keyCode == 48 { // Tab
                if count > 0 {
                    DispatchQueue.main.async {
                        if event.modifierFlags.contains(.shift) {
                            self.navState.selectedIndex = self.navState.selectedIndex <= 0 ? count - 1 : self.navState.selectedIndex - 1
                        } else {
                            self.navState.selectedIndex = self.navState.selectedIndex >= count - 1 ? 0 : self.navState.selectedIndex + 1
                        }
                    }
                    return nil
                }
            } else if event.keyCode == 36 { // Return / Enter
                if self.navState.selectedIndex >= 0 && self.navState.selectedIndex < count {
                    let entry = entries[self.navState.selectedIndex]
                    DispatchQueue.main.async {
                        self.activateEntry(entry)
                    }
                    return nil
                }
            } else if event.keyCode == 53 { // Esc
                DispatchQueue.main.async {
                    self.close()
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func activateEntry(_ entry: CommandPaletteEntry) {
        switch entry {
        case .recent(let query):
            model.useRecentSearch(query)
            model.submitCommandSearch()
        case .score(let item):
            model.openCatalogItem(item)
            close()
        case .article(let article):
            model.navigate(.article(id: article.id))
            close()
        }
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
                .onChange(of: model.commandQuery) { _ in
                    model.commandQueryDidChange()
                    navState.selectedIndex = queryIsEmpty ? -1 : 0
                }
                .onSubmit {
                    if navState.selectedIndex >= 0 && navState.selectedIndex < selectableEntries.count {
                        activateEntry(selectableEntries[navState.selectedIndex])
                    } else {
                        model.submitCommandSearch()
                    }
                }
                .accessibilityLabel("搜索曲谱、歌手或文章")
            if !queryIsEmpty {
                Button {
                    model.commandQuery = ""
                    model.commandQueryDidChange()
                    navState.selectedIndex = -1
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
                    navState.selectedIndex = queryIsEmpty ? -1 : 0
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
                Text("按 ↑↓ 选择结果，回车打开")
                    .font(.system(size: 10))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
        }
        .padding(.horizontal, 23)
        .padding(.bottom, 15)
    }

    @ViewBuilder
    private var results: some View {
        ScrollViewReader { proxy in
            Group {
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
                    .scrollIndicators(.automatic)
                }
            }
            .onChange(of: navState.selectedIndex) { newIndex in
                let entries = selectableEntries
                if newIndex >= 0 && newIndex < entries.count {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(entries[newIndex].id, anchor: .center)
                    }
                }
            }
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
                    Button("清除全部") {
                        model.clearRecentSearches()
                        navState.selectedIndex = -1
                    }
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
                ForEach(Array(model.recentSearches.enumerated()), id: \.element) { index, query in
                    let isSelected = navState.selectedIndex == index
                    HStack(spacing: 10) {
                        Button {
                            activateEntry(.recent(query))
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isSelected ? MIMITheme.darkGold : MIMITheme.mutedInk)
                                Text(query)
                                    .font(MIMITheme.bodyFont(size: 12, weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? MIMITheme.ink : MIMITheme.bodyInk)
                                Spacer()
                                if isSelected {
                                    HStack(spacing: 4) {
                                        Text("↵").font(.system(size: 11, weight: .bold))
                                        Text("搜索").font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundStyle(MIMITheme.darkGold)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(MIMITheme.paper, in: Capsule())
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.removeRecentSearch(query)
                            if navState.selectedIndex >= model.recentSearches.count - 1 {
                                navState.selectedIndex = model.recentSearches.count - 2
                            }
                        } label: {
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
                    .background(isSelected ? Color(hex: 0xF2EAE1) : MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? MIMITheme.darkGold.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                    .id("recent:\(query)")
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
        let isSelected = navState.selectedIndex >= 0 && navState.selectedIndex < selectableEntries.count && selectableEntries[navState.selectedIndex] == .score(item)

        return Button {
            activateEntry(.score(item))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .foregroundStyle(isSelected ? MIMITheme.darkGold : MIMITheme.mutedInk)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color(hex: 0xEADCC9) : MIMITheme.paper, in: RoundedRectangle(cornerRadius: 9))
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

                if isSelected {
                    HStack(spacing: 4) {
                        Text("↵").font(.system(size: 11, weight: .bold))
                        Text("打开").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MIMITheme.paper, in: Capsule())
                } else {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(isSelected ? Color(hex: 0xF2EAE1) : MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? MIMITheme.darkGold.opacity(0.4) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandResultButtonStyle())
        .id("score:\(item.id)")
    }

    private func articleResult(_ article: CatalogArticle) -> some View {
        let isSelected = navState.selectedIndex >= 0 && navState.selectedIndex < selectableEntries.count && selectableEntries[navState.selectedIndex] == .article(article)

        return Button {
            activateEntry(.article(article))
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

                if isSelected {
                    HStack(spacing: 4) {
                        Text("↵").font(.system(size: 11, weight: .bold))
                        Text("阅读").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(MIMITheme.terracotta)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xF7E8E0), in: Capsule())
                } else {
                    Image(systemName: "arrow.up.left")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(isSelected ? Color(hex: 0xF2EAE1) : MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? MIMITheme.terracotta.opacity(0.4) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(CommandResultButtonStyle())
        .id("article:\(article.id)")
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if navState.selectedIndex >= 0 && navState.selectedIndex < selectableEntries.count {
                Label("↵ 立即打开", systemImage: "arrow.turn.down.left")
                    .foregroundStyle(MIMITheme.darkGold)
            } else {
                Label("↵ 查看全部", systemImage: "return")
            }
            Label("↑↓ 切换选择", systemImage: "arrow.up.and.down")
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
