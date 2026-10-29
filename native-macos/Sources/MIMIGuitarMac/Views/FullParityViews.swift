import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

private struct PaperPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(2.6).foregroundStyle(Color(hex: 0x8A7151))
            Text(title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
            Text(subtitle).font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.mutedInk)
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct PaperNotice: View {
    let text: String
    var error = false
    var body: some View {
        Label(text, systemImage: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(MIMITheme.bodyFont(size: 13, weight: .medium))
            .foregroundStyle(error ? Color(hex: 0x9F3828) : Color(hex: 0x2E6B47))
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background((error ? Color(hex: 0xFCEFEB) : Color(hex: 0xEEF5ED)), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct PaperSectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MIMITheme.displayFont(size: 18, weight: .medium)).tracking(-0.18).foregroundStyle(MIMITheme.ink)
            if let detail { Text(detail).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }
        }
    }
}

struct PersonalLibraryView: View {
    @EnvironmentObject private var model: AppModel
    var onRequestScrollToSection: ((String) -> Void)? = nil
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
    @State private var selectedCategory = "guitar"

    private var allScores: [PersonalScore] { model.personalScores }
    private var queueScores: [PersonalScore] {
        model.practiceItems.filter { $0.status != .archived }.compactMap { item in allScores.first { $0.id == item.scoreId } }
    }
    private var archivedScores: [PersonalScore] {
        model.practiceItems.filter { $0.status == .archived }.compactMap { item in allScores.first { $0.id == item.scoreId } }
    }
    private var favoriteScores: [PersonalScore] {
        let favoriteIDs = Set(model.personalSnapshot.favorites)
        return allScores.filter { favoriteIDs.contains($0.id) }
    }
    private var importedScores: [PersonalScore] { allScores.filter { $0.source == "private" } }

    private func synchronizeLibraryLocation(for section: LibrarySection) {
        let target: String
        switch section {
        case .allScores:
            target = "library-catalog-search"
        case .guitar:
            catalogSearchCategory = "guitar"
            target = "library-catalog-search"
        case .ukulele:
            catalogSearchCategory = "ukulele"
            target = "library-catalog-search"
        case .bass:
            selectedCategory = "bass"
            model.selectedImportCategory = "bass"
            target = "library-import"
        case .favorites:
            target = "library-favorites"
        case .queue:
            target = "library-practice"
        case .recent:
            target = "library-recent"
        case .imported:
            target = "library-imported"
        case .projects:
            target = "library-projects"
        }

        if model.showArchivedPracticeQueueOnLibrary {
            onRequestScrollToSection?("library-archived")
            DispatchQueue.main.async {
                if model.showArchivedPracticeQueueOnLibrary {
                    model.showArchivedPracticeQueueOnLibrary = false
                }
            }
        } else {
            onRequestScrollToSection?(target)
        }
    }

    private func consumeLibraryScrollRequest() {
        guard let section = model.requestedLibraryScrollSection else { return }
        model.requestedLibraryScrollSection = nil
        synchronizeLibraryLocation(for: section)
    }

