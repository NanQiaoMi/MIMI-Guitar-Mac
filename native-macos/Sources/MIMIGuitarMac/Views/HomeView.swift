import MIMICore
import SwiftUI

private struct HomeHeroFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private final class HomeHeroSpotlight: ObservableObject {
    @Published var center = UnitPoint(x: 0.85, y: 0.08)
}

private struct HomeHeroBackdrop: View {
    @ObservedObject var spotlight: HomeHeroSpotlight

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [MIMITheme.paperWhite.opacity(0.97), Color(hex: 0xFCF8F0), MIMITheme.paperWhite], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [MIMITheme.warmGold.opacity(0.12), .clear], center: spotlight.center, startRadius: 10, endRadius: 600)
            PaperGrainOverlay()
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var heroIsVisible = false
    @State private var didSelectInitialHero = false
    @State private var heroSpotlight = HomeHeroSpotlight()
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
    private var fullMotionAllowed: Bool { motionPreference == "system" && !reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            hero
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                masterpieceSection
                bentoSection
                rankingSection
                theorySection
                studyNotesSection
                callToAction
                footer
            }
            .padding(.top, 64)
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
        .onChange(of: motionPreference) { _ in
            if !fullMotionAllowed { heroSpotlight.center = UnitPoint(x: 0.85, y: 0.08) }
        }
        .onChange(of: reduceMotion) { _ in
            if !fullMotionAllowed { heroSpotlight.center = UnitPoint(x: 0.85, y: 0.08) }
        }
        .onChange(of: model.rankingPeriod) { newValue in model.loadRankings(for: newValue) }
        .onPreferenceChange(HomeHeroFramePreferenceKey.self) { frame in
            let isVisible = frame.maxY > 0 && frame.minY < 900
            guard isVisible != heroIsVisible else { return }
            heroIsVisible = isVisible
        }
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
                                .frame(height: 3).offset(y: 3)
                        }
                }
                .font(MIMITheme.displayFont(size: 48, weight: .bold))
                .tracking(-1.2)
                .lineSpacing(8)
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
            HomeHeroBackdrop(spotlight: heroSpotlight)
        }
        .onContinuousHover { phase in
            guard fullMotionAllowed else { heroSpotlight.center = UnitPoint(x: 0.85, y: 0.08); return }
            switch phase {
            case .active(let location):
                // The full hero's spotlight tracks the pointer, matching the source's fine-pointer surface.
                heroSpotlight.center = UnitPoint(x: min(1, max(0, location.x / 1240)), y: min(1, max(0, location.y / 585)))
            case .ended:
                heroSpotlight.center = UnitPoint(x: 0.85, y: 0.08)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous).stroke(MIMITheme.faintBorder, lineWidth: 1))
        .shadow(color: MIMITheme.bodyInk.opacity(0.06), radius: 28, x: 0, y: 10)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HomeHeroFramePreferenceKey.self, value: proxy.frame(in: .global))
        })
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 17), GridItem(.flexible(), spacing: 17), GridItem(.flexible(), spacing: 17), GridItem(.flexible(), spacing: 17)], spacing: 19) {
                ForEach(HomeMasterpieceStageData.rows) { info in
                    if let item = model.homeMasterpieces.first(where: { $0.id == info.id }) {
                        MasterpieceCard(item: item, info: info, controller: model.auditionController)
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 19), GridItem(.flexible(), spacing: 19), GridItem(.flexible(), spacing: 19)], spacing: 19) {
                SynthesizerBentoCard(item: bentoItem, controller: model.auditionController)
                    .gridCellColumns(2)
                    .id(bentoItem?.id ?? "no-bento-item")
                NotationBentoCard()
                TrackMixerBentoCard()
                FretboardBentoCard(item: bentoItem, controller: model.auditionController)
                    .gridCellColumns(2)
                    .id(bentoItem?.id ?? "no-bento-item")
            }
        }
    }

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                MIMISectionHeading(title: "全站研习热门排行榜", subtitle: "按曲库收录的热度浏览，找到下一首想练的曲子。")
                HStack(spacing: 5) {
                    ForEach(RankingPeriod.allCases) { period in
                        Button { model.loadRankings(for: period) } label: {
                            Text(period.title).font(MIMITheme.bodyFont(size: 11, weight: .medium))
                                .foregroundStyle(model.rankingPeriod == period ? .white : MIMITheme.bodyInk)
                                .padding(.horizontal, 12).frame(height: 34)
                                .background(model.rankingPeriod == period ? MIMITheme.ink : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(4).background(MIMITheme.paper, in: Capsule())
                Button("查看完整榜单 →") { model.navigate(.catalog(.all)); model.sort = .popular; model.sortDidChange() }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 14) {
                ForEach(Array(model.homeRankings.prefix(10).enumerated()), id: \.element.id) { index, item in
                    RankingRow(index: index + 1, item: item, controller: model.auditionController)
                }
            }
            if model.homeRankings.isEmpty {
                ContentEmptyStrip(title: "榜单正在准备", detail: "只有带有可播放原谱的真实曲库条目会进入榜单。")
            }
        }
    }

    private var theorySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            MIMISectionHeading(title: "乐理进阶天梯与调性探索罗盘", subtitle: "清晰规划你的吉他研习路线，从零基础启蒙到专业大师级独奏。")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 13), count: 5), spacing: 13) {
                ForEach(TheoryLevel.rows) { row in
                    Button { model.navigate(.catalog(.guitar)); model.difficultyFilter = row.level; model.filterDidChange() } label: {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack {
                                MIMIPill(title: "L\(row.level)", tint: row.color, fill: row.color.opacity(0.08))
                                Spacer()
                                Text("LEVEL 0\(row.level)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                            }
                            Text(row.title).font(MIMITheme.displayFont(size: 17, weight: .bold)).foregroundStyle(MIMITheme.ink)
                            Text(row.detail).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3).frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                            Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("经典研习代表作:").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                                Text(row.representatives).font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.ink).lineLimit(2)
                            }
                        }
                        .padding(15).frame(maxWidth: .infinity, minHeight: 213, alignment: .topLeading)
                        .mimiCard(radius: 18, fill: MIMITheme.paperWhite)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(alignment: .top, spacing: 20) {
                keyFamilyPanel.frame(maxWidth: .infinity)
                stylePanel.frame(maxWidth: .infinity)
            }
        }
    }

    private var keyFamilyPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("常用调性色彩与和弦家族").font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("点击快速探索对应调性曲谱").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(KeyFamily.rows) { key in
                    Button { model.navigate(.catalog(.all)); model.keyFilter = key.key; model.filterDidChange() } label: {
                        VStack(spacing: 6) {
                            Text(key.title).font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundStyle(key.color)
                            Text(key.chords).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1).minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity, minHeight: 59)
                        .background(.white, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(MIMITheme.softBorder, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(20).mimiCard(radius: 22, fill: Color(hex: 0xFAF7F2))
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("曲风分类与编曲体裁").font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Spacer()
                Button("全部 →") { model.navigate(.catalog(.all)) }.font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
            FlowPills(items: TheoryStyle.rows) { style in
                model.navigate(.catalog(.all)); model.styleFilter = style.value; model.filterDidChange()
            }
            Spacer(minLength: 0)
            HStack {
                Text("未找到想要的曲谱？").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(Color(hex: 0x8F6D2B))
                Spacer()
                Button("上传自制手稿 →") { model.navigate(.upload) }
                    .font(MIMITheme.bodyFont(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7).background(MIMITheme.ink, in: Capsule()).buttonStyle(.plain)
            }
            .padding(11).background(MIMITheme.warmGold.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
        }
        .padding(20).frame(minHeight: 205).mimiCard(radius: 22, fill: MIMITheme.paperWhite)
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(recentSessions) { session in
                        let score = model.personalSnapshot.scores.first(where: { $0.id == session.scoreId })
                        PracticeMemoryCard(session: session, score: score)
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
        .shadow(color: MIMITheme.ink.opacity(0.22), radius: 24, y: 12)
    }

    private var footer: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top, spacing: 35) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        Text("M").font(MIMITheme.displayFont(size: 17, weight: .bold)).foregroundStyle(MIMITheme.paperWhite).frame(width: 36, height: 36).background(MIMITheme.ink, in: RoundedRectangle(cornerRadius: 11))
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
    @State private var placeholderCharacter = 0
    @State private var deletingPlaceholder = false
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
        stopTypewriter(reset: true)
        guard canRunTypewriter else { return }
        scheduleTypewriter(after: 0.75)
    }

    private func stopTypewriter(reset: Bool) {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        guard reset else { return }
        placeholderIndex = 0
        placeholderCharacter = 0
        deletingPlaceholder = false
        displayedPlaceholder = HomeSearchPlaceholder.values[0]
    }

    private func scheduleTypewriter(after interval: TimeInterval) {
        typewriterTimer?.invalidate()
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            typewriterTimer = nil
            guard canRunTypewriter else { stopTypewriter(reset: true); return }
            let text = HomeSearchPlaceholder.values[placeholderIndex]
            if deletingPlaceholder {
                placeholderCharacter = max(0, placeholderCharacter - 1)
                displayedPlaceholder = String(text.prefix(placeholderCharacter))
                if placeholderCharacter == 0 {
                    deletingPlaceholder = false
                    placeholderIndex = (placeholderIndex + 1) % HomeSearchPlaceholder.values.count
                    scheduleTypewriter(after: 0.4)
                } else {
                    scheduleTypewriter(after: 0.03)
                }
            } else {
                placeholderCharacter = min(text.count, placeholderCharacter + 1)
                displayedPlaceholder = String(text.prefix(placeholderCharacter))
                if placeholderCharacter >= text.count {
                    deletingPlaceholder = true
                    scheduleTypewriter(after: 2.6)
                } else {
                    scheduleTypewriter(after: 0.075)
                }
            }
        }
    }
}

