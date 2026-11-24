import MIMICore
import SwiftUI

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
        VStack(alignment: .leading, spacing: sectionSpacing) {
            hero
            masterpieceSection
            bentoSection
            rankingSection
            theorySection
                .id("home-theory-section")
            studyNotesSection
            callToAction
            footer
                .id("home-footer-section")
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
                MIMISectionHeading(
                    title: "精选曲目展示",
                    subtitle: "华语经典与入门必弹名作，原版六线谱前奏试听与一键研习"
                )
                Spacer()
                Button {
                    model.navigate(.catalog(.all))
                    model.sort = .popular
                    model.sortDidChange()
                } label: {
                    HStack(spacing: 5) {
                        Text("浏览全部曲谱")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(MIMITheme.paperWhite, in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
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
        VStack(alignment: .leading, spacing: 22) {
            MIMISectionHeading(
                title: "乐理进阶天梯与调性探索罗盘",
                subtitle: "清晰规划你的吉他研习路线，从零基础启蒙到专业大师级独奏"
            )

            // Progressive Connected Stage Stepper Rail
            HStack(spacing: 0) {
                ForEach(Array(TheoryLevel.rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        model.navigate(.catalog(.guitar))
                        model.difficultyFilter = row.level
                        model.filterDidChange()
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 19, height: 19)
                                Text("\(row.level)")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Text(row.stage)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MIMITheme.ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2A2520),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(row.color.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)

                    if index < TheoryLevel.rows.count - 1 {
                        HStack(spacing: 3) {
                            Rectangle()
                                .fill(LinearGradient(colors: [row.color.opacity(0.4), TheoryLevel.rows[index + 1].color.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                                .frame(height: 2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(TheoryLevel.rows[index + 1].color.opacity(0.6))
                        }
                        .frame(maxWidth: 36)
                        .padding(.horizontal, 4)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            // 5 Progressive Level Cards
            HStack(alignment: .top, spacing: 12) {
                ForEach(TheoryLevel.rows) { row in
                    TheoryLevelCard(row: row) {
                        model.navigate(.catalog(.guitar))
                        model.difficultyFilter = row.level
                        model.filterDidChange()
                    }
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
                    KeyFamilyButton(key: key) {
                        model.navigate(.catalog(.all))
                        model.keyFilter = key.key
                        model.filterDidChange()
                    }
                }
            }
        }
        .padding(20)
        .frame(minHeight: 224, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dynamic(lightHex: 0xFAF7F2, darkHex: 0x24201C),
                            Color.dynamic(lightHex: 0xF5F0E6, darkHex: 0x1F1B17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MIMITheme.softBorder, lineWidth: 1)
        )
        .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.03), radius: 8, y: 2)
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Text("曲风分类与编曲体裁")
                        .font(MIMITheme.displayFont(size: 18, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                    MIMIPill(title: "6大体裁", tint: MIMITheme.bodyInk, fill: MIMITheme.warmGold.opacity(0.10))
                }
                Spacer()
                Button {
                    model.navigate(.catalog(.all))
                } label: {
                    HStack(spacing: 4) {
                        Text("全部曲谱")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2A2520), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(TheoryStyle.rows) { style in
                    TheoryStyleTile(style: style) {
                        model.navigate(.catalog(.all))
                        model.styleFilter = style.value
                        model.filterDidChange()
                    }
                }
            }

            Spacer(minLength: 4)

            // Custom Tab Submission Callout
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MIMITheme.darkGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text("未找到想要的曲谱？")
                        .font(MIMITheme.displayFont(size: 12.5, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
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
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(MIMITheme.ink, in: Capsule())
                    .buttonStyle(.plain)

                    Button("制谱工坊 PRO") {
                        model.navigate(.studio)
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2A2520), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1))
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.dynamic(lightHex: 0xF5EFE4, darkHex: 0x2A2520))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MIMITheme.softBorder, lineWidth: 1)
            )
        }
        .padding(20)
        .frame(minHeight: 224, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dynamic(lightHex: 0xFAF7F2, darkHex: 0x24201C),
                            Color.dynamic(lightHex: 0xF5F0E6, darkHex: 0x1F1B17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MIMITheme.softBorder, lineWidth: 1)
        )
        .shadow(color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.03), radius: 8, y: 2)
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
        VStack(spacing: 28) {
            // Main Top Content
            HStack(alignment: .top, spacing: 36) {
                // Left Brand Column & Colophon Bookplate
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        MIMILogoView(size: 40, cornerRadius: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MIMI Guitar")
                                .font(MIMITheme.displayFont(size: 20, weight: .bold))
                                .foregroundStyle(MIMITheme.ink)
                            Text("数字乐谱 · 严谨研习工坊")
                                .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                                .foregroundStyle(MIMITheme.darkGold)
                        }
                    }

                    // Inscription blockquote
                    HStack(alignment: .top, spacing: 10) {
                        Rectangle()
                            .fill(MIMITheme.warmGold.gradient)
                            .frame(width: 3)
                            .cornerRadius(1.5)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("“把每一份乐谱，都当作一页书来对待。”")
                                .font(MIMITheme.displayFont(size: 13, weight: .semibold))
                                .foregroundStyle(MIMITheme.ink)
                            Text("为吉他与尤克里里演奏者打造的离线优先乐谱系统，提供六线谱原手稿排版、原声音轨播放控制与本地研习记录。")
                                .font(MIMITheme.bodyFont(size: 11))
                                .foregroundStyle(MIMITheme.mutedInk)
                                .lineSpacing(3.5)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.dynamic(lightHex: 0xF3EFE6, darkHex: 0x2A251F))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MIMITheme.softBorder.opacity(0.7), lineWidth: 1)
                    )

                    // Architecture & Capability Badges
                    HStack(spacing: 7) {
                        HomeFooterPill(icon: "apple.logo", title: "macOS 原生", color: MIMITheme.ink)
                        HomeFooterPill(icon: "bolt.fill", title: "120Hz 渲染", color: MIMITheme.warmGold)
                        HomeFooterPill(icon: "lock.shield.fill", title: "100% 离线私有", color: MIMITheme.green)
                    }
                }
                .frame(maxWidth: 370, alignment: .leading)

                // Right 4 Curated Category Tiles
                HStack(alignment: .top, spacing: 20) {
                    HomeFooterColumn(
                        title: "曲谱生态",
                        icon: "music.quarternote.3",
                        iconColor: MIMITheme.terracotta,
                        links: [
                            ("吉他曲谱全集", .catalog(.guitar)),
                            ("尤克里里专区", .catalog(.ukulele)),
                            ("经典指弹独奏", .catalog(.guitar)),
                            ("原版民谣弹唱", .catalog(.guitar)),
                            ("按热度排序浏览", .catalog(.all))
                        ],
                        onNavigate: { model.navigate($0) }
                    )

                    HomeFooterColumn(
                        title: "核心特性",
                        icon: "tuningfork",
                        iconColor: MIMITheme.warmGold,
                        links: [
                            ("六线谱与简谱排版", .document(.help)),
                            ("多音轨原声试听", .catalog(.all)),
                            ("吉他指板与和弦", .catalog(.guitar)),
                            ("速度与移调控制", .document(.help)),
                            ("无损打印与导出", .document(.help))
                        ],
                        onNavigate: { model.navigate($0) }
                    )

                    HomeFooterColumn(
                        title: "工坊研习",
                        icon: "waveform.and.magnifyingglass",
                        iconColor: Color.dynamic(lightHex: 0xA86A3D, darkHex: 0xD4945C),
                        links: [
                            ("制谱工坊 PRO", .studio),
                            ("我的练习中心", .practice(scoreID: nil)),
                            ("个人曲谱书库", .library),
                            ("深度专栏文章", .articles),
                            ("动效与交互偏好", .motion)
                        ],
                        onNavigate: { model.navigate($0) }
                    )

                    HomeFooterColumn(
                        title: "关于规范",
                        icon: "shield.lefthalf.filled",
                        iconColor: MIMITheme.green,
                        links: [
                            ("使用帮助与快捷键", .document(.help)),
                            ("隐私与本地安全", .document(.privacy)),
                            ("用户服务协议", .document(.agreement)),
                            ("乐谱版权说明", .document(.copyright)),
                            ("开源与授权说明", .document(.licenses))
                        ],
                        onNavigate: { model.navigate($0) }
                    )
                }
                .frame(maxWidth: .infinity)
            }

            // Divider Line
            Rectangle()
                .fill(MIMITheme.softBorder.opacity(0.85))
                .frame(height: 1)

            // Bottom Colophon Status Bar
            HStack(spacing: 14) {
                // Left copyright & craft declaration
                VStack(alignment: .leading, spacing: 2) {
                    Text("© 2026 MIMI Guitar Workshop. All rights reserved.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk)
                    Text("专为严谨吉他演奏与研习打造 · 本地优先数字乐谱架构")
                        .font(.system(size: 9.5))
                        .foregroundStyle(MIMITheme.mutedInk)
                }

                Spacer()

                // Center Library Readiness status pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(MIMITheme.green)
                        .frame(width: 6, height: 6)
                    Text("本地引擎已就绪 · \(model.catalogCount > 0 ? "\(model.catalogCount)" : "16,233") 首曲库")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.dynamic(lightHex: 0xF3EFE6, darkHex: 0x2A251F))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MIMITheme.softBorder, lineWidth: 1)
                )

                Spacer()

                // Right quick actions
                HStack(spacing: 9) {
                    Button { model.presentCommandPalette() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("快捷指令")
                                .font(MIMITheme.bodyFont(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(MIMITheme.bodyInk)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2C2721), in: Capsule())
                        .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button { model.navigate(.document(.contact)) } label: {
                        Text("联系我们")
                            .font(MIMITheme.bodyFont(size: 10.5))
                            .foregroundStyle(MIMITheme.bodyInk)
                    }
                    .buttonStyle(.plain)

                    Button { model.navigate(.document(.uploadPolicy)) } label: {
                        Text("上传政策")
                            .font(MIMITheme.bodyFont(size: 10.5))
                            .foregroundStyle(MIMITheme.bodyInk)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NotificationCenter.default.post(name: .init("MIMI.ScrollToTop"), object: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 9, weight: .bold))
                            Text("返回顶部")
                                .font(MIMITheme.bodyFont(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(MIMITheme.darkGold)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            Color.dynamic(lightHex: 0xFFFFFF, darkHex: 0x2C2721),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.dynamic(lightHex: 0xFFFEFA, darkHex: 0x25211D),
                            Color.dynamic(lightHex: 0xF7F4EB, darkHex: 0x201C18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MIMITheme.softBorder, lineWidth: 1)
        )
        .shadow(
            color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000)).opacity(0.04),
            radius: 12,
            y: 4
        )
        .padding(.top, 10)
        .padding(.bottom, 24)
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