    private func restoreLibraryCategorySelection() {
        selectedCategory = model.selectedImportCategory
        switch model.selectedLibrarySection {
        case .guitar: catalogSearchCategory = "guitar"
        case .ukulele: catalogSearchCategory = "ukulele"
        default: break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaperPageHeader(eyebrow: "本设备个人资料", title: "我的谱", subtitle: "收藏、待练和个人导入保存在当前设备。导出备份可迁移到其他设备。")
            if let actionMessage { PaperNotice(text: actionMessage, error: actionMessage.contains("失败")) }
            VStack(alignment: .leading, spacing: 32) {
                catalogSearchSection
                personalImportSection
                practiceSection
                archivedSection
                favoritesSection
                importedScoresSection
                projectCollection
            }
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

    private var catalogSearchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaperSectionTitle(title: "添加曲库曲谱", detail: "曲库搜索支持吉他与尤克里里；搜索结果可保存为本设备上的真实曲库引用。")
            HStack(spacing: 8) {
                Picker("曲库分类", selection: $catalogSearchCategory) {
                    Text("吉他曲库").tag("guitar")
                    Text("尤克里里").tag("ukulele")
                }
                .pickerStyle(.menu)
                .frame(width: 145, height: 44)
                .background(Color(hex: 0xFBFAF6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
                    TextField("曲名或艺人", text: $catalogQuery)
                        .textFieldStyle(.plain)
                        .font(MIMITheme.bodyFont(size: 13))
                        .onSubmit(searchCatalog)
                    if !catalogQuery.isEmpty {
                        Button { catalogQuery = ""; invalidateCatalogSearch() } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .padding(.horizontal, 12).frame(height: 44)
                .background(Color(hex: 0xFBFAF6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))
                Button(catalogSearchIsBusy ? "正在搜索…" : "搜索曲库", action: searchCatalog)
                    .buttonStyle(PaperProminentButtonStyle())
                    .frame(minHeight: 44)
                    .disabled(catalogSearchIsBusy || catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.contentRoot == nil)
            }
            if catalogSearchIsBusy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在搜索“\(catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines))”…").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }
            }
            if let catalogSearchMessage {
                PaperNotice(text: catalogSearchMessage, error: catalogSearchError)
            }
            if !catalogResults.isEmpty {
                Text("显示 \(catalogResults.count) 个搜索结果")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                LazyVStack(spacing: 0) {
                    ForEach(Array(catalogResults.enumerated()), id: \.element.id) { index, item in
                        catalogSearchResult(item)
                        if index < catalogResults.count - 1 { Rectangle().fill(Color(hex: 0xE8E2D4)).frame(height: 1) }
                    }
                }
            }
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-catalog-search")
    }

    private func catalogSearchResult(_ item: CatalogItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Button(item.title) { model.openCatalogItem(item) }
                    .buttonStyle(.plain).font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                Text("\(item.artist ?? "未知艺人") · \(item.category == "ukulele" ? "尤克里里" : "吉他") · \(item.format.uppercased())\((item.format == "xhe" || item.scoreURL?.isEmpty != false) ? " · 仅可阅读" : "")")
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(2)
            }
            Spacer(minLength: 6)
            Button("打开曲谱") { model.openCatalogItem(item) }.buttonStyle(PaperSecondaryButtonStyle())
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
        .padding(.vertical, 12)
    }

    private var personalImportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "导入个人谱", detail: "个人导入的乐器分类独立设置，支持吉他、尤克里里与贝斯。")
            HStack(spacing: 10) {
                Picker("个人谱导入分类", selection: $selectedCategory) {
                    Text("吉他").tag("guitar"); Text("尤克里里").tag("ukulele"); Text("贝斯").tag("bass")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140, height: 44)
                .fixedSize(horizontal: true, vertical: false)
                .background(Color(hex: 0xFBFAF6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))
                Text("IBE、Guitar Pro、XHE 与 MIMI 工坊曲谱会保存在本机；原始文件与可播放谱分别保存。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(2)
                Spacer(minLength: 4)
                Button { model.selectedImportCategory = selectedCategory; model.importScoreWithPanel() } label: {
                    Label(model.isImporting ? "正在导入…" : "选择文件并导入", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PaperProminentButtonStyle()).disabled(model.isImporting)
            }
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-import")
    }

    private var practiceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "待练", detail: "调整队列顺序与练习状态，记录目标和难点，或继续练习。")
            if queueScores.isEmpty {
                sectionEmpty(title: "还没有待练曲谱。", detail: "可从上方搜索添加，或导入个人谱。", action: "继续找谱", destination: .catalog(.all))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(queueScores.enumerated()), id: \.element.id) { index, score in
                        personalScoreCard(score, mode: .queue(index: index))
                    }
                }
            }
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-practice")
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "已归档", detail: "归档的曲谱会保留在这里，可随时恢复到待练。")
            if archivedScores.isEmpty {
                sectionEmpty(title: "没有已归档曲谱。", detail: "待练曲谱归档后会显示在这里。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(archivedScores) { score in personalScoreCard(score, mode: .archived) }
                }
            }
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-archived")
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "收藏", detail: "保存在本设备个人资料中的曲库引用与个人谱。")
            if favoriteScores.isEmpty {
                sectionEmpty(title: "还没有收藏的曲谱。", detail: "在曲谱卡片或详情页点按心形，可保存到这里。", action: "继续找谱", destination: .catalog(.all))
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(favoriteScores) { score in personalScoreCard(score, mode: .favorite) }
                }
            }
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-favorites")
    }

    private var importedScoresSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "个人导入", detail: "管理本机保存的个人原件、播放版本与关联练习。")
            if importedScores.isEmpty {
                sectionEmpty(title: "还没有导入个人曲谱。", detail: "从上方选择文件并导入；原件与练习版本会分别保存在本机。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(importedScores) { score in personalScoreCard(score, mode: .imported) }
                }
            }
            recentHistorySection
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-imported")
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            PaperSectionTitle(title: "最近浏览", detail: "最近打开的曲谱记录保存在本机；清理记录不会删除曲谱或练习数据。")
            if model.recentEntries.isEmpty {
                Text("还没有浏览记录。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(Array(model.recentEntries.prefix(8))) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(MIMITheme.darkGold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                            Text("\(entry.artist ?? "") · \(Date(timeIntervalSince1970: entry.time / 1000).formatted(date: .abbreviated, time: .shortened))")
                                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button("打开") { openHistoryEntry(entry) }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                    .padding(11).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.top, 5)
        .id("library-recent")
    }

    private func sectionEmpty(title: String, detail: String, action: String? = nil, destination: NativeRoute? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(MIMITheme.bodyFont(size: 13, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
            Text(detail).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            if let action, let destination {
                Button(action) { model.navigate(destination) }.buttonStyle(PaperSecondaryButtonStyle()).padding(.top, 3)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 12))
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
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack { RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xF5F0E6)); Image(systemName: score.source == "private" ? "doc.badge.arrow.up" : "music.note").foregroundStyle(MIMITheme.darkGold) }
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Button(score.title) { model.openPersonalScore(score) }.buttonStyle(.plain)
                        .font(MIMITheme.bodyFont(size: 14, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                    Text("\(score.artist.isEmpty ? "未知艺人" : score.artist) · \(score.category) · \(score.format.uppercased()) · \(score.source == "private" ? "个人导入" : "曲库引用")")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(2)
                    if let warnings = score.warnings, !warnings.isEmpty { Label(warnings.joined(separator: "；"), systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(MIMITheme.terracotta).lineLimit(3) }
                }
                Spacer(minLength: 4)
                if let practice { Text(statusLabel(practice.status)).font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.darkGold).padding(.horizontal, 9).padding(.vertical, 5).background(MIMITheme.warmGold.opacity(0.12), in: Capsule()) }
            }

            switch mode {
            case .queue(let index):
                HStack(spacing: 7) {
                    Text("队列顺序 \(index + 1)").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                    Spacer(minLength: 4)
                    Button("上移") { model.movePracticeScore(score.id, offset: -1) }.buttonStyle(PaperSecondaryButtonStyle()).disabled(index == 0)
                    Button("下移") { model.movePracticeScore(score.id, offset: 1) }.buttonStyle(PaperSecondaryButtonStyle()).disabled(index == queueScores.count - 1)
                    Menu {
                        ForEach([PracticeStatus.todo, .practicing, .mastered], id: \.rawValue) { status in Button(statusLabel(status)) { model.setPracticeStatus(scoreID: score.id, status: status) } }
                    } label: { Label("状态", systemImage: "slider.horizontal.3") }.menuStyle(.borderlessButton)
                    Button { model.navigate(.practice(scoreID: score.id)) } label: { Label("开始练习", systemImage: "metronome") }.buttonStyle(PaperProminentButtonStyle())
                    Button("归档") { model.setPracticeStatus(scoreID: score.id, status: .archived) }.buttonStyle(PaperSecondaryButtonStyle())
                    Button("移出待练", role: .destructive) { model.removePracticeScore(score.id) }.buttonStyle(PaperSecondaryButtonStyle())
                }
            case .archived:
                HStack {
                    Button("恢复到待练") { model.setPracticeStatus(scoreID: score.id, status: .todo) }.buttonStyle(PaperProminentButtonStyle())
                    Button("移出待练", role: .destructive) { model.removePracticeScore(score.id) }.buttonStyle(PaperSecondaryButtonStyle())
                    Spacer()
                    Button { model.openPersonalScore(score) } label: { Label("打开曲谱", systemImage: "arrow.up.right.square") }.buttonStyle(PaperSecondaryButtonStyle())
                }
            case .favorite, .imported:
                HStack(spacing: 8) {
                    Button { model.openPersonalScore(score) } label: { Label("打开曲谱", systemImage: "arrow.up.right.square") }.buttonStyle(PaperSecondaryButtonStyle())
                    if let practice, practice.status != .archived {
                        Button { model.navigate(.practice(scoreID: score.id)) } label: { Label("继续练习", systemImage: "metronome") }.buttonStyle(PaperProminentButtonStyle())
                    } else {
                        Button("加入待练") { addPersonalScoreToPractice(score) }.buttonStyle(PaperProminentButtonStyle())
                    }
                    if case .favorite = mode {
                        Button("取消收藏", role: .destructive) { removeFavorite(score) }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                    Spacer()
                }
            }

            if case .queue = mode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("练习备注").font(.system(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.mutedInk)
                    TextEditor(text: Binding(get: { note }, set: { value in
                        if noteBases[score.id] == nil { noteBases[score.id] = practice?.note ?? "" }
                        noteDrafts[score.id] = String(value.prefix(5000)); noteMessages[score.id] = nil
                    }))
                        .font(MIMITheme.bodyFont(size: 13)).frame(minHeight: 70, maxHeight: 100)
                        .padding(7).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))
                    HStack {
                        if let message = noteMessages[score.id] { Text(message).font(.system(size: 11)).foregroundStyle(message.contains("冲突") || message.contains("失败") ? MIMITheme.terracotta : MIMITheme.green) }
                        Spacer()
                        Button("撤销草稿") { noteDrafts[score.id] = practice?.note ?? ""; noteBases[score.id] = nil; noteMessages[score.id] = "已还原到已保存备注。" }
                            .disabled(noteDrafts[score.id] == nil || noteDrafts[score.id] == practice?.note)
                        Button("保存备注") { saveNote(scoreID: score.id, text: note, expectedBase: noteBases[score.id] ?? practice?.note ?? "") }
                            .buttonStyle(.borderedProminent).tint(MIMITheme.darkGold)
                            .disabled(noteDrafts[score.id] == nil || note == practice?.note)
                    }
                }
            }
        }
        .padding(16).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE5E5E5), lineWidth: 1))
    }

    private var projectCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "个人工坊工程", detail: "从这里继续编辑，或把保存版本转换为待练谱。导入原件单独保管。")
            if model.personalSnapshot.projects.isEmpty { Text("还没有工坊工程。打开制谱工坊 PRO 可新建工程或导入曲谱。")
                .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk).padding(25).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            } else {
                ForEach(model.personalSnapshot.projects.sorted { $0.updatedAt > $1.updatedAt }) { project in
                    HStack { Image(systemName: "square.grid.3x3.square").foregroundStyle(MIMITheme.darkGold)
                        VStack(alignment: .leading, spacing: 3) { Text(project.title).font(MIMITheme.displayFont(size: 17, weight: .semibold)); Text("\(project.tracks.count) 条音轨 · \(project.bars.count) 小节 · \(project.key) · \(project.initialTempo) BPM").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                        Spacer(); Button("继续编辑") { model.navigate(.studioProject(id: project.id)) }.buttonStyle(PaperProminentButtonStyle())
                    }.padding(16).mimiCard(fill: MIMITheme.paperWhite)
                }
            }
            Button("打开制谱工坊 PRO") { model.navigate(.studio) }.buttonStyle(PaperSecondaryButtonStyle())
        }
        .padding(24).mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE8E2D4), shadowOpacity: 0.025)
        .id("library-projects")
    }

    private func statusLabel(_ status: PracticeStatus) -> String {
        switch status { case .todo: return "待练"; case .practicing: return "练习中"; case .mastered: return "已掌握"; case .archived: return "已归档" }
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

private struct PaperProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 37).background(MIMITheme.ink.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PaperSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
            .padding(.horizontal, 14).frame(minHeight: 37).background(MIMITheme.paperWhite, in: Capsule())
            .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1)).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct PracticeDayBucket: Identifiable {
    let date: Date
    let durationMs: Double
    var id: TimeInterval { date.timeIntervalSince1970 }
}

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.mimiViewportHeight) private var viewportHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var activeScoreID: String?
    @State private var didResolveInitialPracticeSelection = false
    @State private var focusedReviewSessionID: String?
    @State private var showCompleted = false

    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    private var scores: [PersonalScore] { model.personalScores }
    private var activePracticeScores: [PersonalScore] {
        model.practiceItems.filter { $0.status != .archived }.compactMap { item in
            scores.first(where: { $0.id == item.scoreId })
        }
    }
    private var practiceRows: [(PracticeItem, PersonalScore)] {
        model.practiceItems.compactMap { item in scores.first(where: { $0.id == item.scoreId }).map { (item, $0) } }
            .filter { showCompleted ? $0.0.status == .mastered : $0.0.status == .todo || $0.0.status == .practicing }
    }
    private var sessions: [PracticeSession] { model.personalSnapshot.sessions.sorted { $0.updatedAt > $1.updatedAt } }
    private var recentSessions: [PracticeSession] { Array(sessions.prefix(12)) }
    private var requestedScore: PersonalScore? {
        guard let activeScoreID else { return nil }
        return scores.first(where: {
            $0.id == activeScoreID || ($0.source == "catalog" && ($0.sourceId == activeScoreID || "catalog:\($0.sourceId)" == activeScoreID))
        })
    }
    private var activeScore: PersonalScore? {
        guard let requestedScore,
              model.practiceItems.contains(where: { $0.scoreId == requestedScore.id && $0.status != .archived }) else { return nil }
        return requestedScore
    }
    private var selectionErrorMessage: String? {
        guard activeScoreID != nil else { return nil }
        guard let requestedScore else { return "请求的曲谱已从本机资料移除，或尚未加入待练。" }
        guard let queueItem = model.practiceItems.first(where: { $0.scoreId == requestedScore.id }) else {
            return "这份曲谱目前不在待练列表中；请先从“我的谱”加入待练。"
        }
        if queueItem.status == .archived { return "这份曲谱已归档，请先从“我的谱”恢复到待练。" }
        return nil
    }
    private var selectedReview: PracticeSession? { sessions.first(where: { $0.id == focusedReviewSessionID }) }
    private var totalTime: Double { sessions.flatMap(\.slices).reduce(0) { $0 + $1.durationMs } }
    private var localCalendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = .current
        return value
    }
    private var dayBuckets: [PracticeDayBucket] {
        let calendar = localCalendar
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        let dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: firstDay) }
        var totals = Dictionary(uniqueKeysWithValues: dates.map { (calendar.startOfDay(for: $0), 0.0) })
        var unique = Set<String>()
        for session in model.personalSnapshot.sessions {
            for slice in session.slices {
                let uniqueKey = "\(session.id)\u{0}\(slice.id)"
                guard unique.insert(uniqueKey).inserted, slice.startedAt.isFinite, slice.durationMs.isFinite,
                      slice.startedAt >= 0, slice.durationMs > 0 else { continue }
                var cursor = Date(timeIntervalSince1970: slice.startedAt / 1000)
                let end = cursor.addingTimeInterval(slice.durationMs / 1000)
                while cursor < end, let interval = calendar.dateInterval(of: .day, for: cursor) {
                    let next = min(end, interval.end)
                    let day = calendar.startOfDay(for: cursor)
                    if totals[day] != nil { totals[day, default: 0] += next.timeIntervalSince(cursor) * 1000 }
                    guard next > cursor else { break }
                    cursor = next
                }
            }
        }
        return dates.map { day in PracticeDayBucket(date: day, durationMs: totals[calendar.startOfDay(for: day)] ?? 0) }
    }
    private var todayBucket: PracticeDayBucket? { dayBuckets.last }
    private var reviewWarnings: [String] {
        var result: [String] = []
        for session in model.personalSnapshot.sessions {
            for slice in session.slices where slice.id.isEmpty || !slice.startedAt.isFinite || !slice.durationMs.isFinite || slice.startedAt < 0 || slice.durationMs <= 0 {
                result.append("练习记录 \(session.id) 中有无效时段，未计入汇总")
            }
            if !scores.contains(where: { $0.id == session.scoreId }) { result.append("练习记录 \(session.id) 所关联的曲谱缺失") }
        }
        return Array(NSOrderedSet(array: result)) as? [String] ?? result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: model.isScoreFocused ? 0 : 20) {
            focusChrome {
                VStack(alignment: .leading, spacing: 20) {
                    PaperPageHeader(eyebrow: "个人练习", title: "继续练习", subtitle: "从本设备待练曲目中选择一首。个人谱只在本地读取；曲库谱使用本机曲库资源。")
                    practiceScorePicker
                }
            }
            if let activeScore, let root = model.contentRoot, let store = model.personalStore {
                NativePlayerPane(
                    item: nil,
                    personalScore: activeScore,
                    contentRoot: root,
                    personalStore: store,
                    mode: .practice,
                    onPersonalDataChanged: model.personalDataDidChange,
                    isFocused: model.isScoreFocused,
                    viewportHeight: model.isScoreFocused ? viewportHeight : nil,
                    onToggleFocus: { model.toggleScoreFullscreen() }
                )
                .frame(minHeight: model.isScoreFocused ? (viewportHeight ?? 640) : 640, maxHeight: model.isScoreFocused ? .infinity : nil)
                .mimiCard(radius: 20, fill: MIMITheme.paperWhite)
            } else if let selectionErrorMessage {
                PaperNotice(text: selectionErrorMessage, error: true)
            } else if activeScoreID != nil {
                PaperNotice(text: "本机个人资料尚未就绪，无法载入这份练习曲谱。", error: true)
            } else if activePracticeScores.isEmpty {
                VStack(alignment: .center, spacing: 10) {
                    Text("待练列表还是空的").font(MIMITheme.proseFont(size: 15, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text("先从曲库收藏或导入一份谱，随后加入待练。")
                        .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                    Button("打开我的谱") { model.navigate(.library) }.buttonStyle(PaperProminentButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
            }
            focusChrome { practiceReview }
            focusChrome { practiceQueueManagement }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: model.isScoreFocused ? viewportHeight : nil, alignment: .top)
        .animation(motionPolicy.allowsSpatialMotion ? motionPolicy.panelAnimation : nil, value: model.isScoreFocused)
        .onAppear {
            model.refreshPersonalData()
            applyPracticeRouteSelection(model.route)
        }
        .onChange(of: model.route) { route in applyPracticeRouteSelection(route) }
        .onChange(of: model.personalSnapshot) { _ in
            if !didResolveInitialPracticeSelection { selectInitialPracticeScoreIfAvailable() }
        }
    }

    private func focusChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(model.isScoreFocused ? 0 : 1)
                .animation(motionPolicy.panelAnimation, value: model.isScoreFocused)
        }
            .frame(height: model.isScoreFocused ? 0 : nil, alignment: .top)
            .animation(motionPolicy.allowsSpatialMotion ? motionPolicy.panelAnimation : nil, value: model.isScoreFocused)
            .clipped()
            .allowsHitTesting(!model.isScoreFocused)
            .accessibilityHidden(model.isScoreFocused)
    }

    private func applyPracticeRouteSelection(_ route: NativeRoute) {
        guard case .practice(let requestedID) = route else { return }
        guard let requestedID else {
            activeScoreID = nil
            didResolveInitialPracticeSelection = false
            selectInitialPracticeScoreIfAvailable()
            return
        }
        let matchingScore = scores.first(where: {
            $0.id == requestedID || ($0.source == "catalog" && ($0.sourceId == requestedID || "catalog:\($0.sourceId)" == requestedID))
        })
        activeScoreID = matchingScore?.id ?? requestedID
        didResolveInitialPracticeSelection = true
    }

    private func selectInitialPracticeScoreIfAvailable() {
        guard !didResolveInitialPracticeSelection, let firstScore = activePracticeScores.first else { return }
        activeScoreID = firstScore.id
        didResolveInitialPracticeSelection = true
    }

    private var practiceScorePicker: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                Text("选择练习曲谱")
                    .font(MIMITheme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(MIMITheme.ink)
                    .fixedSize()
                Picker("选择练习曲谱", selection: Binding(
                    get: { activeScoreID },
                    set: { scoreID in
                        activeScoreID = scoreID
                        didResolveInitialPracticeSelection = true
                    }
                )) {
                    Text("选择一首待练曲谱").tag(nil as String?)
                    if let activeScoreID, !activePracticeScores.contains(where: { $0.id == activeScoreID }) {
                        Text("当前曲目待处理").tag(activeScoreID as String?)
                    }
                    ForEach(activePracticeScores) { score in
                        Text(score.artist.isEmpty ? score.title : "\(score.title) · \(score.artist)")
                            .tag(score.id as String?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("管理我的谱") { model.navigate(.library) }.buttonStyle(PaperSecondaryButtonStyle())
        }
        .padding(16)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private var practiceQueueManagement: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center) {
                PaperSectionTitle(title: showCompleted ? "已掌握曲目" : "待练队列", detail: "按队列顺序练习；每首曲目可保存备注、恢复断点或查看练习回顾。")
            }
            HStack(spacing: 12) {
                metric("待练曲目", value: "\(model.practiceItems.filter { $0.status == .todo || $0.status == .practicing }.count)", icon: "text.badge.plus")
                metric("练习会话", value: "\(sessions.count)", icon: "clock")
                metric("累计伴奏时长", value: durationLabel(totalTime), icon: "metronome")
                Spacer(minLength: 4)
                Toggle("已掌握", isOn: $showCompleted).toggleStyle(.switch).controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 13) {
                if practiceRows.isEmpty {
                    if showCompleted || !activePracticeScores.isEmpty {
                        Text(showCompleted ? "还没有标记为已掌握的曲目。" : "待练队列为空。可从曲库详情加入曲目。")
                            .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk).padding(22).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
                        Button("打开曲库") { model.navigate(.catalog(.all)) }.buttonStyle(PaperProminentButtonStyle())
                    }
                } else {
                    ForEach(Array(practiceRows.enumerated()), id: \.element.0.scoreId) { index, row in
                        let (entry, score) = row
                        HStack(spacing: 13) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(MIMITheme.darkGold).frame(width: 34, height: 34).background(MIMITheme.warmGold.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(score.title).font(MIMITheme.displayFont(size: 17, weight: .semibold))
                                Text("\(score.artist.isEmpty ? "未知演奏者" : score.artist) · \(statusLabel(entry.status))").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                                Text(entry.note.isEmpty ? "暂无队列备注" : entry.note).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineLimit(2)
                            }
                            Spacer()
                            if let last = sessions.first(where: { $0.scoreId == score.id }) {
                                Button("打开回顾") { focusedReviewSessionID = last.id }.buttonStyle(PaperSecondaryButtonStyle())
                            } else { Button("打开回顾") {}.buttonStyle(PaperSecondaryButtonStyle()).disabled(true) }
                            Button("继续练习") {
                                activeScoreID = score.id
                                model.preparePracticeScore(score.id)
                            }.buttonStyle(PaperProminentButtonStyle())
                        }.padding(14).mimiCard(radius: 16, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
                    }
                }
            }
        }
        .padding(18)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private var practiceReview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                PaperSectionTitle(title: "练习回顾", detail: "仅统计播放器已记录的伴奏播放时段，不代表实际演奏时长。")
                Spacer()
                Text("本地时区：\(TimeZone.current.identifier)").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            }
            if !reviewWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 5) { Text("部分练习记录未能完整汇总").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); ForEach(reviewWarnings, id: \.self) { Text("• \($0)") } }
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(Color(hex: 0x765514)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xFFF8E8), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今天 · \(todayBucket.map(dayLabel) ?? "今天")").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    Text(durationLabel(todayBucket?.durationMs ?? 0)).font(MIMITheme.displayFont(size: 24, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text("近 7 个本地日").font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.mutedInk).padding(.top, 6)
                    ForEach(dayBuckets) { bucket in HStack { Text(dayLabel(bucket)).foregroundStyle(MIMITheme.mutedInk); Spacer(); Text(durationLabel(bucket.durationMs)).foregroundStyle(MIMITheme.bodyInk) }.font(MIMITheme.bodyFont(size: 11)) }
                }
                .padding(16).frame(width: 260, alignment: .leading).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近练习记录").font(MIMITheme.bodyFont(size: 14, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    if recentSessions.isEmpty {
                        Text("还没有已保存的练习记录。播放记录在播放器保存后会显示在这里。")
                            .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).padding(15).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
                    } else {
                        ForEach(recentSessions) { session in reviewSessionRow(session) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let session = selectedReview { reviewDetail(session) }
        }
        .padding(18).mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private func reviewSessionRow(_ session: PracticeSession) -> some View {
        let score = scores.first(where: { $0.id == session.scoreId })
        let item = model.personalSnapshot.practiceItems.first(where: { $0.scoreId == session.scoreId })
        let availability: String = score == nil ? "曲谱已不可用" : item?.status == .archived ? "已归档" : item == nil ? "已移出待练" : "待练队列"
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(score.map { "\($0.title)\($0.artist.isEmpty ? "" : " · \($0.artist)")" } ?? "曲谱已不可用")
                    .font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                Spacer()
                Text(statusLabel(session.state)).font(MIMITheme.bodyFont(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).background(MIMITheme.warmGold.opacity(0.12), in: Capsule())
            }
            Text("已保存伴奏时长：\(durationLabel(sessionDuration(session))) · \(timestampLabel(session.updatedAt, timezone: session.timezone))")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            if !session.note.isEmpty { Text("备注：\(session.note)").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineLimit(3) }
            HStack(spacing: 9) {
                Text(availability).font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                Button("打开回顾") { focusedReviewSessionID = session.id }.buttonStyle(PaperSecondaryButtonStyle())
                if score != nil, item?.status == .archived {
                    Button("前往我的谱恢复") { model.showArchivedPracticeQueue() }.buttonStyle(PaperSecondaryButtonStyle())
                } else if score != nil, item == nil {
                    Button("前往我的谱管理") { model.selectSection(.queue) }.buttonStyle(PaperSecondaryButtonStyle())
                } else if let score {
                    Button("打开这首曲谱的练习") { activeScoreID = score.id; model.preparePracticeScore(score.id) }.buttonStyle(PaperProminentButtonStyle())
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(session.id == focusedReviewSessionID ? Color(hex: 0xF5F0E6) : MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.faintBorder, lineWidth: 1))
    }

    private func reviewDetail(_ session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack { PaperSectionTitle(title: "会话详情", detail: "\(session.timezone) · \(statusLabel(session.state))"); Spacer(); Button("关闭回顾") { focusedReviewSessionID = nil }.buttonStyle(PaperSecondaryButtonStyle()) }
            let score = scores.first(where: { $0.id == session.scoreId })
            Text("曲目：\(score?.title ?? "曲谱已不可用")\(score?.artist.isEmpty == false ? " · \(score!.artist)" : "")")
                .font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text("开始：\(timestampLabel(session.startedAt, timezone: session.timezone)) · 最近更新：\(timestampLabel(session.updatedAt, timezone: session.timezone))\(session.endedAt.map { " · 结束：\(timestampLabel($0, timezone: session.timezone))" } ?? "")")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            if !session.note.isEmpty { Text("会话备注：\n\(session.note)").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).textSelection(.enabled) }
            if let plan = session.speedPlan {
                Text("速度计划：\(plan.startBpm, specifier: "%.0f") → \(plan.targetBpm, specifier: "%.0f") BPM；每级 +\(plan.stepBpm, specifier: "%.0f")，每级 \(plan.lapsPerLevel) 圈；当前 \(plan.currentBpm, specifier: "%.0f") BPM，已完成 \(plan.completedLaps) 圈。\(plan.loopRange.map { "循环 tick \($0.startTick)–\($0.endTick)。" } ?? "")")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk)
            }
            PaperSectionTitle(title: "播放时段", detail: "按会话中保存的片段去重；跨本地午夜的片段按实际时长拆分到每日汇总。")
            if session.slices.isEmpty { Text("此会话尚无有效播放时段。") .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
            ForEach(session.slices.sorted { $0.sequence < $1.sequence }) { slice in
                HStack { Text("第 \(slice.sequence + 1) 段 · \(timestampLabel(slice.startedAt, timezone: session.timezone))"); Spacer(); Text(durationLabel(slice.durationMs)); Text(slice.epoch).foregroundStyle(MIMITheme.mutedInk) }
                    .font(MIMITheme.bodyFont(size: 10)).padding(.vertical, 5).overlay(alignment: .bottom) { Rectangle().fill(MIMITheme.faintBorder).frame(height: 1) }
            }
        }
        .padding(16).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sessionDuration(_ session: PracticeSession) -> Double {
        var ids = Set<String>()
        return session.slices.filter { ids.insert($0.id).inserted && $0.durationMs.isFinite && $0.durationMs > 0 }.reduce(0) { $0 + $1.durationMs }
    }
    private func dayLabel(_ bucket: PracticeDayBucket) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "MM-dd"
        let today = localCalendar.isDateInToday(bucket.date)
        return formatter.string(from: bucket.date) + (today ? " 今天" : "")
    }
    private func timestampLabel(_ milliseconds: Double, timezone: String) -> String {
        guard milliseconds.isFinite, milliseconds > 0 else { return "时间未知" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.timeZone = TimeZone(identifier: timezone) ?? .current; formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).foregroundStyle(MIMITheme.darkGold); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 10)).foregroundStyle(MIMITheme.mutedInk); Text(value).font(MIMITheme.displayFont(size: 16, weight: .semibold)).foregroundStyle(MIMITheme.ink) } }
            .padding(.horizontal, 13).padding(.vertical, 9).mimiCard(radius: 14, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
    }
    private func statusLabel(_ status: PracticeStatus) -> String { switch status { case .todo: return "待练"; case .practicing: return "练习中"; case .mastered: return "已掌握"; case .archived: return "已归档" } }
    private func statusLabel(_ state: String) -> String { switch state { case "active": return "进行中"; case "paused": return "已暂停"; case "interrupted": return "已中断"; case "completed": return "已完成"; default: return "未知状态" } }
    private func durationLabel(_ milliseconds: Double) -> String {
        guard milliseconds.isFinite, milliseconds > 0 else { return "0 分钟" }
        let seconds = Int(milliseconds / 1000); if seconds < 60 { return "\(seconds) 秒" }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, remainder = seconds % 60
        return [hours > 0 ? "\(hours) 小时" : "", minutes > 0 ? "\(minutes) 分钟" : "", remainder > 0 ? "\(remainder) 秒" : ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct BackupSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var coordinator: BackupCoordinator?
    @State private var v1Preview: PersonalBackupV1Preview?
    @State private var v2Preview: PersonalBackupV2Preview?
    @State private var isBusy = false
    @State private var progress = ""
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var restoreTask: Task<Void, Never>?

    private var data: PersonalData { model.personalSnapshot }
    private var entityCount: Int {
        data.scores.count + data.favorites.count + data.practiceItems.count + data.practiceFragments.count + data.resumes.count + data.sessions.count + data.projects.count + data.originals.count + data.history.count
    }
    private var referencedAssetIDs: [String] {
        Array(Set(data.scores.flatMap { [$0.assetId, $0.originalAssetId].compactMap { $0 } } + data.originals.map(\.assetId))).sorted()
    }
    private var store: PersonalStore? { model.personalStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaperPageHeader(eyebrow: "本设备个人资料", title: "数据与备份", subtitle: "查看本设备资料、导出完整备份，或先校验备份内容再合并恢复。")
            if let notice { PaperNotice(text: notice) }
            if let errorMessage { PaperNotice(text: errorMessage, error: true) }
            if isBusy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(progress.isEmpty ? "正在处理个人资料…" : progress).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }.padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02) }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    PaperSectionTitle(title: "本机资料状态", detail: "SQLite 个人资料与曲库快照分开保存在 Application Support 中。")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        dataMetric("个人曲谱", data.scores.count, "music.note.list")
                        dataMetric("收藏", data.favorites.count, "heart")
                        dataMetric("待练 / 归档", data.practiceItems.count, "metronome")
                        dataMetric("练习会话", data.sessions.count, "clock")
                        dataMetric("工坊工程", data.projects.count, "square.grid.3x3.square")
                        dataMetric("练习片段", data.practiceFragments.count, "point.topleft.down.curvedto.point.bottomright.up")
                        dataMetric("播放断点", data.resumes.count, "bookmark")
                        dataMetric("浏览历史", data.history.count, "clock.arrow.circlepath")
                    }
                    HStack { Label("Revision \(data.revision)", systemImage: "number"); Spacer(); Label("\(referencedAssetIDs.count) 份引用附件", systemImage: "paperclip"); Spacer(); Label(data.migrationCompleted ? "本机资料已就绪" : "迁移未完成", systemImage: data.migrationCompleted ? "checkmark.circle" : "exclamationmark.triangle") }
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(data.migrationCompleted ? MIMITheme.mutedInk : MIMITheme.terracotta)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    PaperSectionTitle(title: "v1 JSON 备份", detail: "兼容原站单文件格式，包含完整个人实体与所有引用附件。")
                    HStack(spacing: 10) {
                        Button("生成完整 v1 JSON…", action: exportV1).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy || !data.migrationCompleted)
                        Text("最多 64 MiB；单附件 30 MiB、附件合计 927 MiB、最多 500 份附件与 10,000 个资料实体。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "v2 长期分卷备份", detail: "每卷负载最多 8 MiB；全部卷由 MIMI2VOL 头、分块和 SHA-256 校验。")
                    HStack(spacing: 10) {
                        Button("生成 v2 备份文件夹…", action: exportV2).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy || !data.migrationCompleted)
                        Text("最多 128 卷，总文件大小不超过 1 GiB；生成后清单与卷文件都会写入所选位置下的新文件夹。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "校验并恢复 v1", detail: "先选择一个完整 JSON 文件并验证 schema、摘要、清单、附件及实体上限。预览不会改变本机资料。")
                    HStack(spacing: 10) {
                        Button("选择并校验 JSON 备份…", action: previewV1).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy)
                        if v1Preview != nil { Button("取消预览") { v1Preview = nil }.buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy) }
                    }
                    if let preview = v1Preview {
                        backupPreview(title: "v1 完整性校验通过", revision: preview.expectedRevision, scoreCount: preview.data.scores.count, attachmentCount: preview.assets.count, fileSize: preview.fileSize, detail: "Schema \(preview.manifest.schemaVersion) · \(preview.data.favorites.count) 收藏 · \(preview.data.practiceItems.count) 练习条目 · \(preview.data.sessions.count) 会话 · \(preview.data.projects.count) 工程")
                        HStack { Button("合并并恢复此备份", action: restoreV1).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy); Text("恢复会将这份通过校验的快照合并到当前资料，遇到冲突由存储层保留可恢复的双方记录。") .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "校验并恢复 v2 分卷", detail: "先选择一份 JSON 清单，再选择同一备份的全部二进制卷。卷顺序不限；缺卷、混卷或损坏都会拒绝预览。")
                    HStack(spacing: 10) {
                        Button("选择清单与全部分卷…", action: previewV2).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy)
                        if v2Preview != nil { Button("取消预览并清理暂存", action: cancelV2Preview).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy) }
                    }
                    if let preview = v2Preview {
                        backupPreview(title: "v2 全部卷校验通过", revision: preview.expectedRevision, scoreCount: preview.data.scores.count, attachmentCount: preview.assetCount, fileSize: preview.fileSize, detail: "Schema \(preview.manifest.schemaVersion) · \(preview.volumeCount) 卷 · \(preview.data.favorites.count) 收藏 · \(preview.data.practiceItems.count) 练习条目 · \(preview.data.sessions.count) 会话 · \(preview.data.projects.count) 工程")
                        HStack { Button("合并并恢复此备份", action: restoreV2).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy); Text("暂存附件须全部通过长度与 SHA-256 校验后，才会用单个事务提交。") .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())
            Text("备份只包含本机个人资料，不读取浏览器 IndexedDB 或浏览器 localStorage。请保留原备份文件；原生资料目录：\(model.userDataDirectory?.path ?? "初始化后显示")")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).textSelection(.enabled)
        }
        .onAppear { model.refreshPersonalData(); if let store { coordinator = BackupCoordinator(store: store) } }
        .onChange(of: model.personalSnapshot.revision) { _ in if let store { coordinator = BackupCoordinator(store: store) } }
        .onDisappear { restoreTask?.cancel() }
    }

    private func dataMetric(_ title: String, _ count: Int, _ symbol: String) -> some View {
        HStack(spacing: 9) { Image(systemName: symbol).foregroundStyle(MIMITheme.darkGold); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 10)).foregroundStyle(MIMITheme.mutedInk); Text(count.formatted()).font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(MIMITheme.ink) } }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
    }
    private func backupPreview(title: String, revision: Int, scoreCount: Int, attachmentCount: Int, fileSize: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "checkmark.seal.fill").font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.green)
            Text(detail).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk)
            Text("\(scoreCount) 份曲谱 · \(attachmentCount) 份附件 · \(String(format: "%.2f", Double(fileSize) / 1_048_576)) MiB · 预览基于本机 revision \(revision)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xEEF5ED), in: RoundedRectangle(cornerRadius: 12))
    }

    private func exportV1() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MIMI-Personal-Backup-v1.json"; panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        runTask("正在验证个人资料并生成 v1 JSON…") {
            let bytes = try await coordinator.exportV1()
            try bytes.write(to: destination, options: .atomic)
            await MainActor.run { notice = "完整 v1 备份已写入：\(destination.path)"; NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        }
    }
    private func exportV2() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSOpenPanel(); panel.title = "选择 v2 备份保存位置"; panel.prompt = "选择此文件夹"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        runTask("正在生成 v2 清单和分卷文件…") {
            let output = try await coordinator.exportV2(to: directory)
            await MainActor.run { notice = "v2 备份已写入 \(output.manifestURL.deletingLastPathComponent().path)，包含清单和 \(output.volumeURLs.count) 卷（\(String(format: "%.2f", Double(output.totalFileBytes) / 1_048_576)) MiB）。"; NSWorkspace.shared.activateFileViewerSelecting([output.manifestURL]) }
        }
    }
    private func previewV1() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSOpenPanel(); panel.title = "选择 v1 JSON 个人资料备份"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runTask("正在验证 JSON 摘要、实体和完整附件…") {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= PersonalBackupLimits.maximumV1BackupBytes else { throw PersonalBackupError.invalid("JSON 备份超过 64 MiB 上限，未读取或恢复。") }
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let preview = try await coordinator.previewV1(bytes)
            await MainActor.run { v1Preview = preview; v2Preview = nil; notice = nil }
        }
    }
    private func previewV2() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let manifestPanel = NSOpenPanel(); manifestPanel.title = "选择 v2 备份 JSON 清单"; manifestPanel.allowedContentTypes = [.json]; manifestPanel.canChooseDirectories = false; manifestPanel.allowsMultipleSelection = false
        guard manifestPanel.runModal() == .OK, let manifestURL = manifestPanel.url else { return }
        let volumePanel = NSOpenPanel(); volumePanel.title = "选择此清单对应的全部 MIMI2VOL 分卷"; volumePanel.allowedContentTypes = [UTType(filenameExtension: "mibak2") ?? .data]; volumePanel.canChooseDirectories = false; volumePanel.allowsMultipleSelection = true
        guard volumePanel.runModal() == .OK, !volumePanel.urls.isEmpty else { return }
        runTask("正在逐卷校验版本、长度和 SHA-256…") {
            let metadata = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
            guard let size = metadata[.size] as? NSNumber, size.intValue <= PersonalBackupLimits.maximumManifestBytes else { throw PersonalBackupError.invalid("v2 JSON 清单超过 64 MiB 上限。") }
            let bytes = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            let preview = try await coordinator.previewV2(manifest: bytes, volumeURLs: volumePanel.urls)
            await MainActor.run { v2Preview = preview; v1Preview = nil; notice = nil }
        }
    }
    private func restoreV1() {
        guard let coordinator, let preview = v1Preview else { return }
        runTask("正在以 revision \(preview.expectedRevision) 合并完整 v1 备份…") {
            _ = try await coordinator.restoreV1(preview, expectedRevision: preview.expectedRevision)
            await MainActor.run { v1Preview = nil; notice = "v1 备份已通过完整校验并合并提交；本机资料已更新。"; model.refreshPersonalData() }
        }
    }
    private func restoreV2() {
        guard let coordinator, let preview = v2Preview else { return }
        runTask("正在提交 v2 备份事务…") {
            _ = try await coordinator.restoreV2(preview, expectedRevision: preview.expectedRevision)
            await MainActor.run { v2Preview = nil; notice = "v2 备份已通过全部卷校验并合并提交；本机资料已更新。"; model.refreshPersonalData() }
        }
    }
    private func cancelV2Preview() {
        guard let coordinator, let preview = v2Preview else { v2Preview = nil; return }
        runTask("正在取消预览并清理暂存附件…") {
            try await coordinator.cancelV2Preview(preview)
            await MainActor.run { v2Preview = nil; notice = "v2 预览已取消，暂存附件已清理；本机资料未改变。" }
        }
    }
    private func runTask(_ status: String, operation: @escaping () async throws -> Void) {
        restoreTask?.cancel(); isBusy = true; progress = status; errorMessage = nil; notice = nil
        restoreTask = Task { @MainActor in
            defer { isBusy = false; progress = "" }
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct PaperGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) { configuration.label; configuration.content }
            .padding(18).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(MIMITheme.softBorder, lineWidth: 1))
    }
}