private struct HeroFeatureCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    let item: CatalogItem
    let masterpiece: SourceMasterpiece
    let controller: NativeAuditionController
    let onShuffle: () -> Void
    let onOpen: () -> Void
    @StateObject private var auditionState: AuditionItemViewState

    @State private var tiltX = 0.0
    @State private var tiltY = 0.0
    @State private var shine = UnitPoint(x: 0.5, y: 0.5)
    @State private var isHovered = false

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var isActive: Bool { playback.isActive }
    private var fullMotionAllowed: Bool { motionPreference == "system" && !reduceMotion }

    init(item: CatalogItem, masterpiece: SourceMasterpiece, controller: NativeAuditionController, onShuffle: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.item = item
        self.masterpiece = masterpiece
        self.controller = controller
        self.onShuffle = onShuffle
        self.onOpen = onOpen
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id, tracksClock: true))
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
        .background {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xFAF7F0), MIMITheme.paperWhite, Color(hex: 0xFAF6EE)], startPoint: .topLeading, endPoint: .bottomTrailing)
                GeometryReader { proxy in
                    RadialGradient(colors: [Color.white.opacity(0.72), .clear], center: shine, startRadius: 4, endRadius: max(proxy.size.width, proxy.size.height) * 0.9)
                        .opacity(isHovered && fullMotionAllowed ? 0.85 : 0)
                }
                .allowsHitTesting(false)
            }
        }
        .mimiCard(radius: 25, fill: .clear, border: MIMITheme.softBorder, shadowOpacity: 0.09)
        .rotation3DEffect(.degrees(fullMotionAllowed ? tiltX : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        .rotation3DEffect(.degrees(fullMotionAllowed ? tiltY : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
        .scaleEffect(isHovered && fullMotionAllowed ? 1.01 : 1)
        .animation(fullMotionAllowed ? .timingCurve(0.2, 0, 0, 1, duration: 0.2) : nil, value: tiltX)
        .animation(fullMotionAllowed ? .timingCurve(0.2, 0, 0, 1, duration: 0.2) : nil, value: tiltY)
        .onContinuousHover { phase in
            guard fullMotionAllowed else { resetHover(); return }
            switch phase {
            case .active(let location):
                isHovered = true
                tiltX = min(6, max(-6, (location.y / 460 - 0.5) * -12))
                tiltY = min(6, max(-6, (location.x / 405 - 0.5) * 12))
                shine = UnitPoint(x: min(1, max(0, location.x / 405)), y: min(1, max(0, location.y / 460)))
            case .ended: resetHover()
            }
        }
        .onChange(of: motionPreference) { _ in resetHover() }
        .onChange(of: reduceMotion) { _ in resetHover() }
    }

    private func resetHover() {
        isHovered = false
        tiltX = 0
        tiltY = 0
        shine = UnitPoint(x: 0.5, y: 0.5)
    }
}

private struct MasterpieceCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    let item: CatalogItem
    let info: StageMasterpiece
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState
    @State private var tiltX = 0.0
    @State private var tiltY = 0.0
    @State private var shine = UnitPoint(x: 0.5, y: 0.5)
    @State private var isHovered = false

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var playing: Bool { playback.isPlaying }
    private var isActive: Bool { playback.isActive }
    private var fullMotionAllowed: Bool { motionPreference == "system" && !reduceMotion }

    init(item: CatalogItem, info: StageMasterpiece, controller: NativeAuditionController) {
        self.item = item
        self.info = info
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

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
                Button { model.openCatalogItem(item) } label: {
                    Text(info.title).font(MIMITheme.displayFont(size: 19, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                }.buttonStyle(.plain)
                Text("\(info.artist) · \(info.key) 调 \(info.sheetForm)")
                    .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
            }
            Text(info.description)
                .font(MIMITheme.proseFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3).lineLimit(2).frame(minHeight: 34, alignment: .topLeading)
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
                Button {
                    controller.toggle(item: item)
                } label: {
                    HStack(spacing: 7) {
                        if playback.isLoading { ProgressView().controlSize(.small) }
                        else { Image(systemName: playing ? "pause.fill" : "play.fill") }
                        Text(playback.isLoading ? "加载曲谱…" : (playing ? "暂停播放" : "试听原谱"))
                        Spacer()
                        if isActive { Text(playback.statusMessage).lineLimit(1).font(.system(size: 9)) }
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
                Button("研习 →") { model.openCatalogItem(item) }.font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
        }
        .padding(15)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(MIMITheme.paperWhite)
                GeometryReader { proxy in
                    RadialGradient(colors: [MIMITheme.warmGold.opacity(0.13), .clear], center: shine, startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.8)
                        .opacity(isHovered && fullMotionAllowed ? 1 : 0)
                }
                .allowsHitTesting(false)
            }
        }
        .mimiCard(radius: 20, fill: .clear, shadowOpacity: isHovered ? 0.12 : 0.04)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .rotation3DEffect(.degrees(fullMotionAllowed ? tiltX : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
        .rotation3DEffect(.degrees(fullMotionAllowed ? tiltY : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
        .scaleEffect(isHovered && fullMotionAllowed ? 1.01 : 1)
        .animation(fullMotionAllowed ? .timingCurve(0.2, 0, 0, 1, duration: 0.2) : nil, value: tiltX)
        .onContinuousHover { phase in
            guard fullMotionAllowed else { resetHover(); return }
            switch phase {
            case .active(let location):
                isHovered = true
                tiltX = min(6, max(-6, (location.y / 340 - 0.5) * -12))
                tiltY = min(6, max(-6, (location.x / 280 - 0.5) * 12))
                shine = UnitPoint(x: min(1, max(0, location.x / 280)), y: min(1, max(0, location.y / 340)))
            case .ended: resetHover()
            }
        }
        .onChange(of: motionPreference) { _ in resetHover() }
        .onChange(of: reduceMotion) { _ in resetHover() }
    }

    private func resetHover() {
        isHovered = false
        tiltX = 0
        tiltY = 0
        shine = UnitPoint(x: 0.5, y: 0.5)
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
        _globalAuditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, tracksClock: true))
        _itemAuditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item?.id))
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
                Text("内置原声吉他 SoundFont 高清合成器").font(MIMITheme.displayFont(size: 21, weight: .bold)).foregroundStyle(MIMITheme.ink)
                Text("通过捆绑的谱面渲染与本地音源播放，谱面和声音保持同步。点击试听以打开真实随包原谱，不自动播放。")
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(4)
            }
            Button {
                if let item { controller.toggle(item: item, previewDuration: 30) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSunnyPlaying ? "pause.fill" : "play.fill")
                    Text(isSunnyPlaying ? "暂停试听《\(item?.title ?? "")》" : "试听典藏原谱")
                    Spacer()
                    Text(playing ? "\(clock(globalAuditionState.clock.currentTime)) / \(clock(globalAuditionState.clock.endTime))" : "30s")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.bodyInk)
                .padding(12).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(MIMITheme.softBorder, lineWidth: 1))
            }.buttonStyle(.plain).disabled(item?.scoreURL == nil)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<28, id: \.self) { index in
                    let baseline = Double((index * 19 + 31) % 57 + 20)
                    let live = playing ? baseline * (0.55 + 0.45 * abs(sin(globalAuditionState.clock.currentTime * 4 + Double(index) * 0.47))) : baseline
                    Capsule().fill(LinearGradient(colors: [Color(hex: 0x8F6D2B), MIMITheme.warmGold], startPoint: .bottom, endPoint: .top))
                        .frame(maxWidth: .infinity).frame(height: CGFloat(live)).opacity(0.48 + live / 180)
                }
            }
            .frame(height: 76).padding(.horizontal, 10).padding(.top, 4)
            .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14))
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
    private func clock(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NotationBentoCard: View {
    @State private var activeNotation = "mixed"
    private let choices = [("混排", "mixed"), ("纯六线", "tab"), ("数字谱", "jianpu")]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                MIMIPill(title: "🎼 简六双排", tint: MIMITheme.bodyInk, fill: MIMITheme.paper)
                Spacer()
                Text("同步预览").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
            }
            Text("简谱 · 六线谱 · 和弦一键切换").font(MIMITheme.displayFont(size: 18, weight: .bold)).foregroundStyle(MIMITheme.ink)
            Text("切换示例中的简谱与 TAB 谱行，看看三种排布各自保留哪些信息。")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(3)
            HStack(spacing: 3) {
                ForEach(choices, id: \.1) { choice in
                    Button { activeNotation = choice.1 } label: {
                        Text(choice.0).font(.system(size: 10, weight: .medium)).foregroundStyle(activeNotation == choice.1 ? .white : MIMITheme.bodyInk)
                            .padding(.horizontal, 9).frame(height: 29).background(activeNotation == choice.1 ? MIMITheme.ink : MIMITheme.paper, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(3).background(MIMITheme.paper, in: Capsule())
            VStack(spacing: 7) {
                if activeNotation == "mixed" || activeNotation == "jianpu" {
                    HStack {
                        ForEach(["1", "2", "3", "5"], id: \.self) { value in
                            Text(value).frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(MIMITheme.terracotta)
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(MIMITheme.paper).frame(height: 1) }
                }
                if activeNotation == "mixed" || activeNotation == "tab" {
                    HStack {
                        ForEach(Array(["0", "2", "3", "2"].enumerated()), id: \.offset) { _, value in
                            Text(value).frame(maxWidth: .infinity)
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MIMITheme.mutedInk)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .center)
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(MIMITheme.softBorder, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                MIMIPill(title: choices.first(where: { $0.1 == activeNotation })?.0 ?? "混排", tint: MIMITheme.darkGold, fill: MIMITheme.paperWhite.opacity(0.95)).padding(8)
            }
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
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(MIMITheme.softBorder).frame(height: 5)
                                Capsule().fill(MIMITheme.mutedInk.opacity(0.4))
                                    .overlay {
                                        if !mutedTracks.contains(track.id) {
                                            Capsule().fill(MIMITheme.warmGold.gradient)
                                        }
                                    }
                                    .frame(width: proxy.size.width * (mutedTracks.contains(track.id) ? 0 : track.volume), height: 5)
                            }.frame(maxHeight: .infinity)
                        }.frame(height: 14)
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
        _globalAuditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, tracksClock: true, tracksNotes: true))
        _itemAuditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item?.id))
    }

    private var playback: AuditionPlaybackSnapshot { itemAuditionState.snapshot }
    private var isPlaying: Bool { globalAuditionState.snapshot.isPlaying }
    private var isSunnyPlaying: Bool { playback.isPlaying }
    private var isDemoLoading: Bool { playback.isLoading }
    private var demoError: String? { playback.errorMessage }

    private var highlightedFrets: [FretPosition] {
        if isPlaying {
            let actualNotes = globalAuditionState.activeNotes.map { FretPosition(string: $0.string, fret: $0.fret) }
            if !actualNotes.isEmpty { return actualNotes }
            let patternIndex = Int((globalAuditionState.clock.currentTime * 1_000) / 280) % chordPatterns.count
            return chordPatterns[patternIndex]
        }
        return [activeFret ?? FretPosition(string: 2, fret: 3)]
    }

    private func isHighlighted(_ position: FretPosition) -> Bool {
        highlightedFrets.contains(position)
    }

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
        VStack(spacing: 0) {
            ForEach(Array(stringNames.enumerated()), id: \.offset) { stringIndex, _ in
                HStack(spacing: 0) {
                    ForEach(fretNumbers, id: \.self) { fret in
                        fretCell(stringIndex: stringIndex, fret: fret)
                    }
                }
            }
        }
        .background(LinearGradient(colors: [Color(hex: 0x42372B), Color(hex: 0x5A4836)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 7))
        .overlay { fretMarkers }
    }

    private func fretCell(stringIndex: Int, fret: Int) -> some View {
        let position = FretPosition(string: 6 - stringIndex, fret: fret)
        let highlighted = isHighlighted(position)
        return Button { activeFret = position } label: {
            ZStack {
                Rectangle().fill(highlighted ? MIMITheme.terracotta.opacity(0.18) : Color.clear)
                if highlighted {
                    Circle().fill(MIMITheme.terracotta).frame(width: 15, height: 15)
                        .overlay(Text(fret == 0 ? "0" : "\(fret)").font(.system(size: 7, weight: .bold)).foregroundStyle(.white))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .overlay(alignment: .bottom) {
                Rectangle().fill(stringIndex < 2 ? Color(hex: 0xC8C2B6) : MIMITheme.warmGold.opacity(0.85))
                    .frame(height: CGFloat(1 + (stringIndex / 2)))
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color(hex: 0xCFC6B7)).frame(width: fret == 0 ? 3 : 1.4)
            }
        }
        .buttonStyle(.plain)
    }

    private var fretMarkers: some View {
        GeometryReader { proxy in
            ForEach([3, 5, 7, 9, 12], id: \.self) { fret in
                if let column = fretNumbers.firstIndex(of: fret) {
                    Circle().fill(Color(hex: 0xD9C79E).opacity(0.7)).frame(width: 5, height: 5)
                        .position(x: proxy.size.width * (CGFloat(column) + 0.5) / CGFloat(fretNumbers.count), y: proxy.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }
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

private struct RankingRow: View {
    @EnvironmentObject private var model: AppModel
    let index: Int
    let item: CatalogItem
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState
    private var playing: Bool { auditionState.snapshot.isPlaying }
    private var medal: Color { index == 1 ? Color(hex: 0xC49A45) : (index == 2 ? Color(hex: 0xA5A6A7) : (index == 3 ? Color(hex: 0xB97950) : MIMITheme.softBorder)) }

    init(index: Int, item: CatalogItem, controller: NativeAuditionController) {
        self.index = index
        self.item = item
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller, itemID: item.id))
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(index <= 3 ? .white : MIMITheme.bodyInk)
                .frame(width: 37, height: 37)
                .background {
                    if index <= 3 {
                        RoundedRectangle(cornerRadius: 12).fill(medal.gradient)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(MIMITheme.paper)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(index <= 3 ? .white.opacity(0.6) : MIMITheme.softBorder, lineWidth: 1))
            Button { model.openCatalogItem(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(MIMITheme.displayFont(size: 15, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.artist ?? "未知歌手").lineLimit(1)
                        Text("·").foregroundStyle(MIMITheme.softBorder)
                        Text(item.key.map { "\($0) 调" } ?? "调性未标注").lineLimit(1)
                    }.font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            DifficultyBadge(difficulty: item.difficulty)
            Label(item.displayHeat, systemImage: "flame.fill").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MIMITheme.terracotta)
            Button { controller.toggle(item: item, previewDuration: 30) } label: {
                HStack(spacing: 4) { Image(systemName: playing ? "pause.fill" : "play.fill"); Text(playing ? "播放中" : "播放") }
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
                    .padding(.horizontal, 9).frame(minHeight: 35)
                    .background(MIMITheme.paper, in: Capsule()).overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            }.buttonStyle(.plain).disabled(item.scoreURL == nil)
        }
        .padding(12).frame(minHeight: 61)
        .background {
            if index <= 3 {
                RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [.white, Color(hex: 0xFFFCF5)], startPoint: .leading, endPoint: .trailing))
            } else {
                RoundedRectangle(cornerRadius: 17).fill(MIMITheme.paperWhite)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(index <= 3 ? MIMITheme.warmGold.opacity(0.28) : MIMITheme.softBorder, lineWidth: 1))
        .shadow(color: MIMITheme.bodyInk.opacity(0.035), radius: 7, y: 2)
    }
}

private enum TheoryLevel: Identifiable {
    case value(Int, String, String, String)
    var id: Int { level }
    var level: Int { if case .value(let value, _, _, _) = self { return value }; return 0 }
    var title: String { if case .value(_, let value, _, _) = self { return value }; return "" }
    var detail: String { if case .value(_, _, let value, _) = self { return value }; return "" }
    var representatives: String { if case .value(_, _, _, let value) = self { return value }; return "" }
    var color: Color { [Color(hex: 0x2E7D32), Color(hex: 0x00838F), Color(hex: 0x1565C0), Color(hex: 0xE65100), Color(hex: 0xB71C1C)][max(0, level - 1)] }
    static let rows: [TheoryLevel] = [
        .value(1, "零基础 · 启蒙", "单音旋律、入门和弦与简单分解扫弦", "《小星星》《老男孩》"),
        .value(2, "初级 · 熟练弹唱", "常用大调开放和弦、基础切音与前奏滑音", "《晴天》《后来》《平凡之路》"),
        .value(3, "中级 · 进阶独奏", "F 大横按攻克、击勾弦与中级指弹复调编曲", "《反方向的钟》《我记得》《海阔天空》"),
        .value(4, "高级 · 舞台指弹", "拍弦、点弦、人工泛音与复杂变拍子", "《卡农》《加州旅馆》《风之诗》"),
        .value(5, "专业 · 大师总谱", "多声部交响化吉他、特殊调弦法与极速独奏", "《Fight》《Wings You are the HERO》"),
    ]
}

private struct KeyFamily: Identifiable {
    let key: String; let title: String; let chords: String; let color: Color
    var id: String { key }
    static let rows = [
        KeyFamily(key: "C", title: "C 大调", chords: "C - Dm - Em - F - G - Am", color: Color(hex: 0x1565C0)),
        KeyFamily(key: "G", title: "G 大调", chords: "G - Am - Bm - C - D - Em", color: Color(hex: 0x2E7D32)),
        KeyFamily(key: "D", title: "D 大调", chords: "D - Em - F#m - G - A - Bm", color: Color(hex: 0xE65100)),
        KeyFamily(key: "A", title: "A 大调", chords: "A - Bm - C#m - D - E - F#m", color: Color(hex: 0x7B1FA2)),
        KeyFamily(key: "E", title: "E 大调", chords: "E - F#m - G#m - A - B - C#m", color: Color(hex: 0xC2185B)),
        KeyFamily(key: "F", title: "F 大调", chords: "F - Gm - Am - Bb - C - Dm", color: Color(hex: 0x00838F)),
        KeyFamily(key: "Em", title: "Em 小调", chords: "Em - F#dim - G - Am - Bm - C", color: Color(hex: 0x5C4A38)),
        KeyFamily(key: "Am", title: "Am 小调", chords: "Am - Bdim - C - Dm - Em - F", color: Color(hex: 0xC84B31)),
    ]
}

private struct TheoryStyle: Identifiable {
    let value: Int; let title: String
    var id: Int { value }
    static let rows = [TheoryStyle(value: 101, title: "流行"), TheoryStyle(value: 102, title: "摇滚"), TheoryStyle(value: 103, title: "民谣"), TheoryStyle(value: 105, title: "配乐"), TheoryStyle(value: 107, title: "乡村"), TheoryStyle(value: 109, title: "金属")]
}

private struct FlowPills: View {
    let items: [TheoryStyle]
    let action: (TheoryStyle) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(items) { pill($0) } }
            VStack(alignment: .leading, spacing: 8) {
                HStack { ForEach(Array(items.prefix(3))) { pill($0) } }
                HStack { ForEach(Array(items.dropFirst(3))) { pill($0) } }
            }
        }
    }
    private func pill(_ item: TheoryStyle) -> some View {
        Button { action(item) } label: {
            Text(item.title).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk)
                .padding(.horizontal, 12).padding(.vertical, 7).background(MIMITheme.paper, in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
        }.buttonStyle(.plain)
    }
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
        Canvas { context, size in
            for row in stride(from: 0.0, through: size.height, by: 16) {
                for column in stride(from: 0.0, through: size.width, by: 16) {
                    let seed = Int((row / 16) * 31 + (column / 16) * 17)
                    let alpha = Double((seed * 19 % 13) + 2) / 1000
                    let dot = CGRect(x: column + CGFloat(seed % 3), y: row + CGFloat((seed * 7) % 4), width: 1, height: 1)
                    context.fill(Path(ellipseIn: dot), with: .color(MIMITheme.bodyInk.opacity(alpha * (opacity / 0.14))))
                }
            }
        }.allowsHitTesting(false)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty != false }
}
