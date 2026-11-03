import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var isDropTargeted = false
    @State private var contentViewportHeight: CGFloat = 0

    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    private func isPracticeRoute(_ route: NativeRoute) -> Bool {
        if case .practice = route { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Keep the one audio host mounted at the window root behind background
            if let contentRoot = model.contentRoot, let store = model.personalStore {
                NativeAuditionHost(controller: model.auditionController, contentRoot: contentRoot, personalStore: store)
                    .frame(width: 320, height: 240)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            ZStack {
                MIMITheme.paper
                StaticPaperAmbience()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationChrome
                pageContainer
            }
        }
        .background {
            MainWindowBridge(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AuditionStatusBar(controller: model.auditionController)
                .environmentObject(model)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(MIMITheme.signalBlue, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: receiveDroppedFiles)
        .onOpenURL(perform: handleOpenURL)
        .sheet(isPresented: $model.isCommandPalettePresented) {
            CommandPaletteView()
                .environmentObject(model)
                .frame(width: 736, height: 590)
        }
        .alert(model.alertTitle, isPresented: Binding(
            get: { model.isShowingAlert },
            set: { if !$0 { model.dismissAlert() } }
        )) {
            Button("好", role: .cancel) { model.dismissAlert() }
        } message: {
            Text(model.alertMessage)
        }
        .onAppear {
            model.setRouteTransitionCaptureHandler { }
        }
        .onDisappear {
            model.setRouteTransitionCaptureHandler(nil)
        }
        .onExitCommand { model.handleScoreFocusEscape() }
        .animation(motionPolicy.controlAnimation, value: isDropTargeted)
        .environment(\.mimiFooterNavigate) { route in model.navigate(route) }
    }

    private var pageContainer: some View {
        GeometryReader { viewport in
            ZStack {
                pageContent(for: model.route)
                    .id(model.route)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: viewport.size.height, maxHeight: .infinity, alignment: .top)
            .environment(\.mimiViewportHeight, viewport.size.height)
            .onAppear {
                contentViewportHeight = viewport.size.height
            }
            .onChange(of: viewport.size.height) { newHeight in
                contentViewportHeight = newHeight
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motionPolicy == .off ? nil : .easeInOut(duration: 0.10), value: model.route)
    }

    private var navigationChrome: some View {
        VStack(spacing: 0) {
            HStack {
                NativeNavigationBar()
                    .frame(maxWidth: 1240)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .opacity(model.isScoreFocused ? 0 : 1)
        }
        .frame(height: model.isScoreFocused ? 0 : nil, alignment: .top)
        .clipped()
        .allowsHitTesting(!model.isScoreFocused)
        .accessibilityHidden(model.isScoreFocused)
        .animation(motionPolicy.panelAnimation, value: model.isScoreFocused)
        .zIndex(5)
    }

    private func basePageTopPadding(for route: NativeRoute) -> CGFloat {
        switch route {
        case .catalog(_), .catalogQuery(_, _), .search(_, _): return 32
        case .practice, .library, .dataSettings: return 40
        case .articles, .article(_), .account(_): return 0
        default: return 24
        }
    }

    private func pageContentMaxWidth(for route: NativeRoute) -> CGFloat {
        switch route {
        case .library:
            return 1120
        case .dataSettings:
            return 960
        default:
            return 1240
        }
    }

    private var pageContentHorizontalPadding: CGFloat {
        return 24
    }

    @ViewBuilder
    private func pageContent(for route: NativeRoute) -> some View {
        switch route {
        case .home:
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    pageContentWithSiteFooter(for: route, bottomPadding: 30, includeFooter: false) { HomeView() }
                        .id("home-scroll-top")
                }
                    .scrollIndicators(.hidden)
                    .onReceive(NotificationCenter.default.publisher(for: .init("MIMI.ScrollToTop"))) { _ in
                        withAnimation(reduceMotion || motionPreference == "off" ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo("home-scroll-top", anchor: .top)
                        }
                    }
            }
        case .catalog, .catalogQuery:
            ScrollView(.vertical) {
                pageContentWithSiteFooter(for: route) { CatalogListView() }
            }
                .scrollIndicators(.hidden)
        case .search(_, let domain):
            ScrollView(.vertical) {
                pageContentWithSiteFooter(for: route) {
                    Group {
                        if domain == .article { ArticleListView(isSearchResults: true) }
                        else { CatalogListView(isSearchResults: true) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        case .score(let id):
            ScoreDetailView(explicitScoreID: id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .studio:
            studioWorkspacePane()
        case .studioClone(_):
            if let source = model.studioCloneSource, model.contentRoot != nil, model.personalStore != nil {
                studioWorkspacePane(cloneFrom: source)
            } else {
                studioRouteGate(
                    loadingMessage: "正在读取要改编的曲谱…",
                    missingMessage: "没有取得要改编的曲谱资料。",
                    backLabel: "返回工坊"
                )
            }
        case .studioScore(_):
            if let score = model.studioClonePersonalScore, model.contentRoot != nil, model.personalStore != nil {
                studioWorkspacePane(cloneFromScore: score)
            } else {
                studioRouteGate(
                    loadingMessage: "正在读取个人曲谱…",
                    missingMessage: "没有取得个人曲谱资料。",
                    backLabel: "返回工坊"
                )
            }
        case .studioProject(let projectID):
            if let project = model.studioProjectToOpen, model.contentRoot != nil, model.personalStore != nil {
                if project.id == projectID {
                    studioProjectPane(project)
                } else {
                    studioRouteGate(
                        loadingMessage: "正在读取所选工坊工程…",
                        missingMessage: "没有取得所选工坊工程资料。",
                        backLabel: "返回工坊"
                    )
                }
            } else {
                studioRouteGate(
                    loadingMessage: "正在读取所选工坊工程…",
                    missingMessage: "没有取得所选工坊工程资料。",
                    backLabel: "返回工坊"
                )
            }
        case .practice:
            GeometryReader { geometry in
                ScrollView {
                    pageContentWithSiteFooter(for: route) { PracticeView() }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(model.isScoreFocused)
                .environment(\.mimiViewportHeight, geometry.size.height)
            }
        case .library:
            ScrollViewReader { proxy in
                ScrollView {
                    pageContentWithSiteFooter(for: route) {
                        PersonalLibraryView(onRequestScrollToSection: { target in
                            DispatchQueue.main.async {
                                withAnimation(reduceMotion || motionPreference == "off" ? nil : .easeInOut(duration: 0.22)) {
                                    proxy.scrollTo(target, anchor: .top)
                                }
                            }
                        })
                    }
                }
                .scrollIndicators(.hidden)
            }
        case .dataSettings:
            ScrollView { pageContentWithSiteFooter(for: route) { BackupSettingsView() } }.scrollIndicators(.hidden)
        case .articles:
            ScrollView { pageContentWithSiteFooter(for: route) { ArticleListView() } }.scrollIndicators(.hidden)
        case .article(let id):
            ScrollView { pageContentWithSiteFooter(for: route) { ArticleDetailView(articleID: id) } }.scrollIndicators(.hidden)
        case .publishArticle:
            ScrollView { pageContentWithSiteFooter(for: route) { PublishArticleView() } }.scrollIndicators(.hidden)
        case .account(let area):
            ScrollView { pageContentWithSiteFooter(for: route) { AccountView(area: area) } }.scrollIndicators(.hidden)
        case .login, .register, .authenticationReturn, .resetPassword:
            ScrollView { pageContentWithSiteFooter(for: route) { AccountAuthView() } }.scrollIndicators(.hidden)
        case .upload:
            ScrollView { pageContentWithSiteFooter(for: route) { PublicUploadDisabledView() } }.scrollIndicators(.hidden)
        case .document(let page):
            ScrollView { pageContentWithSiteFooter(for: route) { DocumentPageView(page: page) } }.scrollIndicators(.hidden)
        case .motion:
            ScrollView { pageContentWithSiteFooter(for: route) { MotionExperienceView() } }.scrollIndicators(.hidden)
        case .showcase:
            ScrollView { pageContentWithSiteFooter(for: route) { ShowcasePageView() } }.scrollIndicators(.hidden)
        }
    }

    private func pageContentWithSiteFooter<Content: View>(
        for route: NativeRoute,
        bottomPadding: CGFloat = 48,
        includeFooter: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, pageContentHorizontalPadding)
                .padding(.top, model.isScoreFocused && isPracticeRoute(route) ? 0 : basePageTopPadding(for: route))
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: model.isScoreFocused && isPracticeRoute(route) ? .infinity : pageContentMaxWidth(for: route))
                .frame(maxWidth: .infinity, alignment: .top)
            if !model.isScoreFocused && includeFooter {
                Spacer(minLength: 32)
                MIMISiteFooter()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: contentViewportHeight > 0 ? contentViewportHeight : nil, alignment: .top)
        .background(
            RouteScrollPositionTracker(model: model, route: route)
                .frame(width: 0, height: 0),
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func studioWorkspacePane(cloneFrom: CatalogItem? = nil, cloneFromScore: PersonalScore? = nil) -> some View {
        if let contentRoot = model.contentRoot, let store = model.personalStore {
            NativeStudioPane(contentRoot: contentRoot, personalStore: store, onOpenPractice: { id in model.navigate(.practice(scoreID: id)) }, onPersonalDataChanged: model.personalDataDidChange, onStudioFileConsumed: { if let url = model.pendingStudioImportURL { model.consumeStudioImportURL(url) } }, cloneFrom: cloneFrom, cloneFromScore: cloneFromScore, importURL: model.pendingStudioImportURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.contentRoot == nil, model.bootstrapMessage == nil {
            VStack(spacing: 11) {
                ProgressView()
                Text("正在准备本地工坊资料…").font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.bootstrapMessage != nil {
            studioRouteGate(
                loadingMessage: "正在准备本地工坊资料…",
                missingMessage: "本地工坊资料尚未就绪。",
                backLabel: "返回工坊"
            )
        } else {
            WorkspaceUnavailableView(title: "工坊数据尚未就绪", message: model.bootstrapMessage ?? "正在准备本地工坊资料。")
        }
    }

    @ViewBuilder
    private func studioProjectPane(_ project: StudioProject) -> some View {
        if let contentRoot = model.contentRoot, let store = model.personalStore {
            NativeStudioPane(contentRoot: contentRoot, personalStore: store, onOpenPractice: { id in model.navigate(.practice(scoreID: id)) }, onPersonalDataChanged: model.personalDataDidChange, openProject: project)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            studioRouteGate(
                loadingMessage: "正在准备工坊资料…",
                missingMessage: "工坊本地资料尚未就绪。",
                backLabel: "返回工坊"
            )
        }
    }

    private func studioRouteGate(loadingMessage: String, missingMessage: String, backLabel: String) -> some View {
        Group {
            if model.studioLoadIsLoading || (model.contentRoot == nil && model.bootstrapMessage == nil) {
                VStack(spacing: 11) {
                    ProgressView()
                    Text(loadingMessage).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                }
            } else {
                let message = model.studioLoadMessage ?? model.bootstrapMessage ?? missingMessage
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(MIMITheme.terracotta)
                    Text("工坊内容无法载入").font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
                    Text(message).font(MIMITheme.bodyFont(size: 13)).foregroundStyle(MIMITheme.mutedInk)
                        .multilineTextAlignment(.center).textSelection(.enabled).frame(maxWidth: 500)
                    HStack(spacing: 9) {
                        Button("重试") {
                            if model.bootstrapMessage != nil || model.contentRoot == nil { model.retryBootstrap() }
                            else { model.retryStudioRoute() }
                        }
                        .buttonStyle(.borderedProminent).tint(MIMITheme.darkGold)
                        Button(model.canNavigateBack ? "返回上一页" : backLabel) {
                            if model.canNavigateBack { model.navigateBack() }
                            else { model.navigate(.studio) }
                        }
                        .buttonStyle(PaperSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleOpenURL(_ url: URL) {
        if url.isFileURL {
            model.routeImportedFile(url)
        } else {
            model.openURL(url)
        }
    }

    private func receiveDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil else { return }
            let url = (item as? URL) ?? (item as? NSURL).map { $0 as URL } ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
            guard let url else { return }
            DispatchQueue.main.async { model.routeImportedFile(url) }
        }
        return true
    }
}

private struct NativeNavigationBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @Namespace private var selectionNamespace

    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    private let links: [(String, NativeRoute)] = [
        ("吉他谱", .catalog(.guitar)),
        ("尤克里里", .catalog(.ukulele)),
        ("制谱工坊 PRO", .studio),
        ("专栏文章", .articles),
        ("我的练习", .practice(scoreID: nil)),
        ("我的谱", .library),
        ("备份", .dataSettings),
    ]

    var body: some View {
        HStack(spacing: 20) {
            Button { model.navigate(.home) } label: {
                HStack(spacing: 9) {
                    MIMILogoView(size: 34)
                    Text("MIMI Guitar")
                        .font(MIMITheme.displayFont(size: 17, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(MIMITheme.navigationInk)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            ViewThatFits(in: .horizontal) {
                desktopNavigationLinks
                compactNavigationMenu
            }

            Spacer(minLength: 4)

            Button { model.presentCommandPalette() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                    Text("搜索曲谱…")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MIMITheme.navigationBorder, lineWidth: 1))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MIMITheme.navigationMuted)
                .padding(.horizontal, 12)
                .frame(minWidth: 168, idealWidth: 196, maxWidth: 200, minHeight: 38)
                .background(MIMITheme.navigationSearch, in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.navigationBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)
            .help("全站搜索（⌘K）")

            Menu {
                Button("吉他谱（GP / MusicXML）") { model.navigate(.upload) }
                Button("尤克里里谱") { model.navigate(.upload) }
            } label: {
                Label("上传", systemImage: "arrow.up.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MIMITheme.navigationBrown)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .frame(minHeight: 34)
                    .background(MIMITheme.paperWhite, in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.navigationBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(MIMITheme.navigationPaper, in: Capsule())
        .overlay(Capsule().stroke(MIMITheme.navigationOutline, lineWidth: 1))
        .shadow(color: Color(hex: 0x483620).opacity(0.035), radius: 6, x: 0, y: 3)
        .animation(motionPolicy.navigationAnimation, value: model.route)
    }

    private func isActive(_ target: NativeRoute) -> Bool {
        switch (model.route, target) {
        case (.home, .home): return true
        case (.catalog(let lhs), .catalog(let rhs)): return lhs == rhs
        case (.catalogQuery(let lhs, _), .catalog(let rhs)): return lhs == rhs
        case (.practice, .practice): return true
        case (.library, .library): return true
        case (.dataSettings, .dataSettings): return true
        case (.articles, .articles): return true
        case (.studio, .studio): return true
        case (.studioClone, .studio): return true
        case (.studioScore, .studio): return true
        default: return false
        }
    }

    private var desktopNavigationLinks: some View {
        HStack(spacing: 3) {
            ForEach(links, id: \.0) { label, route in
                Button { model.navigate(route) } label: {
                    HStack(spacing: 5) {
                        if label == "制谱工坊 PRO" {
                            Text("制谱工坊")
                            Text("PRO")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4.5)
                                .padding(.vertical, 1.5)
                                .background(isActive(route) ? MIMITheme.warmGold : MIMITheme.warmGold.opacity(0.18), in: Capsule())
                        } else {
                            Text(label)
                        }
                    }
                    .font(.system(size: 13, weight: navigationFontWeight(label, route: route)))
                    .foregroundStyle(isActive(route) ? Color(hex: 0xFBFAF7) : MIMITheme.navigationBrown)
                    .padding(.horizontal, ["我的练习", "我的谱", "备份"].contains(label) ? 11 : 14)
                    .padding(.vertical, 7)
                    .frame(minHeight: 36)
                    .background {
                        if isActive(route) {
                            if motionPolicy.allowsSpatialMotion {
                                Capsule()
                                    .fill(MIMITheme.navigationInk)
                                    .shadow(color: Color(hex: 0x24201D).opacity(0.15), radius: 3, x: 0, y: 1.5)
                                    .matchedGeometryEffect(id: "selected-navigation-route", in: selectionNamespace)
                            } else {
                                Capsule()
                                    .fill(MIMITheme.navigationInk)
                                    .shadow(color: Color(hex: 0x24201D).opacity(0.15), radius: 3, x: 0, y: 1.5)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(label)
            }
        }
        .padding(4)
        .background(MIMITheme.navigationSegment.opacity(0.85), in: Capsule())
        .overlay(Capsule().stroke(MIMITheme.navigationBorder, lineWidth: 1))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactNavigationMenu: some View {
        Menu {
            ForEach(links, id: \.0) { label, route in
                Button {
                    model.navigate(route)
                } label: {
                    if isActive(route) {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
            Section("账号中心") {
                ForEach(AccountArea.allCases) { area in
                    Button(area.title) { model.navigate(.account(area)) }
                }
                if model.remoteUser != nil {
                    Button("退出登录") { model.logout() }
                } else {
                    Button("登录") { model.navigate(.login) }
                    Button("注册") { model.navigate(.register) }
                }
            }
        } label: {
            Label("导航", systemImage: "line.3.horizontal")
                .font(MIMITheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(MIMITheme.navigationInk)
                .padding(.horizontal, 13)
                .frame(minHeight: 38)
                .background(MIMITheme.navigationSegment.opacity(0.75), in: Capsule())
                .overlay(Capsule().stroke(MIMITheme.navigationBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 44, height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .help("打开导航菜单")
    }

    private func navigationFontWeight(_ label: String, route: NativeRoute) -> Font.Weight {
        let boldActiveLabels = ["吉他谱", "尤克里里", "制谱工坊 PRO", "专栏文章"]
        return isActive(route) && boldActiveLabels.contains(label) ? .bold : .medium
    }
}

private struct AuditionStatusBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    let controller: NativeAuditionController
    @StateObject private var auditionState: AuditionItemViewState

    private var playback: AuditionPlaybackSnapshot { auditionState.snapshot }
    private var clock: AuditionPlaybackClock { auditionState.clock }
    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }
    private var shouldShow: Bool {
        guard playback.isActive, controller.activeItem != nil, !model.isScoreFocused else { return false }
        switch model.route {
        case .score, .practice, .studio, .studioClone, .studioScore, .studioProject:
            return false
        default:
            return true
        }
    }

    init(controller: NativeAuditionController) {
        self.controller = controller
        _auditionState = StateObject(wrappedValue: controller.viewState(tracksClock: true))
    }

    private func formatMilliseconds(_ ms: Double) -> String {
        guard ms.isFinite, ms > 0 else { return "0:00" }
        let totalSeconds = max(0, Int((ms / 1000.0).rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var body: some View {
        Group {
            if shouldShow, let item = controller.activeItem {
                HStack(spacing: 11) {
                    // 1. Play / Pause Circular Button with morphing colors
                    Button {
                        controller.toggle(item: item)
                    } label: {
                        Group {
                            if playback.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .background(
                            playback.isPlaying ? MIMITheme.darkGold : MIMITheme.ink,
                            in: Circle()
                        )
                        .shadow(color: (playback.isPlaying ? MIMITheme.darkGold : Color.black).opacity(0.2), radius: 4, x: 0, y: 1.5)
                    }
                    .buttonStyle(.plain)
                    .help(playback.isPlaying ? "暂停试听" : "继续试听")

                    // 2. Track & Artist Info
                    Button {
                        model.navigate(.score(id: item.id))
                        model.openCatalogItem(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text(playback.activeItemTitle)
                                .font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                                .foregroundStyle(MIMITheme.ink)
                                .lineLimit(1)
                            Text(playback.activeItemArtist)
                                .font(.system(size: 11))
                                .foregroundStyle(MIMITheme.mutedInk)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 130, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("打开曲谱详情")

                    // Divider
                    Rectangle()
                        .fill(MIMITheme.softBorder)
                        .frame(width: 1, height: 24)

                    // 3. FluidAudioWaveform Component
                    MIMIFluidAudioWaveform(
                        isPlaying: playback.isPlaying,
                        bpm: controller.tempo,
                        primaryColor: MIMITheme.ink,
                        secondaryColor: MIMITheme.signalBlue,
                        width: 100,
                        height: 26
                    )

                    // 4. Progress Bar & Time Indicators
                    HStack(spacing: 6) {
                        Text(formatMilliseconds(clock.currentTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(MIMITheme.mutedInk)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 36, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: {
                                    clock.endTime > 0 ? min(1, max(0, clock.currentTime / clock.endTime)) : 0
                                },
                                set: { controller.seek(toRatio: $0) }
                            ),
                            in: 0...1
                        )
                        .frame(width: 85)
                        .tint(playback.isPlaying ? MIMITheme.warmGold : MIMITheme.ink)
                        .disabled(!playback.canPlay || clock.endTime <= 0)

                        Text(formatMilliseconds(clock.endTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                            .foregroundStyle(MIMITheme.mutedInk)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 36, alignment: .leading)
                    }

                    // Divider
                    Rectangle()
                        .fill(MIMITheme.softBorder)
                        .frame(width: 1, height: 24)

                    // 5. Speed Badge
                    Text("♩ \(Int(controller.tempo))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                        .foregroundStyle(MIMITheme.bodyInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color(hex: 0xF7F2E8), in: Capsule())
                        .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1))

                    // 6. Close Button
                    Button {
                        controller.pause()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MIMITheme.mutedInk)
                            .frame(width: 26, height: 26)
                            .background(Color(hex: 0xF2ECE0).opacity(0.8), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("停止并关闭试听")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(height: 56)
                .mimiCard(radius: 18, fill: MIMITheme.paperWhite, shadowOpacity: 0.12)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84, alignment: .bottom)
        .opacity(shouldShow ? 1 : 0)
        .animation(motionPolicy.panelAnimation, value: shouldShow)
        .frame(height: shouldShow ? 84 : 0, alignment: .bottom)
        .animation(motionPolicy.allowsSpatialMotion ? motionPolicy.panelAnimation : nil, value: shouldShow)
        .allowsHitTesting(shouldShow)
        .accessibilityHidden(!shouldShow)
    }
}

struct WorkspaceUnavailableView: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 30)).foregroundStyle(MIMITheme.warmGold)
            Text(title).font(MIMITheme.displayFont(size: 22, weight: .semibold)).foregroundStyle(MIMITheme.ink)
            Text(message).font(MIMITheme.bodyFont(size: 14)).foregroundStyle(MIMITheme.mutedInk).multilineTextAlignment(.center)
            Button("重试") { NotificationCenter.default.post(name: .init("MIMI.RetryBootstrap"), object: nil) }
                .buttonStyle(.borderedProminent).tint(MIMITheme.darkGold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .mimiCard()
    }
}