private struct PracticeDeskIllustration: View {
    var body: some View {
        ZStack {
            let outer = Path { path in
                path.move(to: CGPoint(x: 48, y: 174))
                path.addLine(to: CGPoint(x: 76, y: 34))
                path.addLine(to: CGPoint(x: 104, y: 34))
                path.addLine(to: CGPoint(x: 132, y: 174))
                path.closeSubpath()
            }
            outer.fill(Color(hex: 0xEBE1CF))
            outer.stroke(Color(hex: 0xC2AD8D), lineWidth: 1)

            let inner = Path { path in
                path.move(to: CGPoint(x: 56, y: 164))
                path.addLine(to: CGPoint(x: 80, y: 46))
                path.addLine(to: CGPoint(x: 100, y: 46))
                path.addLine(to: CGPoint(x: 124, y: 164))
                path.closeSubpath()
            }
            inner.fill(Color(hex: 0xFAF5EB))
            inner.stroke(Color(hex: 0xD8CAB4), lineWidth: 1)

            Path { path in
                path.move(to: CGPoint(x: 87, y: 154))
                path.addLine(to: CGPoint(x: 105, y: 47))
            }
            .stroke(Color(hex: 0x725C3B), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: 0x9C7743))
                .frame(width: 15, height: 24)
                .rotationEffect(.degrees(10))
                .position(x: 101.5, y: 87)

            Circle().fill(Color(hex: 0x755C37)).frame(width: 14, height: 14).position(x: 87, y: 154)

            Path { path in
                path.move(to: CGPoint(x: 70, y: 179))
                path.addLine(to: CGPoint(x: 110, y: 179))
            }
            .stroke(Color(hex: 0x755C37), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            Path { path in
                for (x, y) in [(70.0, 66.0), (67, 83), (64, 100), (61, 117), (58, 134)] {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + 12, y: y))
                }
            }
            .stroke(Color(hex: 0xD4C5AC), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 180, height: 200)
        .accessibilityHidden(true)
    }
}

struct ArticleListView: View {
    @EnvironmentObject private var model: AppModel
    var isSearchResults = false

    private var rows: [CatalogArticle] { isSearchResults ? model.searchArticles : model.articles }
    private var title: String { isSearchResults ? "文章搜索结果" : "文章" }
    private var pageCount: Int { max(1, Int(ceil(Double(model.articleTotal) / 9))) }
    private var searchQuery: String { isSearchResults ? model.searchText : model.articleSearch }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Editorial · Notes")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .tracking(2.6).foregroundStyle(Color(hex: 0x8A7151))
                Text(title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
                Text("从零基础入门到进阶技巧，把练琴路上的经验整理成一篇篇短文。")
                    .font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560, alignment: .leading)
                HStack(spacing: 12) {
                    if isSearchResults {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
                            TextField("搜索文章标题或正文", text: $model.searchText)
                                .textFieldStyle(.plain).onSubmit { model.searchArticlesDidChange() }
                        }
                        .padding(.horizontal, 14).frame(width: 300, height: 44)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }
                    articleSortControl
                    Spacer(minLength: 8)
                    if model.articleListIsLoading { ProgressView().controlSize(.small) }
                    Button { model.navigate(.publishArticle) } label: { Label("发布文章", systemImage: "square.and.pencil") }
                        .buttonStyle(PaperProminentButtonStyle())
                }
                .padding(.top, 12)
            }
            .padding(.bottom, 32)
            .overlay(alignment: .bottom) { Rectangle().fill(MIMITheme.softBorder).frame(height: 1) }
            if let message = model.articleListMessage {
                HStack(alignment: .top, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.terracotta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("重试") { retryArticleList() }
                        .buttonStyle(PaperSecondaryButtonStyle()).disabled(model.articleListIsLoading)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(MIMITheme.terracotta.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.terracotta.opacity(0.2), lineWidth: 1))
                .accessibilityElement(children: .contain).padding(.top, 20)
            }
            if model.articleListIsLoading && rows.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("正在载入文章…").font(MIMITheme.bodyFont(size: 13, weight: .medium))
                    Text("正在读取本机文章索引。网络发布功能使用单独的账号服务。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                }.frame(maxWidth: .infinity, minHeight: 160).mimiCard(radius: 24, fill: MIMITheme.paperWhite).padding(.top, 32)
            } else if rows.isEmpty && model.articleListMessage == nil {
                Text(searchQuery.isEmpty ? "文章整理中，敬请期待" : "没有找到相关文章")
                    .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.mutedInk)
                    .frame(maxWidth: .infinity, minHeight: 160).mimiCard(radius: 24, fill: MIMITheme.paperWhite).padding(.top, 32)
            } else if !rows.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 17), GridItem(.flexible(), spacing: 17), GridItem(.flexible(), spacing: 17)], spacing: 17) {
                    ForEach(rows) { article in articleCard(article) }
                }.padding(.top, 32)
            }
            if pageCount > 1 {
                HStack(spacing: 9) {
                    if model.articlePage > 1 {
                        Button("上一页") { model.setArticlePage(model.articlePage - 1) }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                    ForEach(1...pageCount, id: \.self) { page in
                        Button("\(page)") { model.setArticlePage(page) }.buttonStyle(PageNumberStyle(selected: model.articlePage == page))
                    }
                    if model.articlePage < pageCount {
                        Button("下一页") { model.setArticlePage(model.articlePage + 1) }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                }.frame(maxWidth: .infinity).padding(.top, 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            if !isSearchResults { model.loadArticles(immediately: true) }
        }
        .onChange(of: model.articleSort) { _ in model.articleSortDidChange() }
        .onChange(of: model.searchText) { _ in if isSearchResults { model.searchArticlesDidChange() } }
        .onChange(of: model.articleSearch) { _ in if !isSearchResults { model.searchArticlesDidChange() } }
    }

    private var articleSortControl: some View {
        HStack(spacing: 8) {
            articleSortChip("最新", sort: .newest)
            articleSortChip("最热", sort: .popular)
        }
    }

    private func articleSortChip(_ label: String, sort: CatalogArticleSort) -> some View {
        let selected = model.articleSort == sort
        return Button(label) { model.articleSort = sort }
            .font(MIMITheme.bodyFont(size: 13, weight: .medium))
            .foregroundStyle(selected ? Color(hex: 0xFBFAF7) : MIMITheme.bodyInk)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? MIMITheme.navigationInk : MIMITheme.paperWhite, in: Capsule())
            .overlay(Capsule().stroke(selected ? MIMITheme.navigationInk : MIMITheme.softBorder, lineWidth: 1))
            .buttonStyle(.plain)
    }

    private func articleCard(_ article: CatalogArticle) -> some View {
        Button { model.navigate(.article(id: article.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(article.category ?? "乐谱知识") · \(articleDate(article.createdAt)) · \(articleHeat(article.views)) 热度")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                Text(article.title).font(MIMITheme.displayFont(size: 19, weight: .medium)).tracking(-0.19).foregroundStyle(MIMITheme.ink).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Text(articleExcerpt(article.content)).font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.bodyInk).lineLimit(3).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .topLeading).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(MIMITheme.softBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private func articleDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "日期未标注" }
        return String(value.prefix(10))
    }

    private func articleHeat(_ views: Int) -> String {
        guard views >= 10_000 else { return String(views) }
        return String(format: "%.1f万", locale: Locale(identifier: "en_US_POSIX"), Double(views) / 10_000)
    }

    private func articleExcerpt(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "[\\r\\n]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(96)) + "…"
    }

    private func retryArticleList() {
        if model.bootstrapMessage != nil || model.contentRoot == nil { model.retryBootstrap() }
        else if isSearchResults { model.searchArticlesDidChange() }
        else { model.loadArticles(immediately: true) }
    }
}

struct ArticleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let articleID: String
    var body: some View {
        Group {
            if let article = model.selectedArticle, article.id == articleID {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(article.category ?? "乐谱知识") · \(articleDate(article.createdAt))")
                        .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                    Text(article.title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    Divider().overlay(MIMITheme.softBorder).padding(.top, 24).padding(.bottom, 32)
                    Text(article.content).font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.bodyInk)
                        .lineSpacing(12).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Divider().overlay(MIMITheme.softBorder).padding(.top, 40).padding(.bottom, 24)
                    HStack(spacing: 10) {
                        Button { returnToArticleList() } label: { Label("返回文章列表", systemImage: "arrow.left") }.buttonStyle(PaperSecondaryButtonStyle())
                        Button("分享文章") { shareArticle(article) }.buttonStyle(PaperSecondaryButtonStyle())
                        Button("复制标题") { copyArticleTitle(article.title) }.buttonStyle(PaperSecondaryButtonStyle())
                        Spacer()
                        Text("MIMI Guitar").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .padding(40).frame(maxWidth: .infinity, alignment: .leading)
                .mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE5E5E5), shadowOpacity: 0.025)
            } else if model.articleDetailIsLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在载入文章…").font(MIMITheme.bodyFont(size: 13, weight: .medium))
                    Text("文章正文正在从本机索引读取。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                }.frame(maxWidth: .infinity, minHeight: 240).mimiCard(fill: MIMITheme.paperWhite)
            } else if let message = model.articleDetailMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 25)).foregroundStyle(MIMITheme.terracotta)
                    Text("文章暂时无法载入").font(MIMITheme.displayFont(size: 20, weight: .semibold))
                    Text(message).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).multilineTextAlignment(.center).textSelection(.enabled)
                    HStack(spacing: 9) {
                        Button("重试") { retryArticle() }.buttonStyle(PaperProminentButtonStyle())
                        Button("返回文章列表") { returnToArticleList() }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                }.frame(maxWidth: .infinity, minHeight: 280).mimiCard(fill: MIMITheme.paperWhite)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "text.book.closed").font(.system(size: 28, weight: .light)).foregroundStyle(MIMITheme.warmGold)
                    Text("未找到这篇文章").font(MIMITheme.displayFont(size: 20, weight: .semibold))
                    Text("请检查文章编号，或返回文章列表重新选择。")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    Button("返回文章列表") { returnToArticleList() }.buttonStyle(PaperSecondaryButtonStyle())
                }.frame(maxWidth: .infinity, minHeight: 280).mimiCard(fill: MIMITheme.paperWhite)
            }
        }.onAppear { if model.selectedArticle?.id != articleID { model.loadArticle(id: articleID) } }
    }

    private func articleDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "日期未标注" }
        return String(value.prefix(10))
    }

    private func returnToArticleList() {
        if model.canNavigateBack { model.navigateBack() }
        else { model.navigate(.articles) }
    }

    private func retryArticle() {
        if model.bootstrapMessage != nil || model.contentRoot == nil { model.retryBootstrap() }
        else { model.loadArticle(id: articleID) }
    }

    private func shareArticle(_ article: CatalogArticle) {
        guard let url = model.articleShareURL(id: article.id) else {
            model.presentAlert(title: "分享地址不可用", message: "当前文章服务地址无效或尚未配置，无法生成文章链接。你仍可复制标题后手动分享。")
            return
        }
        guard let content = NSApp.keyWindow?.contentView else {
            model.presentAlert(title: "无法打开分享面板", message: "当前窗口不可用，请稍后重试，或使用“复制标题”。")
            return
        }
        let picker = NSSharingServicePicker(items: [article.title, url])
        picker.show(relativeTo: content.bounds, of: content, preferredEdge: .minY)
    }

    private func copyArticleTitle(_ title: String) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(title, forType: .string) {
            model.presentAlert(title: "文章标题已复制", message: "可以粘贴分享文章标题。")
        } else {
            model.presentAlert(title: "无法复制文章标题", message: "剪贴板暂时不可用，请重试。")
        }
    }
}

