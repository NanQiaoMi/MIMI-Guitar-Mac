import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

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
    private var activePracticeScoreTitle: String {
        if let id = activeScoreID, let s = activePracticeScores.first(where: { $0.id == id }) {
            return s.artist.isEmpty ? s.title : "\(s.title) · \(s.artist)"
        }
        return "切换待练曲谱…"
    }
    private var practiceRows: [(PracticeItem, PersonalScore)] {
        model.practiceItems.compactMap { item in (model.personalScoresByID[item.scoreId] ?? scores.first(where: { $0.id == item.scoreId })).map { (item, $0) } }
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

    private static let dailyTips: [String] = [
        "慢练是通往飞速的唯一捷径：在 50% 速度下确保每个音清晰饱满，肌肉记忆自会成倍加速。",
        "左手换把位时拇指切忌大力抓握琴颈，先放松滑行再落指，换弦更轻盈自然。",
        "小节拆分法：把卡手的难点单独圈出 1~2 小节开启循环跟弹，攻克后再连贯演奏。",
        "倾听时值的饱满度：不仅要把音符弹对，更要让每个时值充分延展，伴奏与主旋律才能真正呼吸。",
        "节拍器是乐手最好的朋友：在节奏的律动中寻找松弛感，保持稳定的内拍比盲目提速更重要。",
        "右手拨弦手指以 45 度角切入琴弦，发出的音色最温润结实，避免干瘪杂音。",
        "温故而知新：每次练新曲子前，花 5 分钟弹一首完全掌握的老歌热身，迅速找回最佳手感。"
    ]

    private var dailyTipText: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.dailyTips[abs(dayOfYear) % Self.dailyTips.count]
    }

    private var streakDays: Int {
        let calendar = localCalendar
        let today = calendar.startOfDay(for: Date())
        var currentCheckDay = today
        let todayDuration = todayBucket?.durationMs ?? 0
        if todayDuration <= 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            currentCheckDay = yesterday
        }
        var count = 0
        while true {
            let start = calendar.startOfDay(for: currentCheckDay)
            let dur = dayBuckets.first(where: { calendar.isDate($0.date, inSameDayAs: start) })?.durationMs ?? 0
            if dur > 0 {
                count += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: currentCheckDay) else { break }
                currentCheckDay = prev
            } else {
                break
            }
        }
        return count
    }

    private var weeklyTotalMs: Double {
        dayBuckets.reduce(0) { $0 + $1.durationMs }
    }

    private var weeklyAverageMs: Double {
        weeklyTotalMs / Double(max(1, dayBuckets.count))
    }

    private struct RecommendedScoreItem: Identifiable {
        let id: String
        let title: String
        let artist: String
        let tag: String
        let difficulty: Int
        let bpm: Int
        let key: String
        let reason: String
    }

    private static let recommendedScores: [RecommendedScoreItem] = [
        RecommendedScoreItem(id: "rec_canon", title: "卡农 (Canon in D)", artist: "帕赫贝尔", tag: "和弦分解", difficulty: 3, bpm: 75, key: "D大调", reason: "黄金和弦走向与右手琶音轮指经典练习"),
        RecommendedScoreItem(id: "rec_minuet", title: "G大调小步舞曲", artist: "巴赫", tag: "古典指弹", difficulty: 2, bpm: 84, key: "G大调", reason: "复调独立声部旋律，训练左手指尖力量"),
        RecommendedScoreItem(id: "rec_romance", title: "爱的罗曼史 (Romance)", artist: "西班牙名曲", tag: "轮指与揉弦", difficulty: 2, bpm: 66, key: "Em调", reason: "高低音声部呼应，练习右手力度层次与音色控制"),
        RecommendedScoreItem(id: "rec_castle", title: "天空之城 (Carrying You)", artist: "久石让", tag: "抒情指弹", difficulty: 2, bpm: 68, key: "Am调", reason: "优美旋律与基础和弦结合，提升慢弹连贯度")
    ]

    private struct ChordDrillItem: Identifiable {
        let id: String
        let name: String
        let fingering: String
        let feel: String
        let role: String
    }

    private static let chordDrills: [ChordDrillItem] = [
        ChordDrillItem(id: "c", name: "C", fingering: "X 3 2 0 1 0", feel: "大调主和弦 · 明净开阔", role: "根音第5弦 · 1指按2弦1品"),
        ChordDrillItem(id: "g", name: "G", fingering: "3 2 0 0 0 3", feel: "属和弦 · 宏亮饱满", role: "小指控高音 · 扩张左手手型"),
        ChordDrillItem(id: "am", name: "Am", fingering: "X 0 2 2 1 0", feel: "关系小调 · 抒情灵魂", role: "与C和弦手型无缝转换"),
        ChordDrillItem(id: "em", name: "Em", fingering: "0 2 2 0 0 0", feel: "空灵低沉 · 指弹基石", role: "双指自然下落4/5弦 · 力量支点"),
        ChordDrillItem(id: "fmaj7", name: "Fmaj7", fingering: "X X 3 2 1 0", feel: "优雅色彩 · 朦胧通透", role: "新手友好替代大横按F · 泛音华彩"),
        ChordDrillItem(id: "dm", name: "Dm", fingering: "X X 0 2 3 1", feel: "柔和小调 · 细腻过渡", role: "1指1弦1品 · 3指2弦3品跨度训练")
    ]

    private func handleStartRecommendedScore(_ item: RecommendedScoreItem) {
        if let match = model.items.first(where: { $0.title.localizedCaseInsensitiveContains(item.title.prefix(2)) }) {
            model.preparePracticeScore(match.id)
            activeScoreID = "catalog:\(match.id)"
            model.navigate(.practice(scoreID: match.id))
        } else if let first = model.items.first {
            model.preparePracticeScore(first.id)
            activeScoreID = "catalog:\(first.id)"
            model.navigate(.practice(scoreID: first.id))
        } else {
            model.navigate(.catalog(.all))
        }
    }

    private func handleAddRecommendedScore(_ item: RecommendedScoreItem) {
        if let match = model.items.first(where: { $0.title.localizedCaseInsensitiveContains(item.title.prefix(2)) }) {
            model.preparePracticeScore(match.id)
        } else if let first = model.items.first {
            model.preparePracticeScore(first.id)
        } else {
            model.navigate(.catalog(.all))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: model.isScoreFocused ? 0 : 24) {
            focusChrome {
                VStack(alignment: .leading, spacing: 18) {
                    practiceHeroHeader
                    if !activePracticeScores.isEmpty {
                        practiceScoreConsole
                    }
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
                practiceEmptyStateHub
            }
            focusChrome { practiceReview }
            focusChrome { practiceQueueManagement }
            focusChrome { practiceToolbelt }
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
        }
        .frame(height: model.isScoreFocused ? 0 : nil, alignment: .top)
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

    private var practiceHeroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "guitars.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MIMITheme.darkGold)
                        Text("MIMI PRACTICE STUDIO · 琴房练习室")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(Color(hex: 0x8A7151))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0xF5EDE0), in: Capsule())

                    Text("琴房练习")
                        .font(MIMITheme.displayFont(size: 38, weight: .medium))
                        .tracking(-0.8)
                        .foregroundStyle(MIMITheme.ink)

                    Text("静心倾听指尖触弦的共鸣 · 慢练是通往流畅唯一的阶梯，日进有功。")
                        .font(MIMITheme.bodyFont(size: 14))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .lineSpacing(4)
                }

                Spacer(minLength: 16)

                practiceMotivationCapsule
            }

            dailySparkBanner
        }
    }

    private var practiceMotivationCapsule: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(streakDays > 0 ? Color(hex: 0xE25822) : MIMITheme.mutedInk)
                    Text("连续练习")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Text(streakDays > 0 ? "\(streakDays) 天" : "今日待开启")
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 13))
                        .foregroundStyle(MIMITheme.darkGold)
                    Text("今日练习")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Text(durationLabel(todayBucket?.durationMs ?? 0))
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
        }
    }

    private var dailySparkBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0xD4A017))
                .frame(width: 26, height: 26)
                .background(Color(hex: 0xFFF9E6), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("琴房箴言")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x8C6D38))
                    Text("· 每日小贴士")
                        .font(.system(size: 10))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Text(dailyTipText)
                    .font(MIMITheme.bodyFont(size: 12))
                    .foregroundStyle(MIMITheme.bodyInk)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(hex: 0xFAF6EE), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xEFE5D2), lineWidth: 1))
    }

    private var practiceScoreConsole: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MIMITheme.warmGold.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 16))
                    .foregroundStyle(MIMITheme.darkGold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(activeScore?.title ?? "选择待练曲谱")
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                    .lineLimit(1)
                Text(activeScore.map { ($0.artist.isEmpty ? "未知演奏者" : $0.artist) + " · \($0.format.uppercased())" } ?? "共 \(activePracticeScores.count) 首待练曲谱")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            Spacer(minLength: 10)

            Menu {
                Button("全部待练曲谱…") {
                    activeScoreID = nil
                    didResolveInitialPracticeSelection = true
                }
                ForEach(activePracticeScores) { score in
                    Button {
                        activeScoreID = score.id
                        didResolveInitialPracticeSelection = true
                    } label: {
                        if activeScoreID == score.id {
                            Label(score.artist.isEmpty ? score.title : "\(score.title) · \(score.artist)", systemImage: "checkmark")
                        } else {
                            Text(score.artist.isEmpty ? score.title : "\(score.title) · \(score.artist)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "music.note.list")
                    Text(activePracticeScoreTitle)
                        .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(MIMITheme.ink)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 14)
            .frame(minHeight: 37)
            .background(MIMITheme.paperWhite, in: Capsule())
            .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))
            .shadow(color: Color(hex: 0x483620).opacity(0.02), radius: 4, x: 0, y: 1.5)
            .contentShape(Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .fixedSize(horizontal: true, vertical: false)

            Button("管理我的谱") { model.navigate(.library) }
                .buttonStyle(PaperSecondaryButtonStyle())
        }
        .padding(16)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private var practiceEmptyStateHub: some View {
        VStack(spacing: 22) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [MIMITheme.warmGold.opacity(0.18), .clear], center: .center, startRadius: 0, endRadius: 50))
                        .frame(width: 80, height: 80)

                    Image(systemName: "music.note.house.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(MIMITheme.darkGold)
                }

                VStack(spacing: 6) {
                    Text("琴房已就绪 · 开启你的今日练习")
                        .font(MIMITheme.displayFont(size: 22, weight: .semibold))
                        .foregroundStyle(MIMITheme.ink)

                    Text("挑选一首心仪的曲谱加入待练，在这里你可以慢速跟弹、圈定小节循环击破卡点，伴奏时段将实时自动沉淀为练习记录。")
                        .font(MIMITheme.bodyFont(size: 13))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 580)
                        .lineSpacing(3)
                }

                HStack(spacing: 12) {
                    Button(action: { model.navigate(.catalog(.all)) }) {
                        Label("探索精选曲库", systemImage: "sparkles")
                    }
                    .buttonStyle(PaperProminentButtonStyle())

                    Button(action: { model.navigate(.library) }) {
                        Label("导入本地吉他谱", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PaperSecondaryButtonStyle())

                    Button(action: { model.navigate(.articles) }) {
                        Label("阅读指弹技巧", systemImage: "book.closed")
                    }
                    .buttonStyle(PaperSecondaryButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
            .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.03)

            curatedPracticeSection

            chordWarmupDrillSection
        }
    }

    private var curatedPracticeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("经典热身与精选练习曲推荐", systemImage: "star.fill")
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("点击即可立即加载练习或加入待练")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Self.recommendedScores) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.tag)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color(hex: 0x8F6B28))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(MIMITheme.warmGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                    Text("\(item.key) · \(item.bpm) BPM")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(MIMITheme.mutedInk)
                                }
                                Text(item.title)
                                    .font(MIMITheme.displayFont(size: 15, weight: .semibold))
                                    .foregroundStyle(MIMITheme.ink)
                                Text(item.artist)
                                    .font(MIMITheme.bodyFont(size: 11))
                                    .foregroundStyle(MIMITheme.mutedInk)
                            }
                            Spacer()
                            HStack(spacing: 1) {
                                ForEach(0..<item.difficulty, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(MIMITheme.warmGold)
                                }
                            }
                        }

                        Text(item.reason)
                            .font(MIMITheme.bodyFont(size: 11))
                            .foregroundStyle(MIMITheme.bodyInk)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Button("立即练习") { handleStartRecommendedScore(item) }
                                .buttonStyle(PaperProminentButtonStyle())
                            Button("加入待练") { handleAddRecommendedScore(item) }
                                .buttonStyle(PaperSecondaryButtonStyle())
                        }
                    }
                    .padding(14)
                    .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private var chordWarmupDrillSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("开琴 5 分钟 · 基础核心和弦热身", systemImage: "hand.point.up.left.and.text")
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("顺畅转换这组万能和弦，快速唤醒左手指尖肌肉记忆")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(Self.chordDrills) { drill in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(drill.name)
                            .font(MIMITheme.displayFont(size: 18, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                        Text(drill.fingering)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(MIMITheme.darkGold)
                        Text(drill.feel)
                            .font(.system(size: 9))
                            .foregroundStyle(MIMITheme.mutedInk)
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFAF7F0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MIMITheme.faintBorder, lineWidth: 1))
                }
            }
        }
        .padding(18)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private func dayShortLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }

    private func weekdayLabel(_ date: Date) -> String {
        let calendar = localCalendar
        if calendar.isDateInToday(date) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天"
        }
        let weekday = calendar.component(.weekday, from: date)
        let map = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return weekday < map.count ? map[weekday] : ""
    }

    private func durationShortLabel(_ milliseconds: Double) -> String {
        guard milliseconds.isFinite, milliseconds > 0 else { return "0" }
        let minutes = Int(ceil(milliseconds / 60000))
        return "\(minutes)m"
    }

    private var practiceReviewVisualBars: some View {
        let maxVal = max(1800000.0, dayBuckets.map(\.durationMs).max() ?? 0.0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("近 7 天练习律动")
                        .font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                        .foregroundStyle(MIMITheme.ink)
                    Text("本周累计伴奏练习：\(durationLabel(weeklyTotalMs)) · 日均 \(durationLabel(weeklyAverageMs))")
                        .font(MIMITheme.bodyFont(size: 11))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                Spacer()
                Text("目标: 20m/天")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(MIMITheme.darkGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MIMITheme.warmGold.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(dayBuckets) { bucket in
                    let isToday = localCalendar.isDateInToday(bucket.date)
                    let ratio = CGFloat(min(1.0, max(0.06, bucket.durationMs / maxVal)))
                    VStack(spacing: 5) {
                        Text(bucket.durationMs > 0 ? durationShortLabel(bucket.durationMs) : "0")
                            .font(.system(size: 10, weight: bucket.durationMs > 0 ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(bucket.durationMs > 0 ? MIMITheme.ink : MIMITheme.mutedInk.opacity(0.6))
                            .frame(height: 12)

                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isToday ? Color(hex: 0xF5EDE0) : Color(hex: 0xEDE7DC).opacity(0.6))
                                .frame(width: 24, height: 60)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: bucket.durationMs > 0
                                            ? [Color(hex: 0xD4AF37), Color(hex: 0x996515)]
                                            : [Color(hex: 0xE2DACD), Color(hex: 0xD5CCBD)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 24, height: max(6, ratio * 60))
                        }

                        VStack(spacing: 1) {
                            Text(weekdayLabel(bucket.date))
                                .font(.system(size: 9))
                                .foregroundStyle(isToday ? MIMITheme.darkGold : MIMITheme.mutedInk)
                            Text(dayShortLabel(bucket.date))
                                .font(.system(size: 9, weight: isToday ? .bold : .regular, design: .monospaced))
                                .foregroundStyle(isToday ? MIMITheme.ink : MIMITheme.mutedInk)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        isToday ? RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.warmGold.opacity(0.4), lineWidth: 1.5) : nil
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(MIMITheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            let todayDur = todayBucket?.durationMs ?? 0
            let targetDur: Double = 20 * 60 * 1000
            let progress = min(1.0, todayDur / targetDur)
            HStack(spacing: 10) {
                Image(systemName: todayDur >= targetDur ? "checkmark.seal.fill" : "sparkle")
                    .font(.system(size: 11))
                    .foregroundStyle(todayDur >= targetDur ? Color(hex: 0x2E7D32) : MIMITheme.darkGold)

                Text("今日练琴进度")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MIMITheme.bodyInk)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xEFE8DC)).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: 0xD4AF37), Color(hex: 0x8F6B28)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, geo.size.width * CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)

                Text(todayDur > 0 ? "\(Int(progress * 100))%" : "未开始")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
    }

    private var emptyRecentSessionNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(MIMITheme.darkGold.opacity(0.8))
                .padding(.top, 4)
            Text("练习记录静待开启")
                .font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                .foregroundStyle(MIMITheme.ink)
            Text("在曲谱播放器中跟随伴奏练习、慢速调速或开启小节循环时，系统会自动记录伴奏时段并生成节奏突破档案。")
                .font(MIMITheme.bodyFont(size: 11))
                .foregroundStyle(MIMITheme.mutedInk)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)
            Button("从曲库精选挑一首练习") { model.navigate(.catalog(.all)) }
                .buttonStyle(PaperSecondaryButtonStyle())
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.faintBorder, lineWidth: 1))
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

    private var practiceToolbelt: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("琴房好搭档 · 辅助工具与练琴法", systemImage: "tuningfork")
                    .font(MIMITheme.displayFont(size: 16, weight: .semibold))
                    .foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("让每一次练习都更有效率")
                    .font(MIMITheme.bodyFont(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "metronome.fill").foregroundStyle(MIMITheme.darkGold)
                        Text("经典节拍速度参考").font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    }
                    Text("选曲时根据 BPM 预估律动与按弦难度：").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    HStack(spacing: 6) {
                        tempoTag(bpm: 60, name: "抒情慢板")
                        tempoTag(bpm: 80, name: "流行中速")
                        tempoTag(bpm: 100, name: "动感扫弦")
                        tempoTag(bpm: 120, name: "快速轻快")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(MIMITheme.darkGold)
                        Text("科学慢练三步法").font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. 听觉记忆：完整原速听一遍伴奏，找准呼吸感").font(.system(size: 11)).foregroundStyle(MIMITheme.bodyInk)
                        Text("2. 难点切片：圈定卡手小节开启 2 节循环跟弹").font(.system(size: 11)).foregroundStyle(MIMITheme.bodyInk)
                        Text("3. 梯形提速：从 50% 起步，连续 3 遍零失误再 +5 BPM").font(.system(size: 11)).foregroundStyle(MIMITheme.bodyInk)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 1))
            }
        }
        .padding(18)
        .mimiCard(radius: 20, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private func tempoTag(bpm: Int, name: String) -> some View {
        VStack(spacing: 2) {
            Text("\(bpm)").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(MIMITheme.ink)
            Text(name).font(.system(size: 9)).foregroundStyle(MIMITheme.mutedInk)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: 0xF7F2E8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                practiceReviewVisualBars
                    .frame(width: 320)

                VStack(alignment: .leading, spacing: 8) {
                    Text("最近练习记录").font(MIMITheme.bodyFont(size: 14, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    if recentSessions.isEmpty {
                        emptyRecentSessionNotice
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
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "MM-dd"
        return formatter
    }()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    private func dayLabel(_ bucket: PracticeDayBucket) -> String {
        let today = localCalendar.isDateInToday(bucket.date)
        return Self.dayFormatter.string(from: bucket.date) + (today ? " 今天" : "")
    }
    private func timestampLabel(_ milliseconds: Double, timezone: String) -> String {
        guard milliseconds.isFinite, milliseconds > 0 else { return "时间未知" }
        let formatter = Self.timestampFormatter
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
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


struct PracticeDeskIllustration: View {
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

