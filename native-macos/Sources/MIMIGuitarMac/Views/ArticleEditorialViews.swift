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

// MARK: - Rich Article Editorial Markdown Content Renderer

/// Structured editorial renderer that renders headings, callout boxes, diagrams, and paragraphs
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

            // Parse content into sections
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
                        Text(text)
                            .font(MIMITheme.displayFont(size: 20, weight: .bold))
                            .foregroundStyle(MIMITheme.ink)
                    }
                    .padding(.top, 14)

                case .h3(let text):
                    Text(text)
                        .font(MIMITheme.displayFont(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: 0x6E5D48))
                        .padding(.top, 8)

                case .tip(let text):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0xC49A45))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("琴房手账贴士")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x8A7151))
                            Text(text)
                                .font(MIMITheme.proseFont(size: 13.5))
                                .foregroundStyle(MIMITheme.bodyInk)
                                .lineSpacing(5)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFFFBEA), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xE8DEB5), lineWidth: 1))

                case .note(let text):
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: 0x2E6B8A))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("重要说明")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x2E6B8A))
                            Text(text)
                                .font(MIMITheme.proseFont(size: 13.5))
                                .foregroundStyle(MIMITheme.bodyInk)
                                .lineSpacing(5)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xF3F9FC), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xD0E5F0), lineWidth: 1))

                case .paragraph(let text):
                    Text(text)
                        .font(MIMITheme.proseFont(size: 15))
                        .foregroundStyle(MIMITheme.bodyInk)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)

                case .divider:
                    HStack(spacing: 8) {
                        Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                        Text("❖").font(.system(size: 9)).foregroundStyle(MIMITheme.mutedInk)
                        Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private enum BlockKind {
        case h1(String)
        case h2(String)
        case h3(String)
        case tip(String)
        case note(String)
        case paragraph(String)
        case divider
    }

    private struct ContentBlock: Identifiable {
        let id: Int
        let kind: BlockKind
    }

    private func parseSections(_ raw: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        let paragraphs = raw.components(separatedBy: "\n\n")
        var idCounter = 0

        for p in paragraphs {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed == "---" {
                blocks.append(ContentBlock(id: idCounter, kind: .divider))
                idCounter += 1
            } else if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(ContentBlock(id: idCounter, kind: .h1(text)))
                idCounter += 1
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                blocks.append(ContentBlock(id: idCounter, kind: .h2(text)))
                idCounter += 1
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                blocks.append(ContentBlock(id: idCounter, kind: .h3(text)))
                idCounter += 1
            } else if trimmed.hasPrefix("> [!TIP]") {
                let text = trimmed.replacingOccurrences(of: "> [!TIP]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(ContentBlock(id: idCounter, kind: .tip(text)))
                idCounter += 1
            } else if trimmed.hasPrefix("> [!NOTE]") {
                let text = trimmed.replacingOccurrences(of: "> [!NOTE]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                blocks.append(ContentBlock(id: idCounter, kind: .note(text)))
                idCounter += 1
            } else {
                blocks.append(ContentBlock(id: idCounter, kind: .paragraph(trimmed)))
                idCounter += 1
            }
        }
        return blocks
    }
}