struct PublishArticleView: View {
    @EnvironmentObject private var model: AppModel
    private var titleValid: Bool { !model.articleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.articleTitle.count <= 100 }
    private var bodyValid: Bool { model.articleContent.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaperPageHeader(eyebrow: "Editorial · Publish", title: "发布文章", subtitle: "把练琴心得、乐理笔记或曲谱解析分享给更多琴友。")
            if model.remoteUser == nil {
                VStack(spacing: 13) { Text("发布文章需要登录").font(MIMITheme.displayFont(size: 20, weight: .semibold)); Button("去登录") { model.navigate(.login) }.buttonStyle(PaperProminentButtonStyle()) }.frame(maxWidth: .infinity, minHeight: 180).mimiCard(fill: MIMITheme.paperWhite)
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    labeledInput("标题", hint: "文章标题，最多 100 个字符") { TextField("文章标题", text: $model.articleTitle).textFieldStyle(.roundedBorder).onChange(of: model.articleTitle) { if $0.count > 100 { model.articleTitle = String($0.prefix(100)) } } }
                    labeledInput("分类", hint: "如：入门 / 乐理 / 技巧") { Picker("分类", selection: $model.articleCategory) { ForEach(["技巧", "入门", "乐理", "曲谱解析", "练习心得", "资讯"], id: \.self) { Text($0).tag($0) } }.frame(width: 220) }
                    VStack(alignment: .leading, spacing: 6) { Text("内容").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); Text("支持 Markdown 排版，段落用空行分隔。正文至少 10 个字符。").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk); TextEditor(text: $model.articleContent).font(MIMITheme.bodyFont(size: 13)).frame(minHeight: 260).padding(6).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1)) }
                    if let message = model.accountMessage { PaperNotice(text: message, error: model.accountMessageIsError) }
                    HStack { Button("发布") { model.publishArticle() }.buttonStyle(PaperProminentButtonStyle()).disabled(!titleValid || !bodyValid || model.articleBusy); if model.articleBusy { ProgressView().controlSize(.small) }; Button("取消") { model.navigate(.articles) }.buttonStyle(PaperSecondaryButtonStyle()) }
                    Text("发布会向已配置的真实文章 API 发送内容；失败时保留草稿并显示服务器错误。不会生成伪成功状态。")
                        .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                }.padding(22).mimiCard(radius: 20, fill: MIMITheme.paperWhite)
            }
        }.frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
    }
    private func labeledInput<Content: View>(_ label: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(MIMITheme.bodyFont(size: 12, weight: .semibold)); content(); Text(hint).font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk) }
    }
}

