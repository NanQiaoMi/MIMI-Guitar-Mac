import AppKit
import SwiftUI
import MIMICore

// MARK: - Hand-Drawn & Paper Editorial Newspaper Components

/// Newspaper masthead with vintage editorial styling, dateline, volume, and motto.
struct ArticleNewspaperMasthead: View {
    @Binding var selectedCategory: String
    let categories: [String]
    let totalArticles: Int

    var body: some View {
        VStack(spacing: 12) {
            // Top double decorative rule
            VStack(spacing: 2) {
                Rectangle().fill(MIMITheme.ink.opacity(0.85)).frame(height: 2)
                Rectangle().fill(MIMITheme.ink.opacity(0.4)).frame(height: 1)
            }

            // Masthead Title
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VOL. 26 · ISSUE 08")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x8A7151))
                    Text("纸本琴声周刊")
                        .font(MIMITheme.proseFont(size: 15, weight: .semibold))
                        .foregroundStyle(MIMITheme.bodyInk)
                }
                .frame(width: 140, alignment: .leading)

                Spacer()

                VStack(spacing: 4) {
                    Text("MIMI GUITAR EDITORIAL")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(4.0)
                        .foregroundStyle(Color(hex: 0x8A7151))
                    Text("琴房板报 · 专栏特辑")
                        .font(MIMITheme.displayFont(size: 38, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(MIMITheme.ink)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("慢练即是快 · 执琴有道")
                        .font(MIMITheme.proseFont(size: 13, weight: .medium))
                        .foregroundStyle(MIMITheme.bodyInk)
                    Text("晴 · 适宜练琴 · 共收录 \(totalArticles) 篇")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .frame(width: 180, alignment: .trailing)
            }
            .padding(.horizontal, 4)

            // Dateline banner with ornamental symbols
            HStack(spacing: 8) {
                Rectangle().fill(MIMITheme.softBorder).frame(height: 1)
                Text("❖ 每日精选 · 乐理视奏 · 演奏技巧 · 软件手账 ❖")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x8A7151))
                    .fixedSize()
                Rectangle().fill(MIMITheme.softBorder).frame(height: 1)
            }

            // Category Tabs styled like paper page tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        let isSelected = selectedCategory == cat
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCategory = cat
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if isSelected {
                                    Circle().fill(Color(hex: 0xC84B31)).frame(width: 5, height: 5)
                                }
                                Text(cat)
                                    .font(MIMITheme.bodyFont(size: 13, weight: isSelected ? .bold : .medium))
                            }
                            .foregroundStyle(isSelected ? Color(hex: 0x24201D) : MIMITheme.bodyInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color(hex: 0xF4EFE6) : MIMITheme.paperWhite)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color(hex: 0xC49A45) : MIMITheme.softBorder, lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // Bottom double rule
            VStack(spacing: 2) {
                Rectangle().fill(MIMITheme.ink.opacity(0.4)).frame(height: 1)
                Rectangle().fill(MIMITheme.ink.opacity(0.85)).frame(height: 2)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Headline Broadsheet Hero View

/// Front-page headline story broadsheet
struct ArticleHeadlineHeroView: View {
    let article: CatalogArticle
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(article.id)
        } label: {
            HStack(alignment: .top, spacing: 28) {
                // Left Column: Lead story text
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("★ 今日头条特稿")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0xC84B31))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xC84B31).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        Text(article.category ?? "软件教程")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x8A7151))
                        Spacer()
                        Text("⏱ 约 5 分钟深度阅读")
                            .font(.system(size: 11))
                            .foregroundStyle(MIMITheme.mutedInk)
                    }

                    Text(article.title)
                        .font(MIMITheme.displayFont(size: 26, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(cleanedExcerpt(article.content, limit: 140))
                        .font(MIMITheme.proseFont(size: 14))
                        .foregroundStyle(MIMITheme.bodyInk)
                        .lineSpacing(6)
                        .lineLimit(4)

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("标签:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(MIMITheme.mutedInk)
                            Text("AlphaTab 60FPS · A-B循环 · 变调夹 · 虚拟指板")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x6E5D48))
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Text("阅读全版特稿")
                                .font(MIMITheme.bodyFont(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0xC84B31))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0xC84B31))
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right Column: Hand-drawn diagram thumbnail card
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: 0xF7F4EE))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(hex: 0xE2DACD), lineWidth: 1)
                            )

                        VStack(spacing: 6) {
                            // Top pseudo waveform
                            HStack(spacing: 3) {
                                ForEach(0..<20) { idx in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color(hex: 0xC49A45).opacity(0.6))
                                        .frame(width: 4, height: CGFloat(8 + (idx * 7) % 22))
                                }
                            }
                            .frame(height: 32)
                            .padding(.top, 12)

                            // 6 TAB lines schematic
                            VStack(spacing: 4) {
                                ForEach(0..<6) { _ in
                                    Rectangle()
                                        .fill(Color(hex: 0x8C7C6B).opacity(0.35))
                                        .frame(height: 1)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)

                            // Fretboard mini preview
                            HStack(spacing: 12) {
                                Circle().fill(Color(hex: 0xC84B31)).frame(width: 8, height: 8)
                                Text("60FPS 连贯跟谱 · 交互工作台")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(hex: 0x6E5D48))
                            }
                            .padding(.bottom, 10)
                        }

                        // Washi Tape header effect
                        VStack {
                            Rectangle()
                                .fill(Color(hex: 0xC49A45).opacity(0.4))
                                .frame(width: 70, height: 12)
                                .rotationEffect(.degrees(-2))
                                .offset(y: -6)
                            Spacer()
                        }
                    }
                    .frame(width: 240, height: 140)

                    Text("FIG. 01 · 交互播放器工作台架构")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk)
                }
                .frame(width: 250)
            }
            .padding(22)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: 0xD8CEBD), lineWidth: 1.5)
            )
            .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func cleanedExcerpt(_ text: String, limit: Int) -> String {
        let clean = text
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "> [!TIP]", with: "")
            .replacingOccurrences(of: "> [!NOTE]", with: "")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > limit {
            return String(clean.prefix(limit)) + "…"
        }
        return clean
    }
}

