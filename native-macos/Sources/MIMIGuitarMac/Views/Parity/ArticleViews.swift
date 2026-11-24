import MIMICore
import SwiftUI

struct ArticleListView: View {
    @EnvironmentObject private var model: AppModel
    var isSearchResults = false

    @State private var selectedCategory: String = "全部"
    private let categories = ["全部", "软件教程", "演奏技巧", "乐理视奏", "琴房心得", "选琴指南"]

    private var rawRows: [CatalogArticle] { isSearchResults ? model.searchArticles : model.articles }

    private var cleanRows: [CatalogArticle] {
        rawRows.filter { a in
            let isClean = !a.title.hasPrefix("测试文章") && !a.title.hasPrefix("M7 验收文章")
            if selectedCategory == "全部" {
                return isClean
            } else {
                return isClean && (a.category == selectedCategory)
            }
        }
    }

    private var headlineArticle: CatalogArticle? {
        guard !isSearchResults, model.articlePage == 1, selectedCategory == "全部" else { return nil }
        return cleanRows.first(where: { $0.id == "art-player" }) ?? cleanRows.first
    }

    private var gridRows: [CatalogArticle] {
        if let headline = headlineArticle {
            return cleanRows.filter { $0.id != headline.id }
        }
        return cleanRows
    }

    private var pageCount: Int { max(1, Int(ceil(Double(model.articleTotal) / 9))) }
    private var searchQuery: String { isSearchResults ? model.searchText : model.articleSearch }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. Newspaper Editorial Masthead
            ArticleNewspaperMasthead(
                selectedCategory: $selectedCategory,
                categories: categories,
                totalArticles: cleanRows.count
            )

            // 2. Action Controls Bar (Search / Sort / Publish)
            HStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MIMITheme.mutedInk)
                    TextField(isSearchResults ? "搜索文章标题或正文" : "在专栏文章中快速检索…", text: isSearchResults ? $model.searchText : $model.articleSearch)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if isSearchResults { model.searchArticlesDidChange() }
                            else { model.searchArticlesDidChange() }
                        }
                }
                .padding(.horizontal, 14).frame(width: 320, height: 40)
                .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(MIMITheme.softBorder, lineWidth: 1))

                articleSortControl

                Spacer(minLength: 8)

                if model.articleListIsLoading {
                    ProgressView().controlSize(.small)
                }

                Button {
                    model.navigate(.publishArticle)
                } label: {
                    Label("发布文章", systemImage: "square.and.pencil")
                }
                .buttonStyle(PaperProminentButtonStyle())
            }

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
                .accessibilityElement(children: .contain)
            }

            // 3. Featured Headline Story (Broadsheet Hero)
            if let headline = headlineArticle {
                ArticleHeadlineHeroView(article: headline) { id in
                    model.navigate(.article(id: id))
                }
            }

            // 4. Blackboard / Bulletin Board Sticky Cheatsheet Wall
            if !isSearchResults && model.articlePage == 1 {
                ArticleBulletinBoardSection { id in
                    model.navigate(.article(id: id))
                }
            }

            // 5. Editorial Articles Grid Header
            HStack(spacing: 8) {
                Capsule().fill(Color(hex: 0xC49A45)).frame(width: 4, height: 18)
                Text(selectedCategory == "全部" ? "专栏精选 · EDITORIAL ARTICLES" : "\(selectedCategory) · 专栏列表")
                    .font(MIMITheme.displayFont(size: 19, weight: .bold))
                    .foregroundStyle(MIMITheme.ink)
                Spacer()
                Text("共 \(gridRows.count) 篇文章")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MIMITheme.mutedInk)
            }
            .padding(.top, 8)

            // 6. Articles Grid
            if model.articleListIsLoading && gridRows.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("正在载入文章…").font(MIMITheme.bodyFont(size: 13, weight: .medium))
                    Text("正在读取本机文章索引。网络发布功能使用单独的账号服务。")
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .mimiCard(radius: 20, fill: MIMITheme.paperWhite)
            } else if gridRows.isEmpty && model.articleListMessage == nil {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(MIMITheme.mutedInk)
                    Text(searchQuery.isEmpty ? "该分类暂无文章，敬请期待" : "没有找到与「\(searchQuery)」相关的文章")
                        .font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.mutedInk)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .mimiCard(radius: 20, fill: MIMITheme.paperWhite)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(gridRows) { article in
                        ArticlePaperCardView(article: article) { id in
                            model.navigate(.article(id: id))
                        }
                    }
                }
            }

            // Pagination Controls
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
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
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

    private func retryArticleList() {
        if model.bootstrapMessage != nil || model.contentRoot == nil { model.retryBootstrap() }
        else if isSearchResults { model.searchArticlesDidChange() }
        else { model.loadArticles(immediately: true) }
    }
}