struct AccountAuthView: View {
    @EnvironmentObject private var model: AppModel
    private var isRegister: Bool {
        switch model.route {
        case .register: return true
        case .authenticationReturn(_, let isRegistration): return isRegistration
        default: return false
        }
    }
    private var isReset: Bool { if case .resetPassword = model.route { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(isReset ? "Reset" : isRegister ? "Sign up" : "Sign in").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(MIMITheme.mutedInk)
            Text(isReset ? "重置密码" : isRegister ? "注册 MIMI Guitar" : "登录 MIMI Guitar").font(MIMITheme.displayFont(size: 28, weight: .bold)).foregroundStyle(MIMITheme.ink)
            Text(isReset ? "密码重置需要短信验证码服务。当前环境尚未配置真实短信服务，因此此功能暂不可用。" : isRegister ? "使用手机号或邮箱注册，登录后可使用收藏与文章发布。公开曲谱投稿当前暂停。" : "登录后可收藏曲谱、同步浏览记录与上传作品。公开曲谱投稿当前暂停；本机个人资料仍独立保存在本地。")
                .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)

            if isReset {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 5) { Text("手机号").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("输入手机号", text: $model.resetPhone).textFieldStyle(.roundedBorder) }
                    HStack(spacing: 9) { TextField("短信验证码", text: $model.resetCode).textFieldStyle(.roundedBorder); Button("发送验证码") { model.sendResetCode() }.buttonStyle(PaperSecondaryButtonStyle()).disabled(model.accountBusy) }
                    VStack(alignment: .leading, spacing: 5) { Text("新密码").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); SecureField("设置新密码", text: $model.resetPasswordValue).textFieldStyle(.roundedBorder) }
                    Text("当前服务返回 503 时会如实显示短信服务未配置，不会填入或伪造验证码。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    HStack { Button("重置密码") { model.resetPassword() }.buttonStyle(PaperProminentButtonStyle()).disabled(model.accountBusy || model.resetPhone.isEmpty || model.resetCode.isEmpty || model.resetPasswordValue.isEmpty); if model.accountBusy { ProgressView().controlSize(.small) } }
                }
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(alignment: .leading, spacing: 5) { Text("手机号或邮箱").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("手机号或邮箱", text: $model.authAccount).textContentType(.username).textFieldStyle(.roundedBorder) }
                    if isRegister { VStack(alignment: .leading, spacing: 5) { Text("昵称").font(MIMITheme.bodyFont(size: 12, weight: .semibold)); TextField("设置昵称", text: $model.authNickname).textFieldStyle(.roundedBorder) } }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("密码").font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                        if isRegister {
                            SecureField("密码", text: $model.authPassword).textFieldStyle(.roundedBorder).onSubmit { submit() }
                        } else {
                            SecureField("密码", text: $model.authPassword).textContentType(.password).textFieldStyle(.roundedBorder).onSubmit { submit() }
                        }
                    }
                    if let message = model.accountMessage { PaperNotice(text: message, error: model.accountMessageIsError) }
                    HStack(spacing: 11) {
                        Button(isRegister ? "注册" : "登录", action: submit).buttonStyle(PaperProminentButtonStyle()).disabled(model.accountBusy || model.authAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.authPassword.isEmpty || (isRegister && model.authNickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        if model.accountBusy { ProgressView().controlSize(.small) }
                        Spacer()
                        if !isRegister { Button("忘记密码？") { model.navigate(.resetPassword) }.buttonStyle(.plain).foregroundStyle(MIMITheme.darkGold) }
                    }
                    HStack(spacing: 5) { Text(isRegister ? "已有账号？" : "还没有账号？").foregroundStyle(MIMITheme.mutedInk); Button(isRegister ? "去登录" : "立即注册") { model.navigate(isRegister ? .login : .register) }.buttonStyle(.plain).foregroundStyle(MIMITheme.darkGold) }.font(MIMITheme.bodyFont(size: 12))
                }
            }
            Divider().overlay(MIMITheme.softBorder)
            HStack(alignment: .top, spacing: 8) { Image(systemName: "lock.shield").foregroundStyle(MIMITheme.darkGold); Text("账号会话令牌保存在 macOS 钥匙串。HTTP 仅允许 localhost / IPv4 loopback / ::1，其他账号服务必须使用 HTTPS。退出账号不会删除本机收藏、练习或导入曲谱。") }
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        }
        .padding(32).frame(maxWidth: 448, alignment: .leading).mimiCard(radius: 22, fill: MIMITheme.paperWhite)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    private func submit() { if isRegister { model.register() } else { model.login() } }
}

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    let area: AccountArea
    @State private var clearedHistory: [PersonalHistoryEntry]?
    @State private var historyMessage: String?
    @State private var isClearingHistory = false
    @State private var favoritesMessage: String?
    @State private var favoritesMessageIsError = false
    @State private var isRemovingLocalFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text(area.title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
                Spacer()
                if area == .favorites {
                    Button("继续找谱") { model.navigate(.catalog(.all)) }
                        .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.signalBlue).buttonStyle(.plain)
                }
            }
            accountNavigation
            if let message = model.accountMessage { PaperNotice(text: message, error: model.accountMessageIsError) }
            switch area {
            case .favorites: favoritesPanel
            case .creator: creatorPanel
            case .history: historyPanel
            case .profile: profilePanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear { model.loadAccount(area: area) }
    }

    private var accountNavigation: some View {
        HStack(spacing: 4) {
            ForEach(AccountArea.allCases) { candidate in
                Button(candidate.title) { model.navigate(.account(candidate)) }
                    .font(MIMITheme.bodyFont(size: 14, weight: candidate == area ? .medium : .regular))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(candidate == area ? Color(hex: 0xEDE5D8) : .clear, in: RoundedRectangle(cornerRadius: 18))
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            Button("上传") { model.navigate(.upload) }.buttonStyle(PaperSecondaryButtonStyle())
            if model.remoteUser != nil {
                Button(model.accountBusy ? "退出中…" : "退出登录") { model.logout() }
                    .buttonStyle(PaperSecondaryButtonStyle()).disabled(model.accountBusy)
            }
        }
        .padding(8)
        .mimiCard(radius: 24, fill: MIMITheme.paperWhite, border: Color(hex: 0xE5E5E5), shadowOpacity: 0.025)
    }
    private var favoritesPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { PaperSectionTitle(title: "本设备收藏", detail: "与“我的谱”使用同一份本地个人资料，并包含在个人备份中。") ; Spacer(); Button("打开我的谱") { model.selectSection(.favorites) }.buttonStyle(PaperSecondaryButtonStyle()) }
            if let favoritesMessage { PaperNotice(text: favoritesMessage, error: favoritesMessageIsError) }
            let localFavorites = model.personalScores.filter { model.personalSnapshot.favorites.contains($0.id) }
            if localFavorites.isEmpty {
                Text("还没有本设备收藏的曲谱。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            }
            ForEach(localFavorites) { score in
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(MIMITheme.terracotta)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(score.title).font(MIMITheme.bodyFont(size: 14, weight: .semibold))
                        Text(score.source == "catalog" ? "\(score.artist) · \(score.category == "ukulele" ? "尤克里里" : "曲库") · 本设备引用" : "\(score.artist) · 个人谱 · 本设备")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    Spacer()
                    Button("打开") { model.openPersonalScore(score) }.buttonStyle(PaperSecondaryButtonStyle())
                    Button("取消收藏", role: .destructive) { removeLocalFavorite(score) }
                        .buttonStyle(PaperSecondaryButtonStyle()).disabled(isRemovingLocalFavorite)
                }
                .padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }

            HStack { PaperSectionTitle(title: "旧版云端收藏", detail: model.remoteUser == nil ? "登录后读取账号数据库中的旧收藏。" : "这些条目不会自动迁入本机收藏，两类收藏分别管理。") ; Spacer(); if model.accountBusy { ProgressView().controlSize(.small) } }
            if model.remoteUser == nil {
                accountRequired("登录后查看服务器中的旧收藏。", returnArea: .favorites)
            } else if model.remoteFavorites.isEmpty && !model.accountBusy {
                Text("服务器没有可读取的旧收藏。若服务不可用，错误会显示在页面上；空列表不代表本机收藏已删除。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            }
            ForEach(model.remoteFavorites) { favorite in
                let local = model.personalSnapshot.favorites.contains("catalog:\(favorite.id)") || model.personalSnapshot.favorites.contains(favorite.id)
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(MIMITheme.terracotta)
                    VStack(alignment: .leading, spacing: 3) { Text(favorite.title).font(MIMITheme.displayFont(size: 17, weight: .semibold)); Text("\(favorite.artist ?? "未知演奏者") · \(favorite.category) · \(favorite.key ?? "调性未标注") · 热度 \(favorite.heat.formatted())").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    Spacer()
                    Button(local ? "已在本机收藏" : "迁入本机") { model.migrateRemoteFavorite(favorite) }.buttonStyle(PaperSecondaryButtonStyle()).disabled(local || model.accountBusy)
                    Button("从服务器取消") { model.removeRemoteFavorite(favorite) }.buttonStyle(.bordered).disabled(model.accountBusy)
                }.padding(15).mimiCard(radius: 15, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }
        }.padding(18).mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var creatorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.remoteUser == nil { accountRequired("登录后查看创作中心。", returnArea: .creator) }
            VStack(alignment: .leading, spacing: 10) {
                PaperSectionTitle(title: "公开投稿已暂停")
                Text("首期提供个人练习和本地曲谱导入。上传与审核 API 会返回“暂未开放”，不会把模拟审核标记为公开成功。之前的投稿记录会保留；此页面不再提供修改或审核入口。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
                HStack(spacing: 9) { Button("前往“我的谱”本地导入") { model.navigate(.library) }.buttonStyle(PaperProminentButtonStyle()); Button("查看数据与备份") { model.navigate(.dataSettings) }.buttonStyle(PaperSecondaryButtonStyle()) }
                Text("历史投稿计数由旧服务页面提供；当前原生快照不伪造服务器计数。若账号服务不可用，请检查错误提示。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            }.padding(32).frame(maxWidth: 576, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }
    }
    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { PaperSectionTitle(title: "最近打开", detail: "浏览记录保存在本机个人资料中；这里只显示当前设备的记录。") ; Spacer()
                if let clearedHistory { Button("撤销清空（\(clearedHistory.count) 条）") { restoreHistory(clearedHistory) }.buttonStyle(PaperSecondaryButtonStyle()) }
                else { Button(isClearingHistory ? "正在清空…" : "清空浏览记录", role: .destructive) { clearHistory() }.buttonStyle(.bordered).disabled(isClearingHistory || model.recentEntries.isEmpty) }
            }
            if let historyMessage { PaperNotice(text: historyMessage, error: historyMessage.contains("失败")) }
            if model.recentEntries.isEmpty { Text("本机还没有浏览记录。清空历史后，可在这里撤销恢复刚才清除的记录。")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).padding(20).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            } else { ForEach(model.recentEntries) { entry in
                HStack(spacing: 12) { Image(systemName: "clock.arrow.circlepath").foregroundStyle(MIMITheme.darkGold); VStack(alignment: .leading, spacing: 3) { Text(entry.title).font(MIMITheme.bodyFont(size: 14, weight: .semibold)); Text("\(entry.artist ?? "") · \(Date(timeIntervalSince1970: entry.time / 1000).formatted(date: .abbreviated, time: .shortened))").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk) }; Spacer(); Button("打开") { if let score = model.personalScores.first(where: { $0.id == entry.id || $0.sourceId == entry.id || $0.id == "catalog:\(entry.id)" }) { model.openPersonalScore(score) } else { model.navigate(.score(id: entry.id.hasPrefix("catalog:") ? String(entry.id.dropFirst("catalog:".count)) : entry.id)) } }.buttonStyle(PaperSecondaryButtonStyle()) }
                    .padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            } }
        }.padding(18).mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = model.remoteUser {
                HStack(spacing: 15) { Text((user.nickname ?? user.email ?? user.phone ?? "U").prefix(1).uppercased()).font(MIMITheme.displayFont(size: 26, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).frame(width: 64, height: 64).background(Color(hex: 0xF5F0E6), in: Circle()); VStack(alignment: .leading, spacing: 3) { Text(user.nickname ?? "未设置昵称").font(MIMITheme.displayFont(size: 21, weight: .semibold)); Text(user.email ?? user.phone ?? "未绑定手机/邮箱").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }; Spacer(); if model.accountBusy { ProgressView().controlSize(.small) } }
                HStack(spacing: 30) { labeledValue("账号类型", user.email == nil ? "手机账号" : "邮箱账号"); labeledValue("注册时间", user.createdAt ?? "-"); labeledValue("本机资料", "独立保存") }
                Text("退出只清除此服务的会话令牌，不会删除本机个人资料、收藏、练习记录、工程或备份。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            } else { accountRequired("登录后查看个人资料。", returnArea: .profile) }
        }.padding(32).frame(maxWidth: 576, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }
    private func accountRequired(_ text: String, returnArea: AccountArea) -> some View {
        VStack(spacing: 11) { Text(text).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk); HStack { Button("去登录") { model.navigate(.login) }.buttonStyle(PaperProminentButtonStyle()); Button("注册") { model.navigate(.register) }.buttonStyle(PaperSecondaryButtonStyle()) } }.frame(maxWidth: .infinity, minHeight: 110)
    }
    private func removeLocalFavorite(_ score: PersonalScore) {
        guard !isRemovingLocalFavorite, let store = model.personalStore else { return }
        isRemovingLocalFavorite = true
        favoritesMessage = nil
        Task { @MainActor in
            defer { isRemovingLocalFavorite = false }
            do {
                try await store.toggleFavorite(score.id)
                favoritesMessageIsError = false
                favoritesMessage = "已从本设备收藏移除。"
                model.personalDataDidChange()
            } catch {
                favoritesMessageIsError = true
                favoritesMessage = "取消收藏失败：\(error.localizedDescription)"
            }
        }
    }
    private func labeledValue(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(label).font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk); Text(value).font(MIMITheme.bodyFont(size: 12, weight: .medium)) } }
    private func clearHistory() {
        guard let store = model.personalStore else { return }; let old = model.personalSnapshot.history; isClearingHistory = true; historyMessage = nil
        Task { @MainActor in defer { isClearingHistory = false }; do { var data = try await store.snapshot(); data.history = []; _ = try await store.commit(data, expectedRevision: data.revision); clearedHistory = old; historyMessage = "已清空 \(old.count) 条浏览记录；曲谱和练习内容保留。"; model.personalDataDidChange() } catch { historyMessage = "清空失败：\(error.localizedDescription)" } }
    }
    private func restoreHistory(_ old: [PersonalHistoryEntry]) {
        guard let store = model.personalStore else { return }
        Task { @MainActor in do { var data = try await store.snapshot(); data.history = old; _ = try await store.commit(data, expectedRevision: data.revision); clearedHistory = nil; historyMessage = "已恢复清空前的浏览记录。"; model.personalDataDidChange() } catch { historyMessage = "恢复失败：\(error.localizedDescription)" } }
    }
}

private struct DocumentSection: Identifiable {
    let heading: String
    let body: String
    var id: String { heading }
}

struct DocumentPageView: View {
    @EnvironmentObject private var model: AppModel
    let page: DocumentPage

    private var sections: [DocumentSection] {
        switch page {
        case .privacy: return [
            .init(heading: "引言", body: "我们非常重视你的隐私与个人信息保护。本政策说明 MIMI Guitar（下称\"本站\"）在提供服务过程中可能收集的信息、使用方式以及你的相关权利。"),
            .init(heading: "一、我们可能收集的信息", body: "在未登录状态下，本站可以正常浏览与播放全部曲谱，不要求提供任何个人信息。仅当你使用收藏、浏览记录同步、上传等功能时，可能涉及账号信息（邮箱或手机号、昵称、头像）与操作记录（收藏列表、上传记录）。"),
            .init(heading: "二、信息收集的用途及使用规则", body: "我们收集的信息仅用于：提供并优化曲谱浏览与播放服务、保存你的收藏与上传记录、在你请求时与你联系。浏览记录默认保存在你的本地设备（浏览器 localStorage）中，不会上传服务器。原生 Mac 版本的个人资料保存在本机应用支持目录，不会读取浏览器资料。"),
            .init(heading: "三、信息的共享、转让及披露", body: "我们不会出售你的个人信息。除法律法规要求、或为保障本站运行所必需的服务提供商外，我们不会向第三方共享你的个人信息。"),
            .init(heading: "四、我们的信息安全保护", body: "我们采用合理的技术与管理措施保护信息存储安全，包括密码哈希存储、传输加密等。但请注意，任何网络传输与存储方式都无法保证绝对安全。"),
            .init(heading: "五、未成年人信息保护", body: "若你为未成年人，请在监护人指导下使用本站。我们不会主动收集未成年人的个人信息。"),
            .init(heading: "六、免责条款", body: "本站为学习与演示用途的复刻项目，所展示曲谱内容来自公开渠道迁移的演示数据。因使用本站内容产生的任何直接或间接损失，本站不承担相应责任。"),
            .init(heading: "七、本政策的适用范围", body: "本政策适用于本站提供的全部页面与服务。若本站接入第三方服务，其隐私规则以第三方公示为准。"),
            .init(heading: "八、如何联系我们", body: "如对本政策有任何疑问，或希望查询、更正、删除你的个人信息，请通过「联系我们」页面与我们取得联系。"),
        ]
        case .agreement: return [
            .init(heading: "一、服务说明", body: "本站（MIMI Guitar）为「谱全了」guistudy.com 的全站功能复刻学习项目，提供吉他谱与尤克里里谱的浏览、显示、在线播放与上传等服务。注册并使用本站服务，即表示你已阅读、理解并同意本协议的全部条款。"),
            .init(heading: "二、账号与安全", body: "你应妥善保管账号密码，并对其名下账号产生的全部行为负责。若发现账号被他人盗用或存在安全漏洞，请及时通过「联系我们」告知我们。"),
            .init(heading: "三、内容与版权", body: "站内曲谱内容来自公开渠道迁移的演示数据，著作权归原作者与上传者所有。上传者应保证其上传内容不侵犯第三方合法权益；如涉及侵权，我们将在核实后依法处理。"),
            .init(heading: "四、用户行为规范", body: "不得利用本站从事任何违反法律法规或损害他人权益的行为，包括但不限于：上传违法内容、批量抓取数据、攻击服务器、滥用下载或播放接口等。"),
            .init(heading: "五、服务的变更与中断", body: "我们可能根据需要对服务内容、功能进行调整，或对服务进行维护。因维护、升级、不可抗力等原因导致服务中断的，本站不承担由此产生的责任。"),
            .init(heading: "六、免责声明", body: "本站为学习与演示用途的项目，不对内容的准确性、完整性与可用性作出任何明示或默示的保证。因使用本站内容产生的损失，本站不承担相应责任。"),
            .init(heading: "七、协议的修改", body: "我们可能适时修订本协议，修订后的协议将在本站公布。继续使用本站服务即视为接受修订后的协议。"),
            .init(heading: "八、争议解决", body: "因本协议产生的争议，双方应友好协商解决；协商不成的，依法向有管辖权的人民法院提起诉讼。"),
        ]
        case .copyright: return [
            .init(heading: "版权声明", body: "本站（MIMI Guitar）为学习与演示用途的复刻项目。站内曲谱数据来源于对公开网站 guistudy.com（谱全了）热门曲谱子集的迁移，仅用于功能研究、开发学习与非商业演示。曲谱及录音的著作权归原作者、原权利人所有。"),
            .init(heading: "侵权告知", body: "如果你认为本站展示的任何内容侵犯了你的合法权益，请向我们提供以下信息以便核查：权利人的身份证明、被侵权内容的链接与描述、你的联系方式。我们将在核实后尽快处理，包括对相关内容进行下架或标注。"),
            .init(heading: "投诉渠道", body: "请通过「联系我们」页面提交侵权投诉，或直接发送邮件至站内公示的联系邮箱，主题请注明「版权投诉」。"),
            .init(heading: "商用前须知", body: "本站当前为本地开发与学习演示版本。若计划将本项目用于正式商用，必须替换为已获得授权的内容，或与版权方签署相应授权协议；否则由此产生的法律风险由使用者自行承担。"),
        ]
        case .uploadPolicy: return [
            .init(heading: "一、可上传的内容", body: "本站支持上传 Guitar Pro 格式曲谱文件（.gp3 / .gp4 / .gp5 / .gpx / .gp），并自动解析谱面、生成可在线播放的谱面文件与首屏预览图。"),
            .init(heading: "二、上传者声明", body: "上传即表示你声明并保证：你对上传内容拥有相应权利，或已获得权利人的合法授权；上传内容不侵犯任何第三方的著作权、商标权、隐私权等合法权益。"),
            .init(heading: "三、审核机制", body: "上传作品将先进入「审核中」状态，经审核通过后方可公开展示。我们保留拒绝、下架或删除任何不符合本政策内容的权利。"),
            .init(heading: "四、禁止内容", body: "禁止上传以下内容：违法或侵权内容、恶意代码或病毒、批量灌水与重复内容、与音乐谱面无实质关系的内容等。"),
            .init(heading: "五、侵权处理", body: "如权利人认为某上传内容侵犯其权益，可通过「联系我们」页面提交投诉。我们将在核实后下架相关内容，并视情况对上传者账号作出处理。"),
            .init(heading: "六、免责说明", body: "本站为学习与演示用途的复刻项目，上传内容的版权责任由上传者自行承担。因上传内容引发的纠纷，本站不承担相应责任。"),
        ]
        case .help: return [
            .init(heading: "如何查找乐谱", body: "在首页排行榜或「吉他谱」「尤克里里」列表中浏览；也可以使用顶部的筛选（难度、调性、调弦、谱型、排序）缩小范围，或在搜索框输入曲名 / 艺人直接检索。"),
            .init(heading: "如何播放乐谱", body: "进入曲谱详情页，播放器会自动加载谱面。点击播放按钮即可试听，支持变速、节拍器、预备拍、变调夹、循环区间、音轨混音等控制。"),
            .init(heading: "如何打印乐谱", body: "使用播放器的「打印」功能，会重新渲染纯谱面并打开 macOS 打印面板；选择打印机或保存为 PDF。"),
            .init(heading: "如何保存乐谱为 PDF", body: "使用播放器的「PDF」按钮，谱面将按页面导出为 PDF，并通过保存面板选择位置；只有写入成功后才会报告成功。"),
            .init(heading: "乐谱难度如何划分", body: "难度分为零基础、初级、中级、高级、专业五档，对应 1 到 5 级。零基础适合刚接触吉他的新手，专业级通常包含复杂技巧或原版编配。"),
            .init(heading: "为什么有些谱没有难度标注", body: "部分曲谱在上传时未提供难度信息，这类谱在列表中不会显示难度标签，不影响查看与播放。"),
            .init(heading: "下载或播放遇到问题怎么办", body: "请先重试加载本地谱面；若曲库资源缺失，请打开「联系我们」页面查看反馈渠道。原生版本的账号服务需要配置有效地址。"),
        ]
        default: return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: page == .help ? 32 : 21) {
            PaperPageHeader(eyebrow: eyebrow, title: page.title, subtitle: introductoryText)
            if page == .about { aboutContent }
            else if page == .contact { contactContent }
            else if page == .licenses { licensesContent }
            else { policyContent }
            HStack(spacing: 9) {
                if page != .help { documentButton("帮助中心", .help) }
                if page != .contact { documentButton("联系我们", .contact) }
                if page != .uploadPolicy { documentButton("上传政策", .uploadPolicy) }
                if page != .licenses { documentButton("授权说明", .licenses) }
            }.padding(.top, 4)
        }
        .frame(maxWidth: page == .help ? 768 : 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
    }

    private var eyebrow: String {
        switch page { case .help: return "Help"; case .about: return "About"; case .privacy: return "Privacy"; case .agreement: return "Agreement"; case .copyright: return "Copyright"; case .licenses: return "Licenses"; case .contact: return "Contact"; case .uploadPolicy: return "Upload Policy" }
    }
    private var introductoryText: String {
        switch page {
        case .about: return "MIMI Guitar 是一个吉他与尤克里里专属的乐谱网站：在这里，你可以浏览、搜索海量曲谱，在线查看六线谱与和弦谱，并直接播放试听，跟练自己喜欢的歌曲。原生 Mac 版将个人收藏、练习与备份保存在本机。"
        case .licenses: return "本项目基于多个开源项目构建，以下为本项目依赖的主要开源组件及其许可证。请在使用与分发时遵守相应许可证条款。"
        case .contact: return "欢迎提供播放、下载、搜索问题反馈与功能建议；版权事项请注明「版权」或「商务」。"
        case .uploadPolicy: return "以下保留原站上传政策正文。Mac 原生版本的公开投稿入口维持关闭，本地个人曲谱导入不属于公开投稿。"
        case .privacy: return ""
        case .agreement: return ""
        case .copyright: return ""
        case .help: return ""
        }
    }
    private var policyContent: some View {
        VStack(alignment: .leading, spacing: page == .help ? 24 : 15) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    Text(section.heading).font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text(section.body).font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                }.padding(page == .help ? 24 : 17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 17, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
            }
            if page == .uploadPolicy { PaperNotice(text: "公开曲谱投稿当前暂停。上方原文保留为来源政策说明，不代表原生应用接受或提交投稿。") }
        }
    }
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("本站是「谱全了」（guistudy.com）的功能复刻学习项目，采用其核心的产品形态与交互逻辑，并套用 refero「General Intelligence Company」编辑风设计系统重新落地视觉。项目从零实现了曲谱数据管线、在线播放器、排行榜、筛选排序、搜索、文章等内容。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(6)
            PaperSectionTitle(title: "核心能力")
            ForEach(["吉他谱 / 尤克里里谱：弹唱谱、指弹谱、和弦谱、六线谱", "在线播放：高亮同步、自动滚动、变速、节拍器、变调夹、循环、多音轨混音", "排行与筛选：热门 / 最新榜单，按难度、调性、调弦、谱型筛选", "导出：打印乐谱、生成 PDF 并选择保存位置", "搜索：按曲名 / 艺人检索全站曲谱", "个人资料：本地收藏、待练、导入、练习记录与完整备份"], id: \.self) { item in Label(item, systemImage: "checkmark.circle.fill").font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk) }
            PaperSectionTitle(title: "就从今天，踏上你的音乐之旅")
            Text("无论你是零基础新手，还是想要进阶的乐手，这里都有适合你的曲谱。如有任何问题，欢迎通过联系我们与我们沟通。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5)
        }.padding(21).mimiCard(radius: 19, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }
    private var contactContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 14) {
                contactCard(title: "功能建议 / 问题反馈", body: "在使用过程中遇到播放、下载、搜索等问题，或希望提出新功能建议，欢迎随时联系我们。", email: "support@mimi-guitar.local")
                contactCard(title: "版权与商务", body: "涉及曲谱版权、授权合作等事宜，请通过以下渠道联系，邮件主题请注明「版权」或「商务」。", email: "legal@mimi-guitar.local")
            }
            VStack(alignment: .leading, spacing: 7) { PaperSectionTitle(title: "项目说明"); Text("本项目是「谱全了」guistudy.com 的全站功能复刻学习项目，为本地开发与演示版本。如需部署、商用或数据授权，请通过上方联系方式沟通。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5) }.padding(19).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }
    }
    private func contactCard(title: String, body: String, email: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { PaperSectionTitle(title: title); Text(body).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4); Button("邮箱：\(email)") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(email, forType: .string); model.presentAlert(title: "邮箱地址已复制", message: email) }.buttonStyle(.plain).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold) }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }
    private var licensesContent: some View {
        let sources: [(String, String, String, String)] = [
            ("Astro", "MIT License", "页面框架与 SSR 服务端渲染", "https://astro.build/"),
            ("Svelte 5", "MIT License", "播放器等交互岛屿组件", "https://svelte.dev/"),
            ("Tailwind CSS v4", "MIT License", "样式与设计系统落地", "https://tailwindcss.com/"),
            ("AlphaTab", "MPL-2.0", "乐谱解析、渲染与播放引擎", "https://alphatab.net/"),
            ("Prisma", "Apache-2.0", "数据库 ORM", "https://www.prisma.io/"),
            ("jsPDF", "MIT License", "谱面 PDF 生成", "https://github.com/parallax/jsPDF"),
            ("Fraunces / Inter 字体", "OFL-1.1", "标题与正文字体（本地自托管）", "https://fonts.google.com/"),
            ("sf2 音源", "演示用途", "按乐器分发的 General MIDI 音源（迁移自原站，商用需替换为授权音源）", "—"),
            ("SONiVOX SoundFont", "随包授权文件", "内置 General MIDI 音源；分发条件以随包授权和 NOTICE 为准", "https://www.sonivoxmi.com/")
        ]
        return VStack(alignment: .leading, spacing: 14) {
            Text(introductoryText).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5)
            ForEach(sources, id: \.0) { name, license, role, url in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) { Text(name).font(MIMITheme.bodyFont(size: 14, weight: .semibold)); Text(role).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(license).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.darkGold)
                        if url == "—" {
                            Text("—").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                        } else {
                            Button("官网") { if let destination = URL(string: url) { NSWorkspace.shared.open(destination) } }.buttonStyle(.plain).font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.signalBlue)
                        }
                    }
                }.padding(.vertical, 9)
                Divider().overlay(MIMITheme.faintBorder)
            }
            if let resource = Bundle.main.resourceURL {
                VStack(alignment: .leading, spacing: 9) {
                    PaperSectionTitle(title: "随应用附带的许可与来源全文")
                    bundledLicenseButton("AlphaTab MPL-2.0 许可证全文", resource: resource, relativePath: "Player/third-party/alphaTab-MPL-2.0.txt")
                    bundledLicenseButton("AlphaTab 集成依赖清单", resource: resource, relativePath: "Player/third-party/alphaTab-integrated-libraries.txt")
                    bundledLicenseButton("Fraunces OFL-1.1 全文", resource: resource, relativePath: "Design/Fonts/OFL-Fraunces.txt")
                    bundledLicenseButton("Inter OFL-1.1 全文", resource: resource, relativePath: "Design/Fonts/OFL-Inter.txt")
                    bundledLicenseButton("SONiVOX SoundFont 授权全文", resource: resource, relativePath: "Licenses/SONiVOX/LICENSE.txt")
                    bundledLicenseButton("SONiVOX SoundFont NOTICE", resource: resource, relativePath: "Licenses/SONiVOX/NOTICE.md")
                    bundledLicenseButton("SONiVOX SoundFont 来源说明", resource: resource, relativePath: "Licenses/SONiVOX/README-source.md")
                    Text("按钮会从应用包打开实际随附文件；路径缺失时会显示明确提示。许可和 NOTICE 以应用包内原文为准。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                }.padding(14).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14))
            }
        }.padding(20).mimiCard(radius: 19, fill: MIMITheme.paperWhite)
    }

    private func bundledLicenseButton(_ title: String, resource: URL, relativePath: String) -> some View {
        Button(title) {
            let file = relativePath.split(separator: "/").reduce(resource) { $0.appendingPathComponent(String($1)) }
            guard FileManager.default.fileExists(atPath: file.path) else {
                model.presentAlert(title: "许可文件未随包提供", message: "应用资源中找不到：\(relativePath)")
                return
            }
            NSWorkspace.shared.open(file)
        }.buttonStyle(PaperSecondaryButtonStyle())
    }
    private func documentButton(_ title: String, _ destination: DocumentPage) -> some View {
        Button(title) { model.navigate(.document(destination)) }.buttonStyle(PaperSecondaryButtonStyle())
    }
}