// MARK: - Bulletin Board & Blackboard Sticky Cheatsheet Wall

/// Corkboard / bulletin board section with hand-drawn pinned sticky notes.
struct ArticleBulletinBoardSection: View {
    let onNavigateToArticle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xC84B31))
                Text("琴房板报 · 每日速查便签与指弹手账")
                    .font(MIMITheme.displayFont(size: 18, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                Text("CHEATSHEET WALL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color(hex: 0x8A7151))
                Spacer()
                Text("点击便签直达详解")
                    .font(.system(size: 11))
                    .foregroundStyle(MIMITheme.mutedInk)
            }

            // 4 Hand-drawn sticky notes grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ], spacing: 14) {
                // Sticky Note 1: Capo
                stickyNoteCard(
                    title: "变调夹换调速查",
                    tag: "演奏技巧",
                    notes: ["D调夹2品 · F调夹5品", "紧靠品丝2mm安装", "女生唱男生歌黄金调"],
                    articleID: "art-capo",
                    bgColor: Color(hex: 0xFFFBEA),
                    borderColor: Color(hex: 0xE8DEB5),
                    rotation: -1.0
                )

                // Sticky Note 2: Studio Shortcuts
                stickyNoteCard(
                    title: "工坊极速键盘录入",
                    tag: "软件手账",
                    notes: ["1~6 快速切换时值", "0~24 键入弦品位", "空格试听 · ⌘S保存"],
                    articleID: "art-studio",
                    bgColor: Color(hex: 0xF3F9F4),
                    borderColor: Color(hex: 0xD0E5D5),
                    rotation: 1.0
                )

                // Sticky Note 3: TAB Anatomy
                stickyNoteCard(
                    title: "六线谱符号解构",
                    tag: "乐理视奏",
                    notes: ["h击弦 · p勾弦 · /滑音", "b推弦 · ~颤音", "上细下粗低头看弹"],
                    articleID: "art-tab",
                    bgColor: Color(hex: 0xFFF4EE),
                    borderColor: Color(hex: 0xF0D2C5),
                    rotation: -0.8
                )

                // Sticky Note 4: Measure Slicing
                stickyNoteCard(
                    title: "A-B循环攻坚心法",
                    tag: "琴房心得",
                    notes: ["难点小节精准切片", "50%慢速起步爬梯", "每日递增 +5 BPM"],
                    articleID: "art-practice",
                    bgColor: Color(hex: 0xF6F2EB),
                    borderColor: Color(hex: 0xDDD4C5),
                    rotation: 0.6
                )
            }
        }
        .padding(18)
        .background(Color(hex: 0xFBF8F2), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: 0xE5DDD0), lineWidth: 1)
        )
    }

    private func stickyNoteCard(
        title: String,
        tag: String,
        notes: [String],
        articleID: String,
        bgColor: Color,
        borderColor: Color,
        rotation: Double
    ) -> some View {
        Button {
            onNavigateToArticle(articleID)
        } label: {
            ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tag)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: 0x8A7151))
                        Spacer()
                    }
                    .padding(.top, 4)

                    Text(title)
                        .font(MIMITheme.displayFont(size: 15, weight: .bold))
                        .foregroundStyle(MIMITheme.ink)
                        .lineLimit(1)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: 0xC84B31))
                                Text(note)
                                    .font(MIMITheme.proseFont(size: 12))
                                    .foregroundStyle(MIMITheme.bodyInk)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    HStack {
                        Spacer()
                        Text("查看技巧 →")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0xC84B31))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                .background(bgColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
                .shadow(color: Color(hex: 0x3E2E18).opacity(0.06), radius: 3, x: 0, y: 2)

                // Pushpin icon decoration
                Circle()
                    .fill(Color(hex: 0xC84B31))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1))
                    .offset(y: -4)
            }
            .rotationEffect(.degrees(rotation))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Artistic Newspaper Article Card

/// Sketched book folio / newspaper article card for grid display
struct ArticlePaperCardView: View {
    let article: CatalogArticle
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(article.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Top metadata line with stamp
                HStack(alignment: .center, spacing: 6) {
                    Text(article.category ?? "乐谱知识")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0xC84B31))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color(hex: 0xC84B31).opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    Text(articleDate(article.createdAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk)

                    Spacer()

                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xC49A45))
                        Text(articleHeat(article.views))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x6E5D48))
                    }
                }

                // Article Title
                Text(article.title)
                    .font(MIMITheme.displayFont(size: 17, weight: .bold))
                    .tracking(-0.15)
                    .foregroundStyle(MIMITheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Clean excerpt with serif prose font
                Text(articleExcerpt(article.content))
                    .font(MIMITheme.proseFont(size: 13.5))
                    .foregroundStyle(MIMITheme.bodyInk)
                    .lineSpacing(5)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 6)

                // Card Footer
                HStack {
                    Text("⏱ 约 4 分钟阅读")
                        .font(.system(size: 11))
                        .foregroundStyle(MIMITheme.mutedInk)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("阅读全文")
                            .font(MIMITheme.bodyFont(size: 12, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                    }
                }
                .padding(.top, 4)
                .overlay(alignment: .top) {
                    Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 185, alignment: .topLeading)
            .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(MIMITheme.softBorder, lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x483620).opacity(0.03), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func articleDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "2026-08-15" }
        return String(value.prefix(10))
    }

    private func articleHeat(_ views: Int) -> String {
        guard views >= 10_000 else { return "\(views)" }
        return String(format: "%.1f万", locale: Locale(identifier: "en_US_POSIX"), Double(views) / 10_000)
    }

    private func articleExcerpt(_ value: String) -> String {
        let clean = value
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "> [!TIP]", with: "")
            .replacingOccurrences(of: "> [!NOTE]", with: "")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(90)) + "…"
    }
}

