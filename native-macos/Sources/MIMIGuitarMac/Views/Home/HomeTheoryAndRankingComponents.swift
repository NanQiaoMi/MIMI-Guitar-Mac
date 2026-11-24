import MIMICore
import SwiftUI

struct PodiumCard: View {
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

struct RankingRow: View {
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

struct TheoryLevel: Identifiable {
    let level: Int
    let stage: String
    let title: String
    let detail: String
    let reps: [String]
    let color: Color
    var id: Int { level }

    static let rows: [TheoryLevel] = [
        TheoryLevel(level: 1, stage: "启蒙破冰", title: "零基础 · 启蒙", detail: "单音旋律、入门开放和弦与基础扫弦", reps: ["小星星", "老男孩"], color: Color(hex: 0x2D7A4D)),
        TheoryLevel(level: 2, stage: "弹唱基石", title: "初级 · 熟练弹唱", detail: "常用大调和弦、基础切音与前奏滑音", reps: ["晴天", "后来", "平凡之路"], color: Color(hex: 0x2A7B72)),
        TheoryLevel(level: 3, stage: "复调独奏", title: "中级 · 进阶独奏", detail: "F大横按攻克、击勾弦与中级指弹复调", reps: ["反方向的钟", "我记得", "海阔天空"], color: Color(hex: 0x2B4C6F)),
        TheoryLevel(level: 4, stage: "舞台炫技", title: "高级 · 舞台指弹", detail: "拍弦（Slap）、点弦、人工泛音与变拍子", reps: ["卡农", "加州旅馆", "风之诗"], color: Color(hex: 0xC05621)),
        TheoryLevel(level: 5, stage: "大师造极", title: "专业 · 大师总谱", detail: "多声部交响吉他、特殊调弦法与极速独奏", reps: ["Fight", "Wings", "黄昏"], color: Color(hex: 0x975A16))
    ]
}

struct TheoryLevelCard: View {
    let row: TheoryLevel
    let onSelect: () -> Void

    init(row: TheoryLevel, onSelect: @escaping () -> Void) {
        self.row = row
        self.onSelect = onSelect
    }
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Top Color Accent Bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [row.color, row.color.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                    .padding(.bottom, 12)

                // Header badge row
                HStack(alignment: .center) {
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(row.color)
                                .frame(width: 17, height: 17)
                            Text("\(row.level)")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text(row.stage)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(row.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(row.color.opacity(0.12), in: Capsule())

                    Spacer(minLength: 4)

                    Text("LEVEL 0\(row.level)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk.opacity(0.7))
                }
                .padding(.bottom, 10)

                // Title
                Text(row.title)
                    .font(MIMITheme.displayFont(size: 15, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                    .padding(.bottom, 6)

                // Detail text
                Text(row.detail)
                    .font(MIMITheme.bodyFont(size: 11.5))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                    .padding(.bottom, 10)

                // Divider
                Rectangle()
                    .fill(MIMITheme.softBorder.opacity(0.85))
                    .frame(height: 1)
                    .padding(.bottom, 10)

                // Song Recommendations section
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 8.5))
                            .foregroundStyle(MIMITheme.darkGold)
                        Text("经典研习代表作：")
                            .font(MIMITheme.bodyFont(size: 10, weight: .medium))
                            .foregroundStyle(MIMITheme.mutedInk)
                    }

                    FlowSongPills(songs: row.reps, tint: row.color)
                }

                Spacer(minLength: 4)

                // Bottom Action Pill
                HStack {
                    Text("探索曲目")
                        .font(MIMITheme.bodyFont(size: 10.5, weight: .semibold))
                        .foregroundStyle(isHovered ? row.color : MIMITheme.mutedInk)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isHovered ? row.color : MIMITheme.mutedInk)
                        .offset(x: isHovered ? 2 : 0)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 242, maxHeight: 242, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.dynamic(lightHex: isHovered ? 0xFFFFFF : 0xFCFAF7, darkHex: isHovered ? 0x2A2520 : 0x24201C))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isHovered ? row.color.opacity(0.65) : MIMITheme.softBorder, lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(
                color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000))
                    .opacity(isHovered ? 0.08 : 0.025),
                radius: isHovered ? 8 : 3,
                y: isHovered ? 3 : 1
            )
            .offset(y: isHovered ? -2 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
    }
}

