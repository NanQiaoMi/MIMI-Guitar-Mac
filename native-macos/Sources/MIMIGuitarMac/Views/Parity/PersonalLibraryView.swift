import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

struct PersonalLibraryView: View {
    @EnvironmentObject private var model: AppModel
    var onRequestScrollToSection: ((String) -> Void)? = nil

    enum PersonalLibraryTab: String, CaseIterable, Identifiable {
        case queue = "待练队列"
        case favorites = "我的收藏"
        case imported = "本地导入"
        case projects = "工坊工程"
        case archived = "已归档"
        case recent = "最近浏览"
        case search = "曲库查找"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .queue: return "list.bullet.rectangle"
            case .favorites: return "heart.fill"
            case .imported: return "doc.badge.arrow.up"
            case .projects: return "music.quarternote.3"
            case .archived: return "archivebox"
            case .recent: return "clock.arrow.circlepath"
            case .search: return "magnifyingglass"
            }
        }
    }

    @State private var selectedTab: PersonalLibraryTab = .queue
    @State private var localFilterText = ""
    @State private var catalogQuery = ""
    @State private var catalogSearchCategory = "guitar"
    @State private var catalogResults: [CatalogItem] = []
    @State private var catalogSearchMessage: String?
    @State private var catalogSearchError = false
    @State private var catalogSearchIsBusy = false
    @State private var catalogSearchGeneration = 0
    @State private var actionMessage: String?
    @State private var noteDrafts: [String: String] = [:]
    @State private var noteBases: [String: String] = [:]
    @State private var noteMessages: [String: String] = [:]
    @State private var editingNoteScoreID: String?
    @State private var selectedCategory = "guitar"

    private var allScores: [PersonalScore] { model.personalScores }
    private var queueScores: [PersonalScore] {
        model.practiceItems.filter { $0.status != .archived }.compactMap { item in model.personalScoresByID[item.scoreId] ?? allScores.first { $0.id == item.scoreId } }
    }
    private var archivedScores: [PersonalScore] {
        model.practiceItems.filter { $0.status == .archived }.compactMap { item in model.personalScoresByID[item.scoreId] ?? allScores.first { $0.id == item.scoreId } }
    }
    private var favoriteScores: [PersonalScore] {
        let favoriteIDs = Set(model.personalSnapshot.favorites)
        return allScores.filter { favoriteIDs.contains($0.id) }
    }
    private var importedScores: [PersonalScore] { allScores.filter { $0.source == "private" } }

    private func tabCount(for tab: PersonalLibraryTab) -> Int? {
        switch tab {
        case .queue: return queueScores.count
        case .favorites: return favoriteScores.count
        case .imported: return importedScores.count
        case .projects: return model.personalSnapshot.projects.count
        case .archived: return archivedScores.count
        case .recent: return model.recentEntries.count
        case .search: return nil
        }
    }

    private func filterScores(_ scores: [PersonalScore]) -> [PersonalScore] {
        let q = localFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return scores }
        return scores.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.category.lowercased().contains(q)
        }
    }

    private func synchronizeLibraryLocation(for section: LibrarySection) {
        if model.showArchivedPracticeQueueOnLibrary {
            selectedTab = .archived
            DispatchQueue.main.async {
                if model.showArchivedPracticeQueueOnLibrary {
                    model.showArchivedPracticeQueueOnLibrary = false
                }
            }
            onRequestScrollToSection?("library-archived")
            return
        }

        switch section {
        case .allScores:
            selectedTab = .search
        case .guitar:
            catalogSearchCategory = "guitar"
            selectedTab = .search
        case .ukulele:
            catalogSearchCategory = "ukulele"
            selectedTab = .search
        case .bass:
            selectedCategory = "bass"
            model.selectedImportCategory = "bass"
            selectedTab = .imported
        case .favorites:
            selectedTab = .favorites
        case .queue:
            selectedTab = .queue
        case .recent:
            selectedTab = .recent
        case .imported:
            selectedTab = .imported
        case .projects:
            selectedTab = .projects
        }

        onRequestScrollToSection?("library-content")
    }

    private func consumeLibraryScrollRequest() {
        guard let section = model.requestedLibraryScrollSection else { return }
        model.requestedLibraryScrollSection = nil
        synchronizeLibraryLocation(for: section)
    }

    private func restoreLibraryCategorySelection() {
        selectedCategory = model.selectedImportCategory
        switch model.selectedLibrarySection {
        case .guitar:
            catalogSearchCategory = "guitar"
            selectedTab = .search
        case .ukulele:
            catalogSearchCategory = "ukulele"
            selectedTab = .search
        case .bass:
            selectedCategory = "bass"
            selectedTab = .imported
        case .favorites:
            selectedTab = .favorites
        case .queue:
            selectedTab = .queue
        case .imported:
            selectedTab = .imported
        case .projects:
            selectedTab = .projects
        case .recent:
            selectedTab = .recent
        default:
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            headerSection

            if let actionMessage {
                PaperNotice(text: actionMessage, error: actionMessage.contains("失败"))
            }

            VStack(alignment: .leading, spacing: 18) {
                tabBarSection
                contentSection
            }
            .id("library-content")
        }
        .onAppear {
            model.refreshPersonalData()
            restoreLibraryCategorySelection()
            consumeLibraryScrollRequest()
        }
        .onChange(of: model.requestedLibraryScrollSection) { section in
            if section != nil { consumeLibraryScrollRequest() }
        }
        .onChange(of: model.showArchivedPracticeQueueOnLibrary) { shouldShowArchived in
            if shouldShowArchived { consumeLibraryScrollRequest() }
        }
        .onChange(of: selectedCategory) { model.selectedImportCategory = $0 }
        .onChange(of: catalogSearchCategory) { _ in invalidateCatalogSearch() }
        .onChange(of: catalogQuery) { _ in invalidateCatalogSearch() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MIMIPill(title: "LOCAL VAULT", tint: MIMITheme.darkGold, fill: MIMITheme.warmGold.opacity(0.12))
                        Text("本设备个人资料").font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    Text("我的谱")
                        .font(MIMITheme.displayFont(size: 34, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .padding(.vertical, 1)
                    Text("收藏、待练、自制曲谱与练习数据安全保存在本地。支持直接导入 GP / IBE / XHE 格式并随时导出备份。")
                        .font(MIMITheme.bodyFont(size: 13))
                        .foregroundStyle(MIMITheme.bodyInk)
                        .lineSpacing(3)
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    PaperMenuPicker(
                        title: "乐器",
                        selection: $selectedCategory,
                        options: [
                            PaperMenuOption("guitar", "吉他", icon: "guitars"),
                            PaperMenuOption("ukulele", "尤克里里", icon: "music.note"),
                            PaperMenuOption("bass", "贝斯", icon: "tuningfork"),
                        ],
                        prefix: "乐器："
                    )

                    Button {
                        model.selectedImportCategory = selectedCategory
                        model.importScoreWithPanel()
                    } label: {
                        Label(model.isImporting ? "正在导入…" : "导入个人谱", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PaperProminentButtonStyle())
                    .disabled(model.isImporting)

                    Button {
                        model.navigate(.dataSettings)
                    } label: {
                        Label("数据管理", systemImage: "gearshape")
                    }
                    .buttonStyle(PaperSecondaryButtonStyle())
                }
            }

            // Metric Summary Pills
            HStack(spacing: 12) {
                metricPill(title: "待练队列", count: queueScores.count, icon: "list.bullet.rectangle", color: MIMITheme.darkGold) {
                    withAnimation { selectedTab = .queue }
                }
                metricPill(title: "我的收藏", count: favoriteScores.count, icon: "heart.fill", color: MIMITheme.terracotta) {
                    withAnimation { selectedTab = .favorites }
                }
                metricPill(title: "本地导入", count: importedScores.count, icon: "doc.badge.arrow.up", color: MIMITheme.signalBlue) {
                    withAnimation { selectedTab = .imported }
                }
                metricPill(title: "工坊工程", count: model.personalSnapshot.projects.count, icon: "music.quarternote.3", color: Color(hex: 0x5D4836)) {
                    withAnimation { selectedTab = .projects }
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func metricPill(title: String, count: Int, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                    .foregroundStyle(MIMITheme.bodyInk)
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tabBarSection: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PersonalLibraryTab.allCases) { tab in
                        let isSelected = selectedTab == tab
                        let count = tabCount(for: tab)
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                Text(tab.rawValue)
                                    .font(MIMITheme.bodyFont(size: 12, weight: isSelected ? .semibold : .medium))
                                if let count, count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(isSelected ? Color.white.opacity(0.25) : MIMITheme.warmGold.opacity(0.18), in: Capsule())
                                }
                            }
                            .foregroundStyle(isSelected ? .white : MIMITheme.bodyInk)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isSelected ? MIMITheme.ink : MIMITheme.paperWhite, in: Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : MIMITheme.softBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if selectedTab != .search {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(MIMITheme.mutedInk)
                    TextField("在此列表中筛选...", text: $localFilterText)
                        .textFieldStyle(.plain)
                        .font(MIMITheme.bodyFont(size: 12))
                    if !localFilterText.isEmpty {
                        Button { localFilterText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(MIMITheme.mutedInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: 200, height: 36)
                .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch selectedTab {
        case .queue:
            queueView
                .id("library-practice")
        case .favorites:
            favoritesView
                .id("library-favorites")
        case .imported:
            importedView
                .id("library-imported")
                .id("library-import")
        case .projects:
            projectsView
                .id("library-projects")
        case .archived:
            archivedView
                .id("library-archived")
        case .recent:
            recentView
                .id("library-recent")
        case .search:
            catalogSearchView
                .id("library-catalog-search")
        }
    }

    private var queueView: some View {
        VStack(alignment: .leading, spacing: 14) {
            let filtered = filterScores(queueScores)
            if queueScores.isEmpty {
                sectionEmpty(title: "待练队列目前为空", detail: "可从下方“曲库查找”中搜索喜欢的曲目加入待练，或导入自己的吉他谱。", action: "前往曲库查找", destination: nil) {
                    selectedTab = .search
                }
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的待练曲谱", detail: "请尝试更改搜索关键词或清空筛选条件。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, score in
                        personalScoreCard(score, mode: .queue(index: index))
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var favoritesView: some View {
        VStack(alignment: .leading, spacing: 14) {
            let filtered = filterScores(favoriteScores)
            if favoriteScores.isEmpty {
                sectionEmpty(title: "还没有收藏的曲谱", detail: "在曲谱卡片或详情页点击心形图标即可收藏到这里。", action: "前往曲库查找", destination: nil) {
                    selectedTab = .search
                }
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的收藏曲谱", detail: "请尝试更改搜索关键词或清空筛选条件。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { score in
                        personalScoreCard(score, mode: .favorite)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var importedView: some View {
        VStack(alignment: .leading, spacing: 18) {
            importBanner

            let filtered = filterScores(importedScores)
            if importedScores.isEmpty {
                sectionEmpty(title: "还没有导入个人曲谱", detail: "点击上方“选择文件并导入”支持导入 GP / IBE / XHE 格式。")
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的导入曲谱", detail: "请尝试更改搜索关键词或清空筛选条件。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { score in
                        personalScoreCard(score, mode: .imported)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var importBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("导入本地个人乐谱")
                        .font(MIMITheme.displayFont(size: 17, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .padding(.vertical, 1)
                    Text("支持 IBE、Guitar Pro (.gp, .gp3, .gp4, .gp5, .gpx) 与 XHE 格式。导入的曲谱与原始文件独立保管并完整校验。")
                        .font(MIMITheme.bodyFont(size: 12))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                PaperMenuPicker(
                    title: "乐器",
                    selection: $selectedCategory,
                    options: [
                        PaperMenuOption("guitar", "吉他", icon: "guitars"),
                        PaperMenuOption("ukulele", "尤克里里", icon: "music.note"),
                        PaperMenuOption("bass", "贝斯", icon: "tuningfork"),
                    ],
                    prefix: "乐器："
                )

                Button {
                    model.selectedImportCategory = selectedCategory
                    model.importScoreWithPanel()
                } label: {
                    Label(model.isImporting ? "正在解析导入…" : "选择文件并导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PaperProminentButtonStyle())
                .disabled(model.isImporting)
            }
        }
        .padding(18)
        .background(Color(hex: 0xFDFBF7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private var projectsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("个人工坊工程")
                        .font(MIMITheme.displayFont(size: 18, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .padding(.vertical, 1)
                    Text("从这里继续编辑草稿，或把已保存工程转为待练谱。")
                        .font(MIMITheme.bodyFont(size: 12))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
                Button {
                    model.navigate(.studio)
                } label: {
                    Label("进入制谱工坊 PRO", systemImage: "plus")
                }
                .buttonStyle(PaperProminentButtonStyle())
            }

            let filtered = model.personalSnapshot.projects.filter { p in
                let q = localFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !q.isEmpty else { return true }
                return p.title.lowercased().contains(q)
            }.sorted { $0.updatedAt > $1.updatedAt }

            if model.personalSnapshot.projects.isEmpty {
                sectionEmpty(title: "还没有工坊工程草稿", detail: "打开制谱工坊 PRO 可从空白工程或现有曲谱开始改编制谱。", action: "打开工坊 PRO", destination: .studio)
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的工程", detail: "请尝试更改搜索关键词或清空筛选条件。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { project in
                        HStack(alignment: .center, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(hex: 0xF5F0E6))
                                Image(systemName: "music.quarternote.3")
                                    .font(.system(size: 18))
                                    .foregroundStyle(MIMITheme.darkGold)
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(MIMITheme.displayFont(size: 15, weight: .bold))
                                    .foregroundStyle(MIMITheme.ink)
                                    .lineLimit(1)
                                Text("\(project.tracks.count) 条音轨 · \(project.bars.count) 小节 · \(project.key) 调 · \(project.initialTempo) BPM")
                                    .font(MIMITheme.bodyFont(size: 11))
                                    .foregroundStyle(MIMITheme.mutedInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button("继续编辑") {
                                model.navigate(.studioProject(id: project.id))
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                        }
                        .padding(16)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var archivedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            let filtered = filterScores(archivedScores)
            if archivedScores.isEmpty {
                sectionEmpty(title: "没有已归档曲谱", detail: "在待练队列中点击“归档”的曲谱会显示在这里，可随时恢复到待练。")
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的归档曲谱", detail: "请尝试更改搜索关键词。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { score in
                        personalScoreCard(score, mode: .archived)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var recentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let filtered = model.recentEntries.filter { e in
                let q = localFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !q.isEmpty else { return true }
                return e.title.lowercased().contains(q) || (e.artist ?? "").lowercased().contains(q)
            }
            if model.recentEntries.isEmpty {
                sectionEmpty(title: "还没有浏览记录", detail: "在播放器中打开曲谱后会自动记录在这里。清理记录不会删除曲谱。")
            } else if filtered.isEmpty {
                sectionEmpty(title: "没有匹配筛选结果的浏览记录", detail: "请尝试更改搜索关键词。")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(filtered.prefix(16))) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(MIMITheme.darkGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                                    .foregroundStyle(MIMITheme.ink)
                                    .lineLimit(1)
                                Text("\(entry.artist ?? "未知艺人") · \(Date(timeIntervalSince1970: entry.time / 1000).formatted(date: .abbreviated, time: .shortened))")
                                    .font(MIMITheme.bodyFont(size: 11))
                                    .foregroundStyle(MIMITheme.mutedInk)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Button("打开曲谱") {
                                openHistoryEntry(entry)
                            }
                            .buttonStyle(PaperSecondaryButtonStyle())
                        }
                        .padding(14)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }
                }
            }
        }
    }

    private var catalogSearchView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("搜索全站曲库并添加")
                    .font(MIMITheme.displayFont(size: 18, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                    .padding(.vertical, 1)
                Text("输入曲名或艺人快速检索，搜索结果可直接加入本设备待练或收藏。")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            HStack(spacing: 8) {
                PaperMenuPicker(
                    title: "曲库分类",
                    selection: $catalogSearchCategory,
                    options: [
                        PaperMenuOption("guitar", "吉他曲库", icon: "guitars"),
                        PaperMenuOption("ukulele", "尤克里里", icon: "music.note"),
                    ]
                )

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
                    TextField("输入曲名或艺人名搜索…", text: $catalogQuery)
                        .textFieldStyle(.plain)
                        .font(MIMITheme.bodyFont(size: 13))
                        .onSubmit(searchCatalog)
                    if !catalogQuery.isEmpty {
                        Button { catalogQuery = ""; invalidateCatalogSearch() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .padding(.horizontal, 12).frame(height: 42)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))

                Button(catalogSearchIsBusy ? "正在搜索…" : "搜索曲库", action: searchCatalog)
                    .buttonStyle(PaperProminentButtonStyle())
                    .frame(minHeight: 42)
                    .disabled(catalogSearchIsBusy || catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.contentRoot == nil)
            }

            if catalogSearchIsBusy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在搜索“\(catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines))”…")
                        .font(MIMITheme.bodyFont(size: 12))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .padding(.vertical, 4)
            }

            if let catalogSearchMessage {
                PaperNotice(text: catalogSearchMessage, error: catalogSearchError)
            }

            if !catalogResults.isEmpty {
                Text("显示 \(catalogResults.count) 个搜索结果")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)

                LazyVStack(spacing: 10) {
                    ForEach(catalogResults) { item in
                        catalogSearchResult(item)
                    }
                }
            }
        }
        .padding(22)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private func catalogSearchResult(_ item: CatalogItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Button(item.title) { model.openCatalogItem(item) }
                    .buttonStyle(.plain)
                    .font(MIMITheme.displayFont(size: 14, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                    .lineLimit(1)
                Text("\(item.artist ?? "未知艺人") · \(item.category == "ukulele" ? "尤克里里" : "吉他") · \(item.format.uppercased())\((item.format == "xhe" || item.scoreURL?.isEmpty != false) ? " · 仅可阅读" : "")")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button("打开曲谱") { model.openCatalogItem(item) }
                .buttonStyle(PaperSecondaryButtonStyle())
            Button(model.isFavorite(item) ? "已收藏" : "收藏") {
                if !model.isFavorite(item) { model.toggleFavorite(for: item) }
            }
            .buttonStyle(PaperSecondaryButtonStyle())
            .disabled(model.isFavorite(item))

            Button(model.isQueued(item) ? "已在待练" : "加入待练") {
                if !model.isQueued(item) { model.toggleQueue(for: item) }
            }
            .buttonStyle(PaperProminentButtonStyle())
            .disabled(model.isQueued(item) || item.format == "xhe" || item.scoreURL?.isEmpty != false)
            .help(item.format == "xhe" || item.scoreURL?.isEmpty != false ? "这份曲谱没有可播放下载资源；仍可打开文本谱阅读" : "加入本设备待练队列")
        }
        .padding(.vertical, 10)
    }

    private func sectionEmpty(title: String, detail: String, action: String? = nil, destination: NativeRoute? = nil, customAction: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(MIMITheme.warmGold.opacity(0.8))
            Text(title)
                .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                .foregroundStyle(MIMITheme.ink)
                .padding(.vertical, 1)
            Text(detail)
                .font(MIMITheme.bodyFont(size: 12))
                .foregroundStyle(MIMITheme.mutedInk)
                .multilineTextAlignment(.center)
            if let action {
                Button(action) {
                    if let customAction {
                        customAction()
                    } else if let destination {
                        model.navigate(destination)
                    }
                }
                .buttonStyle(PaperProminentButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MIMITheme.faintBorder, lineWidth: 1))
    }

    private enum ScoreCardMode {
        case queue(index: Int)
        case archived
        case favorite
        case imported
    }

    private func personalScoreCard(_ score: PersonalScore, mode: ScoreCardMode) -> some View {
        let practice = model.personalSnapshot.practiceItems.first(where: { $0.scoreId == score.id })
        let note = noteDrafts[score.id] ?? practice?.note ?? ""
        let isEditingNote = editingNoteScoreID == score.id || noteDrafts[score.id] != nil

        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(score.source == "private" ? Color(hex: 0xFDF6EA) : Color(hex: 0xF5F0E6))
                    VStack(spacing: 2) {
                        Image(systemName: scoreIcon(for: score))
                            .font(.system(size: 16))
                            .foregroundStyle(score.source == "private" ? MIMITheme.terracotta : MIMITheme.darkGold)
                        Text(score.format.uppercased())
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Button(score.title) {
                            model.openPersonalScore(score)
                        }
                        .buttonStyle(.plain)
                        .font(MIMITheme.displayFont(size: 15, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .lineLimit(1)
                        .padding(.vertical, 1)

                        if score.source == "private" {
                            MIMIPill(title: "个人导入", tint: MIMITheme.terracotta, fill: MIMITheme.terracotta.opacity(0.08))
                        } else {
                            MIMIPill(title: "曲库引用", tint: MIMITheme.darkGold, fill: MIMITheme.warmGold.opacity(0.1))
                        }

                        MIMIPill(title: categoryLabel(score.category), tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                    }

                    HStack(spacing: 8) {
                        Text(score.artist.isEmpty ? "未知艺人" : score.artist)
                            .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                            .foregroundStyle(MIMITheme.bodyInk)
                            .lineLimit(1)

                        if let practice {
                            Text("·").foregroundStyle(MIMITheme.softBorder)
                            HStack(spacing: 4) {
                                Circle().fill(statusColor(practice.status)).frame(width: 5, height: 5)
                                Text(statusLabel(practice.status))
                                    .font(MIMITheme.bodyFont(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(practice.status))
                            }
                        }
                    }

                    if let warnings = score.warnings, !warnings.isEmpty {
                        Label(warnings.joined(separator: "；"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(MIMITheme.terracotta)
                            .lineLimit(2)
                            .padding(.top, 1)
                    }
                }

                Spacer(minLength: 6)

                HStack(spacing: 7) {
                    switch mode {
                    case .queue(let index):
                        Text("序号 \(String(format: "%02d", index + 1))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(MIMITheme.mutedInk)
                            .padding(.horizontal, 6)

                        Button {
                            model.movePracticeScore(score.id, offset: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())
                        .disabled(index == 0)
                        .help("在待练队列中上移")

                        Button {
                            model.movePracticeScore(score.id, offset: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())
                        .disabled(index == queueScores.count - 1)
                        .help("在待练队列中下移")

                        Menu {
                            ForEach([PracticeStatus.todo, .practicing, .mastered], id: \.rawValue) { status in
                                Button(statusLabel(status)) {
                                    model.setPracticeStatus(scoreID: score.id, status: status)
                                }
                            }
                            Divider()
                            Button("归档到已归档列表") {
                                model.setPracticeStatus(scoreID: score.id, status: .archived)
                            }
                            Button("移出待练队列", role: .destructive) {
                                model.removePracticeScore(score.id)
                            }
                        } label: {
                            Label("状态", systemImage: "slider.horizontal.3")
                        }
                        .menuStyle(.borderlessButton)

                        Button {
                            model.openPersonalScore(score)
                        } label: {
                            Label("打开", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                        Button {
                            model.navigate(.practice(scoreID: score.id))
                        } label: {
                            Label("练习", systemImage: "metronome")
                        }
                        .buttonStyle(PaperProminentButtonStyle())

                    case .archived:
                        Button("恢复到待练") {
                            model.setPracticeStatus(scoreID: score.id, status: .todo)
                        }
                        .buttonStyle(PaperProminentButtonStyle())

                        Button("移出", role: .destructive) {
                            model.removePracticeScore(score.id)
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                        Button {
                            model.openPersonalScore(score)
                        } label: {
                            Label("打开曲谱", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                    case .favorite:
                        Button {
                            model.openPersonalScore(score)
                        } label: {
                            Label("打开曲谱", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                        if let practice, practice.status != .archived {
                            Button {
                                model.navigate(.practice(scoreID: score.id))
                            } label: {
                                Label("继续练习", systemImage: "metronome")
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                        } else {
                            Button("加入待练") {
                                addPersonalScoreToPractice(score)
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                        }

                        Button("取消收藏", role: .destructive) {
                            removeFavorite(score)
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                    case .imported:
                        Button {
                            model.openPersonalScore(score)
                        } label: {
                            Label("打开曲谱", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                        if let practice, practice.status != .archived {
                            Button {
                                model.navigate(.practice(scoreID: score.id))
                            } label: {
                                Label("继续练习", systemImage: "metronome")
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                        } else {
                            Button("加入待练") {
                                addPersonalScoreToPractice(score)
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                        }

                        Menu {
                            Button {
                                model.exportOriginal(score)
                            } label: {
                                Label("导出原始文件", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button("删除个人谱", role: .destructive) {
                                model.deletePrivateScore(score)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(MIMITheme.mutedInk)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            if case .queue = mode {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("练习备注与要点", systemImage: "note.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MIMITheme.mutedInk)
                        Spacer()
                        if !isEditingNote {
                            Button(note.isEmpty ? "添加备注" : "编辑备注") {
                                editingNoteScoreID = score.id
                            }
                            .font(MIMITheme.bodyFont(size: 10, weight: .medium))
                            .foregroundStyle(MIMITheme.darkGold)
                            .buttonStyle(.plain)
                        }
                    }

                    if isEditingNote {
                        TextEditor(text: Binding(get: { note }, set: { value in
                            if noteBases[score.id] == nil { noteBases[score.id] = practice?.note ?? "" }
                            noteDrafts[score.id] = String(value.prefix(5000))
                            noteMessages[score.id] = nil
                        }))
                        .font(MIMITheme.bodyFont(size: 12))
                        .frame(minHeight: 65, maxHeight: 95)
                        .padding(7)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))

                        HStack {
                            if let message = noteMessages[score.id] {
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(message.contains("冲突") || message.contains("失败") ? MIMITheme.terracotta : MIMITheme.green)
                            }
                            Spacer()
                            Button("取消") {
                                editingNoteScoreID = nil
                                noteDrafts[score.id] = nil
                            }
                            .buttonStyle(PaperSecondaryButtonStyle())

                            Button("保存备注") {
                                saveNote(scoreID: score.id, text: note, expectedBase: noteBases[score.id] ?? practice?.note ?? "")
                                editingNoteScoreID = nil
                            }
                            .buttonStyle(PaperProminentButtonStyle())
                            .disabled(noteDrafts[score.id] == nil || note == practice?.note)
                        }
                    } else if !note.isEmpty {
                        Text(note)
                            .font(MIMITheme.bodyFont(size: 12))
                            .foregroundStyle(MIMITheme.bodyInk)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color(hex: 0xFAF7F0), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.faintBorder, lineWidth: 1))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private func scoreIcon(for score: PersonalScore) -> String {
        switch score.category.lowercased() {
        case "ukulele": return "guitars"
        case "bass": return "waveform"
        default: return "guitars"
        }
    }

    private func categoryLabel(_ cat: String) -> String {
        switch cat.lowercased() {
        case "ukulele": return "尤克里里"
        case "bass": return "贝斯"
        default: return "吉他"
        }
    }

    private func statusColor(_ status: PracticeStatus) -> Color {
        switch status {
        case .todo: return MIMITheme.darkGold
        case .practicing: return MIMITheme.signalBlue
        case .mastered: return MIMITheme.green
        case .archived: return MIMITheme.mutedInk
        }
    }

    private func statusLabel(_ status: PracticeStatus) -> String {
        switch status {
        case .todo: return "待练"
        case .practicing: return "练习中"
        case .mastered: return "已掌握"
        case .archived: return "已归档"
        }
    }

    private func searchCatalog() {
        let text = catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let contentRoot = model.contentRoot else { return }
        catalogSearchGeneration += 1
        let generation = catalogSearchGeneration
        let category = catalogSearchCategory
        let databaseURL = AppPaths.catalogURL(contentRoot: contentRoot)
        catalogResults = []
        catalogSearchMessage = nil
        catalogSearchError = false
        catalogSearchIsBusy = true
        Task { @MainActor in
            do {
                let rows = try await Task.detached(priority: .userInitiated) { () throws -> [CatalogItem] in
                    let store = try CatalogStore(databaseURL: databaseURL)
                    let page = try await store.search(CatalogQuery(text: text, category: category, sort: .popular, limit: 20))
                    return page.items
                }.value
                guard generation == catalogSearchGeneration else { return }
                catalogResults = rows
                catalogSearchMessage = rows.isEmpty ? "没有找到匹配的曲谱。" : nil
                catalogSearchIsBusy = false
            } catch {
                guard generation == catalogSearchGeneration else { return }
                catalogSearchError = true
                catalogSearchMessage = "本地曲库搜索失败：\(error.localizedDescription)"
                catalogSearchIsBusy = false
            }
        }
    }

    private func invalidateCatalogSearch() {
        catalogSearchGeneration += 1
        catalogResults = []
        catalogSearchMessage = nil
        catalogSearchIsBusy = false
        catalogSearchError = false
    }

    private func addPersonalScoreToPractice(_ score: PersonalScore) {
        guard let store = model.personalStore else { return }
        Task { @MainActor in
            do {
                _ = try await store.joinPractice(score)
                model.personalDataDidChange()
                actionMessage = "已将《\(score.title)》加入待练。"
            } catch { actionMessage = "加入待练失败：\(error.localizedDescription)" }
        }
    }

    private func removeFavorite(_ score: PersonalScore) {
        guard let store = model.personalStore else { return }
        Task { @MainActor in
            do {
                try await store.toggleFavorite(score.id)
                model.personalDataDidChange()
                actionMessage = "已从本机收藏移除《\(score.title)》。"
            } catch { actionMessage = "取消收藏失败：\(error.localizedDescription)" }
        }
    }

    private func openHistoryEntry(_ entry: PersonalHistoryEntry) {
        if let score = allScores.first(where: { $0.id == entry.id || $0.sourceId == entry.id || $0.id == "catalog:\(entry.id)" }) {
            model.openPersonalScore(score)
        } else {
            let id = entry.id.hasPrefix("catalog:") ? String(entry.id.dropFirst("catalog:".count)) : entry.id
            model.navigate(.score(id: id))
        }
    }

    private func saveNote(scoreID: String, text: String, expectedBase: String) {
        guard let store = model.personalStore else { return }
        let submittedText = String(text.prefix(5000))
        Task { @MainActor in
            do {
                _ = try await store.updatePracticeNote(
                    scoreID: scoreID,
                    note: submittedText,
                    expectedNote: expectedBase
                )
                if noteDrafts[scoreID] == text {
                    noteBases[scoreID] = nil
                    noteDrafts[scoreID] = nil
                    noteMessages[scoreID] = "备注已保存。"
                } else {
                    noteBases[scoreID] = submittedText
                    noteMessages[scoreID] = "已保存本次提交；后续编辑尚未保存。"
                }
                model.personalDataDidChange()
            } catch { noteMessages[scoreID] = "保存失败：\(error.localizedDescription)" }
        }
    }
}