// MARK: - Native SwiftUI Tutorial Diagram Views

/// Vector diagram of the Player Architecture for `art-player`
struct PlayerArchitectureDiagramView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Text("FIG. 01 · 交互播放器工作台四大视窗协同全景")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8A7151))
                Spacer()
                Text("AlphaTab 60FPS 内核")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC84B31))
            }

            // 1. Fluid Audio Waveform
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("① 顶部流体波形条与全局时间针")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x584A3B))
                    Spacer()
                    Text("01:24 / 03:48 · BPM 78")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MIMITheme.mutedInk)
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: 0xF8F5EE))
                        .frame(height: 38)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE2DACD), lineWidth: 1))

                    // Waveform lines
                    HStack(spacing: 3) {
                        ForEach(0..<45) { idx in
                            let h = CGFloat(6 + ((idx * 13 + 5) % 26))
                            RoundedRectangle(cornerRadius: 1)
                                .fill(idx < 18 ? Color(hex: 0xC84B31).opacity(0.7) : Color(hex: 0xC49A45).opacity(0.4))
                                .frame(width: 4, height: h)
                        }
                    }
                    .padding(.horizontal, 12)

                    // Playhead cursor
                    Rectangle()
                        .fill(Color(hex: 0xC84B31))
                        .frame(width: 2, height: 34)
                        .offset(x: 140)
                }
            }

            // 2. Score follow-scroll area
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("② 60FPS 垂直/水平曲谱视窗（含 A-B 攻坚循环区）")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x584A3B))
                    Spacer()
                    Text("自动连贯跟谱 · 无翻页顿挫")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: 0x2E7D32))
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE2DACD), lineWidth: 1))

                    VStack(spacing: 10) {
                        // 6 stave lines
                        ForEach(0..<6) { line in
                            Rectangle()
                                .fill(Color(hex: 0xD8CEBD))
                                .frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Measure dividers & A-B loop area
                    HStack(spacing: 0) {
                        Spacer().frame(width: 60)
                        Text("T\nA\nB")
                            .font(MIMITheme.displayFont(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x6E5D48))
                            .lineSpacing(2)

                        Spacer().frame(width: 40)

                        // Measure 1
                        HStack(spacing: 24) {
                            Text("3").font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("0").font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        // Bar line
                        Rectangle().fill(Color(hex: 0x8C7C6B)).frame(width: 1.5, height: 60).padding(.horizontal, 16)

                        // Measure 2 (Loop A-B)
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(hex: 0xC49A45).opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(hex: 0xC49A45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                )

                            HStack(spacing: 20) {
                                Text("A").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(hex: 0xC84B31))
                                Text("2").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(Color(hex: 0xC84B31))
                                    .padding(4)
                                    .background(Circle().fill(Color(hex: 0xC84B31).opacity(0.15)))
                                Text("2").font(.system(size: 12, weight: .bold, design: .monospaced))
                                Text("B").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(hex: 0xC84B31))
                            }
                        }
                        .frame(width: 160, height: 70)

                        // Bar line
                        Rectangle().fill(Color(hex: 0x8C7C6B)).frame(width: 1.5, height: 60).padding(.horizontal, 16)

                        // Measure 3
                        HStack(spacing: 20) {
                            Text("0").font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("1").font(.system(size: 12, weight: .bold, design: .monospaced))
                        }

                        Spacer()
                    }
                }
            }

            // 3. Floating HUD Controls
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xC49A45)).frame(width: 18, height: 18)
                        .overlay(Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.white))
                    Text("播放 / 暂停")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(hex: 0x24201D), in: Capsule())
                .foregroundStyle(.white)

                Text("0.85x 变速")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(hex: 0xF2ECE0), in: Capsule())

                Text("节拍器: 开启")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(hex: 0xF2ECE0), in: Capsule())

                Text("Capo: 2品")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC84B31))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(hex: 0xC84B31).opacity(0.1), in: Capsule())

                Text("循环 A-B [开启]")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x8F6B28))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(hex: 0xC49A45).opacity(0.2), in: Capsule())

                Spacer()
                Text("③ 浮动控制舱")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8A7151))
            }

            // 4. Virtual Fretboard
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("④ 底部木质虚拟指板（音位火花尾迹实时映射）")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0x584A3B))
                    Spacer()
                    Text("支持鼠标点击试听")
                        .font(.system(size: 10))
                        .foregroundStyle(MIMITheme.mutedInk)
                }

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: 0xF4EFE6))
                        .frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xD8CEBD), lineWidth: 1))

                    // Strings
                    VStack(spacing: 6) {
                        ForEach(0..<6) { s in
                            Rectangle()
                                .fill(Color(hex: 0x6E5D48))
                                .frame(height: CGFloat(1.0 + Double(s) * 0.25))
                        }
                    }
                    .padding(.horizontal, 24)

                    // Fret wires
                    HStack(spacing: 48) {
                        ForEach(1..<7) { fret in
                            VStack(spacing: 2) {
                                Rectangle().fill(Color(hex: 0xA89B88)).frame(width: 2, height: 46)
                                Text("\(fret)品").font(.system(size: 7, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
                            }
                        }
                    }
                    .padding(.leading, 60)

                    // Note spark dot on 4th string 2nd fret
                    Circle()
                        .fill(Color(hex: 0xC84B31))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .overlay(Text("E").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
                        .offset(x: 130, y: -2)
                }
            }
        }
        .padding(18)
        .background(Color(hex: 0xFEFFFC), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE2DACD), lineWidth: 1.5))
        .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 3, x: 0, y: 2)
    }
}

