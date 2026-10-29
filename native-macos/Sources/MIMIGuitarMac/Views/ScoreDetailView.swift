import AppKit
import MIMICore
import SwiftUI

struct ScoreDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var expandedDescriptionScoreID: String?

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if let item = model.selectedItem {
                catalogDetail(item)
                    .transition(.opacity)
            } else if let score = model.selectedPersonalScore {
                personalDetail(score)
                    .transition(.opacity)
            } else if let message = model.loadMessage {
                loadFailure(message)
            } else if model.isLoading {
                VStack(spacing: 11) {
                    ProgressView()
                    Text("正在载入曲谱…").font(MIMITheme.displayFont(size: 20, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text("正在从本机曲库或个人资料中读取所选曲谱。")
                        .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.bootstrapMessage {
                bootstrapFailure(message)
            } else {
                emptyState(title: "选择一首曲谱", message: "从曲库或个人资料中选择曲谱，即可查看谱面与播放控制。")
            }
        }
        .background(MIMITheme.paper)
        .animation(motionPolicy.pageAnimation, value: model.selectedItem?.id ?? model.selectedPersonalScore?.id)
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "music.note.list").font(.system(size: 34, weight: .light)).foregroundStyle(MIMITheme.warmGold)
            Text(title).font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(message).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk).multilineTextAlignment(.center).frame(maxWidth: 440)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(MIMITheme.terracotta)
            Text("曲谱暂时无法载入").font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(message).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                .multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 480)
            HStack(spacing: 9) {
                if let scoreID = requestedScoreID {
                    Button("重试") { model.loadScore(id: scoreID) }.buttonStyle(.borderedProminent).tint(MIMITheme.darkGold)
                }
                Button("返回曲库") { returnFromScore() }.buttonStyle(PaperSecondaryButtonStyle())
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bootstrapFailure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(MIMITheme.terracotta)
            Text("本地曲库尚未就绪").font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(message).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                .multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 480)
            HStack(spacing: 9) {
                Button("重试") { model.retryBootstrap() }.buttonStyle(.borderedProminent).tint(MIMITheme.darkGold)
                Button("返回曲库") { returnFromScore() }.buttonStyle(PaperSecondaryButtonStyle())
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var requestedScoreID: String? {
        guard case .score(let id) = model.route else { return nil }
        return id
    }

    private func returnFromScore() {
        if model.canNavigateBack { model.navigateBack() }
        else { model.navigate(.catalog(.all)) }
    }

    private func catalogDetail(_ item: CatalogItem) -> some View {
        GeometryReader { geometry in
            let viewportHeight = playerViewportHeight(in: geometry.size.height)
            let pageInset = scorePageInset(for: geometry.size.width)
            ScrollView(.vertical) {
                VStack(spacing: model.isScoreFocused ? 0 : 24) {
                    VStack(alignment: .leading, spacing: model.isScoreFocused ? 0 : 20) {
                        if !model.isScoreFocused { catalogHero(item).padding(.horizontal, pageInset) }
                        if let contentRoot = model.contentRoot, let store = model.personalStore {
                            NativePlayerPane(
                                item: item,
                                personalScore: model.selectedPersonalScore,
                                contentRoot: contentRoot,
                                personalStore: store,
                                importedFileURL: model.selectedImportedFileURL,
                                onPersonalDataChanged: model.personalDataDidChange,
                                isFocused: model.isScoreFocused,
                                viewportHeight: viewportHeight,
                                onToggleFocus: { model.toggleScoreFullscreen() }
                            )
                            .id(item.id)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, model.isScoreFocused ? 0 : 1)
                            .mimiCard(radius: model.isScoreFocused ? 0 : 20, fill: MIMITheme.paperWhite, shadowOpacity: model.isScoreFocused ? 0 : 0.04)
                            .padding(.horizontal, model.isScoreFocused ? 0 : pageInset)

                            if !model.isScoreFocused {
                                screenshotAndMetadata(item).padding(.horizontal, pageInset)
                                if !tags(for: item).isEmpty { tagSection(item).padding(.horizontal, pageInset) }
                                if !model.relatedItems.isEmpty { relatedSection(model.relatedItems, category: item.category).padding(.horizontal, pageInset) }
                                recentHistorySection(for: item).padding(.horizontal, pageInset)
                            }
                        } else {
                            WorkspaceUnavailableView(title: "播放器资料尚未就绪", message: model.bootstrapMessage ?? "播放器依赖本地曲谱资源和个人资料索引。")
                                .frame(height: 420)
                        }
                    }
                    .padding(.vertical, model.isScoreFocused ? 0 : 32)
                    .frame(maxWidth: model.isScoreFocused ? .infinity : 1240, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)

                    if !model.isScoreFocused { MIMISiteFooter().padding(.top, 12) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .background(RouteScrollPositionTracker(model: model).frame(width: 1, height: 1).opacity(0))
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(model.isScoreFocused)
            .background(MIMITheme.paper)
        }
    }

    private func personalDetail(_ score: PersonalScore) -> some View {
        GeometryReader { geometry in
            let viewportHeight = playerViewportHeight(in: geometry.size.height)
            let pageInset = scorePageInset(for: geometry.size.width)
            ScrollView(.vertical) {
                VStack(spacing: model.isScoreFocused ? 0 : 24) {
                    VStack(alignment: .leading, spacing: model.isScoreFocused ? 0 : 20) {
                        if !model.isScoreFocused { personalHero(score).padding(.horizontal, pageInset) }
                        if let contentRoot = model.contentRoot, let store = model.personalStore {
                            NativePlayerPane(
                                item: nil,
                                personalScore: score,
                                contentRoot: contentRoot,
                                personalStore: store,
                                importedFileURL: model.selectedImportedFileURL,
                                onPersonalDataChanged: model.personalDataDidChange,
                                isFocused: model.isScoreFocused,
                                viewportHeight: viewportHeight,
                                onToggleFocus: { model.toggleScoreFullscreen() }
                            )
                            .id(score.id)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, model.isScoreFocused ? 0 : 1)
                            .mimiCard(radius: model.isScoreFocused ? 0 : 20, fill: MIMITheme.paperWhite, shadowOpacity: model.isScoreFocused ? 0 : 0.04)
                            .padding(.horizontal, model.isScoreFocused ? 0 : pageInset)

                            if !model.isScoreFocused, let warnings = score.warnings, !warnings.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("原件迁移说明", systemImage: "exclamationmark.triangle.fill").font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(MIMITheme.terracotta)
                                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 16, fill: MIMITheme.paperWhite, shadowOpacity: 0.025).padding(.horizontal, pageInset)
                            }
                        } else {
                            WorkspaceUnavailableView(title: "播放器资料尚未就绪", message: model.bootstrapMessage ?? "本机曲谱资源正在准备。")
                                .frame(height: 420)
                        }
                    }
                    .padding(.vertical, model.isScoreFocused ? 0 : 32)
                    .frame(maxWidth: model.isScoreFocused ? .infinity : 1240, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)

                    if !model.isScoreFocused { MIMISiteFooter().padding(.top, 12) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .background(RouteScrollPositionTracker(model: model).frame(width: 1, height: 1).opacity(0))
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(model.isScoreFocused)
            .background(MIMITheme.paper)
        }
    }

    private func playerViewportHeight(in availableHeight: CGFloat) -> CGFloat {
        let usableHeight = availableHeight.isFinite && availableHeight > 0 ? availableHeight : 760
        if model.isScoreFocused { return max(480, usableHeight) }
        return min(780, max(600, usableHeight * 0.78))
    }

    private func scorePageInset(for geometryWidth: CGFloat) -> CGFloat {
        let rootSize = min(17.5, max(14, 13.44 + 0.0035 * geometryWidth))
        return rootSize * (geometryWidth >= 640 ? 1.5 : 1)
    }

    private func catalogHero(_ item: CatalogItem) -> some View {
        let description = scoreDescription(item)
        let isDescriptionExpanded = expandedDescriptionScoreID == item.id
        let canExpandDescription = description.count > 56

        return VStack(alignment: .leading, spacing: 8) {
            NativeScoreDetailFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                Button { model.navigateBack() } label: { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(MIMITheme.mutedInk).help("返回上一个曲库页面")
                scoreChip(categoryName(item.category), tint: MIMITheme.terracotta)
                if item.difficulty > 0 { scoreChip(item.difficultyLabel, tint: Color(hex: 0x8F6D2B)) }
                if item.sheetForm > 0 { scoreChip(item.sheetFormLabel, tint: Color(hex: 0x2E7D32)) }
                if let key = nonempty(item.key) { scoreChip("\(key) 调", tint: MIMITheme.bodyInk) }
                if let bpm = item.bpm { scoreChip("♩ = \(bpm)", tint: MIMITheme.mutedInk) }
                Label(item.displayHeat, systemImage: "flame.fill").font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.terracotta)
            }

            catalogTitleAndActions(item)

            HStack(alignment: .top, spacing: 8) {
                Text(description)
                    .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(Color(hex: 0x705C42))
                    .lineSpacing(3).lineLimit(isDescriptionExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canExpandDescription {
                    Button {
                        withAnimation(motionPolicy.panelAnimation) {
                            expandedDescriptionScoreID = isDescriptionExpanded ? nil : item.id
                        }
                    } label: {
                        Label(isDescriptionExpanded ? "收起" : "展开", systemImage: isDescriptionExpanded ? "chevron.up" : "chevron.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(MIMITheme.bodyFont(size: 11, weight: .medium))
                    .foregroundStyle(MIMITheme.darkGold)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help(isDescriptionExpanded ? "收起曲谱说明" : "展开完整曲谱说明")
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 1)
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xF2EDE4)).frame(height: 1).offset(y: -5) }
        }
        .padding(12)
        .mimiCard(radius: 16, fill: MIMITheme.paperWhite, shadowOpacity: 0.03)
    }

    private func personalHero(_ score: PersonalScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NativeScoreDetailFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                Button { model.navigateBack() } label: { Label("返回", systemImage: "chevron.left") }.buttonStyle(.plain).foregroundStyle(MIMITheme.mutedInk)
                scoreChip(score.source == "private" ? "本机原件" : "曲库引用", tint: Color(hex: 0x8F6D2B))
                scoreChip(score.category, tint: MIMITheme.terracotta)
                scoreChip(score.format.uppercased(), tint: MIMITheme.bodyInk)
            }
            personalTitleAndActions(score)
            Text("\(score.artist.isEmpty ? "未知演奏者" : score.artist) · \(score.category) · \(score.format.uppercased()) · \(score.source == "private" ? "仅保存在本机" : "曲库来源")")
                .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(Color(hex: 0x705C42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .mimiCard(radius: 16, fill: MIMITheme.paperWhite, shadowOpacity: 0.03)
    }

    private func catalogTitleAndActions(_ item: CatalogItem) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                catalogTitleAndArtist(item)
                Spacer(minLength: 4)
                catalogQuickActions(item)
            }
            VStack(alignment: .leading, spacing: 7) {
                catalogTitleAndArtist(item)
                NativeScoreDetailFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                    catalogQuickActionButtons(item)
                    ScoreDetailActionMenu(item: item, controller: model.auditionController).id(item.id)
                }
            }
        }
    }

    private func catalogTitleAndArtist(_ item: CatalogItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(MIMITheme.displayFont(size: 24, weight: .bold)).foregroundStyle(MIMITheme.ink)
                .lineLimit(2).textSelection(.enabled)
            if let artist = nonempty(item.artist) {
                Text(artist).font(MIMITheme.bodyFont(size: 15, weight: .medium)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func catalogQuickActions(_ item: CatalogItem) -> some View {
        HStack(spacing: 6) {
            catalogQuickActionButtons(item)
            ScoreDetailActionMenu(item: item, controller: model.auditionController).id(item.id)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func catalogQuickActionButtons(_ item: CatalogItem) -> some View {
        ScoreActionButton(title: model.isFavorite(item) ? "已收藏" : "收藏", symbol: model.isFavorite(item) ? "heart.fill" : "heart", action: { model.toggleFavorite(for: item) })
            .disabled(item.id.hasPrefix("imported-"))
            .help(item.id.hasPrefix("imported-") ? "本机导入谱暂不支持收藏" : "收藏这首曲谱")
        ScoreActionButton(title: model.isQueued(item) ? "移出待练" : "加入待练", symbol: model.isQueued(item) ? "text.badge.minus" : "text.badge.plus", action: { model.toggleQueue(for: item) })
            .disabled(item.id.hasPrefix("imported-"))
            .help(item.id.hasPrefix("imported-") ? "本机导入谱暂不支持加入待练" : "加入或移出待练列表")
        ScoreActionButton(title: "分享", symbol: "square.and.arrow.up", action: { model.share(item) })
    }

    private func personalTitleAndActions(_ score: PersonalScore) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                personalTitleAndArtist(score)
                Spacer(minLength: 4)
                personalActions(score)
            }
            VStack(alignment: .leading, spacing: 7) {
                personalTitleAndArtist(score)
                personalActions(score)
            }
        }
    }

    private func personalTitleAndArtist(_ score: PersonalScore) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(score.title).font(MIMITheme.displayFont(size: 24, weight: .bold)).foregroundStyle(MIMITheme.ink).lineLimit(2).textSelection(.enabled)
            Text(score.artist.isEmpty ? "未知演奏者" : score.artist).font(MIMITheme.bodyFont(size: 15, weight: .medium)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func personalActions(_ score: PersonalScore) -> some View {
        NativeScoreDetailFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
            ScoreActionButton(title: "改编到工坊", symbol: "square.and.pencil", action: { model.navigate(.studioScore(id: score.id)) })
            ScoreActionButton(title: "练习回顾", symbol: "metronome", prominent: true, action: { model.preparePracticeScore(score.id); model.navigate(.practice(scoreID: score.id)) })
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func scoreChip(_ title: String, tint: Color) -> some View {
        Text(title).font(MIMITheme.bodyFont(size: 10, weight: .semibold)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tint.opacity(0.19), lineWidth: 1))
    }

    private func scoreDescription(_ item: CatalogItem) -> String {
        let form = item.sheetForm > 0 ? item.sheetFormLabel : "曲谱"
        let formName = form.hasSuffix("谱") ? String(form.dropLast()) : form
        if item.difficulty == 0 { return "\(categoryName(item.category))\(form)，适合吉他爱好者学习弹唱" }
        let descriptions = [
            1: "适合完全没接触过吉他的初学者，和弦简单、节奏平稳，容易上手。",
            2: "节奏简单易上手，适合刚入门、正在积累曲库的吉他爱好者。",
            3: "节奏与和弦有一定变化，适合有一定基础的练习者。",
            4: "指法与节奏较复杂，适合中高级进阶练习。",
            5: "编配完整、难度较高，适合专业水平的演奏者。",
        ]
        return "\(item.difficultyLabel)\(formName)谱，\(descriptions[min(5, max(1, item.difficulty))] ?? "适合对应水平的练习者。")"
    }

    private func screenshotAndMetadata(_ item: CatalogItem) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Group {
                if let screenshot = nonempty(item.screenshotURL) {
                    CatalogThumbnail(reference: screenshot, contentRoot: model.contentRoot, size: CGSize(width: 420, height: 270))
                        .frame(width: 420, height: 270).clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    ZStack { RoundedRectangle(cornerRadius: 16).fill(MIMITheme.paper); VStack(spacing: 9) { Image(systemName: "music.note.list").font(.system(size: 32, weight: .light)); Text("暂无谱面截图") } .font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }
                        .frame(width: 420, height: 270)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("曲谱信息").font(MIMITheme.displayFont(size: 21, weight: .semibold)).foregroundStyle(MIMITheme.ink); Spacer(); Label(item.displayHeat, systemImage: "flame.fill").font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.terracotta) }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                    Group {
                        metadata("乐器", categoryName(item.category))
                        metadata("演奏难度", difficultyName(item.difficulty))
                        metadata("谱型", item.sheetFormLabel)
                        metadata("曲风", styleName(item.style))
                        metadata("调性", item.key ?? "未标注")
                        metadata("调弦", item.tuningText ?? item.tuning ?? "未标注")
                        metadata("速度", item.bpm.map { "\($0) BPM" } ?? "未标注")
                        metadata("拍号", item.timeSignature ?? "未标注")
                        metadata("变调夹", item.capo.map { "第 \($0) 品" } ?? "未标注")
                        metadata("格式", item.format.uppercased())
                    }
                    Group {
                        metadata("上传者", item.uploader ?? "未标注")
                        metadata("发布日期", item.publishDate ?? item.createdAt ?? "未标注")
                        if let updatedAt = item.updatedAt { metadata("更新日期", updatedAt) }
                    }
                }
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 18, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
        }
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
            Text(value).font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.bodyInk).lineLimit(2).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(MIMITheme.displayFont(size: 21, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(text).font(MIMITheme.proseFont(size: 14)).foregroundStyle(MIMITheme.bodyInk).lineSpacing(6).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 18, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    private func tagSection(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("标签").font(MIMITheme.displayFont(size: 19, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            ViewThatFits(in: .horizontal) {
                HStack { tagPills(item) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 7) { tagPills(item) }
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading).mimiCard(radius: 18, fill: MIMITheme.paperWhite, shadowOpacity: 0.025)
    }

    @ViewBuilder private func tagPills(_ item: CatalogItem) -> some View {
        ForEach(Array(tags(for: item).enumerated()), id: \.offset) { _, value in
            Text(value).font(MIMITheme.bodyFont(size: 11, weight: .medium)).foregroundStyle(MIMITheme.bodyInk).padding(.horizontal, 11).padding(.vertical, 7).background(MIMITheme.paper, in: Capsule())
        }
    }

    private func relatedSection(_ items: [CatalogItem], category: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text("相关推荐曲谱").font(MIMITheme.displayFont(size: 21, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                Spacer()
                Button("查看更多 →") { model.navigate(.catalog(CatalogCategory(rawValue: category) ?? .all)) }
                    .font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.darkGold).buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 400), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(items) { related in relatedCard(related) }
            }
        }
    }

    private func relatedCard(_ item: CatalogItem) -> some View {
        Button { model.openCatalogItem(item) } label: {
            HStack(spacing: 14) {
                CatalogThumbnail(reference: item.screenshotURL, contentRoot: model.contentRoot, size: CGSize(width: 96, height: 96))
                    .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title).font(MIMITheme.displayFont(size: 15, weight: .semibold)).foregroundStyle(MIMITheme.ink).lineLimit(1)
                        Spacer(minLength: 0)
                        Label(item.displayHeat, systemImage: "flame.fill").font(MIMITheme.bodyFont(size: 10, weight: .medium)).foregroundStyle(MIMITheme.terracotta).fixedSize()
                    }
                    Text(item.artist ?? "未知歌手").font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                    HStack(spacing: 6) {
                        MIMIPill(title: "\(item.key ?? "G") 调")
                        MIMIPill(title: item.sheetForm > 0 ? item.sheetFormLabel : "六线谱")
                        if item.difficulty > 0 { DifficultyBadge(difficulty: item.difficulty) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .mimiCard(radius: 14, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
        }.buttonStyle(.plain)
    }

    private func recentHistorySection(for item: CatalogItem) -> some View {
        let recent = Array(model.recentEntries.filter { $0.id != item.id && ($0.category == item.category || $0.artist == item.artist) }.prefix(6))
        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("最近浏览的相近曲目").font(MIMITheme.displayFont(size: 19, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    ForEach(recent) { entry in
                        HStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(MIMITheme.darkGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
                                Text("\(entry.artist ?? "") · \(Date(timeIntervalSince1970: entry.time / 1_000).formatted(date: .abbreviated, time: .shortened))").font(MIMITheme.bodyFont(size: 10)).foregroundStyle(MIMITheme.mutedInk)
                            }
                            Spacer()
                            Button("打开") { model.navigate(.score(id: entry.id.hasPrefix("catalog:") ? String(entry.id.dropFirst("catalog:".count)) : entry.id)) }.buttonStyle(PaperSecondaryButtonStyle())
                        }.padding(10).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02)
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }.buttonStyle(.bordered).help(title)
    }
    private func nonempty(_ value: String?) -> String? { value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    private func tags(for item: CatalogItem) -> [String] {
        guard let rawTags = nonempty(item.tags) else { return [] }
        let values: [String]
        if let data = rawTags.data(using: .utf8), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            values = decoded
        } else if rawTags.hasPrefix("[") && rawTags.hasSuffix("]") {
            return []
        } else {
            values = rawTags.split(whereSeparator: { ",，;；|#、\n".contains($0) }).map(String.init)
        }
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private func categoryName(_ value: String) -> String {
        switch value.lowercased() { case "guitar": return "吉他"; case "ukulele": return "尤克里里"; case "bass": return "贝斯"; default: return value }
    }
    private func difficultyName(_ value: Int) -> String { [0: "未标注", 1: "零基础", 2: "初级", 3: "中级", 4: "高级", 5: "专业"][value] ?? "未标注" }
    private func styleName(_ value: Int?) -> String {
        guard let value else { return "未标注" }
        return [101: "流行", 102: "摇滚", 103: "民谣", 105: "配乐", 107: "乡村", 109: "金属"][value] ?? "其他"
    }
}

private struct NativeScoreDetailFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widthLimit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + horizontalSpacing + size.width > widthLimit {
                widestRow = max(widestRow, x)
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }
            if x > 0 { x += horizontalSpacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, x)
        return CGSize(width: widthLimit.isFinite ? widthLimit : widestRow, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + horizontalSpacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            if x > bounds.minX { x += horizontalSpacing }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ScoreDetailActionMenu: View {
    @EnvironmentObject private var model: AppModel
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
        Menu {
            Button {
                controller.play(item: item)
            } label: {
                Label(playLabel, systemImage: playback.isActive && playback.isPlaying ? "waveform" : "play.fill")
            }
            Button {
                controller.toggle(item: item, previewDuration: 30)
            } label: {
                Label(previewLabel, systemImage: playback.isActive && playback.isPlaying ? "pause.fill" : "headphones")
            }
            if playback.isActive && !playback.statusMessage.isEmpty {
                Text(playback.statusMessage)
            }
            Button("改编到制谱工坊") { model.navigate(.studioClone(sourceID: item.id)) }
            Button("加入练习并打开回顾") { model.preparePracticeScore(item.id); model.navigate(.practice(scoreID: item.id)) }
            Divider()
            Button("下载原始曲谱…") { model.openDownload(for: item) }
            Button("复制曲谱链接") { model.copyShareLink(for: item) }
            Button("分享曲谱…") { model.share(item) }
        } label: { Label("更多", systemImage: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .help("播放、改编、下载或分享")
    }

    private var playLabel: String {
        if playback.isActive && playback.isLoading { return "正在加载完整曲谱…" }
        if playback.isActive && playback.isPlaying { return "正在播放完整曲谱" }
        return "播放完整曲谱"
    }

    private var previewLabel: String {
        if playback.isActive && playback.isLoading { return "正在加载试听…" }
        if playback.isActive && playback.isPlaying { return "暂停 30 秒试听" }
        return "试听 30 秒"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