struct PublicUploadDisabledView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            PaperPageHeader(eyebrow: "Upload · 本地导入", title: "公开投稿已暂停", subtitle: "公开上传与审核仍关闭。原站上传 API 会返回“暂未开放”；本页面不会尝试提交或伪造审核结果。")
            VStack(alignment: .leading, spacing: 12) {
                Label("本地导入仍可使用", systemImage: "square.and.arrow.down.fill").font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                Text("把你有权使用的曲谱导入本机个人资料。原件与可播放副本会分别保存；单个文件最大 30 MiB。导入内容不会公开发布。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
                HStack { Button("导入到我的谱") { model.importScoreWithPanel() }.buttonStyle(PaperProminentButtonStyle()).disabled(model.isImporting); Button("查看数据与备份") { model.navigate(.dataSettings) }.buttonStyle(PaperSecondaryButtonStyle()) }
            }.padding(22).frame(maxWidth: 700, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
            VStack(alignment: .leading, spacing: 7) { PaperSectionTitle(title: "政策与联系"); Text("原站上传政策保留用于说明内容规范，但不表示当前公开投稿入口已经开放。版权投诉与授权问题请查看版权政策和联系我们页面。")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk); HStack { documentButton("查看上传政策", .uploadPolicy); documentButton("版权政策", .copyright); documentButton("联系我们", .contact) } }
                .padding(18).frame(maxWidth: 700, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
        }.frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
    }
    private func documentButton(_ title: String, _ page: DocumentPage) -> some View { Button(title) { model.navigate(.document(page)) }.buttonStyle(PaperSecondaryButtonStyle()) }
}

struct MotionExperienceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var storedPreference = "system"
    @State private var previewExpanded = false
    @State private var selectedStep = 0
    @State private var selectedPracticePreview = 0
    @State private var practiceTempo = 60.0
    @State private var gradualSpeedup = true
    @State private var folioIndex = 0
    @State private var folioCoverOpen = false
    @State private var replayGeneration = 0

    private var preference: MIMIMotionPreference { MIMIMotionPreference(rawValue: storedPreference) ?? .off }
    private var motionEnabled: Bool { !reduceMotion && preference != .off }
    private var preferenceDescription: String {
        switch storedPreference {
        case "system":
            return "跟随设备设置：系统未要求减少动态时使用完整效果，系统开启减少动态效果时自动静止。"
        case "gentle":
            return "使用短淡入，不做位移、倾斜或背景运动。"
        case "off":
            return "界面状态直接到达终态，不播放装饰动效。"
        default:
            return "无法识别已保存的动效偏好，当前按静止效果处理。"
        }
    }
    private var effectiveMotionDescription: String {
        if reduceMotion { return "设备系统减少动态效果已启用，当前实际效果为静止。" }
        switch storedPreference {
        case "gentle": return "当前实际效果：轻柔。"
        case "off": return "当前实际效果：静止。"
        case "system": return "当前实际效果：完整。"
        default: return "无法读取有效偏好，当前按静止效果处理。"
        }
    }
    private var motionPersistenceDescription: String {
        UserDefaults.standard.object(forKey: "mimi.motion.preference") == nil
            ? "尚未保存个人选择；当前使用系统默认。更改后会保存在本机应用设置，不纳入个人数据备份。"
            : "偏好已保存在本机应用设置，不纳入个人数据备份。"
    }
    private var motionDuration: Double {
        if reduceMotion || preference == .off { return 0 }
        return preference == .gentle ? 0.12 : 0.2
    }
    private var folioItems: [CatalogItem] { Array(model.homeMasterpieces.prefix(5)) }
    private var folioItem: CatalogItem? { folioItems.isEmpty ? model.homeFeatured.first : folioItems[folioIndex % folioItems.count] }
    private var practicePreview: (index: String, title: String, body: String, mark: String) {
        switch selectedPracticePreview {
        case 1: return ("02", "把困难留在一小段。", "选好 A-B，放慢难点，再用小步提速接近目标。", "选段 · 循环 · 提速")
        case 2: return ("03", "听见一点点进步。", "记下这次的感受，下次从熟悉的位置继续。", "记录 · 回看 · 继续")
        default: return ("01", "先找回手指的节奏。", "从舒适的速度开始，让每一次拨弦都清楚、均匀。", "慢速 · 放松 · 均匀")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("MIMI GUITAR / A QUIETER RHYTHM").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2.4).foregroundStyle(MIMITheme.darkGold)
                Text("让每一次切换，\n都顺着你的手。").font(MIMITheme.displayFont(size: 45, weight: .medium)).foregroundStyle(MIMITheme.ink).lineSpacing(5)
                Text("从选一段谱，到打开工具，再回到练习。用轻柔、连贯的反馈，让注意力留在音乐里。")
                    .font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.mutedInk).lineSpacing(6).frame(maxWidth: 650)
            }
            preferencePanel
            VStack(alignment: .leading, spacing: 15) {
                PaperSectionTitle(title: "交互反馈体验", detail: "下方控件只保留此页面状态，不写入练习记录。")
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("一页安静的练习桌").font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.mutedInk)
                        Text("选择、调整，然后继续。").font(MIMITheme.displayFont(size: 20, weight: .medium)).foregroundStyle(MIMITheme.ink)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(MIMITheme.warmGold).frame(width: 5, height: 5)
                        Text("交互预览").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("控制反馈 · 200 ms").font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                        PracticeDeskIllustration().scaleEffect(0.72).frame(width: 130, height: 145).frame(maxWidth: .infinity)
                        HStack { ForEach(0..<4, id: \.self) { index in
                            Button { withAnimation(animation(duration: 0.2)) { selectedStep = index } } label: { Text("步骤 \(index + 1)").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(selectedStep == index ? .white : MIMITheme.bodyInk).padding(.horizontal, 11).frame(height: 35).background(selectedStep == index ? MIMITheme.ink : MIMITheme.paper, in: Capsule()) }
                                .buttonStyle(.plain)
                        } }
                        HStack(spacing: 7) { ForEach(0..<4, id: \.self) { index in Capsule().fill(index <= selectedStep ? MIMITheme.warmGold : MIMITheme.softBorder).frame(height: 4) } }
                            .animation(animation(duration: 0.2), value: selectedStep)
                        Text("焦点反馈立即稳定；轻柔偏好只保留短淡入，不移动内容。Reduce Motion 或静止模式会直接呈现目标状态。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                        Text("不着急，慢慢来。每一次细小调整，都是下一次进步的开始。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                        Button("试试快捷搜索 ↗") { model.presentCommandPalette() }
                            .buttonStyle(.plain).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 5) {
                            ForEach(Array(["热身", "分段", "回顾"].enumerated()), id: \.offset) { index, title in
                                Button {
                                    withAnimation(animation(duration: 0.2)) { selectedPracticePreview = index }
                                } label: {
                                    Text(title).font(MIMITheme.bodyFont(size: 11, weight: selectedPracticePreview == index ? .semibold : .regular))
                                        .foregroundStyle(selectedPracticePreview == index ? MIMITheme.ink : MIMITheme.mutedInk)
                                        .padding(.horizontal, 10).frame(height: 30)
                                        .background(selectedPracticePreview == index ? MIMITheme.paperWhite : .clear, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(selectedPracticePreview == index ? .isSelected : [])
                            }
                        }.padding(3).background(MIMITheme.paper, in: Capsule())
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(practicePreview.index) / DAILY PRACTICE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.4).foregroundStyle(MIMITheme.darkGold)
                            Text(practicePreview.title).font(MIMITheme.displayFont(size: 18, weight: .medium)).foregroundStyle(MIMITheme.ink)
                            Text(practicePreview.body).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineSpacing(4)
                            Text(practicePreview.mark).font(MIMITheme.bodyFont(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(MIMITheme.darkGold).padding(.top, 2)
                        }.frame(maxWidth: .infinity, minHeight: 116, alignment: .leading).padding(12).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 11))
                        Button { withAnimation(animation(duration: 0.26)) { previewExpanded.toggle() } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("练习设置").font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
                                    Text("调整节奏，保留你的步调").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                                }
                                Spacer()
                                Image(systemName: previewExpanded ? "chevron.up" : "chevron.down").foregroundStyle(MIMITheme.mutedInk)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                        }.buttonStyle(.plain)
                        if previewExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("起步速度").font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
                                    Spacer()
                                    Text("\(Int(practiceTempo))").font(MIMITheme.displayFont(size: 22, weight: .medium)).foregroundStyle(MIMITheme.ink).monospacedDigit()
                                    Text("BPM").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                                }
                                Slider(value: $practiceTempo, in: 40...120, step: 5).tint(MIMITheme.darkGold).accessibilityLabel("起步速度")
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("逐步提速").font(MIMITheme.bodyFont(size: 11, weight: .medium))
                                        Text(gradualSpeedup ? "每次前进一小步" : "先保持舒适的速度").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                                    }
                                    Spacer()
                                    Toggle("逐步提速", isOn: $gradualSpeedup).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                }.padding(.top, 8).overlay(alignment: .top) { Rectangle().fill(MIMITheme.softBorder).frame(height: 1) }
                            }
                            .padding(12).background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 11))
                                .transition(motionEnabled ? .opacity.combined(with: .move(edge: .top)) : .identity)
                        }
                        HStack {
                            Text("准备好了，就开始吧。").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                            Spacer(minLength: 5)
                            Button("打开我的练习 →") { model.navigate(.practice(scoreID: nil)) }
                                .buttonStyle(.plain).font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(MIMITheme.darkGold)
                        }
                        Text("面板展开只调整容器高度；此处只预览控件状态，不写入练习记录。")
                            .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                        Text("减少动态效果时，内容直接显示。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("页面切换 · 280 ms").font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                        HStack(spacing: 8) { ForEach(["曲库", "工坊", "练习"], id: \.self) { item in Button(item) { withAnimation(animation(duration: 0.28)) { selectedStep = ["曲库", "工坊", "练习"].firstIndex(of: item) ?? 0 } }.buttonStyle(PaperSecondaryButtonStyle()) } }
                        Text("搜索结果只淡入少量新卡片；离开页面缩短淡出到 160 ms。静止模式不运行过渡。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("装饰性动作 · 受偏好控制").font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                        MotionPlaybackDemo(item: model.homeFeatured.first, controller: model.auditionController)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
                }
            }
            folioSection
            HStack(alignment: .center, spacing: 14) {
                Text("动画偏好保存在本机应用设置中；下方练习与纸页预览只保留本页状态，不写入练习记录。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("去我的谱 ↗") { model.navigate(.library) }.buttonStyle(PaperProminentButtonStyle())
            }.padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                PaperSectionTitle(title: "动效时间与状态")
                Text("控制微反馈 120 ms；控件 200 ms；面板 260 ms；页面进入 280 ms、离开 160 ms；纸页翻动 360 ms。动效使用 cubic-bezier(0.2, 0, 0, 1)，收束使用 cubic-bezier(0.22, 1, 0.36, 1)。墨线绘制 1.4 秒，纸封面 3D 翻转 1.3 秒，声波纹 2.8 秒循环。纸页 reveal 只在再次滚入视口时触发，首屏不隐藏内容。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).lineSpacing(5)
                Text("减少动态效果或“静止”模式会停用装饰运动和循环动画；“轻柔”只保留不超过 120 ms 的淡入与焦点反馈。偏好保存在本机应用设置中。")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            }.padding(18).mimiCard(fill: MIMITheme.paperWhite)
        }
        .frame(maxWidth: 1050, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 18)
        .onChange(of: preference) { _ in settleFolio() }
        .onChange(of: reduceMotion) { _ in settleFolio() }
    }

    private var preferencePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    PaperSectionTitle(title: "动画偏好")
                    Text(preferenceDescription).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Picker("动画偏好", selection: $storedPreference) { ForEach(MIMIMotionPreference.allCases) { item in Text(item.title).tag(item.rawValue) } }
                    .pickerStyle(.segmented).frame(width: 300)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(effectiveMotionDescription)
                Text(motionPersistenceDescription)
            }
            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            .padding(.top, 11).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(MIMITheme.faintBorder).frame(height: 1) }
            Text("设备系统的“减少动态效果”设置始终优先生效，手动选择也不会覆盖它。")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        }.padding(17).mimiCard(fill: MIMITheme.paperWhite)
    }

    private var folioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                PaperSectionTitle(title: "换一页，换一种心情。", detail: "试着翻动纸页，或用页码选择。以下为内置示例曲目，仅用于交互展示。")
                Spacer()
                Button("全部曲谱 →") { model.navigate(.catalog(.guitar)) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("重播纸页开场") { replayFolioOpening() }.buttonStyle(PaperSecondaryButtonStyle())
            }
            HStack(alignment: .top, spacing: 18) {
                if let item = folioItem {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .topTrailing) {
                            CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 460, height: 270))
                                .frame(maxWidth: .infinity).frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 14) { Text("MIMI GUITAR").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2); Spacer(); Text(item.title).font(MIMITheme.displayFont(size: 24, weight: .semibold)); Text(item.artist ?? "MIMI GUITAR / PAPER FOLIO").font(MIMITheme.bodyFont(size: 11)); Text("FOLIO 0\(folioIndex + 1) / \(folioItems.count)").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5) }
                                .foregroundStyle(MIMITheme.paperWhite).padding(22).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [Color(hex: 0x554331), Color(hex: 0x312820)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                                .rotation3DEffect(.degrees(folioCoverOpen ? -172 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.65)
                                .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0xB39156)).frame(width: 7).opacity(0.8).padding(.vertical, 9) }
                                .accessibilityHidden(folioCoverOpen)
                        }
                        HStack(spacing: 8) {
                            Button { changeFolio(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(PaperSecondaryButtonStyle()).disabled(folioItems.count < 2)
                            ForEach(Array(folioItems.enumerated()), id: \.element.id) { index, entry in Button("\(index + 1)") { selectFolio(index) }.buttonStyle(PageNumberStyle(selected: index == folioIndex)) }
                            Button { changeFolio(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(PaperSecondaryButtonStyle()).disabled(folioItems.count < 2)
                            Spacer(); Button(folioCoverOpen ? "合上封面" : "翻开封面") { withAnimation(folioAnimation) { folioCoverOpen.toggle() } }.buttonStyle(PaperProminentButtonStyle())
                        }
                        Text("\(item.title) · \(item.artist ?? "未知演奏者") · \(item.sheetFormLabel)")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                        HStack(spacing: 6) {
                            folioBadge(item.key.map { "\($0) 调" } ?? "原调")
                            if let difficulty = folioDifficulty(item.difficulty) { folioBadge(difficulty) }
                            Spacer()
                            Label(item.displayHeat, systemImage: "flame.fill").font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.terracotta)
                        }
                    }.frame(maxWidth: 580)
                } else { ContentEmptyStrip(title: "示例曲谱尚未载入", detail: "等待本地曲库资源就绪后可翻阅示例。") }
                VStack(alignment: .leading, spacing: 11) {
                    PaperSectionTitle(title: "纸页切换")
                    Text("每次翻页用 source catalog 中的真实曲谱和截图，页码变化后等待谱面稳定再解除翻页状态。重播会先复位，再播放 1.3 秒的封面翻转。")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(5)
                    Label("Reduce Motion：\(reduceMotion ? "已启用" : "未启用")", systemImage: "figure.walk.motion").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    Label("当前偏好：\(preference.title)", systemImage: motionEnabled ? "sparkles" : "pause.circle").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    Button("打开曲库") { model.navigate(.catalog(.guitar)) }.buttonStyle(PaperSecondaryButtonStyle())
                }.frame(maxWidth: 280, alignment: .leading).padding(17).mimiCard(fill: MIMITheme.paperWhite)
            }
        }.padding(19).mimiCard(radius: 22, fill: MIMITheme.paperWhite)
    }
    private var folioAnimation: Animation? { motionEnabled ? .timingCurve(0.2, 0, 0, 1, duration: 0.36) : nil }
    private func animation(duration: Double) -> Animation? { motionEnabled ? .timingCurve(0.2, 0, 0, 1, duration: preference == .gentle ? min(duration, 0.12) : duration) : nil }
    private func selectFolio(_ index: Int) { guard folioItems.indices.contains(index) else { return }; withAnimation(folioAnimation) { folioIndex = index; folioCoverOpen = false } }
    private func changeFolio(_ offset: Int) { guard !folioItems.isEmpty else { return }; selectFolio((folioIndex + offset + folioItems.count) % folioItems.count) }
    private func settleFolio() { replayGeneration += 1; folioCoverOpen = false }
    private func folioBadge(_ title: String) -> some View {
        Text(title).font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
            .padding(.horizontal, 9).padding(.vertical, 5).background(MIMITheme.paper, in: Capsule())
    }
    private func folioDifficulty(_ value: Int) -> String? {
        guard (1...5).contains(value) else { return nil }
        return ["零基础", "初级", "中级", "高级", "专业"][value - 1]
    }
    private func replayFolioOpening() {
        guard motionEnabled else { folioCoverOpen = false; return }
        replayGeneration += 1; let generation = replayGeneration; folioCoverOpen = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            guard generation == replayGeneration, motionEnabled else { return }
            withAnimation(.timingCurve(0.25, 1, 0.35, 1, duration: 1.3)) { folioCoverOpen = true }
        }
    }
}