struct FlowSongPills: View {
    let songs: [String]
    let tint: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) {
                ForEach(songs, id: \.self) { song in
                    songBadge(song)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(Array(songs.prefix(2)), id: \.self) { song in
                        songBadge(song)
                    }
                }
                if songs.count > 2 {
                    HStack(spacing: 3) {
                        ForEach(Array(songs.dropFirst(2)), id: \.self) { song in
                            songBadge(song)
                        }
                    }
                }
            }
        }
    }

    private func songBadge(_ title: String) -> some View {
        Text("《\(title)》")
            .font(MIMITheme.bodyFont(size: 9.5, weight: .medium))
            .foregroundStyle(MIMITheme.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.dynamic(lightHex: 0xF3EFE7, darkHex: 0x2E2822), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(MIMITheme.softBorder, lineWidth: 0.8))
    }
}

struct KeyFamily: Identifiable {
    let key: String
    let tonic: String
    let title: String
    let mood: String
    let chords: String
    let color: Color
    var id: String { key }

    static let rows = [
        KeyFamily(key: "C", tonic: "C", title: "C 大调", mood: "纯净基石 · 温暖明朗", chords: "C · G · Am · F", color: Color(hex: 0x2C4A6F)),
        KeyFamily(key: "G", tonic: "G", title: "G 大调", mood: "民谣灵魂 · 清澈开阔", chords: "G · D · Em · C", color: Color(hex: 0x2D7A4D)),
        KeyFamily(key: "D", tonic: "D", title: "D 大调", mood: "明快辉煌 · 抒情指弹", chords: "D · A · Bm · G", color: Color(hex: 0xC05621)),
        KeyFamily(key: "A", tonic: "A", title: "A 大调", mood: "清亮激昂 · 流行摇滚", chords: "A · E · F#m · D", color: Color(hex: 0x6E3985)),
        KeyFamily(key: "E", tonic: "E", title: "E 大调", mood: "浑厚深沉 · 蓝调布鲁斯", chords: "E · B · C#m · A", color: Color(hex: 0xA22358)),
        KeyFamily(key: "F", tonic: "F", title: "F 大调", mood: "柔和浪漫 · 横按试炼", chords: "F · C · Dm · Bb", color: Color(hex: 0x2A7B72)),
        KeyFamily(key: "Em", tonic: "Em", title: "Em 小调", mood: "苍凉质朴 · 幽谷民谣", chords: "Em · C · G · D", color: Color(hex: 0x5C4A38)),
        KeyFamily(key: "Am", tonic: "Am", title: "Am 小调", mood: "凄美深情 · 经典流行", chords: "Am · F · C · G", color: Color(hex: 0x9F3A25)),
    ]
}

struct KeyFamilyButton: View {
    let key: KeyFamily
    let onSelect: () -> Void

    init(key: KeyFamily, onSelect: @escaping () -> Void) {
        self.key = key
        self.onSelect = onSelect
    }
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [key.color, key.color.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                        Text(key.tonic)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: key.color.opacity(0.25), radius: 2, y: 1)