/// Vector diagram of the Studio Workflow for `art-studio`
struct StudioWorkflowDiagramView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FIG. 02 · 制谱工坊 PRO 工作台与全键盘驱动体系")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8A7151))
                Spacer()
                Text("分段蓝图 · 和弦调色板 · 歌词排版")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC49A45))
            }

            // Top Toolbar + Blueprint Timeline
            HStack(spacing: 8) {
                Text("晴天 (指弹独奏版)")
                    .font(MIMITheme.displayFont(size: 13, weight: .bold))
                Text("BPM: 76 · 4/4拍 · G调")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: 0xF2ECE0), in: Capsule())

                Spacer()

                // Blueprints
                HStack(spacing: 4) {
                    blueprintBadge("Intro 前奏", color: Color(hex: 0xC49A45))
                    blueprintBadge("Verse 主歌", color: Color(hex: 0xC84B31))
                    blueprintBadge("Chorus 副歌", color: Color(hex: 0x41A1CF))
                    blueprintBadge("Outro 尾奏", color: Color(hex: 0x8C7C6B))
                }
            }

            // Middle Area: Sheet Canvas + Chord Palette
            HStack(alignment: .top, spacing: 12) {
                // Editing Canvas
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TAB 乐谱编辑视窗")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MIMITheme.mutedInk)
                        Spacer()
                        Text("当前光标: 第 6 小节 第 2 拍")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: 0xC84B31))
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white)
                            .frame(height: 90)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE2DACD), lineWidth: 1))

                        VStack(spacing: 10) {
                            ForEach(0..<6) { _ in
                                Rectangle().fill(Color(hex: 0xD8CEBD)).frame(height: 1)
                            }
                        }
                        .padding(.horizontal, 14)

                        HStack(spacing: 24) {
                            Text("Em7").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x6E5D48))
                            Text("0").font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("2").font(.system(size: 12, weight: .bold, design: .monospaced))

                            // Active edit cursor box
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: 0xC84B31).opacity(0.15))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xC84B31), lineWidth: 1.5))
                                Text("3").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(Color(hex: 0xC84B31))
                            }
                            .frame(width: 22, height: 20)

                            Text("0").font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("Cadd9").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x6E5D48))
                            Text("3").font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }

                    // Lyrics Drawer mini
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.system(size: 9)).foregroundStyle(MIMITheme.mutedInk)
                        Text("歌词对齐: 故事的小黄花 从出生那年就飘着...")
                            .font(MIMITheme.proseFont(size: 11))
                            .foregroundStyle(Color(hex: 0x6E5D48))
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)

                // Chord Palette & Shortcut Box
                VStack(alignment: .leading, spacing: 6) {
                    Text("和弦调色板 (一键置入)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MIMITheme.mutedInk)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        chordPill("G")
                        chordPill("Em7")
                        chordPill("Cadd9")
                        chordPill("Dsus4")
                        chordPill("Am7")
                        chordPill("D/F#")
                    }

                    // Shortcut key pills
                    VStack(alignment: .leading, spacing: 2) {
                        Text("⚡ 快捷键: 1~6切时值 · 0~24按品 · Space试听")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x8A7151))
                    }
                    .padding(.top, 4)
                }
                .frame(width: 170)
            }
        }
        .padding(18)
        .background(Color(hex: 0xFEFFFC), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE2DACD), lineWidth: 1.5))
        .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 3, x: 0, y: 2)
    }

    private func blueprintBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    private func chordPill(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color(hex: 0x24201D))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(Color(hex: 0xF4EFE6), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xE2DACD), lineWidth: 1))
    }
}