struct ShowcasePageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mimi.motion.preference") private var storedMotionPreference = "system"
    @State private var selectedTab = "卡片"
    @State private var selectedFilter = "全部难度"
    @State private var selectedColor = 0
    @State private var selectedShowcase = "全部"
    @State private var showExpanded = false
    @State private var selectedStep = 0
    @State private var selectedForm = 0
    @State private var heroSearch = ""
    @State private var heroSpotlight = ShowcaseHeroSpotlight()
    @State private var cinemaOpen = false
    @State private var blurImageSettled = false
    @State private var particlesShifted = false
    @State private var blurSectionIsVisible = false
    @State private var cinemaSectionIsVisible = false
    @State private var blurReplayGeneration = 0
    @State private var cinemaReplayGeneration = 0
    @State private var blurReplayWorkItem: DispatchWorkItem?
    @State private var cinemaReplayWorkItem: DispatchWorkItem?
    @State private var showcaseSearch = ""
    @State private var gridSelection: String?
    private let navTabs = ["全部", "动效", "导航", "Hero", "卡片", "筛选", "微交互", "页脚", "播放器"]
    private let colors: [Color] = [MIMITheme.warmGold, MIMITheme.terracotta, MIMITheme.green, MIMITheme.signalBlue]

    private var motionPreference: MIMIMotionPreference { MIMIMotionPreference(rawValue: storedMotionPreference) ?? .off }
    private var motionAllowed: Bool { !reduceMotion && motionPreference != .off && scenePhase == .active }
    private var spatialMotionAllowed: Bool { motionAllowed && motionPreference == .system }
    private var particleMotionAllowed: Bool { spatialMotionAllowed && blurSectionIsVisible }
    private var showcaseItem: CatalogItem? { model.homeFeatured.first }
    private var showcaseItems: [CatalogItem] {
        model.homeFeatured.filter { item in
            (selectedFilter == "全部难度" || item.difficulty == (["零基础": 1, "初级": 2, "中级": 3, "高级": 4, "专业": 5][selectedFilter] ?? 0)) &&
            (selectedForm == 0 || item.sheetForm == selectedForm)
        }
    }
    private var showcaseMotion: Animation? {
        guard motionAllowed else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: motionPreference == .gentle ? 0.12 : 0.2)
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 23) {
            showcaseBanner
            HStack(spacing: 7) {
                ForEach(navTabs, id: \.self) { tab in
                    Button(tab) { withAnimation(showcaseMotion) { selectedShowcase = tab } }
                        .buttonStyle(PaperPageTabStyle(selected: selectedShowcase == tab))
                        .accessibilityAddTraits(selectedShowcase == tab ? .isSelected : [])
                }
            }.padding(4).background(MIMITheme.paper, in: Capsule())

            Group {
                if shouldShow("动效") { motionStatusPanel }
                if shouldShow("卡片") { holographicCardSection }
                if shouldShow("动效") { cinematicOpeningSection }
                if shouldShow("播放器") {
                    VStack(alignment: .leading, spacing: 23) {
                        playerStatusPanel
                        VStack(alignment: .leading, spacing: 14) {
                            PaperSectionTitle(title: "3. Virtual Fretboard 物理吉他指板与音符光晕", detail: "按弦和品位选择高亮位置，显示六弦与品柱刻度。")
                            FretboardBentoCard(controller: model.auditionController)
                        }
                    }
                }
                if shouldShow("卡片") {
                    VStack(alignment: .leading, spacing: 23) {
                        tabCardGridSection
                        cardStylePanel
                    }
                }
                if shouldShow("Hero") {
                    VStack(alignment: .leading, spacing: 23) {
                        heroShowcasePanel
                        blurUpParticlesSection
                    }
                }
            }
            Group {
                if shouldShow("微交互") { actionControlsSection }
                if shouldShow("筛选") {
                    VStack(alignment: .leading, spacing: 23) {
                        filterStatusPanel
                        filterBarSection
                        difficultyMatrixSection
                    }
                }
                if shouldShow("导航") {
                    VStack(alignment: .leading, spacing: 23) {
                        navigationPanel
                        navigationEntryPanel
                    }
                }
                if shouldShow("页脚") { footerShowcasePanel }
                if selectedShowcase == "全部" {
                    Text("展示控件对应原站导航、筛选、卡片、播放器与动效组件；示例只使用真实本地曲库数据。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).padding(.top, 5)
                }
            }
        }
        .frame(maxWidth: 1080, alignment: .leading).frame(maxWidth: .infinity, alignment: .top).padding(.top, 9)
        .onChange(of: spatialMotionAllowed) { enabled in
            if !enabled {
                stopCinemaOpening()
                particlesShifted = false
                heroSpotlight.center = UnitPoint(x: 0.5, y: 0.45)
                if motionAllowed && blurSectionIsVisible {
                    stopBlurUp()
                    replayBlurUp()
                }
            } else if blurSectionIsVisible {
                replayBlurUp()
            }
        }
        .onChange(of: motionAllowed) { enabled in
            if enabled {
                if blurSectionIsVisible { replayBlurUp() }
            } else {
                stopBlurUp()
                stopCinemaOpening()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if blurSectionIsVisible && motionAllowed { replayBlurUp() }
            } else {
                stopBlurUp()
                stopCinemaOpening()
            }
        }
        .onChange(of: selectedShowcase) { _ in
            if !shouldShow("Hero") {
                blurSectionIsVisible = false
                stopBlurUp()
            }
            if !shouldShow("动效") {
                cinemaSectionIsVisible = false
                stopCinemaOpening()
            }
        }
        .onDisappear {
            blurSectionIsVisible = false
            cinemaSectionIsVisible = false
            stopBlurUp()
            stopCinemaOpening()
        }
    }

    private func shouldShow(_ category: String) -> Bool {
        selectedShowcase == "全部" || selectedShowcase == category
    }

    private var showcaseBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0x22C55E)).frame(width: 7, height: 7)
                Text("Design System · refero-styles Ui")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(MIMITheme.paper, in: Capsule())
            .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            Text("全站高级 UI 与动效全家桶 Showcase")
                .font(MIMITheme.displayFont(size: 48, weight: .medium)).tracking(-0.96).foregroundStyle(MIMITheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("这里汇集站内预置的界面与交互动效示例，可试用曲库筛选、指板演示与纸页转场。展示曲目和数字均为内置示例，不代表实时目录统计；实际动画表现会随设备、浏览器和动效偏好变化。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.mutedInk).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 760, alignment: .leading)
        }
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(MIMITheme.softBorder).frame(height: 1) }
    }

    private var navigationPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            PaperSectionTitle(title: "导航与搜索胶囊")
            HStack(spacing: 12) {
                Text("M").font(MIMITheme.displayFont(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 38).background(MIMITheme.ink, in: Circle())
                Text("MIMI Guitar").font(MIMITheme.displayFont(size: 19, weight: .semibold))
                Spacer()
                ForEach(["吉他谱", "尤克里里", "工坊", "专栏"], id: \.self) { label in
                    Button(label) {
                        selectedTab = label
                        switch label {
                        case "吉他谱": model.navigate(.catalog(.guitar))
                        case "尤克里里": model.navigate(.catalog(.ukulele))
                        case "工坊": model.navigate(.studio)
                        default: model.navigate(.articles)
                        }
                    }
                    .font(MIMITheme.bodyFont(size: 11)).padding(.horizontal, 10).frame(height: 33)
                    .background(label == selectedTab ? MIMITheme.ink : MIMITheme.paper, in: Capsule())
                    .foregroundStyle(label == selectedTab ? .white : MIMITheme.bodyInk).buttonStyle(.plain)
                }
                Button("搜索 ⌘K") { model.presentCommandPalette() }.buttonStyle(PaperSecondaryButtonStyle())
            }.padding(14).mimiCard(radius: 20, fill: MIMITheme.paperWhite)
        }
    }

    private var navigationEntryPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            PaperSectionTitle(title: "真实入口")
            HStack(spacing: 9) {
                Button("打开交互体验") { model.navigate(.motion) }.buttonStyle(PaperProminentButtonStyle())
                Button("打开吉他曲库") { model.navigate(.catalog(.guitar)) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("查看帮助中心") { model.navigate(.document(.help)) }.buttonStyle(PaperSecondaryButtonStyle())
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }

    private var heroShowcasePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "5. Hero Showcase with Blur-Up & Particles", detail: "输入曲名、演奏者或和弦后回车进入真实搜索；也可打开命令面板。")
            GeometryReader { proxy in
                ZStack {
                    MIMITheme.paperWhite
                    ShowcaseHeroSpotlightLayer(spotlight: heroSpotlight)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("全站曲库", systemImage: "music.note.list").font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold)
                            Spacer()
                            Text("\(model.catalogCount.formatted()) 首").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                        }
                        Text("把下一首想练的曲子找出来。")
                            .font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
                            TextField("曲名、歌手或和弦", text: $heroSearch).textFieldStyle(.plain).onSubmit(submitHeroSearch)
                            Button("检索") { submitHeroSearch() }.buttonStyle(PaperProminentButtonStyle())
                        }.padding(.horizontal, 13).frame(height: 44).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
                        HStack(spacing: 7) {
                            Text("热门搜索").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                            ForEach(["周杰伦", "赵雷", "晴天", "G Em7 Cadd9"], id: \.self) { term in
                                Button(term) { heroSearch = term; submitHeroSearch() }
                                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.bodyInk)
                                    .padding(.horizontal, 9).padding(.vertical, 5).background(MIMITheme.paper, in: Capsule())
                                    .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                        }
                        Button { model.presentCommandPalette() } label: { Label("打开搜索与命令面板 ⌘K", systemImage: "command") }
                            .buttonStyle(.plain).font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.darkGold)
                    }.padding(20)
                }
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(MIMITheme.softBorder, lineWidth: 1))
                .onContinuousHover { phase in
                    guard spatialMotionAllowed, proxy.size.width > 0, proxy.size.height > 0 else {
                        heroSpotlight.center = UnitPoint(x: 0.5, y: 0.45)
                        return
                    }
                    switch phase {
                    case .active(let point):
                        heroSpotlight.center = UnitPoint(x: min(1, max(0, point.x / proxy.size.width)), y: min(1, max(0, point.y / proxy.size.height)))
                    case .ended:
                        heroSpotlight.center = UnitPoint(x: 0.5, y: 0.45)
                    }
                }
            }
            .frame(height: 238)
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var footerShowcasePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "Mega Footer · 快速入口与试听状态", detail: "页脚链接进入对应原生页面；播放按钮使用共享的真实曲库试听状态。")
            HStack(spacing: 11) {
                Text("M").font(MIMITheme.displayFont(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 36, height: 36).background(MIMITheme.ink, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("MIMI Guitar").font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    Text("纸本墨韵 · 专业数字乐谱工坊").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
                ShowcaseFooterPlaybackControl(defaultItem: model.homeFeatured.first, controller: model.auditionController)
            }
            Divider().overlay(MIMITheme.softBorder)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 8) {
                Button("吉他曲库") { model.navigate(.catalog(.guitar)) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("尤克里里") { model.navigate(.catalog(.ukulele)) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("制谱工坊") { model.navigate(.studio) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("专栏文章") { model.navigate(.articles) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("我的练习") { model.navigate(.practice(scoreID: nil)) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("我的谱") { model.navigate(.library) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("数据与备份") { model.navigate(.dataSettings) }.buttonStyle(PaperSecondaryButtonStyle())
                Button("交互体验") { model.navigate(.motion) }.buttonStyle(PaperSecondaryButtonStyle())
            }
            Text("© MIMI Guitar · 示例页的试听与页面链接均使用当前应用中的真实状态。")
                .font(MIMITheme.bodyFont(size: 9)).foregroundStyle(MIMITheme.mutedInk)
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var filterStatusPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "筛选状态")
            Picker("难度", selection: $selectedFilter) {
                ForEach(["全部难度", "零基础", "初级", "中级", "高级", "专业"], id: \.self) { Text($0).tag($0) }
            }.frame(width: 170)
            HStack {
                ForEach(["全部谱型", "指弹", "弹唱", "六线 4", "六线 7"], id: \.self) { label in
                    let value = ["全部谱型": 0, "弹唱": 1, "指弹": 2, "六线 4": 4, "六线 7": 7][label] ?? 0
                    Button { selectedForm = value } label: {
                        MIMIPill(title: label, tint: value == selectedForm ? MIMITheme.darkGold : MIMITheme.bodyInk, fill: value == selectedForm ? MIMITheme.warmGold.opacity(0.12) : MIMITheme.paper)
                    }.buttonStyle(.plain)
                }
            }
            Button("清空筛选") { selectedFilter = "全部难度"; selectedForm = 0 }.buttonStyle(PaperSecondaryButtonStyle())
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }

    private var cardStylePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "纸卡 / 标签")
            HStack { Circle().fill(colors[selectedColor]).frame(width: 9); Text("精选曲目卡片").font(MIMITheme.bodyFont(size: 14, weight: .semibold)); Spacer(); Text("FOLIO 01").font(.system(size: 9, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk) }
            Text("留白、纸纹、暖灰边线与金色标记构成曲谱卡片。选择标记颜色以预览状态。").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            HStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    Button { selectedColor = index } label: {
                        Circle().fill(color).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(.white, lineWidth: selectedColor == index ? 2 : 0))
                    }.buttonStyle(.plain).accessibilityLabel("选择标记颜色 \(index + 1)")
                }
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }

    private var playerStatusPanel: some View {
        ShowcasePlayerStatusPanel(defaultItem: showcaseItem, controller: model.auditionController, contentRoot: model.contentRoot, isExpanded: $showExpanded, onAdvanceRate: advancePlaybackRate)
    }

    private var motionStatusPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            PaperSectionTitle(
                title: "MIMI Guitar 动效与交互体验展台",
                detail: "这里汇集八组可操作的界面交互示例，涵盖导航、卡片、筛选、微交互、页脚与播放器；动效遵循全站偏好。"
            )
            Button("切换示例状态") {
                withAnimation(showcaseMotion) { selectedStep = (selectedStep + 1) % 4 }
            }.buttonStyle(PaperSecondaryButtonStyle())
            ProgressView(value: Double(selectedStep + 1), total: 4).tint(MIMITheme.warmGold)
            Text("微反馈、控件、面板和页面切换的节奏与状态可在交互体验页逐项调整。")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            Button("打开交互体验设置 →") { model.navigate(.motion) }
                .buttonStyle(.plain).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold)
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(fill: MIMITheme.paperWhite)
    }

    private var holographicCardSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "1. 3D Holographic Foil Cards (全息彩虹箔面与光斑折射)", detail: "拖动卡片改变透视角度；减少动态效果或静止模式会锁定平面。")
            if let item = showcaseItem {
                ShowcaseHolographicCard(
                    item: item,
                    contentRoot: model.contentRoot,
                    folioNumber: (model.homeMasterpieces.firstIndex(of: item) ?? 0) + 1,
                    strokeColor: colors[selectedColor],
                    spatialMotionAllowed: spatialMotionAllowed,
                    motion: showcaseMotion
                )
                .frame(height: 280).mimiCard(radius: 19, fill: MIMITheme.paperWhite)
            } else { ContentEmptyStrip(title: "等待本地曲谱载入", detail: "此区域会使用真实曲库截图。") }
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var cinematicOpeningSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(
                title: "2. Masterpiece Cinema Intro (电影级开场幕帘交互面板)",
                detail: "使用本地曲库截图展示纸页开场；播放前会检查本机动效偏好，减少动态效果时保持静止。"
            )
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("CINEMATIC OPENING ENGINE")
                            .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.1)
                            .foregroundStyle(Color(hex: 0xF5C07B))
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Color(hex: 0xF5C07B).opacity(0.1), in: Capsule())
                            .overlay(Capsule().stroke(Color(hex: 0xF5C07B).opacity(0.3), lineWidth: 1))
                        Text("电影级开场物理驻波与动力学字距")
                            .font(MIMITheme.displayFont(size: 21, weight: .medium)).foregroundStyle(.white)
                        Text("Mac 原生预览以本地曲库截图呈现纸页翻转；动画遵循当前动效偏好与系统减少动态效果设置。")
                            .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(.white.opacity(0.72)).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 520, alignment: .leading)
                        Button(cinemaOpen ? "重播纸页开场" : "播放纸页开场") { replayCinemaOpening() }
                            .buttonStyle(PaperProminentButtonStyle()).disabled(!spatialMotionAllowed || showcaseItem == nil)
                    }
                    Spacer(minLength: 0)
                    if let item = showcaseItem {
                        ZStack(alignment: .leading) {
                            CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 420, height: 190))
                                .frame(width: 320, height: 175).clipShape(RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("MIMI GUITAR · PAPER SCORE").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3)
                                Spacer(); Text(item.title).font(MIMITheme.displayFont(size: 17, weight: .semibold)); Text(item.artist ?? "未知演奏者").font(MIMITheme.bodyFont(size: 10))
                            }.foregroundStyle(MIMITheme.paperWhite).padding(15).frame(width: 320, height: 175, alignment: .leading)
                                .background(LinearGradient(colors: [Color(hex: 0x554331), Color(hex: 0x312820)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                                .rotation3DEffect(.degrees(cinemaOpen ? -172 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.65)
                                .accessibilityHidden(cinemaOpen)
                        }.frame(width: 320, height: 175).clipShape(RoundedRectangle(cornerRadius: 13))
                    } else { ContentEmptyStrip(title: "开场示例尚未载入", detail: "等待真实谱面截图。") }
                }
            }.padding(24)
                .background(LinearGradient(colors: [Color(hex: 0x17171D), Color(hex: 0x0A0A0F)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0xF5C07B).opacity(0.2), lineWidth: 1))
        }
            .onAppear { cinemaSectionIsVisible = true }
            .onDisappear {
                cinemaSectionIsVisible = false
                stopCinemaOpening()
            }
    }

    private var tabCardGridSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "4. TabCardGrid 动态排版与 FLIP 弹簧过渡 (TabCardGrid.svelte)", detail: "卡片来自已载入的热门曲谱，选择卡片打开详情或试听原谱。")
            if showcaseItems.isEmpty { ContentEmptyStrip(title: "此难度与谱型暂时没有示例", detail: "调整上方筛选后显示本机曲库中的匹配项。") }
            else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(Array(showcaseItems.prefix(9))) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { gridSelection = item.id; model.openCatalogItem(item) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 320, height: 145)).frame(height: 145).clipShape(RoundedRectangle(cornerRadius: 11))
                                    Text(item.title).font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                                    Text("\(item.artist ?? "未知演奏者") · \(item.key ?? "調性未標註")").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                                }.padding(10).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(gridSelection == item.id ? MIMITheme.warmGold : MIMITheme.softBorder, lineWidth: gridSelection == item.id ? 2 : 1))
                            }.buttonStyle(.plain)
                            ShowcasePreviewButton(item: item, controller: model.auditionController)
                        }
                        .transition(motionAllowed ? .opacity : .identity)
                    }
                }.animation(showcaseMotion, value: selectedFilter + "-\(selectedForm)")
            }
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var blurUpParticlesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaperSectionTitle(title: "Hero Blur-up 与纸屑光点", detail: "模糊截图载入后清晰显示；点按重播 blur-up。减少动态效果下直接呈现清晰状态。")
            if let item = showcaseItem {
                ZStack {
                    CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 840, height: 240))
                        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                        .blur(radius: blurImageSettled || !spatialMotionAllowed ? 0 : 10)
                        .opacity(blurImageSettled || !motionAllowed ? 1 : 0.72)
                    GeometryReader { proxy in
                        ForEach(0..<7, id: \.self) { index in
                            Group {
                                if particleMotionAllowed {
                                    Circle().fill(index.isMultiple(of: 2) ? MIMITheme.warmGold : .white)
                                        .frame(width: index.isMultiple(of: 3) ? 7 : 4, height: index.isMultiple(of: 3) ? 7 : 4)
                                        .offset(y: particlesShifted ? -9 : 0)
                                        .animation(.linear(duration: 2.8).repeatForever(autoreverses: true), value: particlesShifted)
                                } else {
                                    Circle().fill(index.isMultiple(of: 2) ? MIMITheme.warmGold : .white)
                                        .frame(width: index.isMultiple(of: 3) ? 7 : 4, height: index.isMultiple(of: 3) ? 7 : 4)
                                }
                            }
                            .position(x: proxy.size.width * CGFloat((index * 29 + 13) % 93 + 3) / 100, y: proxy.size.height * CGFloat((index * 37 + 7) % 78 + 8) / 100)
                            .opacity(0.68)
                        }.allowsHitTesting(false)
                    }.frame(height: 220)
                    VStack { Spacer(); HStack { Text(item.title).font(MIMITheme.displayFont(size: 19, weight: .semibold)).foregroundStyle(.white); Spacer(); Button("重播 Blur-up") { replayBlurUp() }.buttonStyle(PaperSecondaryButtonStyle()) }.padding(14) }
                }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                    .onAppear {
                        blurSectionIsVisible = true
                        replayBlurUp()
                    }
                    .onDisappear {
                        blurSectionIsVisible = false
                        stopBlurUp()
                    }
            } else { ContentEmptyStrip(title: "Hero 截图尚未载入", detail: "等待真实曲库资源。") }
        }
        .padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var actionControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaperSectionTitle(title: "6. 微交互反馈：红心粒子爆炸与磨砂 Toast (FavoriteButton & ShareButton)", detail: "三种操作分别使用本机收藏、macOS 分享面板与保存对话框。")
            if let item = showcaseItem {
                HStack(spacing: 10) {
                    Button { model.toggleFavorite(for: item) } label: { Label(model.isFavorite(item) ? "已收藏" : "收藏", systemImage: model.isFavorite(item) ? "heart.fill" : "heart") }.buttonStyle(PaperProminentButtonStyle())
                    Button { model.share(item) } label: { Label("分享…", systemImage: "square.and.arrow.up") }.buttonStyle(PaperSecondaryButtonStyle())
                    Button { model.openDownload(for: item) } label: { Label("下载原谱…", systemImage: "arrow.down.to.line") }.buttonStyle(PaperSecondaryButtonStyle()).disabled(item.scoreURL == nil && item.xheURL == nil)
                    Button { model.navigate(.studioClone(sourceID: item.id)) } label: { Label("改编到工坊", systemImage: "square.and.pencil") }.buttonStyle(PaperSecondaryButtonStyle())
                }
            } else { ContentEmptyStrip(title: "没有可操作的曲谱", detail: "动作会在真实曲目载入后启用。") }
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var filterBarSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "7. 18px 胶囊几何筛选栏 (FilterBar.astro)", detail: "下方筛选先在真实本地示例中预览；按“应用到曲库”后进入对应曲库过滤结果。")
            HStack(spacing: 9) {
                Picker("难度", selection: $selectedFilter) { ForEach(["全部难度", "零基础", "初级", "中级", "高级", "专业"], id: \.self) { Text($0).tag($0) } }.frame(width: 145)
                Picker("谱型", selection: $selectedForm) { Text("全部谱型").tag(0); Text("弹唱谱").tag(1); Text("指弹谱").tag(2); Text("和弦谱").tag(3); Text("六线谱 4").tag(4); Text("六线谱 7").tag(7) }.frame(width: 145)
                TextField("曲名或演奏者", text: $showcaseSearch).textFieldStyle(.roundedBorder)
                Button("应用到曲库") { applyShowcaseFilters() }.buttonStyle(PaperProminentButtonStyle())
            }
            Text("当前预览：\(showcaseItems.count) 首 · \(selectedFilter) · \(selectedForm == 0 ? "全部谱型" : "谱型 \(selectedForm)")")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private var difficultyMatrixSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaperSectionTitle(title: "8. 5 段发光 Pip 难度矩阵 (DifficultyMatrix.svelte)", detail: "选择任一等级，曲库会按此真实难度查询。")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 5), spacing: 9) {
                ForEach(Array(["零基础", "初级", "中级", "高级", "专业"].enumerated()), id: \.offset) { index, label in
                    let level = index + 1
                    let count = model.homeMasterpieces.filter { $0.difficulty == level }.count
                    Button { openDifficulty(level) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LEVEL 0\(level)").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(MIMITheme.darkGold)
                            Text(label).font(MIMITheme.displayFont(size: 16, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                            Text("\(count) 首精选").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                            ProgressView(value: Double(count), total: Double(max(1, model.homeMasterpieces.count))).tint(colors[index % colors.count])
                        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(18).mimiCard(radius: 21, fill: MIMITheme.paperWhite)
    }

    private func replayCinemaOpening() {
        guard cinemaSectionIsVisible, scenePhase == .active, spatialMotionAllowed, showcaseItem != nil else {
            stopCinemaOpening()
            return
        }
        cinemaReplayWorkItem?.cancel()
        cinemaReplayGeneration += 1
        let generation = cinemaReplayGeneration
        cinemaOpen = false
        let workItem = DispatchWorkItem {
            guard generation == cinemaReplayGeneration,
                  cinemaSectionIsVisible,
                  scenePhase == .active,
                  spatialMotionAllowed else { return }
            cinemaReplayWorkItem = nil
            withAnimation(.timingCurve(0.25, 1, 0.35, 1, duration: 1.3)) { cinemaOpen = true }
        }
        cinemaReplayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    private func replayBlurUp() {
        guard blurSectionIsVisible, scenePhase == .active, motionAllowed else {
            stopBlurUp()
            return
        }
        blurReplayWorkItem?.cancel()
        blurReplayGeneration += 1
        let generation = blurReplayGeneration
        blurImageSettled = false
        let workItem = DispatchWorkItem {
            guard generation == blurReplayGeneration,
                  blurSectionIsVisible,
                  scenePhase == .active,
                  motionAllowed else { return }
            blurReplayWorkItem = nil
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: motionPreference == .gentle ? 0.12 : 0.22)) { blurImageSettled = true }
            guard spatialMotionAllowed else { return }
            withAnimation(.linear(duration: 2.8).repeatForever(autoreverses: true)) { particlesShifted.toggle() }
        }
        blurReplayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: workItem)
    }

    private func stopBlurUp() {
        blurReplayGeneration += 1
        blurReplayWorkItem?.cancel()
        blurReplayWorkItem = nil
        particlesShifted = false
        blurImageSettled = true
    }

    private func stopCinemaOpening() {
        cinemaReplayGeneration += 1
        cinemaReplayWorkItem?.cancel()
        cinemaReplayWorkItem = nil
        cinemaOpen = false
    }

    private func applyShowcaseFilters() {
        model.navigate(.catalog(.guitar))
        model.searchText = showcaseSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        model.searchField = .all
        model.difficultyFilter = ["零基础": 1, "初级": 2, "中级": 3, "高级": 4, "专业": 5][selectedFilter]
        model.sheetFormFilter = selectedForm == 0 ? nil : selectedForm
        model.filterDidChange()
    }

    private func submitHeroSearch() {
        let query = heroSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { model.presentCommandPalette(); return }
        model.navigate(.search(query: query, domain: .all))
    }

    private func openDifficulty(_ level: Int) {
        selectedFilter = [1: "零基础", 2: "初级", 3: "中级", 4: "高级", 5: "专业"][level] ?? "全部难度"
        model.navigate(.catalog(.guitar))
        model.difficultyFilter = level
        model.filterDidChange()
    }

    private func advancePlaybackRate() {
        let audio = model.auditionController
        guard audio.sourceTempo > 0 else { return }
        let rates = [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0]
        let current = audio.tempo / audio.sourceTempo
        let next = rates.first(where: { $0 > current + 0.01 }) ?? rates[0]
        audio.setTempo(audio.sourceTempo * next)
    }

}

private final class ShowcaseHeroSpotlight: ObservableObject {
    @Published var center = UnitPoint(x: 0.5, y: 0.45)
}

private struct ShowcaseHeroSpotlightLayer: View {
    @ObservedObject var spotlight: ShowcaseHeroSpotlight

    var body: some View {
        RadialGradient(colors: [MIMITheme.warmGold.opacity(0.17), .clear], center: spotlight.center, startRadius: 5, endRadius: 420)
    }
}

private struct ShowcaseHolographicCard: View {
    let item: CatalogItem
    let contentRoot: URL?
    let folioNumber: Int
    let strokeColor: Color
    let spatialMotionAllowed: Bool
    let motion: Animation?
    @State private var tilt = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                CatalogThumbnail(reference: item.screenshotURL, contentRoot: contentRoot, size: CGSize(width: 760, height: 300))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                LinearGradient(colors: [.clear, MIMITheme.ink.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FOLIO · 0\(folioNumber)").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                    Text(item.title).font(MIMITheme.displayFont(size: 23, weight: .semibold))
                    Text("\(item.artist ?? "未知演奏者") · \(item.key ?? "调性未标注") · \(item.sheetFormLabel)").font(MIMITheme.bodyFont(size: 11))
                }.foregroundStyle(.white).padding(18)
                LinearGradient(colors: [.white.opacity(0.24), .clear, MIMITheme.warmGold.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.screen).opacity(spatialMotionAllowed ? min(0.38, abs(tilt.width + tilt.height) / 30) : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(strokeColor.opacity(0.8), lineWidth: 1.5))
            .rotation3DEffect(.degrees(Double(tilt.height)), axis: (x: 1, y: 0, z: 0), perspective: 0.72)
            .rotation3DEffect(.degrees(Double(tilt.width)), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard spatialMotionAllowed, proxy.size.width > 0, proxy.size.height > 0 else { return }
                tilt = CGSize(width: min(11, max(-11, (value.location.x / proxy.size.width - 0.5) * 22)), height: min(9, max(-9, (0.5 - value.location.y / proxy.size.height) * 18)))
            }.onEnded { _ in withAnimation(motion) { tilt = .zero } })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title) 全息纸卡，拖动可改变透视")
            .onChange(of: spatialMotionAllowed) { enabled in if !enabled { tilt = .zero } }
        }
    }
}