                    Text(key.title)
                        .font(MIMITheme.displayFont(size: 13, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(key.color)
                        .opacity(isHovered ? 1 : 0)
                }

                Text(key.mood)
                    .font(MIMITheme.bodyFont(size: 9.5, weight: .regular))
                    .foregroundStyle(MIMITheme.mutedInk)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Text("走向")
                        .font(MIMITheme.bodyFont(size: 8.5, weight: .medium))
                        .foregroundStyle(MIMITheme.mutedInk.opacity(0.8))
                    Text(key.chords)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(isHovered ? key.color : MIMITheme.bodyInk)
                }
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Color.dynamic(lightHex: 0xF2ECE2, darkHex: 0x2D2721),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.dynamic(lightHex: isHovered ? 0xFFFFFF : 0xFCFAF7, darkHex: isHovered ? 0x2A2520 : 0x24201C))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isHovered ? key.color.opacity(0.55) : MIMITheme.softBorder, lineWidth: isHovered ? 1.2 : 1)
            )
            .shadow(
                color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000))
                    .opacity(isHovered ? 0.06 : 0.02),
                radius: isHovered ? 5 : 2,
                y: isHovered ? 2 : 1
            )
            .offset(y: isHovered ? -1.5 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
    }
}

struct TheoryStyle: Identifiable {
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

struct TheoryStyleTile: View {
    let style: TheoryStyle
    let onSelect: () -> Void

    init(style: TheoryStyle, onSelect: @escaping () -> Void) {
        self.style = style
        self.onSelect = onSelect
    }
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            isHovered
                                ? MIMITheme.warmGold.opacity(0.18)
                                : Color.dynamic(lightHex: 0xF2ECE1, darkHex: 0x302922)
                        )
                        .frame(width: 32, height: 32)
                    Image(systemName: style.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isHovered ? MIMITheme.darkGold : Color.dynamic(lightHex: 0x8C6B46, darkHex: 0xC4A47E))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(MIMITheme.displayFont(size: 12.5, weight: .bold))
                        .foregroundStyle(isHovered ? MIMITheme.darkGold : MIMITheme.ink)
                    Text(style.desc)
                        .font(MIMITheme.bodyFont(size: 9.5))
                        .foregroundStyle(MIMITheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(MIMITheme.darkGold)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.dynamic(lightHex: isHovered ? 0xFFFFFF : 0xFCFAF7, darkHex: isHovered ? 0x2A2520 : 0x24201C))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isHovered ? MIMITheme.warmGold.opacity(0.6) : MIMITheme.softBorder, lineWidth: isHovered ? 1.2 : 1)
            )
            .shadow(
                color: Color(nsColor: .dynamic(lightHex: 0x483620, darkHex: 0x000000))
                    .opacity(isHovered ? 0.05 : 0.015),
                radius: isHovered ? 4 : 2,
                y: isHovered ? 1.5 : 0.5
            )
            .offset(y: isHovered ? -1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
    }
}

struct PracticeMemoryCard: View {
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


struct HomeFooterPill: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(MIMITheme.bodyInk)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            Color.dynamic(lightHex: 0xF3EFE6, darkHex: 0x2D2721),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(MIMITheme.softBorder, lineWidth: 1)
        )
    }
}

struct HomeFooterColumn: View {
    let title: String
    let icon: String
    let iconColor: Color
    let links: [(String, NativeRoute)]
    let onNavigate: (NativeRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(MIMITheme.displayFont(size: 13.5, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
            }
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, item in
                    HomeFooterInteractiveLink(title: item.0, route: item.1, onNavigate: onNavigate)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeFooterInteractiveLink: View {
    let title: String
    let route: NativeRoute
    let onNavigate: (NativeRoute) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onNavigate(route)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isHovered ? "chevron.right" : "circle.fill")
                    .font(.system(size: isHovered ? 7.5 : 3.5, weight: .bold))
                    .foregroundStyle(isHovered ? MIMITheme.darkGold : MIMITheme.mutedInk.opacity(0.4))
                    .frame(width: 8, alignment: .center)

                Text(title)
                    .font(MIMITheme.bodyFont(size: 11.5, weight: isHovered ? .medium : .regular))
                    .foregroundStyle(isHovered ? MIMITheme.darkGold : MIMITheme.bodyInk)
                    .offset(x: isHovered ? 1.5 : 0)
            }
            .padding(.vertical, 1.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