/// Vector diagram of TAB Anatomy for `art-tab`
struct TabAnatomyDiagramView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FIG. 03 · 吉他六线谱（TAB）物理映射与技巧符号对照")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8A7151))
                Spacer()
                Text("直观指位 · 上细下粗")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2E6B8A))
            }

            // 6 Strings diagram with labels
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .trailing, spacing: 10) {
                    Text("1 弦 (高音 E · 最细)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0xC84B31))
                    Text("2 弦 (B 音)").font(.system(size: 10)).foregroundStyle(Color(hex: 0x584A3B))
                    Text("3 弦 (G 音)").font(.system(size: 10)).foregroundStyle(Color(hex: 0x584A3B))
                    Text("4 弦 (D 音)").font(.system(size: 10)).foregroundStyle(Color(hex: 0x584A3B))
                    Text("5 弦 (A 音)").font(.system(size: 10)).foregroundStyle(Color(hex: 0x584A3B))
                    Text("6 弦 (低音 E · 最粗)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0xC84B31))
                }
                .frame(width: 130)

                // Stave lines with example notes
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .frame(height: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xE2DACD), lineWidth: 1))

                    VStack(spacing: 16) {
                        ForEach(0..<6) { idx in
                            Rectangle()
                                .fill(Color(hex: 0x8C7C6B))
                                .frame(height: CGFloat(1.0 + Double(idx) * 0.25))
                        }
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 32) {
                        VStack(spacing: 4) {
                            Text("0").font(.system(size: 12, weight: .bold, design: .monospaced))
                            Text("空弦音").font(.system(size: 9)).foregroundStyle(MIMITheme.mutedInk)
                        }

                        VStack(spacing: 4) {
                            Text("0 h 2").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0x2E6B8A))
                            Text("击弦(Hammer)").font(.system(size: 9)).foregroundStyle(Color(hex: 0x2E6B8A))
                        }

                        VStack(spacing: 4) {
                            Text("2 / 4").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xC49A45))
                            Text("滑音(Slide)").font(.system(size: 9)).foregroundStyle(Color(hex: 0x8F6B28))
                        }

                        VStack(spacing: 4) {
                            Text("3 p 0").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0x2E6B8A))
                            Text("勾弦(Pull-off)").font(.system(size: 9)).foregroundStyle(Color(hex: 0x2E6B8A))
                        }

                        // G Chord column
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: 0xC49A45).opacity(0.15))
                            VStack(spacing: 3) {
                                Text("3").font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("0").font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("0").font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("0").font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("2").font(.system(size: 10, weight: .bold, design: .monospaced))
                                Text("3").font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                        }
                        .frame(width: 32, height: 110)

                        Text("纵向排列\n=和弦同时弹")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: 0x6E5D48))
                            .lineSpacing(2)
                    }
                    .padding(.leading, 24)
                }
            }
        }
        .padding(18)
        .background(Color(hex: 0xFEFFFC), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE2DACD), lineWidth: 1.5))
        .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 3, x: 0, y: 2)
    }
}

/// Vector diagram of Capo Transposition Matrix for `art-capo`
struct CapoTranspositionDiagramView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FIG. 04 · 变调夹（Capo）常用定调换算速查表")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8A7151))
                Spacer()
                Text("人声黄金换 Key")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0xC84B31))
            }

            VStack(spacing: 4) {
                // Table header
                HStack {
                    Text("目标原曲调").font(.system(size: 11, weight: .bold)).frame(width: 90, alignment: .leading)
                    Text("建议使用指法").font(.system(size: 11, weight: .bold)).frame(width: 120, alignment: .leading)
                    Text("变调夹品位").font(.system(size: 11, weight: .bold)).frame(width: 110, alignment: .leading)
                    Text("特点与说明").font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Color(hex: 0x584A3B))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(hex: 0xF4EFE6), in: RoundedRectangle(cornerRadius: 6))

                capoRow(target: "D 调", finger: "C 调指法", capo: "Capo 2 品", desc: "温暖中音，流行弹唱最常用", highlight: false)
                capoRow(target: "E 调", finger: "C 调 / D 调指法", capo: "Capo 4品 / 2品", desc: "声音清脆通透，适合民谣女声", highlight: false)
                capoRow(target: "F 调", finger: "C 调指法", capo: "Capo 5 品 ★", desc: "彻底免除大横按，女生唱男生歌首选", highlight: true)
                capoRow(target: "G 调", finger: "G 调指法", capo: "Capo 0 (不夹)", desc: "最经典扫弦和声织体", highlight: false)
                capoRow(target: "A 调", finger: "G 调指法", capo: "Capo 2 品", desc: "欢快跳跃，适合轻快节奏", highlight: false)
            }

            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xC49A45))
                Text("安装秘诀: 靠近音孔侧品丝 2mm 夹持，夹好后在 MIMI 详情页轻拨试听校音。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: 0x6E5D48))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(Color(hex: 0xFEFFFC), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE2DACD), lineWidth: 1.5))
        .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 3, x: 0, y: 2)
    }

    private func capoRow(target: String, finger: String, capo: String, desc: String, highlight: Bool) -> some View {
        HStack {
            Text(target).font(MIMITheme.displayFont(size: 12, weight: .bold)).frame(width: 90, alignment: .leading)
            Text(finger).font(.system(size: 11)).frame(width: 120, alignment: .leading)
            Text(capo)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(highlight ? Color(hex: 0xC84B31) : Color(hex: 0x24201D))
                .frame(width: 110, alignment: .leading)
            Text(desc).font(.system(size: 11)).foregroundStyle(MIMITheme.bodyInk).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(highlight ? Color(hex: 0xC84B31).opacity(0.06) : Color(hex: 0xFBFAF6), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Rich Article Editorial Markdown Content Components

/// Physical keyboard keycap badge component
struct EditorialKeycapView: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(hex: 0x332B24))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color.white, Color(hex: 0xF7F4EC)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(hex: 0xD0C8BA), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
    }
}

/// Rich inline markdown text renderer that strips raw syntax (**bold**, `code`) and renders styled text
struct EditorialFormattedText: View {
    let markdown: String
    let fontSize: CGFloat
    let color: Color
    let isBoldDefault: Bool

    init(_ markdown: String, fontSize: CGFloat = 14.5, color: Color = MIMITheme.bodyInk, isBoldDefault: Bool = false) {
        self.markdown = markdown
        self.fontSize = fontSize
        self.color = color
        self.isBoldDefault = isBoldDefault
    }