private struct ShowcasePlayerStatusPanel: View {
    let defaultItem: CatalogItem?
    let controller: NativeAuditionController
    let contentRoot: URL?
    @Binding var isExpanded: Bool
    let onAdvanceRate: () -> Void
    @StateObject private var auditionState: AuditionItemViewState

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var item: CatalogItem? { controller.activeItem ?? defaultItem }
    private var playbackRateLabel: String { String(format: "%.2f×", playback.playbackRate) }

    init(defaultItem: CatalogItem?, controller: NativeAuditionController, contentRoot: URL?, isExpanded: Binding<Bool>, onAdvanceRate: @escaping () -> Void) {
        self.defaultItem = defaultItem
        self.controller = controller
        self.contentRoot = contentRoot
        self._isExpanded = isExpanded
        self.onAdvanceRate = onAdvanceRate
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, tracksClock: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PaperSectionTitle(title: "播放器状态")
            if let item {
                HStack(spacing: 13) {
                    CatalogThumbnail(reference: item.screenshotURL, contentRoot: contentRoot, size: CGSize(width: 180, height: 108)).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(MIMITheme.displayFont(size: 18, weight: .semibold))
                        Text(item.artist ?? "未知演奏者").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                        Text(playback.isActive ? playback.statusMessage : "准备就绪").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                    }
                    Spacer()
                    if playback.isLoading { ProgressView().controlSize(.small) }
                    Button { controller.toggle(item: item) } label: {
                        Image(systemName: playback.isActive && playback.isPlaying ? "pause.fill" : "play.fill")
                    }.buttonStyle(PaperProminentButtonStyle()).disabled(playback.isActive && !playback.canPlay && !playback.isLoading)
                }.padding(13).mimiCard(fill: MIMITheme.paperWhite)
            } else {
                Text("本地曲库载入后会显示真实示例曲目。没有可播放资源时按钮会保持禁用。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
            }
            HStack {
                Text("试听时长")
                Button("30 秒") { if let item { controller.toggle(item: item, previewDuration: 30) } }.buttonStyle(PaperSecondaryButtonStyle()).disabled(item == nil)
                Button("60 秒") { if let item { controller.toggle(item: item, previewDuration: 60) } }.buttonStyle(PaperSecondaryButtonStyle()).disabled(item == nil)
                Spacer()
                Toggle("展示展开控件", isOn: $isExpanded).toggleStyle(.switch).controlSize(.small)
            }
            if isExpanded {
                HStack(spacing: 12) {
                    Slider(value: Binding(get: {
                        let clock = auditionState.clock
                        return clock.endTime > 0 ? min(1, max(0, clock.currentTime / clock.endTime)) : 0
                    }, set: { controller.seek(toRatio: $0) }), in: 0...1)
                        .disabled(!playback.canPlay || auditionState.clock.endTime <= 0)
                    Text("\(clock(auditionState.clock.currentTime)) / \(clock(auditionState.clock.endTime))")
                        .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                    Button("速度 \(playbackRateLabel)", action: onAdvanceRate).buttonStyle(PaperSecondaryButtonStyle()).disabled(!playback.canPlay)
                }.transition(.opacity)
            }
        }.padding(17).mimiCard(radius: 20, fill: MIMITheme.paperWhite)
    }

    private func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ShowcasePreviewButton: View {
    let item: CatalogItem
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }

    init(item: CatalogItem, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

    var body: some View {
        Button { controller.toggle(item: item, previewDuration: 30) } label: {
            if playback.isLoading {
                Label("加载试听…", systemImage: "hourglass")
            } else if playback.isPlaying {
                Label("暂停试听", systemImage: "pause.fill")
            } else {
                Label("试听 30 秒", systemImage: "play.fill")
            }
        }
        .buttonStyle(PaperSecondaryButtonStyle())
        .disabled(item.scoreURL == nil)
    }
}

private struct MotionPlaybackDemo: View {
    let item: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }

    init(item: CatalogItem?, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "music.note").foregroundStyle(MIMITheme.darkGold)
                Text("点击播放试听示例")
                Spacer()
                Button {
                    if let item { controller.toggle(item: item) }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(PaperProminentButtonStyle())
                .disabled(item == nil)
            }
            Text(playback.isActive ? playback.statusMessage : "准备就绪")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        }
    }
}

private struct ShowcaseFooterPlaybackControl: View {
    let defaultItem: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }

    init(defaultItem: CatalogItem?, controller: NativeAuditionController) {
        self.defaultItem = defaultItem
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(playback.isActive ? playback.statusMessage : "")
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
            Button {
                if let item = controller.activeItem ?? defaultItem { controller.toggle(item: item) }
            } label: {
                Label(playback.isPlaying ? "暂停试听" : "试听示例", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(PaperSecondaryButtonStyle())
            .disabled(!playback.isActive && defaultItem == nil)
        }
    }
}

private struct PaperPageTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : MIMITheme.bodyInk).padding(.horizontal, 14).frame(height: 36)
            .background(selected ? MIMITheme.ink.opacity(configuration.isPressed ? 0.8 : 1) : .clear, in: Capsule())
    }
}
