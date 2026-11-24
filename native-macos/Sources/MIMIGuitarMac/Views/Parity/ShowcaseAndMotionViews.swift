import MIMICore
import SwiftUI

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
                MIMILogoView(size: 38)
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
                MIMILogoView(size: 36)
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
        _auditionState = StateObject(wrappedValue: controller.viewState(tracksClock: true))
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
                        .lineLimit(1)
                    Button("速度 \(playbackRateLabel)", action: onAdvanceRate).buttonStyle(PaperSecondaryButtonStyle()).disabled(!playback.canPlay)
                }.transition(.opacity)
            }
        }.padding(17).mimiCard(radius: 20, fill: MIMITheme.paperWhite)
    }

    private func clock(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let totalSeconds = max(0, Int((value / 1000.0).rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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
        _auditionState = StateObject(wrappedValue: controller.viewState(itemID: item.id))
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
        _auditionState = StateObject(wrappedValue: controller.viewState())
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
        _auditionState = StateObject(wrappedValue: controller.viewState())
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