    var body: some View {
        if let attr = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attr)
                .font(isBoldDefault ? MIMITheme.displayFont(size: fontSize, weight: .bold) : MIMITheme.proseFont(size: fontSize))
                .foregroundStyle(color)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(markdown)
                .font(isBoldDefault ? MIMITheme.displayFont(size: fontSize, weight: .bold) : MIMITheme.proseFont(size: fontSize))
                .foregroundStyle(color)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Single cell renderer supporting keycap pills and rich text
struct EditorialTableCellView: View {
    let text: String

    var body: some View {
        let keycaps = parseKeycaps(text)
        if keycaps.count > 1 || (keycaps.first?.isKey == true) {
            HStack(spacing: 4) {
                ForEach(0..<keycaps.count, id: \.self) { idx in
                    let item = keycaps[idx]
                    if item.isKey {
                        EditorialKeycapView(key: item.text)
                    } else {
                        EditorialFormattedText(item.text, fontSize: 13, color: MIMITheme.bodyInk)
                    }
                }
            }
        } else {
            EditorialFormattedText(text, fontSize: 13.5, color: MIMITheme.bodyInk)
        }
    }

    private func parseKeycaps(_ raw: String) -> [(isKey: Bool, text: String)] {
        guard raw.contains("`") else { return [(isKey: false, text: raw)] }
        var result: [(isKey: Bool, text: String)] = []
        let parts = raw.components(separatedBy: "`")
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            result.append((isKey: i % 2 == 1, text: part))
        }
        return result
    }
}

/// Rich tutorial table view with aesthetic header, zebra striping, and keycaps
struct EditorialTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 12) {
                ForEach(0..<headers.count, id: \.self) { colIdx in
                    let h = headers[colIdx]
                    Text(h)
                        .font(MIMITheme.displayFont(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x3D3225))
                        .frame(maxWidth: colIdx == headers.count - 1 ? .infinity : columnWidth(colIdx, total: headers.count), alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(hex: 0xF2ECE1))

            Divider().background(Color(hex: 0xE2DACD))

            // Body Rows
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                let row = rows[rowIdx]
                let isEven = rowIdx % 2 == 1
                HStack(spacing: 12) {
                    ForEach(0..<row.count, id: \.self) { colIdx in
                        let cell = row[colIdx]
                        EditorialTableCellView(text: cell)
                            .frame(maxWidth: colIdx == row.count - 1 ? .infinity : columnWidth(colIdx, total: row.count), alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isEven ? Color(hex: 0xFBF9F5) : Color(hex: 0xFFFEFC))

                if rowIdx < rows.count - 1 {
                    Divider().background(Color(hex: 0xEBE4D8).opacity(0.7))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xDDD4C5), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1.5)
        .padding(.vertical, 6)
    }

    private func columnWidth(_ idx: Int, total: Int) -> CGFloat? {
        if total == 3 {
            if idx == 0 { return 110 }
            if idx == 1 { return 150 }
            return nil
        } else if total == 4 {
            if idx == 0 { return 90 }
            if idx == 1 { return 130 }
            if idx == 2 { return 120 }
            return nil
        }
        return 120
    }
}

/// Structured list item data model
struct EditorialListItem: Identifiable {
    let id = UUID()
    let level: Int
    let term: String?
    let text: String
    let keycaps: [(isKey: Bool, text: String)]
}

/// Rich list view supporting indent levels, custom bullets, bold term highlights, and keycaps
struct EditorialListView: View {
    let items: [EditorialListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    if item.level == 0 {
                        Text("❖")
                            .font(.system(size: 8))
                            .foregroundStyle(Color(hex: 0xC49A45))
                            .padding(.top, 5)
                            .frame(width: 14, alignment: .center)
                    } else {
                        Spacer().frame(width: 20)
                        Text("–")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x8A7151))
                            .padding(.top, 3)
                            .frame(width: 14, alignment: .center)
                    }

                    if let term = item.term {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(term)
                                .font(MIMITheme.displayFont(size: 14.5, weight: .bold))
                                .foregroundStyle(Color(hex: 0x24201D))
                            EditorialFormattedText(item.text, fontSize: 14, color: MIMITheme.bodyInk)
                        }
                    } else if item.keycaps.count > 1 || (item.keycaps.first?.isKey == true) {
                        HStack(spacing: 5) {
                            ForEach(0..<item.keycaps.count, id: \.self) { kIdx in
                                let kc = item.keycaps[kIdx]
                                if kc.isKey {
                                    EditorialKeycapView(key: kc.text)
                                } else {
                                    EditorialFormattedText(kc.text, fontSize: 14, color: MIMITheme.bodyInk)
                                }
                            }
                        }
                    } else {
                        EditorialFormattedText(item.text, fontSize: 14, color: MIMITheme.bodyInk)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Step header component with badge and SF Symbol icon
struct EditorialStepHeaderView: View {
    let step: String
    let title: String
    let icon: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(step)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0xC84B31))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color(hex: 0xC84B31).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xC84B31).opacity(0.25), lineWidth: 1))

            if !title.isEmpty {
                Text(title)
                    .font(MIMITheme.displayFont(size: 17, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
            }
        }
        .padding(.top, 10)
    }
}

/// Callout card view stripping leading `>` and rendering clean iconography and text
struct EditorialCalloutView: View {
    let isTip: Bool
    let title: String
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isTip ? "lightbulb.fill" : "info.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(isTip ? Color(hex: 0xC49A45) : Color(hex: 0x2E6B8A))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isTip ? Color(hex: 0x8A7151) : Color(hex: 0x2E6B8A))

