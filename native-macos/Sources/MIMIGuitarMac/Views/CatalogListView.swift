import MIMICore
import SwiftUI

private enum CatalogBrowseMode: String, CaseIterable, Identifiable {
    case gallery, list, folio
    var id: String { rawValue }
    var title: String {
        switch self { case .gallery: return "画廊"; case .list: return "列表"; case .folio: return "展卷" }
    }
    var symbol: String {
        switch self { case .gallery: return "square.grid.2x2"; case .list: return "list.bullet"; case .folio: return "books.vertical" }
    }
}

struct CatalogListView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("mimi.catalog.browseMode") private var browseMode = CatalogBrowseMode.gallery.rawValue
    @AppStorage("mimi.catalog.previewSeconds") private var previewSeconds = 30
    var isSearchResults = false

    private var mode: CatalogBrowseMode { CatalogBrowseMode(rawValue: browseMode) ?? .gallery }
    private var categories: [(String, CatalogCategory)] {
        [("全部典藏", .all), ("吉他谱", .guitar), ("尤克里里", .ukulele)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            filterPaper
            HStack(alignment: .firstTextBaseline) {
                Text(model.isLoading && model.totalMatches == 0 ? "正在检索本地曲库…" : "共找到 \(model.totalMatches.formatted()) 份曲谱")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.mutedInk)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Menu {
                    Button("试听 30 秒") { previewSeconds = 30 }
                    Button("试听 60 秒") { previewSeconds = 60 }
                } label: {
                    Label("试听 \(previewSeconds) 秒", systemImage: "waveform")
                        .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .help("试听时长从实际播放开始计时")
                Text("第 \(model.catalogPage) / \(model.catalogPageCount) 页 · 每页 90 份")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            if let message = model.bootstrapMessage {
                WorkspaceUnavailableView(title: "本地曲库暂不可用", message: message)
                    .frame(minHeight: 320)
            } else if !model.loadMessage.isNilOrEmpty {
                loadError
            } else if model.items.isEmpty && !model.isLoading {
                emptyState
            } else {
                contentForMode
            }
            if model.catalogPageCount > 1 { pageNavigation }
        }
        .onChange(of: model.searchText) { _ in model.searchDidChange() }
        .onChange(of: model.searchField) { _ in model.filterDidChange() }
        .onChange(of: model.sort) { _ in model.sortDidChange() }
        .onChange(of: model.difficultyFilter) { _ in model.filterDidChange() }
        .onChange(of: model.styleFilter) { _ in model.filterDidChange() }
        .onChange(of: model.sheetFormFilter) { _ in model.filterDidChange() }
        .onChange(of: model.keyFilter) { _ in model.filterDidChange() }
        .onChange(of: model.tuningFilter) { _ in model.filterDidChange() }
        .onChange(of: browseMode) { _ in model.selectedItemID = nil }
    }

    private var filterPaper: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                categorySelector
                Spacer(minLength: 8)
                searchField
                browseSelector
            }

            Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)

            CatalogFilterFlowLayout(spacing: 8) {
                difficultyPills
                formPills
                filterMenu(title: styleTitle, symbol: "guitars", options: [("全部类型", nil), ("流行", 101), ("摇滚", 102), ("民谣", 103), ("配乐", 105), ("乡村", 107), ("金属", 109)], selection: model.styleFilter) { model.styleFilter = $0 }
                menuFilter(title: model.keyFilter ?? "全部调性", symbol: "tuningfork", values: ["全部调性", "C", "C#", "D", "Db", "E", "Eb", "F", "F#", "G", "G#", "A", "Ab", "B", "Bb"]) { model.keyFilter = $0 == "全部调性" ? nil : $0 }
                menuFilter(title: model.tuningFilter ?? "全部调弦", symbol: "waveform", values: ["全部调弦", "Standard", "Half-Step Down", "Drop D", "Open G", "DADGAD", "Open D"]) { model.tuningFilter = $0 == "全部调弦" ? nil : $0 }
                sortSelector
                if hasActiveFilters { resetFiltersButton }
            }
        }
        .padding(16)
        .mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.04)
    }

    private var categorySelector: some View {
        HStack(spacing: 2) {
            ForEach(Array(categories.enumerated()), id: \.offset) { _, row in
                let (label, category) = row
                Button { model.selectCatalogCategory(category) } label: {
                    Text(label)
                        .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                        .foregroundStyle(isSelected(category) ? Color(hex: 0x382D1E) : MIMITheme.navigationBrown)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .background(isSelected(category) ? Color(hex: 0xFFFDF8) : .clear, in: Capsule())
                        .overlay(Capsule().stroke(isSelected(category) ? Color(hex: 0xAA8746).opacity(0.28) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(hex: 0xF4EDDF), in: Capsule())
        .overlay(Capsule().stroke(Color(hex: 0xDED3BD), lineWidth: 1))
    }

    private var difficultyPills: some View {
        pillGroup(title: "难度:", options: [("全部难度", nil), ("零基础", 1), ("初级", 2), ("中级", 3), ("高级", 4), ("专业", 5)], selection: model.difficultyFilter) {
            model.difficultyFilter = $0
        }
    }

    private var formPills: some View {
        pillGroup(title: "谱型:", options: [("全部谱型", nil), ("弹唱谱", 1), ("指弹谱", 2), ("和弦谱", 3), ("六线谱", 4), ("版式 7", 7)], selection: model.sheetFormFilter) {
            model.sheetFormFilter = $0
        }
    }

    private func pillGroup(title: String, options: [(String, Int?)], selection: Int?, action: @escaping (Int?) -> Void) -> some View {
        HStack(spacing: 5) {
            Text(title).font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.mutedInk)
            HStack(spacing: 1) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let selected = selection == option.1
                    Button { action(option.1) } label: {
                        Text(option.0)
                            .font(MIMITheme.bodyFont(size: 10, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? .white : MIMITheme.navigationBrown)
                            .padding(.horizontal, 9)
                            .frame(minWidth: 40, minHeight: 42)
                            .background(selected ? Color(hex: 0x8C6D46) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(hex: 0xFDFAF5), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0xE0D6C0), lineWidth: 1))
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title == "难度:" ? "按难度筛选" : "按谱型筛选")
    }

    private var sortSelector: some View {
        HStack(spacing: 1) {
            ForEach(Array(sortOptions.enumerated()), id: \.offset) { _, option in
                let (sort, title) = option
                Button { model.sort = sort } label: {
                    Text(title)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(MIMITheme.bodyFont(size: 10, weight: model.sort == sort ? .semibold : .regular))
                        .foregroundStyle(model.sort == sort ? Color(hex: 0x382D1E) : MIMITheme.navigationBrown)
                        .padding(.horizontal, 11).frame(minHeight: 42)
                        .background(model.sort == sort ? Color(hex: 0xFFFDF8) : .clear, in: Capsule())
                        .overlay(Capsule().stroke(model.sort == sort ? Color(hex: 0xAA8746).opacity(0.28) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Menu {
                sortChoice("曲名排序", sort: .title)
                sortChoice("默认顺序", sort: .providedOrder)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.sort == .title || model.sort == .providedOrder ? MIMITheme.darkGold : MIMITheme.navigationBrown)
                    .frame(width: 34, height: 42)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .help("更多排序方式；当前为\(currentSortTitle)")
        }
        .padding(2)
        .background(Color(hex: 0xF4EDDF), in: Capsule())
        .overlay(Capsule().stroke(Color(hex: 0xDED3BD), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var hasActiveFilters: Bool {
        model.difficultyFilter != nil || model.styleFilter != nil || model.sheetFormFilter != nil || model.keyFilter != nil || model.tuningFilter != nil || !model.searchText.isEmpty
    }

    private var resetFiltersButton: some View {
        Button {
            model.difficultyFilter = nil
            model.styleFilter = nil
            model.sheetFormFilter = nil
            model.keyFilter = nil
            model.tuningFilter = nil
            model.searchText = ""
        } label: {
            Text("重置")
                .font(MIMITheme.bodyFont(size: 10, weight: .medium))
                .foregroundStyle(MIMITheme.terracotta)
                .padding(.horizontal, 12).frame(minHeight: 40)
                .background(MIMITheme.terracotta.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.terracotta.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
            TextField("搜索曲名或歌手", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(MIMITheme.bodyFont(size: 13))
                .frame(minWidth: 190, idealWidth: 240, maxWidth: 280)
            Menu {
                Picker("搜索范围", selection: $model.searchField) {
                    Text("曲名与歌手").tag(CatalogSearchField.all)
                    Text("只搜曲名").tag(CatalogSearchField.title)
                    Text("只搜歌手").tag(CatalogSearchField.artist)
                }
            } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(MIMITheme.bodyInk)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .help("选择搜索范围")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(hex: 0xFDFAF5), in: Capsule())
        .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private var browseSelector: some View {
        HStack(spacing: 2) {
            ForEach(CatalogBrowseMode.allCases) { candidate in
                Button { browseMode = candidate.rawValue } label: {
                    Label(candidate.title, systemImage: candidate.symbol)
                        .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(mode == candidate ? MIMITheme.ink : MIMITheme.mutedInk)
                        .padding(.horizontal, 9)
                        .frame(minHeight: 44)
                        .background(mode == candidate ? Color(hex: 0xFFFDF8) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("\(candidate.title)视图")
            }
        }
        .padding(3)
        .background(Color(hex: 0xF4EDDF), in: Capsule())
        .overlay(Capsule().stroke(Color(hex: 0xDED3BD), lineWidth: 1))
    }

    @ViewBuilder
    private func sortChoice(_ title: String, sort: CatalogSort) -> some View {
        Button {
            model.sort = sort
        } label: {
            if model.sort == sort { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func filterMenu(title: String, symbol: String, options: [(String, Int?)], selection: Int?, action: @escaping (Int?) -> Void) -> some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    action(option.1)
                } label: {
                    if selection == option.1 { Label(option.0, systemImage: "checkmark") } else { Text(option.0) }
                }
            }
        } label: { filterLabel(title: title, symbol: symbol, active: selection != nil) }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func menuFilter(title: String, symbol: String, values: [String], action: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in Button(value) { action(value) } }
        } label: { filterLabel(title: title, symbol: symbol, active: !title.hasPrefix("全部")) }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func filterLabel(title: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title).font(MIMITheme.bodyFont(size: 10, weight: active ? .semibold : .regular)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(active ? MIMITheme.darkGold : MIMITheme.navigationBrown)
        .padding(.horizontal, 11).frame(minHeight: 42)
        .background(Color(hex: 0xFDFAF5), in: Capsule())
        .overlay(Capsule().stroke(active ? MIMITheme.warmGold.opacity(0.48) : Color(hex: 0xE0D6C0), lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sortOptions: [(CatalogSort, String)] {
        [(.popular, "热度"), (.newest, "最新"), (.difficulty, "难度")]
    }

    private var currentSortTitle: String {
        switch model.sort {
        case .popular: return "研习热度"
        case .newest: return "最新上传"
        case .difficulty: return "演奏难度"
        case .title: return "曲名排序"
        case .providedOrder: return "默认顺序"
        }
    }

    @ViewBuilder
    private var contentForMode: some View {
        switch mode {
        case .gallery:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(model.items) { item in GalleryScoreCard(previewSeconds: $previewSeconds, item: item, controller: model.auditionController) }
            }
        case .list:
            LazyVStack(spacing: 0) {
                CatalogTableHeader()
                ForEach(model.items) { item in CatalogTableRow(previewSeconds: $previewSeconds, item: item, controller: model.auditionController) }
            }
            .mimiCard(radius: 18, fill: MIMITheme.paperWhite)
        case .folio:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in FolioScoreCard(item: item, index: index + (model.catalogPage - 1) * 90, previewSeconds: $previewSeconds, controller: model.auditionController) }
            }
        }
    }

    private var pageNavigation: some View {
        HStack(spacing: 7) {
            Button { model.setCatalogPage(model.catalogPage - 1) } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .disabled(model.catalogPage <= 1 || model.isLoading)
            .buttonStyle(PageButtonStyle())
            ForEach(pageNumbers, id: \.self) { page in
                if page == -1 {
                    Text("…").foregroundStyle(MIMITheme.mutedInk).frame(width: 30)
                } else {
                    Button("\(page)") { model.setCatalogPage(page) }
                        .buttonStyle(PageNumberStyle(selected: page == model.catalogPage))
                }
            }
            Button {
                model.setCatalogPage(model.catalogPage + 1)
            } label: { Label("下一页", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                .disabled(model.catalogPage >= model.catalogPageCount || model.isLoading)
                .buttonStyle(PageButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var pageNumbers: [Int] {
        let last = model.catalogPageCount
        if last <= 7 { return Array(1...last) }
        var values = [1]
        if model.catalogPage > 3 { values.append(-1) }
        values += Array(max(2, model.catalogPage - 1)...min(last - 1, model.catalogPage + 1))
        if model.catalogPage < last - 2 { values.append(-1) }
        values.append(last)
        return values
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: model.searchText.isEmpty ? "music.note.list" : "magnifyingglass")
                .font(.system(size: 30, weight: .light)).foregroundStyle(MIMITheme.warmGold)
            Text(model.searchText.isEmpty ? "这里暂时没有曲谱" : "没有找到匹配的曲谱")
                .font(MIMITheme.displayFont(size: 21, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(model.searchText.isEmpty ? "试试清除筛选，或浏览其他分类。" : "试试更短的曲名、歌手或清除部分筛选条件。")
                .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
            Button("清除筛选") {
                model.difficultyFilter = nil; model.styleFilter = nil; model.sheetFormFilter = nil
                model.keyFilter = nil; model.tuningFilter = nil; model.searchText = ""
            }
            .buttonStyle(.bordered).tint(MIMITheme.darkGold)
        }
        .frame(maxWidth: .infinity, minHeight: 270)
        .mimiCard(fill: MIMITheme.paperWhite)
    }

    private var loadError: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MIMITheme.terracotta)
            VStack(alignment: .leading, spacing: 4) {
                Text("本页曲谱暂时无法载入").font(MIMITheme.bodyFont(size: 14, weight: .semibold))
                Text(model.loadMessage ?? "请稍后重试。").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
            }
            Spacer()
            Button("重试") { model.updateSearch() }.buttonStyle(.bordered)
        }
        .padding(20).mimiCard(fill: MIMITheme.paperWhite)
    }

    private func isSelected(_ category: CatalogCategory) -> Bool {
        switch model.route {
        case .catalog(let active), .catalogQuery(let active, _): return active == category
        default: break
        }
        return category == .all
    }
    private var difficultyTitle: String { model.difficultyFilter.map(difficultyName) ?? "全部难度" }
    private var formTitle: String { model.sheetFormFilter.map(formName) ?? "全部谱型" }
    private var styleTitle: String { model.styleFilter.map(styleName) ?? "全部类型" }
    private func difficultyName(_ value: Int) -> String { [1: "零基础", 2: "初级", 3: "中级", 4: "高级", 5: "专业"][value] ?? "全部难度" }
    private func formName(_ value: Int) -> String { [1: "弹唱谱", 2: "指弹谱", 3: "和弦谱", 4: "六线谱（版式 4）", 7: "六线谱（版式 7）"][value] ?? "全部谱型" }
    private func styleName(_ value: Int) -> String { [101: "流行", 102: "摇滚", 103: "民谣", 105: "配乐", 107: "乡村", 109: "金属"][value] ?? "全部类型" }
}

private struct GalleryScoreCard: View {
    @EnvironmentObject private var model: AppModel
    @Binding var previewSeconds: Int
    let item: CatalogItem
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState

    init(previewSeconds: Binding<Int>, item: CatalogItem, controller: NativeAuditionController) {
        self._previewSeconds = previewSeconds
        self.item = item
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

    private var auditionIsPlaying: Bool { auditionState.snapshot.isPlaying }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 112, height: 112))
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
                if hasPlayable {
                    Button { controller.toggle(item: item, previewDuration: TimeInterval(previewSeconds)) } label: {
                        Image(systemName: auditionIsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(MIMITheme.ink.opacity(0.92), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .help("试听原谱（最多 \(previewSeconds) 秒）")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Button { model.openCatalogItem(item) } label: {
                        Text(item.title).font(MIMITheme.displayFont(size: 18, weight: .semibold)).foregroundStyle(Color(hex: 0x2C241B)).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Label(item.displayHeat, systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.bodyInk)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: 0xFBF9F4), in: Capsule())
                        .overlay(Capsule().stroke(Color(hex: 0xE8E2D4), lineWidth: 1))
                }
                Text(item.artist ?? "未知歌手").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                HStack(spacing: 5) {
                    Text("调性参考:").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(Color(hex: 0xA89B8A))
                    ForEach(chordHints, id: \.self) { chord in
                        MIMIPill(title: chord, tint: MIMITheme.bodyInk, fill: Color(hex: 0xFCFAF6))
                    }
                    if chordHints.isEmpty { MIMIPill(title: item.key.map { "\($0) 调" } ?? "调性未标注", fill: Color(hex: 0xFCFAF6)) }
                }
                Spacer(minLength: 0)
                Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                HStack(spacing: 6) {
                    MIMIPill(title: item.key.map { "\($0) 调" } ?? "G 调", fill: Color(hex: 0xFBF9F4))
                    MIMIPill(title: item.sheetFormLabel, fill: Color(hex: 0xFBF9F4))
                    DifficultyBadge(difficulty: item.difficulty)
                    Spacer(minLength: 2)
                    Button { model.toggleFavorite(for: item) } label: {
                        Image(systemName: model.isFavorite(item) ? "heart.fill" : "heart")
                            .foregroundStyle(model.isFavorite(item) ? MIMITheme.terracotta : MIMITheme.navigationBrown)
                            .frame(width: 34, height: 34)
                            .background(MIMITheme.paperWhite, in: Circle())
                            .overlay(Circle().stroke(Color(hex: 0xE0D6C0), lineWidth: 1))
                    }
                    .buttonStyle(.plain).help(model.isFavorite(item) ? "取消收藏" : "收藏")
                    Button("研习  →") { model.openCatalogItem(item) }
                        .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.paperWhite)
                        .padding(.horizontal, 13).frame(minHeight: 36)
                        .background(MIMITheme.ink, in: Capsule())
                        .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 144, alignment: .leading)
        .mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.04)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var hasPlayable: Bool { item.scoreURL != nil && !item.scoreURL!.isEmpty }
    private var chordHints: [String] {
        let tokens = (item.tags ?? "").split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "#" }).map(String.init)
        return Array(tokens.filter { $0.count <= 5 && $0.first?.isUppercase == true }.prefix(3))
    }
}

private struct CatalogTableHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("试听").frame(width: 64)
            Text("曲目 / 歌手").frame(maxWidth: .infinity, alignment: .leading)
            Text("调性").frame(width: 75)
            Text("谱型").frame(width: 80)
            Text("难度").frame(width: 80)
            Text("研习热度").frame(width: 95)
            Text("操作").frame(width: 132)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MIMITheme.mutedInk)
        .padding(.horizontal, 15).padding(.vertical, 12)
        .background(MIMITheme.paper.opacity(0.7))
    }
}

private struct CatalogTableRow: View {
    @EnvironmentObject private var model: AppModel
    @Binding var previewSeconds: Int
    let item: CatalogItem
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState
    @State private var isHovered = false
    private var hasPlayable: Bool { item.scoreURL?.isEmpty == false }
    private var isPlaying: Bool { auditionState.snapshot.isPlaying }

    init(previewSeconds: Binding<Int>, item: CatalogItem, controller: NativeAuditionController) {
        self._previewSeconds = previewSeconds
        self.item = item
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { controller.toggle(item: item, previewDuration: TimeInterval(previewSeconds)) } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(hasPlayable ? MIMITheme.darkGold : MIMITheme.mutedInk.opacity(0.4))
                    .frame(width: 38, height: 38).background(MIMITheme.paper, in: Circle())
            }
            .buttonStyle(.plain).disabled(!hasPlayable)
            .frame(width: 64)
            VStack(alignment: .leading, spacing: 2) {
                Button { model.openCatalogItem(item) } label: { Text(item.title).font(MIMITheme.bodyFont(size: 14, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1) }.buttonStyle(.plain)
                Text(item.artist ?? "未知歌手").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.key ?? "—").frame(width: 75)
            Text(item.sheetFormLabel).frame(width: 80)
            DifficultyBadge(difficulty: item.difficulty).frame(width: 80)
            Label(item.displayHeat, systemImage: "flame.fill").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.terracotta).frame(width: 95)
            HStack(spacing: 7) {
                Button { model.toggleFavorite(for: item) } label: { Image(systemName: model.isFavorite(item) ? "heart.fill" : "heart").foregroundStyle(model.isFavorite(item) ? MIMITheme.terracotta : MIMITheme.bodyInk) }
                    .buttonStyle(.plain).help("收藏曲谱")
                Button("研习") { model.openCatalogItem(item) }
                    .buttonStyle(.borderedProminent).tint(MIMITheme.ink).controlSize(.small)
            }
            .frame(width: 132)
        }
        .font(MIMITheme.bodyFont(size: 12))
        .foregroundStyle(MIMITheme.bodyInk)
        .padding(.horizontal, 15).padding(.vertical, 8)
        .background(isHovered ? MIMITheme.paper.opacity(0.72) : MIMITheme.paperWhite)
        .overlay(alignment: .bottom) { Rectangle().fill(MIMITheme.faintBorder).frame(height: 1) }
        .onHover { isHovered = $0 }
    }
}

private struct FolioScoreCard: View {
    @EnvironmentObject private var model: AppModel
    let item: CatalogItem
    let index: Int
    @Binding var previewSeconds: Int
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState
    private var playing: Bool { auditionState.snapshot.isPlaying }

    init(item: CatalogItem, index: Int, previewSeconds: Binding<Int>, controller: NativeAuditionController) {
        self.item = item
        self.index = index
        self._previewSeconds = previewSeconds
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(String(format: "%03d", index + 1)).font(.system(size: 10, weight: .bold, design: .monospaced))
                Rectangle().fill(MIMITheme.softBorder).frame(width: 1)
                Text(item.displayHeat).font(.system(size: 9, weight: .medium, design: .monospaced)).lineLimit(1)
            }
            .foregroundStyle(MIMITheme.darkGold)
            .frame(width: 42)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(MIMITheme.displayFont(size: 17, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                        Text(item.artist ?? "未知歌手").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(item.key.map { "\($0)" } ?? "·")
                        .font(MIMITheme.displayFont(size: 16, weight: .bold)).foregroundStyle(MIMITheme.darkGold)
                }
                ZStack(alignment: .bottomTrailing) {
                    CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 295, height: 128))
                        .frame(maxWidth: .infinity).frame(height: 128).clipShape(RoundedRectangle(cornerRadius: 12))
                    if item.scoreURL?.isEmpty == false {
                        Button { controller.toggle(item: item, previewDuration: TimeInterval(previewSeconds)) } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 38, height: 38).background(MIMITheme.ink, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain).padding(10)
                    }
                }
                HStack {
                    DifficultyBadge(difficulty: item.difficulty)
                    MIMIPill(title: item.sheetFormLabel)
                    Spacer(minLength: 4)
                    Button { model.openCatalogItem(item) } label: {
                        Label("开启全屏原谱", systemImage: "arrow.up.right.square").font(.system(size: 10, weight: .semibold)).foregroundStyle(MIMITheme.darkGold)
                    }.buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .mimiCard(radius: 16, fill: MIMITheme.paperWhite, shadowOpacity: 0.04)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [MIMITheme.warmGold, MIMITheme.warmGold.opacity(0.28)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4).padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PageButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(configuration.isPressed ? MIMITheme.darkGold : MIMITheme.bodyInk)
            .padding(.horizontal, 12).frame(height: 34)
            .background(MIMITheme.paperWhite, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct CatalogFilterFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                usedWidth = max(usedWidth, x - spacing)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        usedWidth = max(usedWidth, max(0, x - spacing))
        return CGSize(width: min(availableWidth, usedWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PageNumberStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 14, weight: .medium))
            .foregroundStyle(selected ? Color(hex: 0xFFFFFF) : MIMITheme.bodyInk)
            .padding(.horizontal, 15).padding(.vertical, 6)
            .background(selected ? Color(hex: 0x171717) : Color(hex: 0xFAFAFA), in: Capsule())
            .overlay(Capsule().stroke(selected ? Color(hex: 0x171717) : Color(hex: 0xE5E5E5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty != false }
}
