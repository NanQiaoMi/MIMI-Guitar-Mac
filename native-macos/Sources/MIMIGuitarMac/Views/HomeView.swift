import MIMICore
import SwiftUI

private struct HomeHeroBackdrop: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [MIMITheme.paperWhite.opacity(0.97), Color(hex: 0xFCF8F0), MIMITheme.paperWhite], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [MIMITheme.warmGold.opacity(0.12), .clear], center: UnitPoint(x: 0.85, y: 0.08), startRadius: 10, endRadius: 600)
            PaperGrainOverlay()
        }
    }
}

private struct HomeAuditionScope<Content: View>: View {
    @StateObject private var state: AuditionItemViewState
    let content: (AuditionPlaybackSnapshot) -> Content

    init(controller: NativeAuditionController, @ViewBuilder content: @escaping (AuditionPlaybackSnapshot) -> Content) {
        _state = StateObject(wrappedValue: controller.viewState())
        self.content = content
    }

    var body: some View {
        content(state.snapshot)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var heroIsVisible = false
    @State private var didSelectInitialHero = false
    @State private var featuredLoadFailed = false

    private var currentMasterpiece: SourceMasterpiece? {
        guard !HomeMasterpieceData.rows.isEmpty else { return nil }
        return HomeMasterpieceData.rows[model.heroIndex % HomeMasterpieceData.rows.count]
    }
    private var heroItem: CatalogItem? {
        guard let currentMasterpiece else { return nil }
        return model.homeMasterpieces.first(where: { $0.id == currentMasterpiece.id })
    }
    private var bentoItem: CatalogItem? {
        model.homeMasterpieces.first(where: { $0.id == "1sdc49P3eKm" })
            ?? model.homeFeatured.first(where: { $0.id == "1sdc49P3eKm" })
    }
    private var waitingCount: Int {
        model.personalSnapshot.practiceItems.filter { $0.status == .todo || $0.status == .practicing }.count
    }
    private var sessionCount: Int { model.personalSnapshot.sessions.count }
    private var recentSessions: [PracticeSession] { Array(model.personalSnapshot.sessions.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)) }
    private let sectionSpacing: CGFloat = 64

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            hero
            masterpieceSection
            bentoSection
            rankingSection
            theorySection
            studyNotesSection
            callToAction
            footer
        }
        .frame(maxWidth: 1240, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
        .task {
            if model.homeMasterpieces.isEmpty && model.catalogCount > 0 { featuredLoadFailed = true }
        }
        .onAppear {
            if !didSelectInitialHero {
                model.heroIndex = Int.random(in: 0..<HomeMasterpieceData.rows.count)
                didSelectInitialHero = true
            }
            heroIsVisible = true
        }
        .onDisappear {
            heroIsVisible = false
        }
        .onChange(of: model.rankingPeriod) { newValue in model.loadRankings(for: newValue) }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 48) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 9) {
                    Circle().fill(MIMITheme.darkGold).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(MIMITheme.warmGold.opacity(0.45), lineWidth: 5))
                    Text("MIMI GUITAR v2.0")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.2).foregroundStyle(Color(hex: 0x8F6D2B))
                    Text("|").foregroundStyle(MIMITheme.softBorder)
                    Text("当前曲库")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk)
                    Text(model.catalogCount.formatted())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(MIMITheme.terracotta)
                        .padding(.horizontal, 5).background(MIMITheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    Text("首").font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk)
                }
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(LinearGradient(colors: [MIMITheme.paper, Color(hex: 0xF7F2E7), MIMITheme.paper], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.warmGold.opacity(0.42), lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    Text("把每一份乐谱，")
                    Text("都当作一页书来对待")
                        .foregroundStyle(MIMITheme.darkGold)
                        .overlay(alignment: .bottomLeading) {
                            LinearGradient(colors: [MIMITheme.warmGold, Color(hex: 0xE2C078), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(height: 3).offset(y: 8)
                        }
                }
                .font(MIMITheme.displayFont(size: 48, weight: .bold))
                .lineSpacing(10)
                .padding(.vertical, 6)
                .foregroundStyle(MIMITheme.ink)
                .fixedSize(horizontal: false, vertical: true)

                Text("吉他与尤克里里乐谱浏览和个人练习工具，提供六线谱显示、播放控制、本地导入与练习记录。")
                    .font(MIMITheme.bodyFont(size: 15))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(5)
                    .frame(maxWidth: 570, alignment: .leading)

                HomeSearchField(isHeroVisible: heroIsVisible, onSubmit: submitHomeSearch)
                    .frame(maxWidth: 570)

                HomeHotwordFlowLayout(spacing: 7) {
                    Label("热门搜索:", systemImage: "flame.fill")
                        .font(MIMITheme.bodyFont(size: 11))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(height: 26)
                    ForEach(["周杰伦", "陶喆", "赵雷", "痛仰", "押尾桑", "岸部真明", "蔡健雅"], id: \.self) { artist in
                        Button { model.navigate(.search(query: artist, domain: .all)) } label: {
                            Text(artist)
                                .font(MIMITheme.bodyFont(size: 11))
                                .foregroundStyle(MIMITheme.bodyInk)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(MIMITheme.paperWhite, in: Capsule())
                                .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let item = heroItem, let masterpiece = currentMasterpiece {
                HeroFeatureCard(item: item, masterpiece: masterpiece, controller: model.auditionController, onShuffle: shuffleHero, onOpen: { model.openCatalogItem(item) })
                    .id(item.id)
                    .frame(width: 405)
            } else {
                heroLoadingCard
                    .frame(width: 405)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity, minHeight: 560)
        .background {
            HomeHeroBackdrop()
        }
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(MIMITheme.faintBorder, lineWidth: 1))
        .shadow(color: MIMITheme.bodyInk.opacity(0.035), radius: 8, x: 0, y: 3)
    }

    private var heroLoadingCard: some View {
        VStack(spacing: 14) {
            if model.isLoadingHome { ProgressView().tint(MIMITheme.darkGold) }
            Image(systemName: featuredLoadFailed ? "music.note.list" : "music.note")
                .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(MIMITheme.warmGold)
            Text(featuredLoadFailed ? "今日典藏焦点暂不可用" : "正在载入典藏曲谱")
                .font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text("本地曲库就绪后会在这里展示真实乐谱与试听。")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
        .mimiCard(fill: MIMITheme.paperWhite)
    }

    private var masterpieceSection: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(alignment: .bottom) {
                MIMISectionHeading(title: "精选曲目展示", subtitle: "示例曲目展示，查看卡片排版并尝试打开曲谱或试听")
                Spacer()
                Button {
                    model.navigate(.catalog(.all))
                    model.sort = .popular
                    model.sortDidChange()
                } label: {
                    Label("浏览全部曲谱", systemImage: "arrow.right")
                        .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.darkGold)
                }
                .buttonStyle(.plain)
            }
            HomeAuditionScope(controller: model.auditionController) { snapshot in
                HStack(alignment: .top, spacing: 17) {
                    ForEach(HomeMasterpieceStageData.rows) { info in
                        if let item = model.homeMasterpieces.first(where: { $0.id == info.id }) {
                            let isActive = snapshot.activeItemID == item.id
                            MasterpieceCard(
                                item: item,
                                info: info,
                                isPlaying: isActive && snapshot.isPlaying,
                                isLoading: isActive && snapshot.isLoading,
                                statusMessage: isActive ? snapshot.statusMessage : "",
                                onOpen: { model.openCatalogItem(item) },
                                onTogglePlay: { model.auditionController.toggle(item: item) }
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            if model.homeMasterpieces.isEmpty && !model.isLoadingHome {
                ContentEmptyStrip(title: "精选曲谱尚未载入", detail: model.bootstrapMessage ?? "请检查随包曲库资源。")
            }
        }
    }

    private var bentoSection: some View {
        VStack(alignment: .leading, spacing: 23) {
            VStack(alignment: .center, spacing: 9) {
                MIMIPill(title: "⚡ NEXT-GEN MUSIC SCORE ENGINE", tint: Color(hex: 0x8F6D2B), fill: MIMITheme.warmGold.opacity(0.1))
                Text("为严谨研习打造的现代化乐谱特性")
                    .font(MIMITheme.displayFont(size: 30, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Text("谱面、播放、音轨与指板交互，在一页纸上彼此照应。")
                    .font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 19) {
                HStack(alignment: .top, spacing: 19) {
                    SynthesizerBentoCard(item: bentoItem, controller: model.auditionController)
                        .frame(maxWidth: .infinity)
                        .id(bentoItem?.id ?? "no-bento-item")
                    NotationBentoCard()
                        .frame(width: 380)
                }
                HStack(alignment: .top, spacing: 19) {
                    TrackMixerBentoCard()
                        .frame(width: 380)
                    FretboardBentoCard(item: bentoItem, controller: model.auditionController)
                        .frame(maxWidth: .infinity)
                        .id(bentoItem?.id ?? "no-bento-item")
                }
            }
        }
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                MIMISectionHeading(title: "全站研习热门排行榜", subtitle: "按曲库收录的热度浏览，找到下一首想练的曲子。")
                Spacer()
                HStack(spacing: 5) {
                    ForEach(RankingPeriod.allCases) { period in
                        Button { model.loadRankings(for: period) } label: {
                            Text(period.title).font(MIMITheme.bodyFont(size: 11, weight: .medium))
                                .foregroundStyle(model.rankingPeriod == period ? .white : MIMITheme.bodyInk)
                                .padding(.horizontal, 14).frame(height: 34)
                                .background(model.rankingPeriod == period ? MIMITheme.ink : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(MIMITheme.paper, in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))

                Button("查看完整榜单 →") {
                    model.navigate(.catalog(.all))
                    model.sort = .popular
                    model.sortDidChange()
                }
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(MIMITheme.darkGold)
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }

            HomeAuditionScope(controller: model.auditionController) { snapshot in
                let topRankings = Array(model.homeRankings.prefix(10))
                let podiumItems = Array(topRankings.prefix(3))
                let listItems = Array(topRankings.dropFirst(3))

                VStack(spacing: 16) {
                    // 1. Top 3 Grand Podium (冠亚季军荣誉席)
                    if !podiumItems.isEmpty {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(Array(podiumItems.enumerated()), id: \.element.id) { index, item in
                                PodiumCard(
                                    rank: index + 1,
                                    item: item,
                                    isPlaying: snapshot.activeItemID == item.id && snapshot.isPlaying,
                                    onOpen: { model.openCatalogItem(item) },
                                    onTogglePlay: { model.auditionController.toggle(item: item, previewDuration: 30) }
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    // 2. Ranks 4 ~ 10 Grid (4到10名 精选榜位)
                    if !listItems.isEmpty {
                        let leftList = listItems.enumerated().filter { $0.offset % 2 == 0 }
                        let rightList = listItems.enumerated().filter { $0.offset % 2 != 0 }

                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 10) {
                                ForEach(leftList, id: \.element.id) { idx, item in
                                    RankingRow(
                                        index: idx + 4,
                                        item: item,
                                        isPlaying: snapshot.activeItemID == item.id && snapshot.isPlaying,
                                        onOpen: { model.openCatalogItem(item) },
                                        onTogglePlay: { model.auditionController.toggle(item: item, previewDuration: 30) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 10) {
                                ForEach(rightList, id: \.element.id) { idx, item in
                                    RankingRow(
                                        index: idx + 4,
                                        item: item,
                                        isPlaying: snapshot.activeItemID == item.id && snapshot.isPlaying,
                                        onOpen: { model.openCatalogItem(item) },
                                        onTogglePlay: { model.auditionController.toggle(item: item, previewDuration: 30) }
                                    )
                                }
                                if rightList.count < leftList.count {
                                    rankingExploreMoreCard
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            if model.homeRankings.isEmpty {
                ContentEmptyStrip(title: "榜单正在准备", detail: "只有带有可播放原谱的真实曲库条目会进入榜单。")
            }
        }
    }

    private var rankingExploreMoreCard: some View {
        Button {
            model.navigate(.catalog(.all))
            model.sort = .popular
            model.sortDidChange()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16))
                    .foregroundStyle(MIMITheme.darkGold)
                    .frame(width: 34, height: 34)
                    .background(MIMITheme.warmGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现更多热门研习曲目")
                        .font(MIMITheme.displayFont(size: 13, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                    Text("曲库收录海量官方精编、用户工坊工程与名师独奏总谱。")
                        .font(MIMITheme.bodyFont(size: 10))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .lineLimit(1)
                }
                Spacer()
                Text("全部 →")
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.darkGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .background(Color(hex: 0xFDFBF7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.warmGold.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var theorySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            MIMISectionHeading(title: "乐理进阶天梯与调性探索罗盘", subtitle: "清晰规划你的吉他研习路线，从零基础启蒙到专业大师级独奏。")

            // Progressive Connected Stage Breadcrumbs
            HStack(spacing: 0) {
                ForEach(Array(TheoryLevel.rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(row.color)
                            .frame(width: 6, height: 6)
                        Text("L\(row.level) \(row.stage)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(row.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(row.color.opacity(0.08), in: Capsule())

                    if index < TheoryLevel.rows.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(MIMITheme.softBorder)
                            .padding(.horizontal, 6)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // 5 Progressive Level Cards
            HStack(alignment: .top, spacing: 12) {
                ForEach(TheoryLevel.rows) { row in
                    Button {
                        model.navigate(.catalog(.guitar))
                        model.difficultyFilter = row.level
                        model.filterDidChange()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            // Top Stage Tag & Color Pill
                            HStack {
                                MIMIPill(title: "L\(row.level) · \(row.stage)", tint: row.color, fill: row.color.opacity(0.12))
                                Spacer()
                                Text("LEVEL 0\(row.level)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(MIMITheme.mutedInk)
                            }

                            // Level Title
                            Text(row.title)
                                .font(MIMITheme.displayFont(size: 15, weight: .bold))
                                .foregroundStyle(MIMITheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            // Detail text
                            Text(row.detail)
                                .font(MIMITheme.bodyFont(size: 11))
                                .foregroundStyle(MIMITheme.bodyInk)
                                .lineSpacing(2.5)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

                            Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)

                            // Representative Songs Pills
                            VStack(alignment: .leading, spacing: 5) {
                                Text("经典研习代表作:")
                                    .font(MIMITheme.bodyFont(size: 10))
                                    .foregroundStyle(MIMITheme.mutedInk)

                                FlowSongPills(songs: row.reps, tint: row.color)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(row.color.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }

            // Bottom Key Families & Style Classification
            HStack(alignment: .top, spacing: 16) {
                keyFamilyPanel.frame(maxWidth: .infinity)
                stylePanel.frame(maxWidth: .infinity)
            }
        }
    }

    private var keyFamilyPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text("常用调性色彩与和弦家族")
                        .font(MIMITheme.displayFont(size: 18, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                    MIMIPill(title: "8大核心调性", tint: MIMITheme.darkGold, fill: MIMITheme.warmGold.opacity(0.12))
                }
                Spacer()
                Text("点击快速探索对应调性曲谱")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(KeyFamily.rows) { key in
                    keyFamilyButton(key)
                }
            }
        }
        .padding(18)
        .frame(minHeight: 220, alignment: .top)
        .mimiCard(radius: 20, fill: Color(hex: 0xFAF7F2))
    }

    private func keyFamilyButton(_ key: KeyFamily) -> some View {
        Button {
            model.navigate(.catalog(.all))
            model.keyFilter = key.key
            model.filterDidChange()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(key.tonic)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(key.color, in: Circle())

                    Text(key.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(MIMITheme.ink)
                    Spacer()
                }

                Text(key.mood)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .lineLimit(1)

                Text(key.chords)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(key.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Text("曲风分类与编曲体裁")
                        .font(MIMITheme.displayFont(size: 18, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                    MIMIPill(title: "6大体裁", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                }
                Spacer()
                Button("全部曲谱 →") {
                    model.navigate(.catalog(.all))
                }
                .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                .foregroundStyle(MIMITheme.darkGold)
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(TheoryStyle.rows) { style in
                    Button {
                        model.navigate(.catalog(.all))
                        model.styleFilter = style.value
                        model.filterDidChange()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: style.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(MIMITheme.darkGold)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(style.title)
                                    .font(MIMITheme.bodyFont(size: 12, weight: .bold))
                                    .foregroundStyle(MIMITheme.ink)
                                Text(style.desc)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(MIMITheme.mutedInk)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 4)

            // Custom Tab Submission Callout
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("未找到想要的曲谱？")
                        .font(MIMITheme.displayFont(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0x8F6D2B))
                    Text("支持导入 GP / IBE / XHE 格式，也可在制谱工坊自由编配。")
                        .font(MIMITheme.bodyFont(size: 10.5))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("上传自制谱") {
                        model.navigate(.upload)
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(MIMITheme.ink, in: Capsule())
                    .buttonStyle(.plain)

                    Button("制谱工坊") {
                        model.navigate(.studio)
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1))
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(MIMITheme.warmGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.warmGold.opacity(0.2), lineWidth: 1))
        }
        .padding(18)
        .frame(minHeight: 220, alignment: .top)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite)
    }

    private var studyNotesSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("我的练习手记").font(MIMITheme.displayFont(size: 24, weight: .bold)).foregroundStyle(MIMITheme.ink)
                    Text("收藏、待练与练习记录保存在这台 Mac，可在数据设置中备份。")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
                Button { model.navigate(.practice(scoreID: nil)) } label: {
                    Label("进入练习工作台 →", systemImage: "metronome")
                        .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40).background(Color(hex: 0x3D5947), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 5) {
                Text("待练与在练")
                Text("\(waitingCount)").fontWeight(.bold).foregroundStyle(MIMITheme.darkGold)
                Text("首 · 已保存")
                Text("\(sessionCount)").fontWeight(.bold).foregroundStyle(MIMITheme.darkGold)
                Text("次练习")
                Spacer()
                Text("本机个人数据").foregroundStyle(MIMITheme.mutedInk)
            }
            .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk)
            if !recentSessions.isEmpty {
                HStack(spacing: 12) {
                    ForEach(recentSessions) { session in
                        let score = model.personalSnapshot.scores.first(where: { $0.id == session.scoreId })
                        PracticeMemoryCard(session: session, score: score)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text("先在曲库中加入待练，或到“我的谱”导入自己的谱。在播放器中开始练习后，进度与笔记会出现在这里。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        .mimiCard(radius: 26, fill: Color(hex: 0xFFFDFA), shadowOpacity: 0.025)
    }

    private var callToAction: some View {
        VStack(spacing: 21) {
            MIMIPill(title: "✦ OVER \(model.catalogCount.formatted()) MASTERPIECES ✦", tint: Color(hex: 0xE2C078), fill: .white.opacity(0.08))
            Text("立即开启你的数字乐谱研习之旅")
                .font(MIMITheme.displayFont(size: 38, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text("告别劣质 PDF 与错漏百出的手抄谱。在高清原声伴奏中，重拾指尖拨动琴弦的纯粹感动。")
                .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(Color(hex: 0xD5C7B0)).multilineTextAlignment(.center).frame(maxWidth: 680)
            HStack(spacing: 13) {
                Button { model.navigate(.catalog(.all)) } label: {
                    Label("立即探索曲谱库", systemImage: "arrow.right")
                        .font(MIMITheme.bodyFont(size: 13, weight: .bold)).foregroundStyle(MIMITheme.ink)
                        .padding(.horizontal, 22).frame(height: 48)
                        .background(LinearGradient(colors: [MIMITheme.warmGold, Color(hex: 0xDFB55A)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
                Button { model.navigate(.upload) } label: {
                    Label("上传我的乐谱", systemImage: "square.and.arrow.up")
                        .font(MIMITheme.bodyFont(size: 13, weight: .medium)).foregroundStyle(MIMITheme.paperWhite)
                        .padding(.horizontal, 22).frame(height: 48)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.25), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 51).padding(.horizontal, 30)
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2D2926), Color(hex: 0x3A342F), Color(hex: 0x25211E)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [MIMITheme.warmGold.opacity(0.22), .clear], center: .bottomLeading, startRadius: 2, endRadius: 360)
                RadialGradient(colors: [MIMITheme.terracotta.opacity(0.16), .clear], center: .topTrailing, startRadius: 4, endRadius: 330)
                PaperGrainOverlay(opacity: 0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(MIMITheme.warmGold.opacity(0.5), lineWidth: 1))
        .shadow(color: MIMITheme.ink.opacity(0.10), radius: 8, y: 4)
    }

    private var footer: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 35) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        MIMILogoView(size: 36)
                        Text("MIMI Guitar 乐谱与练习").font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink)
                    }
                    Text("把每一份乐谱，都当作一页书来对待。为吉他与尤克里里演奏者提供乐谱浏览、播放控制和本地练习记录。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineSpacing(4).frame(maxWidth: 350, alignment: .leading)
                    HStack(spacing: 7) {
                        MIMIPill(title: "印", tint: MIMITheme.terracotta, fill: MIMITheme.terracotta.opacity(0.08))
                        Text("曲谱浏览 · 本地练习 · 个人备份").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                footerColumn("曲谱生态", links: [("吉他谱大全", .catalog(.guitar)), ("尤克里里精选", .catalog(.ukulele)), ("指弹独奏谱", .catalog(.guitar)), ("经典弹唱谱", .catalog(.guitar)), ("曲谱排序浏览", .catalog(.all))])
                footerColumn("核心功能", links: [("乐谱播放控制", .document(.help)), ("六线谱与简谱显示", .document(.help)), ("音轨播放设置", .document(.help)), ("吉他指板显示", .document(.help)), ("变调与移调设置", .document(.help))])
                footerColumn("乐理与工坊", links: [("个人导入曲谱", .library), ("动效与交互偏好", .motion), ("G 调和弦家族", .catalog(.all)), ("C 调入门精选", .catalog(.all)), ("零基础新手天梯", .catalog(.all))])
                VStack(alignment: .leading, spacing: 11) {
                    Text("关于与政策").font(MIMITheme.displayFont(size: 14, weight: .bold)).foregroundStyle(MIMITheme.ink)
                    footerLink("帮助中心", .document(.help))
                    footerLink("隐私政策", .document(.privacy))
                    footerLink("用户协议", .document(.agreement))
                    footerLink("版权政策", .document(.copyright))
                    footerLink("授权说明", .document(.licenses))
                }
            }
            Rectangle().fill(MIMITheme.softBorder).frame(height: 1)
            HStack {
                Text("© 2026 MIMI Guitar Workshop. All rights reserved.")
                Spacer()
                HStack(spacing: 13) {
                    footerLink("联系我们", .document(.contact))
                    footerLink("上传政策", .document(.uploadPolicy))
                    Button { NotificationCenter.default.post(name: .init("MIMI.ScrollToTop"), object: nil) } label: {
                        Label("返回顶部", systemImage: "arrow.up").font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
                            .padding(.horizontal, 12).padding(.vertical, 7).background(.white, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
        }
        .padding(.horizontal, 8).padding(.top, 36).padding(.bottom, 18)
        .background(MIMITheme.paper.opacity(0.72))
        .overlay(alignment: .top) { Rectangle().fill(MIMITheme.softBorder).frame(height: 1) }
    }

    private func footerColumn(_ title: String, links: [(String, NativeRoute)]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(MIMITheme.displayFont(size: 14, weight: .bold)).foregroundStyle(MIMITheme.ink)
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in footerLink(link.0, link.1) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footerLink(_ title: String, _ route: NativeRoute) -> some View {
        Button(title) { model.navigate(route) }.buttonStyle(.plain)
            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk)
    }

    private func submitHomeSearch(_ rawTerm: String) {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { model.presentCommandPalette(); return }
        model.saveRecentSearch(term)
        model.navigate(.search(query: term, domain: .all))
    }

    private func shuffleHero() {
        guard !HomeMasterpieceData.rows.isEmpty else { return }
        model.heroIndex = (model.heroIndex + 1) % HomeMasterpieceData.rows.count
    }

}

private struct HomeHotwordFlowLayout: Layout {
    var spacing: CGFloat = 7

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

private struct HomeSearchField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    let isHeroVisible: Bool
    let onSubmit: (String) -> Void
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    @State private var displayedPlaceholder = HomeSearchPlaceholder.values[0]
    @State private var placeholderIndex = 0
    @State private var typewriterTimer: Timer?

    private var canRunTypewriter: Bool {
        motionPreference == "system" && !reduceMotion && isHeroVisible && !isFocused && scenePhase == .active
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(MIMITheme.mutedInk).padding(.leading, 16)
            TextField(displayedPlaceholder, text: $searchText)
                .font(MIMITheme.bodyFont(size: 15)).textFieldStyle(.plain)
                .padding(.horizontal, 12).frame(height: 55)
                .focused($isFocused)
                .onSubmit { onSubmit(searchText) }
            Button { onSubmit(searchText) } label: {
                HStack(spacing: 7) {
                    Text("检索").font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                    Text("⌘K").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.warmGold)
                }
                .foregroundStyle(MIMITheme.paperWhite)
                .padding(.horizontal, 17).frame(height: 39)
                .background(MIMITheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain).padding(.trailing, 8)
        }
        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MIMITheme.softBorder, lineWidth: 1))
        .onAppear { syncTypewriter() }
        .onDisappear { stopTypewriter(reset: true) }
        .onChange(of: isFocused) { _ in syncTypewriter() }
        .onChange(of: isHeroVisible) { _ in syncTypewriter() }
        .onChange(of: scenePhase) { _ in syncTypewriter() }
        .onChange(of: motionPreference) { _ in syncTypewriter() }
        .onChange(of: reduceMotion) { _ in syncTypewriter() }
    }

    private func syncTypewriter() {
        stopTypewriter(reset: false)
        guard canRunTypewriter else { return }
        scheduleTypewriter(after: 4.5)
    }

    private func stopTypewriter(reset: Bool) {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        guard reset else { return }
        placeholderIndex = 0
        displayedPlaceholder = HomeSearchPlaceholder.values[0]
    }

    private func scheduleTypewriter(after interval: TimeInterval) {
        typewriterTimer?.invalidate()
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            guard canRunTypewriter else { stopTypewriter(reset: false); return }
            placeholderIndex = (placeholderIndex + 1) % HomeSearchPlaceholder.values.count
            displayedPlaceholder = HomeSearchPlaceholder.values[placeholderIndex]
        }
    }
}

private struct HeroFeatureCard: View {
    let item: CatalogItem
    let masterpiece: SourceMasterpiece
    let controller: NativeAuditionController
    let onShuffle: () -> Void
    let onOpen: () -> Void
    @StateObject private var auditionState: AuditionItemViewState
    @State private var isHovered = false

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var isActive: Bool { playback.isActive }

    init(item: CatalogItem, masterpiece: SourceMasterpiece, controller: NativeAuditionController, onShuffle: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.item = item
        self.masterpiece = masterpiece
        self.controller = controller
        self.onShuffle = onShuffle
        self.onOpen = onOpen
        _auditionState = StateObject(wrappedValue: controller.viewState(itemID: item.id, tracksClock: true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HStack(spacing: 8) {
                    Text(masterpiece.seal).font(MIMITheme.displayFont(size: 13, weight: .bold)).foregroundStyle(masterpiece.sealColor)
                        .frame(width: 27, height: 27).background(masterpiece.sealColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(masterpiece.sealColor.opacity(0.35), lineWidth: 1))
                    Text("今日典藏焦点").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1).foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer(minLength: 3)
                Button(action: onShuffle) {
                    Label("换一曲", systemImage: "shuffle").font(MIMITheme.bodyFont(size: 10, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk).padding(.horizontal, 10).frame(height: 32)
                        .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                }.buttonStyle(.plain).help("切换到下一首源站典藏名作")
                MIMIPill(title: "精选展示", tint: MIMITheme.terracotta, fill: MIMITheme.terracotta.opacity(0.08))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(masterpiece.title).font(MIMITheme.displayFont(size: 26, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Spacer(minLength: 4)
                MIMIPill(title: masterpiece.keyDescription, tint: Color(hex: 0x8F6D2B), fill: MIMITheme.warmGold.opacity(0.12))
            }
            Text("\(masterpiece.artist) · 速度 J=\(masterpiece.bpm) · \(masterpiece.timeSignature)")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("ORIGINAL TAB MANUSCRIPT", systemImage: "music.note")
                        .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.bodyInk)
                    Spacer()
                    Text(masterpiece.level)
                        .font(MIMITheme.bodyFont(size: 10, weight: .semibold))
                        .foregroundStyle(masterpiece.levelColor)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(masterpiece.levelColor.opacity(0.09), in: Capsule())
                        .overlay(Capsule().stroke(masterpiece.levelColor.opacity(0.28), lineWidth: 1))
                }
                HeroTabStaff(masterpiece: masterpiece, progress: isActive && playback.isPlaying && auditionState.clock.endTime > 0 ? auditionState.clock.currentTime / auditionState.clock.endTime : nil)
                    .frame(height: 74)
                Button {
                    if !item.scoreURL.isNilOrEmpty { controller.toggle(item: item) } else { onOpen() }
                } label: {
                    HStack(spacing: 9) {
                        if playback.isLoading { ProgressView().controlSize(.small).tint(.white) }
                        else { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                        Text(playback.isLoading ? "加载曲谱…" : (playback.isPlaying ? "暂停播放" : "播放曲谱"))
                        Spacer()
                        if isActive && !playback.statusMessage.isEmpty {
                            Text(playback.statusMessage).font(.system(size: 9)).lineLimit(1).foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(LinearGradient(colors: [MIMITheme.ink, Color(hex: 0x3D3833), MIMITheme.ink], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(item.scoreURL.isNilOrEmpty)
                if isActive && !playback.isLoading && !playback.isPlaying && !playback.canPlay && !playback.statusMessage.isEmpty {
                    HStack(spacing: 6) {
                        Text("曲谱播放失败：\(playback.statusMessage)").lineLimit(2)
                        Button("打开《\(masterpiece.title)》曲谱", action: onOpen).underline()
                    }
                    .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(Color(hex: 0x9B3328))
                }
            }
            .padding(13)
            .background(Color(hex: 0xFAF8F4), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MIMITheme.softBorder, lineWidth: 1))
            HStack(spacing: 6) {
                Text("核心和弦:").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                ForEach(masterpiece.chords, id: \.self) { chord in HomeChordChip(chord: chord) }
                Spacer(minLength: 4)
                Button("研习 →", action: onOpen).font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(hex: 0xFAF7F0), MIMITheme.paperWhite, Color(hex: 0xFAF6EE)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(isHovered ? MIMITheme.warmGold.opacity(0.45) : MIMITheme.softBorder, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
    }
}

private struct MasterpieceCard: View {
    let item: CatalogItem
    let info: StageMasterpiece
    let isPlaying: Bool
    let isLoading: Bool
    let statusMessage: String
    let onOpen: () -> Void
    let onTogglePlay: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(info.seal).font(MIMITheme.displayFont(size: 12, weight: .bold)).foregroundStyle(MIMITheme.terracotta)
                    .frame(width: 25, height: 25).background(MIMITheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(MIMITheme.terracotta.opacity(0.35), lineWidth: 1))
                Text("NO. \(String(info.id.prefix(4)).uppercased())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                Spacer()
                MIMIPill(title: "精选展示", tint: MIMITheme.terracotta, fill: MIMITheme.terracotta.opacity(0.08))
            }
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    Text(info.title).font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                }.buttonStyle(.plain)
                Text("\(info.artist) · \(info.key) 调 \(info.sheetForm)")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
            }
            Text(info.description)
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3).lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TAB SCORE PREVIEW").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.bodyInk)
                    Spacer()
                    Text("示例排版").font(.system(size: 9, weight: .semibold)).foregroundStyle(MIMITheme.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(MIMITheme.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                StageTabPreview()
                    .frame(height: 58)
                Button(action: onTogglePlay) {
                    HStack(spacing: 7) {
                        if isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                        Text(isLoading ? "加载曲谱…" : (isPlaying ? "暂停播放" : "试听原谱"))
                        Spacer()
                        if !statusMessage.isEmpty { Text(statusMessage).lineLimit(1).font(.system(size: 9)) }
                    }
                    .font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 10).frame(minHeight: 36)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(item.scoreURL.isNilOrEmpty)
            }
            .padding(12)
            .background(Color(hex: 0xFAF8F4), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.softBorder, lineWidth: 1))
            HStack(spacing: 5) {
                ForEach(info.chords.prefix(3), id: \.self) { chord in HomeChordChip(chord: chord, compact: true) }
                Spacer(minLength: 0)
                Button("研习 →", action: onOpen).font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
        }
        .padding(15)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isHovered ? MIMITheme.warmGold.opacity(0.45) : MIMITheme.softBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

private struct HeroTabStaff: View {
    let masterpiece: SourceMasterpiece
    let progress: Double?

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 300, size.height / 74)
            var drawing = context
            drawing.translateBy(x: (size.width - 300 * scale) / 2, y: (size.height - 74 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            let paper = Color(hex: 0xFAF8F4)
            let staff = Color(hex: 0xE0D6C0)
            let divider = Color(hex: 0xD5C7B0)
            let labels: [(String, CGFloat)] = [("T", 23), ("A", 41), ("B", 59)]
            for (label, y) in labels {
                drawing.draw(Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(MIMITheme.mutedInk), at: CGPoint(x: 6, y: y))
            }
            let barLines: [CGFloat] = [20, 292]
            for x in barLines {
                var path = Path(); path.move(to: CGPoint(x: x, y: 12)); path.addLine(to: CGPoint(x: x, y: 62))
                drawing.stroke(path, with: .color(divider), lineWidth: 1.5)
            }
            let staffLines: [CGFloat] = [12, 22, 32, 42, 52, 62]
            for y in staffLines {
                var path = Path(); path.move(to: CGPoint(x: 20, y: y)); path.addLine(to: CGPoint(x: 292, y: y))
                drawing.stroke(path, with: .color(staff), lineWidth: 1)
            }
            for (columnIndex, column) in masterpiece.tabColumns.enumerated() {
                let x: CGFloat = 60 + CGFloat(columnIndex) * 65
                for note in column.notes {
                    let y: CGFloat = 12 + CGFloat(note.string - 1) * 10
                    drawing.fill(Path(CGRect(x: x - 7, y: y - 6, width: 14, height: 12)), with: .color(paper))
                    drawing.draw(Text(String(note.fret)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(note.isRoot ? MIMITheme.terracotta : MIMITheme.ink), at: CGPoint(x: x, y: y + 4))
                }
            }
            if let progress {
                let x = CGFloat(35 + min(1, max(0, progress)) * 245)
                var playhead = Path(); playhead.move(to: CGPoint(x: x, y: 4)); playhead.addLine(to: CGPoint(x: x, y: 70))
                drawing.stroke(playhead, with: .color(MIMITheme.terracotta.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .accessibilityLabel("\(masterpiece.title) 原版六线谱片段")
    }
}

private struct StageTabPreview: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 56)
            var drawing = context
            drawing.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 56 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            let paper = Color(hex: 0xFAF8F4)
            let lineColor = Color(hex: 0xE0D6C0)
            let barLines: [CGFloat] = [10, 230]
            for x in barLines {
                var path = Path(); path.move(to: CGPoint(x: x, y: 8)); path.addLine(to: CGPoint(x: x, y: 48))
                drawing.stroke(path, with: .color(Color(hex: 0xD5C7B0)), lineWidth: 1.2)
            }
            let staffLines: [CGFloat] = [8, 21, 34, 48]
            for y in staffLines {
                var path = Path(); path.move(to: CGPoint(x: 10, y: y)); path.addLine(to: CGPoint(x: 230, y: y))
                drawing.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
            let notes: [[Int]] = [[0, 0, 3], [2, 0, 0], [3, 2, 0], [2, 0, 2]]
            for (column, values) in notes.enumerated() {
                let positions: [CGFloat] = [45, 100, 155, 205]
                let x = positions[column]
                for (row, value) in values.enumerated() {
                    let noteRows: [CGFloat] = [12, 25, 38]
                    let y = noteRows[row]
                    drawing.fill(Path(CGRect(x: x - 7, y: y - 6, width: 14, height: 12)), with: .color(paper))
                    let color = column == 0 ? MIMITheme.terracotta : MIMITheme.ink
                    drawing.draw(Text(String(value)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(color), at: CGPoint(x: x, y: y + 3))
                }
            }
        }
        .accessibilityLabel("TAB 示例排版")
    }
}

private struct SynthesizerTimeBadge: View {
    @StateObject private var clockState: AuditionItemViewState

    init(controller: NativeAuditionController) {
        _clockState = StateObject(wrappedValue: controller.viewState(tracksClock: true))
    }

    var body: some View {
        let cur = max(0, Int((clockState.clock.currentTime / 1000.0).rounded()))
        let end = max(0, Int((clockState.clock.endTime / 1000.0).rounded()))
        Text(String(format: "%d:%02d / %d:%02d", cur / 60, cur % 60, end / 60, end % 60))
            .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SynthesizerEqualizerBars: View {
    let isPlaying: Bool

    // 24 harmonic equalizer bar heights replicated from web BentoGridFeatures.svelte
    private static let baseHeights: [Double] = [
        40, 65, 80, 45, 90, 75, 60, 95, 70, 85, 50, 65,
        90, 40, 75, 85, 60, 70, 95, 55, 80, 65, 90, 45
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                guard w > 0, h > 0 else { return }

                let count = Self.baseHeights.count
                let spacing: CGFloat = 4.0
                let totalSpacing = spacing * CGFloat(count - 1)
                let barWidth = max(2.5, (w - totalSpacing) / CGFloat(count))
                let now = timeline.date.timeIntervalSinceReferenceDate
                let gradient = Gradient(colors: [Color(hex: 0x8F6D2B), MIMITheme.warmGold])

                for (i, base) in Self.baseHeights.enumerated() {
                    let dynamicPercent: Double
                    if isPlaying {
                        // Formula from web: h * (0.6 + 0.5 * sin(time / 120 + i)) -> ~8.33 rad/s angular speed
                        let wave = sin(now * 8.33 + Double(i) * 0.47)
                        dynamicPercent = min(100.0, max(15.0, base * (0.6 + 0.5 * wave)))
                    } else {
                        dynamicPercent = base
                    }

                    let barHeight = max(4.0, h * CGFloat(dynamicPercent / 100.0))
                    let x = CGFloat(i) * (barWidth + spacing)
                    let y = h - barHeight
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 2.5))

                    let opacity = min(1.0, 0.48 + dynamicPercent / 180.0)
                    context.opacity = opacity
                    context.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: x, y: h),
                            endPoint: CGPoint(x: x, y: y)
                        )
                    )
                }
            }
        }
        .frame(height: 76)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

private struct SynthesizerBentoCard: View {
    let item: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var globalAuditionState: AuditionItemViewState
    @StateObject private var itemAuditionState: AuditionItemViewState
    private var playback: AuditionPlaybackSnapshot { globalAuditionState.snapshot }
    private var itemPlayback: AuditionPlaybackSnapshot { itemAuditionState.snapshot }
    private var playing: Bool { playback.isPlaying }
    private var isSunnyPlaying: Bool { itemPlayback.isPlaying }

    init(item: CatalogItem?, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _globalAuditionState = StateObject(wrappedValue: controller.viewState(tracksClock: false))
        _itemAuditionState = StateObject(wrappedValue: controller.viewState(itemID: item?.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(playing ? "正在试听原谱" : "60FPS AUDIO SYNTHESIZER", systemImage: playing ? "waveform" : "waveform.path")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white).padding(.horizontal, 11).padding(.vertical, 6).background(MIMITheme.ink, in: Capsule())
                Spacer()
                Text(playing ? playback.statusMessage : "高保真原谱音源")
                    .font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.terracotta).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("内置原声吉他 SoundFont 高清合成器")
                    .font(MIMITheme.displayFont(size: 21, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                    .padding(.vertical, 1)
                Text("通过捆绑的谱面渲染与本地音源播放，谱面和声音保持同步。点击试听以打开真实随包原谱，不自动播放。")
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let item { controller.toggle(item: item, previewDuration: 30) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSunnyPlaying ? "pause.fill" : "play.fill")
                    Text(isSunnyPlaying ? "暂停试听《\(item?.title ?? "晴天")》" : "试听典藏原谱: 《\(item?.title ?? "晴天")》")
                        .lineLimit(1)
                    Spacer()
                    if playing {
                        SynthesizerTimeBadge(controller: controller)
                    } else {
                        Text("30s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                }
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.bodyInk)
                .padding(12).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.softBorder, lineWidth: 1))
            }.buttonStyle(.plain).disabled(item?.scoreURL == nil)

            // High-performance equalizer bars rendered via Metal Canvas (0 subviews, 0% idle CPU)
            SynthesizerEqualizerBars(isPlaying: playing)

            HStack {
                Label("SONiVOX SoundFont", systemImage: "speaker.wave.2.fill")
                Spacer()
                Text("声音初始化时间不计入试听").foregroundStyle(MIMITheme.mutedInk)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 360, alignment: .leading)
        .background(LinearGradient(colors: [.white, Color(hex: 0xFAF6EE)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .mimiCard(radius: 25)
    }
}

private struct NotationBentoCard: View {
    @State private var activeNotation = "mixed"
    private let choices = [("简谱并排", "mixed"), ("纯六线谱", "tab"), ("数字简谱", "jianpu")]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                MIMIPill(title: "🎼 简六双排", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                Spacer()
                Text("同步预览").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            Text("简谱 · 六线谱 · 和弦一键切换")
                .font(MIMITheme.displayFont(size: 18, weight: .bold))
                .foregroundStyle(MIMITheme.ink)
                .lineLimit(1)
                .padding(.vertical, 1)
            Text("首创简谱与六线谱完美对齐技术，歌词、唱名、左右手指法一目了然。")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.bodyInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 3) {
                ForEach(choices, id: \.1) { choice in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeNotation = choice.1
                        }
                    } label: {
                        Text(choice.0)
                            .font(MIMITheme.bodyFont(size: 11, weight: activeNotation == choice.1 ? .semibold : .medium))
                            .foregroundStyle(activeNotation == choice.1 ? MIMITheme.ink : MIMITheme.bodyInk)
                            .frame(maxWidth: .infinity)
                            .frame(height: 29)
                            .background(activeNotation == choice.1 ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: activeNotation == choice.1 ? Color.black.opacity(0.06) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color(hex: 0xEDE5D8), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(spacing: 8) {
                if activeNotation == "mixed" || activeNotation == "jianpu" {
                    HStack {
                        ForEach(["1", "2", "3", "5"], id: \.self) { value in
                            Text(value)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(MIMITheme.terracotta)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xF0EAE0)).frame(height: 1) }
                }
                if activeNotation == "mixed" || activeNotation == "tab" {
                    HStack {
                        ForEach(Array(["0", "2", "3", "2"].enumerated()), id: \.offset) { _, value in
                            Text(value)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: 0x5C4A38))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: 0xE8E2D4), lineWidth: 1))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25, fill: MIMITheme.paperWhite)
    }
}

private struct BentoDemoTrack: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let volume: Double
}

private struct TrackMixerBentoCard: View {
    @State private var mutedTracks: Set<String> = []
    private let tracks = [
        BentoDemoTrack(id: "guitar", title: "主音吉他", symbol: "guitars", volume: 0.90),
        BentoDemoTrack(id: "bass", title: "贝斯声部", symbol: "waveform", volume: 0.75),
        BentoDemoTrack(id: "drums", title: "打击鼓组", symbol: "music.note.list", volume: 0.60),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                MIMIPill(title: "🎚 多轨调音台", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                Spacer()
                Text("MIXER").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            Text("为每件乐器单独调整聆听重点").font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink)
            Text("静音按钮改变当前预览轨道状态，进入播放器可对真实音轨进行完整混音。")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3)
            VStack(spacing: 10) {
                ForEach(tracks) { track in
                    HStack(spacing: 10) {
                        Image(systemName: track.symbol).frame(width: 20).foregroundStyle(mutedTracks.contains(track.id) ? MIMITheme.mutedInk : MIMITheme.darkGold)
                        Text(track.title).font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.ink).frame(width: 66, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Capsule().fill(MIMITheme.softBorder).frame(height: 5)
                            if !mutedTracks.contains(track.id) {
                                Capsule().fill(MIMITheme.warmGold.gradient)
                                    .frame(height: 5)
                                    .scaleEffect(x: track.volume, y: 1, anchor: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                        Button(mutedTracks.contains(track.id) ? "取消静音" : "MUTE") {
                            if mutedTracks.contains(track.id) { mutedTracks.remove(track.id) } else { mutedTracks.insert(track.id) }
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(mutedTracks.contains(track.id) ? MIMITheme.terracotta : MIMITheme.bodyInk)
                        .padding(.horizontal, 8).frame(height: 27).background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            Label("示例音轨静音状态已更新", systemImage: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color(hex: 0x3D5947))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25)
    }
}

struct FretPosition: Hashable { let string: Int; let fret: Int }

struct FretboardBentoCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var activeFret: FretPosition?
    let item: CatalogItem?
    let controller: NativeAuditionController
    @StateObject private var globalAuditionState: AuditionItemViewState
    @StateObject private var itemAuditionState: AuditionItemViewState
    private let stringNames = ["e", "B", "G", "D", "A", "E"]
    private let fretNumbers = [0, 1, 2, 3, 5, 7, 9, 12]
    private let chordPatterns: [[FretPosition]] = [
        [FretPosition(string: 6, fret: 3), FretPosition(string: 2, fret: 3), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 4, fret: 0), FretPosition(string: 3, fret: 0)],
        [FretPosition(string: 2, fret: 3), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 5, fret: 2), FretPosition(string: 4, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 3, fret: 0), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 5, fret: 3), FretPosition(string: 4, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 3, fret: 0), FretPosition(string: 1, fret: 3)],
        [FretPosition(string: 4, fret: 0), FretPosition(string: 3, fret: 2), FretPosition(string: 2, fret: 3)],
        [FretPosition(string: 1, fret: 2), FretPosition(string: 2, fret: 3)],
    ]

    init(item: CatalogItem? = nil, controller: NativeAuditionController) {
        self.item = item
        self.controller = controller
        _globalAuditionState = StateObject(wrappedValue: controller.viewState(tracksClock: false, tracksNotes: true))
        _itemAuditionState = StateObject(wrappedValue: controller.viewState(itemID: item?.id))
    }

    private var playback: AuditionPlaybackSnapshot { itemAuditionState.snapshot }
    private var isPlaying: Bool { globalAuditionState.snapshot.isPlaying }
    private var isSunnyPlaying: Bool { playback.isPlaying }
    private var isDemoLoading: Bool { playback.isLoading }
    private var demoError: String? { playback.errorMessage }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading
            Text("沿着琴弦与品柱，理解每一个音的位置")
                .font(MIMITheme.displayFont(size: 19, weight: .bold))
                .foregroundStyle(MIMITheme.ink)
            Text("播放《晴天》时指板跟随真实发声音符高亮；停止播放后可点选品位手动查看。")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.bodyInk)
            if let demoError {
                HStack(spacing: 7) {
                    Text("曲谱播放失败：\(demoError)").lineLimit(2)
                    if let item {
                        Button("打开《\(item.title)》曲谱") { model.openCatalogItem(item) }.buttonStyle(.plain).underline()
                    }
                }
                .font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.terracotta)
            }
            fretboard
            fretLabels
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
        .mimiCard(radius: 25)
    }

    private var heading: some View {
        HStack {
            MIMIPill(title: "🎸 虚拟指板", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
            Text("22 品全息指板投影").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.darkGold)
            Spacer(minLength: 6)
            Button {
                activeFret = nil
                if let item { controller.toggle(item: item) }
            } label: {
                HStack(spacing: 6) {
                    if isDemoLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: isSunnyPlaying ? "pause.fill" : "play.fill") }
                    Text(auditionButtonTitle)
                }
                .font(MIMITheme.bodyFont(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(item?.scoreURL == nil)
            .help("播放或暂停《晴天》曲谱")
        }
    }

    private var auditionButtonTitle: String {
        if isDemoLoading { return "加载曲谱…" }
        if isSunnyPlaying { return "暂停《\(item?.title ?? "晴天")》播放" }
        return "播放《\(item?.title ?? "晴天")》曲谱"
    }

    private var fretboard: some View {
        HStack(spacing: 0) {
            stringLabels
            fretGrid
        }
    }

    private var stringLabels: some View {
        VStack(spacing: 0) {
            ForEach(Array(stringNames.enumerated()), id: \.offset) { index, name in
                Text(name)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(index < 3 ? Color(hex: 0xC5A35D) : Color(hex: 0xC9C5BF))
                    .frame(width: 27, height: 26)
            }
        }
    }

    private var fretGrid: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let totalHeight = proxy.size.height
            let colWidth = totalWidth / CGFloat(fretNumbers.count)
            let rowHeight = totalHeight / CGFloat(stringNames.count)
            let notes = globalAuditionState.activeNotes.map { FretPosition(string: $0.string, fret: $0.fret) }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying || !notes.isEmpty)) { timeline in
                Canvas { context, size in
                    // 1. Draw fretboard background
                    let bgRect = CGRect(origin: .zero, size: size)
                    let bgPath = Path(roundedRect: bgRect, cornerRadius: 7)
                    let gradient = Gradient(colors: [Color(hex: 0x42372B), Color(hex: 0x5A4836)])
                    context.fill(bgPath, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

                    // 2. Fret marker inlays at frets 3, 5, 7, 9, 12
                    let markerFrets: [Int] = [3, 5, 7, 9, 12]
                    for (col, fret) in fretNumbers.enumerated() {
                        if markerFrets.contains(fret) {
                            let cx = (CGFloat(col) + 0.5) * colWidth
                            let cy = size.height / 2
                            let dotRect = CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5)
                            context.fill(Path(ellipseIn: dotRect), with: .color(Color(hex: 0xD9C79E).opacity(0.7)))
                        }
                    }

                    // 3. Vertical fret wires
                    for col in 0..<fretNumbers.count {
                        let x = CGFloat(col + 1) * colWidth
                        let wireWidth: CGFloat = (fretNumbers[col] == 0) ? 3 : 1.4
                        let wireRect = CGRect(x: x - wireWidth, y: 0, width: wireWidth, height: size.height)
                        context.fill(Path(wireRect), with: .color(Color(hex: 0xCFC6B7)))
                    }

                    // 4. Horizontal strings
                    for stringIndex in 0..<stringNames.count {
                        let y = (CGFloat(stringIndex) + 0.5) * rowHeight
                        let stringGauge: CGFloat = CGFloat(1 + (stringIndex / 2))
                        let stringRect = CGRect(x: 0, y: y - stringGauge / 2, width: size.width, height: stringGauge)
                        let stringColor = (stringIndex < 2) ? Color(hex: 0xC8C2B6) : MIMITheme.warmGold.opacity(0.85)
                        context.fill(Path(stringRect), with: .color(stringColor))
                    }

                    // 5. Highlighted fret notes (dynamic notes from score or rhythmic chord pattern)
                    let currentHighlights: [FretPosition]
                    if isPlaying {
                        if !notes.isEmpty {
                            currentHighlights = notes
                        } else {
                            let now = timeline.date.timeIntervalSinceReferenceDate
                            let patternIndex = Int(now / 0.28) % chordPatterns.count
                            currentHighlights = chordPatterns[patternIndex]
                        }
                    } else {
                        currentHighlights = [activeFret ?? FretPosition(string: 2, fret: 3)]
                    }

                    for pos in currentHighlights {
                        let stringIndex = 6 - pos.string
                        guard stringIndex >= 0 && stringIndex < stringNames.count else { continue }
                        guard let col = fretNumbers.firstIndex(of: pos.fret) else { continue }
                        let cellRect = CGRect(x: CGFloat(col) * colWidth, y: CGFloat(stringIndex) * rowHeight, width: colWidth, height: rowHeight)
                        context.fill(Path(cellRect), with: .color(MIMITheme.terracotta.opacity(0.18)))

                        let dotDiameter: CGFloat = 15
                        let dotRect = CGRect(x: cellRect.midX - dotDiameter / 2, y: cellRect.midY - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
                        context.fill(Path(ellipseIn: dotRect), with: .color(MIMITheme.terracotta))

                        let text = Text(pos.fret == 0 ? "0" : "\(pos.fret)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.white)
                        context.draw(context.resolve(text), at: CGPoint(x: dotRect.midX, y: dotRect.midY), anchor: .center)
                    }
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { gesture in
                    let col = Int(gesture.location.x / colWidth)
                    let row = Int(gesture.location.y / rowHeight)
                    if col >= 0 && col < fretNumbers.count && row >= 0 && row < stringNames.count {
                        activeFret = FretPosition(string: 6 - row, fret: fretNumbers[col])
                    }
                }
            )
        }
        .frame(height: 156)
    }

    private var fretLabels: some View {
        HStack {
            Text("0品 / 空弦")
            Spacer()
            ForEach(["3", "5", "7", "9"], id: \.self) { fret in
                Text(fret)
                Spacer()
            }
            Text("12")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(MIMITheme.mutedInk)
        .padding(.leading, 29)
    }
}

private struct PodiumCard: View {
    let rank: Int
    let item: CatalogItem
    let isPlaying: Bool
    let onOpen: () -> Void
    let onTogglePlay: () -> Void

    private var medalTitle: String {
        switch rank {
        case 1: return "🥇 榜首 · 金榜荣光"
        case 2: return "🥈 亚军 · 银榜雅韵"
        case 3: return "🥉 季军 · 铜榜华章"
        default: return "TOP \(rank)"
        }
    }

    private var accentGradient: LinearGradient {
        switch rank {
        case 1:
            return LinearGradient(colors: [Color(hex: 0xD4AF37), Color(hex: 0x9B6D28)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2:
            return LinearGradient(colors: [Color(hex: 0x9EA7B2), Color(hex: 0x5C6878)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color(hex: 0xC87D55), Color(hex: 0x8C4E26)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                rank == 1
                    ? LinearGradient(colors: [Color.white, Color(hex: 0xFFFCF5), Color(hex: 0xFDF6EA)], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.white, Color(hex: 0xFAF8F5)], startPoint: .top, endPoint: .bottom)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                rank == 1 ? Color(hex: 0xE6C875).opacity(0.8) : (rank == 2 ? Color(hex: 0xD0D7DE).opacity(0.8) : Color(hex: 0xE2C8B8).opacity(0.8)),
                lineWidth: rank == 1 ? 1.5 : 1
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Badge & Rank Ribbon
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text(String(format: "%02d", rank))
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentGradient, in: Capsule())

                    Text(medalTitle)
                        .font(MIMITheme.bodyFont(size: 11, weight: .bold))
                        .foregroundStyle(rank == 1 ? MIMITheme.darkGold : MIMITheme.bodyInk)
                }

                Spacer()

                Label(item.displayHeat, systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(MIMITheme.terracotta)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(MIMITheme.terracotta.opacity(0.08), in: Capsule())
            }

            // Song Title & Artist
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(MIMITheme.displayFont(size: 17, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(item.artist ?? "未知歌手")
                            .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                            .foregroundStyle(MIMITheme.bodyInk)
                            .lineLimit(1)

                        if let key = item.key {
                            Text("·").foregroundStyle(MIMITheme.softBorder)
                            Text("\(key) 调")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MIMITheme.darkGold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(MIMITheme.warmGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)

            // Bottom Actions & Difficulty Badge
            HStack(spacing: 8) {
                DifficultyBadge(difficulty: item.difficulty)

                Spacer()

                Button(action: onOpen) {
                    Text("详情")
                        .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(MIMITheme.paper, in: Capsule())
                        .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onTogglePlay) {
                    HStack(spacing: 5) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isPlaying ? "试听中" : "试听")
                            .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isPlaying ? .white : MIMITheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(isPlaying ? MIMITheme.darkGold : MIMITheme.warmGold.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(isPlaying ? Color.clear : MIMITheme.warmGold.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(item.scoreURL == nil)
            }
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: Color.black.opacity(rank == 1 ? 0.05 : 0.02), radius: 8, x: 0, y: 2)
    }
}

private struct RankingRow: View {
    let index: Int
    let item: CatalogItem
    let isPlaying: Bool
    let onOpen: () -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Rank number badge
            Text(String(format: "%02d", index))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(MIMITheme.bodyInk)
                .frame(width: 34, height: 34)
                .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))

            // Title & Info
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(MIMITheme.displayFont(size: 14, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.artist ?? "未知歌手")
                            .font(MIMITheme.bodyFont(size: 11))
                            .foregroundStyle(MIMITheme.mutedInk)
                            .lineLimit(1)
                        if let key = item.key {
                            Text("·").foregroundStyle(MIMITheme.softBorder)
                            Text("\(key) 调")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(MIMITheme.mutedInk)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            DifficultyBadge(difficulty: item.difficulty)

            Label(item.displayHeat, systemImage: "flame.fill")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(MIMITheme.terracotta)

            Button(action: onTogglePlay) {
                HStack(spacing: 4) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(isPlaying ? "播放中" : "播放")
                        .font(MIMITheme.bodyFont(size: 10, weight: .medium))
                }
                .foregroundStyle(isPlaying ? MIMITheme.darkGold : MIMITheme.bodyInk)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(isPlaying ? MIMITheme.warmGold.opacity(0.15) : MIMITheme.paper, in: Capsule())
                .overlay(Capsule().stroke(isPlaying ? MIMITheme.darkGold.opacity(0.4) : MIMITheme.softBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(item.scoreURL == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }
}

private struct TheoryLevel: Identifiable {
    let level: Int
    let stage: String
    let title: String
    let detail: String
    let reps: [String]
    let color: Color
    var id: Int { level }

    static let rows: [TheoryLevel] = [
        TheoryLevel(level: 1, stage: "启蒙破冰", title: "零基础 · 启蒙", detail: "单音旋律、入门开放和弦与基础扫弦", reps: ["小星星", "老男孩"], color: Color(hex: 0x2E7D32)),
        TheoryLevel(level: 2, stage: "弹唱基石", title: "初级 · 熟练弹唱", detail: "常用大调和弦、基础切音与前奏滑音", reps: ["晴天", "后来", "平凡之路"], color: Color(hex: 0x00838F)),
        TheoryLevel(level: 3, stage: "复调独奏", title: "中级 · 进阶独奏", detail: "F大横按攻克、击勾弦与中级指弹复调", reps: ["反方向的钟", "我记得", "海阔天空"], color: Color(hex: 0x1565C0)),
        TheoryLevel(level: 4, stage: "舞台炫技", title: "高级 · 舞台指弹", detail: "拍弦（Slap）、点弦、人工泛音与变拍子", reps: ["卡农", "加州旅馆", "风之诗"], color: Color(hex: 0xE65100)),
        TheoryLevel(level: 5, stage: "大师造极", title: "专业 · 大师总谱", detail: "多声部交响吉他、特殊调弦法与极速独奏", reps: ["Fight", "Wings", "黄昏"], color: Color(hex: 0x8F6D2B))
    ]
}

private struct FlowSongPills: View {
    let songs: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                ForEach(songs, id: \.self) { song in
                    songBadge(song)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(songs, id: \.self) { song in
                    songBadge(song)
                }
            }
        }
    }

    private func songBadge(_ title: String) -> some View {
        Text("《\(title)》")
            .font(MIMITheme.bodyFont(size: 10, weight: .medium))
            .foregroundStyle(MIMITheme.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 0.8))
    }
}

private struct KeyFamily: Identifiable {
    let key: String
    let tonic: String
    let title: String
    let mood: String
    let chords: String
    let color: Color
    var id: String { key }

    static let rows = [
        KeyFamily(key: "C", tonic: "C", title: "C 大调", mood: "纯净基石 · 温暖明朗", chords: "C · Dm · Em · F · G · Am", color: Color(hex: 0x1565C0)),
        KeyFamily(key: "G", tonic: "G", title: "G 大调", mood: "民谣灵魂 · 清澈开阔", chords: "G · Am · Bm · C · D · Em", color: Color(hex: 0x2E7D32)),
        KeyFamily(key: "D", tonic: "D", title: "D 大调", mood: "明快辉煌 · 抒情指弹", chords: "D · Em · F#m · G · A · Bm", color: Color(hex: 0xE65100)),
        KeyFamily(key: "A", tonic: "A", title: "A 大调", mood: "清亮激昂 · 流行摇滚", chords: "A · Bm · C#m · D · E · F#m", color: Color(hex: 0x7B1FA2)),
        KeyFamily(key: "E", tonic: "E", title: "E 大调", mood: "浑厚深沉 · 蓝调布鲁斯", chords: "E · F#m · G#m · A · B · C#m", color: Color(hex: 0xC2185B)),
        KeyFamily(key: "F", tonic: "F", title: "F 大调", mood: "柔和浪漫 · 横按试炼", chords: "F · Gm · Am · Bb · C · Dm", color: Color(hex: 0x00838F)),
        KeyFamily(key: "Em", tonic: "Em", title: "Em 小调", mood: "苍凉质朴 · 幽谷民谣", chords: "Em · F#dim · G · Am · Bm · C", color: Color(hex: 0x5C4A38)),
        KeyFamily(key: "Am", tonic: "Am", title: "Am 小调", mood: "凄美深情 · 经典流行", chords: "Am · Bdim · C · Dm · Em · F", color: Color(hex: 0xC84B31)),
    ]
}

private struct TheoryStyle: Identifiable {
    let value: Int
    let title: String
    let desc: String
    let icon: String
    var id: Int { value }
    static let rows = [
        TheoryStyle(value: 101, title: "流行", desc: "流行金曲 · 抒情弹唱", icon: "music.mic"),
        TheoryStyle(value: 102, title: "摇滚", desc: "经典摇滚 · 电声热血", icon: "bolt.fill"),
        TheoryStyle(value: 103, title: "民谣", desc: "原声吉他 · 校园诗意", icon: "guitars"),
        TheoryStyle(value: 105, title: "配乐", desc: "影视原声 · 游戏动漫", icon: "film.fill"),
        TheoryStyle(value: 107, title: "乡村", desc: "指尖律动 · 欢快叙事", icon: "leaf.fill"),
        TheoryStyle(value: 109, title: "金属", desc: "强力和弦 · 极速失真", icon: "flame.fill"),
    ]
}

private struct PracticeMemoryCard: View {
    @EnvironmentObject private var model: AppModel
    let session: PracticeSession
    let score: PersonalScore?
    private var durationMinutes: Int { Int(session.slices.reduce(0) { $0 + $1.durationMs } / 60_000) }

    var body: some View {
        Button { model.navigate(.practice(scoreID: session.scoreId)) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(score?.title ?? "曲谱未找到").font(MIMITheme.displayFont(size: 15, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(durationMinutes) 分钟").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Color(hex: 0x3D5947))
                }
                Text(score?.artist ?? "").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                Text(session.note.isEmpty ? "下次继续练习，随手记下需要攻克的小节。" : session.note)
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineLimit(2).frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                Label(score == nil ? "曲谱已缺失 · 查看我的谱" : "继续练习 →", systemImage: score == nil ? "exclamationmark.circle" : "arrow.right")
                    .font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(Color(hex: 0x3D5947))
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(MIMITheme.softBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct ContentEmptyStrip: View {
    let title: String; let detail: String
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "music.note.list").foregroundStyle(MIMITheme.warmGold)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                if !detail.isEmpty { Text(detail).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
            }
            Spacer()
        }
        .padding(15).mimiCard(radius: 15, fill: MIMITheme.paperWhite)
    }
}

private struct PaperGrainOverlay: View {
    var opacity = 0.14
    var body: some View {
        Image(decorative: PaperAmbienceTile.grain, scale: 2, orientation: .up)
            .resizable(resizingMode: .tile)
            .opacity(opacity / 0.14)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty != false }
}