                ForEach(0..<lines.count, id: \.self) { idx in
                    let l = lines[idx]
                    if l.hasPrefix("- ") || l.hasPrefix("* ") {
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isTip ? Color(hex: 0xC49A45) : Color(hex: 0x2E6B8A))
                            EditorialFormattedText(String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces), fontSize: 13.5, color: MIMITheme.bodyInk)
                        }
                    } else {
                        EditorialFormattedText(l, fontSize: 13.5, color: MIMITheme.bodyInk)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTip ? Color(hex: 0xFFFBEA) : Color(hex: 0xF3F9FC))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTip ? Color(hex: 0xE8DEB5) : Color(hex: 0xD0E5F0), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        .padding(.vertical, 4)
    }
}

// MARK: - Rich Article Editorial Markdown Content Renderer

/// Structured editorial renderer that renders headings, callout boxes, diagrams, tables, and lists
struct ArticleEditorialContent: View {
    let articleID: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // First check if this article corresponds to a special tutorial with an interactive diagram!
            if articleID == "art-player" {
                PlayerArchitectureDiagramView()
                    .padding(.bottom, 8)
            } else if articleID == "art-studio" {
                StudioWorkflowDiagramView()
                    .padding(.bottom, 8)
            } else if articleID == "art-tab" {
                TabAnatomyDiagramView()
                    .padding(.bottom, 8)
            } else if articleID == "art-capo" {
                CapoTranspositionDiagramView()
                    .padding(.bottom, 8)
            }