struct ArticleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let articleID: String

    private var relatedArticles: [CatalogArticle] {
        model.articles.filter { $0.id != articleID && !$0.title.hasPrefix("测试") && !$0.title.hasPrefix("M7") }.prefix(3).map { $0 }
    }

    var body: some View {
        Group {
            if let article = model.selectedArticle, article.id == articleID {
                VStack(alignment: .leading, spacing: 0) {
                    // Top navigation and action header
                    HStack {
                        Button { returnToArticleList() } label: {
                            Label("返回文章列表", systemImage: "arrow.left")
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())

                        Spacer()

                        Text("纸本琴声 · 琴房墨卷")
                            .font(MIMITheme.proseFont(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x8A7151))

                        Spacer()

                        Button("分享墨卷") { shareArticle(article) }.buttonStyle(PaperSecondaryButtonStyle())
                        Button("复制标题") { copyArticleTitle(article.title) }.buttonStyle(PaperSecondaryButtonStyle())
                    }
                    .padding(.bottom, 20)

                    // Open Book Manuscript Page Container
                    VStack(alignment: .leading, spacing: 0) {
                        // Header metadata & title
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(article.category ?? "软件教程")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color(hex: 0xC84B31))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3.5)
                                    .background(Color(hex: 0xC84B31).opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                                Text("出刊日期: \(articleDate(article.createdAt))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(MIMITheme.mutedInk)

                                Spacer()

                                Text("已阅览 \(articleHeat(article.views)) 次 · MIMI 琴房编配组")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: 0x6E5D48))
                            }

                            Text(article.title)
                                .font(MIMITheme.displayFont(size: 34, weight: .bold))
                                .tracking(-0.5)
                                .foregroundStyle(MIMITheme.ink)
                                .lineSpacing(6)
                                .fixedSize(horizontal: false, vertical: true)

                            // Double ornamental divider line
                            VStack(spacing: 2) {
                                Rectangle().fill(MIMITheme.softBorder).frame(height: 1.5)
                                Rectangle().fill(MIMITheme.faintBorder).frame(height: 0.8)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.bottom, 28)

                        // Rich Editorial Content Body
                        ArticleEditorialContent(articleID: article.id, content: article.content)
                            .padding(.bottom, 36)

                        // Bottom Navigation Bar (Seal stamp removed per UX feedback)
                        VStack(spacing: 16) {
                            Rectangle().fill(MIMITheme.faintBorder).frame(height: 1)

                            HStack(alignment: .center) {
                                Text("MIMI GUITAR · 专栏教程")
                                    .font(MIMITheme.displayFont(size: 13, weight: .medium))
                                    .foregroundStyle(MIMITheme.mutedInk)

                                Spacer()

                                HStack(spacing: 10) {
                                    Button { returnToArticleList() } label: {
                                        Label("返回文章列表", systemImage: "arrow.left")
                                    }
                                    .buttonStyle(PaperSecondaryButtonStyle())

                                    Button { shareArticle(article) } label: {
                                        Label("分享文章", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(PaperSecondaryButtonStyle())

                                    Button { copyArticleTitle(article.title) } label: {
                                        Label("复制标题", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(PaperSecondaryButtonStyle())
                                }
                            }
                        }
                        .padding(.top, 14)
                    }
                    .padding(36)
                    .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(hex: 0xD8CEBD), lineWidth: 1.5)
                    )
                    .shadow(color: Color(hex: 0x483620).opacity(0.04), radius: 4, x: 0, y: 2)

                    // Related Reading Section
                    if !relatedArticles.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Capsule().fill(Color(hex: 0xC49A45)).frame(width: 4, height: 18)
                                Text("相关专栏导读")
                                    .font(MIMITheme.displayFont(size: 18, weight: .bold))
                                    .foregroundStyle(MIMITheme.ink)
                                Spacer()
                            }
                            .padding(.top, 36)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)
                            ], spacing: 14) {
                                ForEach(relatedArticles) { rel in
                                    ArticlePaperCardView(article: rel) { id in
                                        model.navigate(.article(id: id))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func articleHeat(_ views: Int) -> String {
        guard views >= 10_000 else { return "\(views)" }
        return String(format: "%.1f万", locale: Locale(identifier: "en_US_POSIX"), Double(views) / 10_000)
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