            // Parse content into rich sections
            ForEach(parseSections(content), id: \.id) { block in
                switch block.kind {
                case .h1(let text):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text)
                            .font(MIMITheme.displayFont(size: 24, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                        Rectangle().fill(Color(hex: 0xC49A45)).frame(width: 48, height: 2.5)
                    }
                    .padding(.top, 10)

                case .h2(let text):
                    HStack(spacing: 8) {
                        Capsule().fill(Color(hex: 0xC84B31)).frame(width: 4, height: 18)
                        Image(systemName: h2Icon(for: text))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(hex: 0xC84B31))
                        Text(text)
                            .font(MIMITheme.displayFont(size: 20, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                    }
                    .padding(.top, 14)

                case .step(let step, let title, let icon):
                    EditorialStepHeaderView(step: step, title: title, icon: icon)

                case .h3(let text):
                    Text(text)
                        .font(MIMITheme.displayFont(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6E5D48))
                        .padding(.top, 8)

                case .table(let headers, let rows):
                    EditorialTableView(headers: headers, rows: rows)

                case .list(let items):
                    EditorialListView(items: items)

                case .tip(let title, let lines):
                    EditorialCalloutView(isTip: true, title: title, lines: lines)

                case .note(let title, let lines):
                    EditorialCalloutView(isTip: false, title: title, lines: lines)

                case .paragraph(let text):
                    EditorialFormattedText(text, fontSize: 15, color: MIMITheme.bodyInk)

                case .divider:
                    HStack(spacing: 8) {
                        Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                        Text("❖ ❖ ❖").font(.system(size: 9)).foregroundStyle(MIMITheme.mutedInk)
                        Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func h2Icon(for title: String) -> String {
        if title.contains("快捷键") || title.contains("键盘") || title.contains("按键") {
            return "keyboard.fill"
        }
        if title.contains("流程") || title.contains("指引") || title.contains("上手") || title.contains("步骤") {
            return "list.bullet.rectangle.portrait.fill"
        }
        if title.contains("和弦") || title.contains("调式") || title.contains("乐理") {
            return "music.quarternote.3"
        }
        if title.contains("六线谱") || title.contains("TAB") || title.contains("琴弦") {
            return "guitars.fill"
        }
        if title.contains("变调夹") || title.contains("Capo") || title.contains("横按") {
            return "tuningfork"
        }
        if title.contains("攻坚") || title.contains("练习") || title.contains("片段") {
            return "flag.fill"
        }
        if title.contains("？") || title.contains("?") || title.contains("为什么") {
            return "questionmark.circle.fill"
        }
        if title.contains("符号") || title.contains("解构") || title.contains("准则") {
            return "character.book.closed.fill"
        }
        return "bookmark.fill"
    }

    private enum BlockKind {
        case h1(String)
        case h2(String)
        case h3(String)
        case step(step: String, title: String, icon: String)
        case table(headers: [String], rows: [[String]])
        case list(items: [EditorialListItem])
        case tip(title: String, lines: [String])
        case note(title: String, lines: [String])
        case paragraph(String)
        case divider
    }

    private struct ContentBlock: Identifiable {
        let id: Int
        let kind: BlockKind
    }

    private func parseSections(_ raw: String) -> [ContentBlock] {
        let lines = raw.components(separatedBy: "\n")
        var blocks: [ContentBlock] = []
        var idCounter = 0
        var i = 0
        let n = lines.count

        while i < n {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed == "---" {
                blocks.append(ContentBlock(id: idCounter, kind: .divider))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(ContentBlock(id: idCounter, kind: .h1(text)))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                blocks.append(ContentBlock(id: idCounter, kind: .h2(text)))
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                let h3Text = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if h3Text.hasPrefix("第") && h3Text.contains("步") {
                    let parts = h3Text.components(separatedBy: "：")
                    let stepStr = parts[0]
                    let titleStr = parts.count > 1 ? parts.dropFirst().joined(separator: "：") : ""
                    var icon = "star.fill"
                    if stepStr.contains("一") || stepStr.contains("1") { icon = "slider.horizontal.3" }
                    else if stepStr.contains("二") || stepStr.contains("2") { icon = "keyboard.fill" }
                    else if stepStr.contains("三") || stepStr.contains("3") { icon = "pianokeys" }
                    else if stepStr.contains("四") || stepStr.contains("4") { icon = "text.quote" }
                    blocks.append(ContentBlock(id: idCounter, kind: .step(step: stepStr, title: titleStr, icon: icon)))
                } else if let fc = h3Text.first, fc.isNumber, let dot = h3Text.firstIndex(of: ".") {
                    let num = String(h3Text[..<dot])
                    let titleStr = String(h3Text[h3Text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                    var icon = "star.fill"
                    if num == "1" { icon = "scissors" }
                    else if num == "2" { icon = "chart.line.uptrend.xyaxis" }
                    else if num == "3" { icon = "clock.arrow.circlepath" }
                    blocks.append(ContentBlock(id: idCounter, kind: .step(step: "步骤 \(num)", title: titleStr, icon: icon)))
                } else {
                    blocks.append(ContentBlock(id: idCounter, kind: .h3(h3Text)))
                }
                idCounter += 1
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var calloutLines: [String] = []
                while i < n && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var l = lines[i].trimmingCharacters(in: .whitespaces)
                    while l.hasPrefix(">") {
                        l = l.dropFirst().trimmingCharacters(in: .whitespaces)
                    }
                    if !l.isEmpty { calloutLines.append(l) }
                    i += 1
                }
                var isTip = false
                var title = "重要说明"
                var startIdx = 0
                if !calloutLines.isEmpty {
                    let first = calloutLines[0]
                    if first.hasPrefix("[!TIP]") {
                        isTip = true
                        title = String(first.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if title.isEmpty { title = "琴房手账贴士" }
                        startIdx = 1
                    } else if first.hasPrefix("[!NOTE]") {
                        isTip = false
                        title = String(first.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                        if title.isEmpty { title = "重要说明" }
                        startIdx = 1
                    }
                }
                let bodyLines = Array(calloutLines[startIdx...])
                let kind: BlockKind = isTip ? .tip(title: title, lines: bodyLines) : .note(title: title, lines: bodyLines)
                blocks.append(ContentBlock(id: idCounter, kind: kind))
                idCounter += 1
                continue
            }

            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                var tableLines: [String] = []
                while i < n && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                func parseRow(_ l: String) -> [String] {
                    var r = l
                    if r.hasPrefix("|") { r.removeFirst() }
                    if r.hasSuffix("|") { r.removeLast() }
                    return r.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                }
                if tableLines.count >= 2 {
                    let headers = parseRow(tableLines[0])
                    var rows: [[String]] = []
                    for tl in tableLines.dropFirst() {
                        if tl.contains("---") { continue }
                        rows.append(parseRow(tl))
                    }
                    blocks.append(ContentBlock(id: idCounter, kind: .table(headers: headers, rows: rows)))
                    idCounter += 1
                }
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var listItems: [EditorialListItem] = []
                while i < n {
                    let cur = lines[i]
                    let t = cur.trimmingCharacters(in: .whitespaces)
                    if t.isEmpty {
                        if i + 1 < n && (lines[i+1].trimmingCharacters(in: .whitespaces).hasPrefix("- ") || lines[i+1].trimmingCharacters(in: .whitespaces).hasPrefix("* ")) {
                            i += 1
                            continue
                        } else {
                            break
                        }
                    }
                    if t.hasPrefix("- ") || t.hasPrefix("* ") {
                        let indent = cur.prefix(while: { $0 == " " || $0 == "\t" }).count
                        let level = indent >= 2 ? 1 : 0
                        let c = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        listItems.append(parseListItem(c, level: level))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(ContentBlock(id: idCounter, kind: .list(items: listItems)))
                idCounter += 1
                continue
            }

            // Normal paragraph
            var pLines: [String] = []
            while i < n {
                let cur = lines[i]
                let t = cur.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t == "---" || t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("|") || t.hasPrefix("- ") || t.hasPrefix("* ") {
                    break
                }
                pLines.append(t)
                i += 1
            }
            if !pLines.isEmpty {
                blocks.append(ContentBlock(id: idCounter, kind: .paragraph(pLines.joined(separator: "\n"))))
                idCounter += 1
            }
        }
        return blocks
    }

    private func parseListItem(_ raw: String, level: Int) -> EditorialListItem {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("**") {
            if let endIdx = s.range(of: "**", range: s.index(s.startIndex, offsetBy: 2)..<s.endIndex) {
                let term = String(s[s.index(s.startIndex, offsetBy: 2)..<endIdx.lowerBound])
                var remainder = String(s[endIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
                if remainder.hasPrefix("：") || remainder.hasPrefix(":") {
                    remainder = String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return EditorialListItem(level: level, term: term, text: remainder, keycaps: parseKeycaps(remainder))
            }
        }
        return EditorialListItem(level: level, term: nil, text: s, keycaps: parseKeycaps(s))
    }

    private func parseKeycaps(_ text: String) -> [(isKey: Bool, text: String)] {
        guard text.contains("`") else { return [(isKey: false, text: text)] }
        var result: [(isKey: Bool, text: String)] = []
        let parts = text.components(separatedBy: "`")
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            result.append((isKey: i % 2 == 1, text: part))
        }
        return result
    }
}
