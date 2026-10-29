import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var isDropTargeted = false
    @StateObject private var routeTransition = MainWindowTransitionState()

    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    private var isPracticeRoute: Bool {
        if case .practice = model.route { return true }
        return false
    }

    var body: some View {
        ZStack {
            MIMITheme.paper.ignoresSafeArea()
            StaticPaperAmbience()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                navigationChrome
                pageContainer
            }

            // Keep the one audio host mounted at the window root while routes and focus chrome change.
            if let contentRoot = model.contentRoot, let store = model.personalStore {
                NativeAuditionHost(controller: model.auditionController, contentRoot: contentRoot, personalStore: store)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
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
            routeTransition.updatePolicy(motionPolicy)
            model.setRouteTransitionCaptureHandler { routeTransition.beginRouteChange() }
        }
        .onDisappear {
            model.setRouteTransitionCaptureHandler(nil)
            routeTransition.clear()
        }
        .onChange(of: model.route) { _ in routeTransition.finishRouteChange() }
        .onChange(of: motionPreference) { _ in routeTransition.updatePolicy(motionPolicy) }
        .onChange(of: reduceMotion) { _ in routeTransition.updatePolicy(motionPolicy) }
        .onExitCommand { model.handleScoreFocusEscape() }
        .animation(motionPolicy.controlAnimation, value: isDropTargeted)
        .environment(\.mimiFooterNavigate) { route in model.navigate(route) }
    }

    private var pageContainer: some View {
        ZStack(alignment: .topLeading) {
            pageBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(routeTransition.incomingOpacity)
                .offset(y: routeTransition.incomingOffset)

            if let snapshot = routeTransition.snapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(routeTransition.snapshotOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            MainWindowBridge(model: model, transition: routeTransition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            .animation(motionPolicy.panelAnimation, value: model.isScoreFocused)
        }
        .frame(height: model.isScoreFocused ? 0 : nil, alignment: .top)
        .animation(motionPolicy.allowsSpatialMotion ? motionPolicy.panelAnimation : nil, value: model.isScoreFocused)
        .clipped()
        .allowsHitTesting(!model.isScoreFocused)
        .accessibilityHidden(model.isScoreFocused)
        .animation(motionPolicy.panelAnimation, value: model.isScoreFocused)
        .zIndex(5)
    }

    private var basePageTopPadding: CGFloat {
        switch model.route {
        case .catalog(_), .catalogQuery(_, _), .search(_, _): return 32
        case .practice, .library, .dataSettings: return 40
        case .articles, .article(_), .account(_): return 0
        default: return 24
        }
    }

    private var pageContentMaxWidth: CGFloat {
        switch model.route {
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
    private var pageBody: some View {
        switch model.route {
        case .home:
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    pageContentWithSiteFooter(bottomPadding: 30) { HomeView() }
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
                pageContentWithSiteFooter { CatalogListView() }
            }
                .scrollIndicators(.hidden)
        case .search(_, let domain):
            ScrollView(.vertical) {
                pageContentWithSiteFooter {
                    Group {
                        if domain == .article { ArticleListView(isSearchResults: true) }
                        else { CatalogListView(isSearchResults: true) }
                    }
                }
            }
            .scrollIndicators(.hidden)
        case .score:
            ScoreDetailView()
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
                    pageContentWithSiteFooter { PracticeView() }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(model.isScoreFocused)
                .environment(\.mimiViewportHeight, geometry.size.height)
            }
        case .library:
            ScrollViewReader { proxy in
                ScrollView {
                    pageContentWithSiteFooter {
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
            ScrollView { pageContentWithSiteFooter { BackupSettingsView() } }.scrollIndicators(.hidden)
        case .articles:
            ScrollView { pageContentWithSiteFooter { ArticleListView() } }.scrollIndicators(.hidden)
        case .article(let id):
            ScrollView { pageContentWithSiteFooter { ArticleDetailView(articleID: id) } }.scrollIndicators(.hidden)
        case .publishArticle:
            ScrollView { pageContentWithSiteFooter { PublishArticleView() } }.scrollIndicators(.hidden)
        case .account(let area):
            ScrollView { pageContentWithSiteFooter { AccountView(area: area) } }.scrollIndicators(.hidden)
        case .login, .register, .authenticationReturn, .resetPassword:
            ScrollView { pageContentWithSiteFooter { AccountAuthView() } }.scrollIndicators(.hidden)
        case .upload:
            ScrollView { pageContentWithSiteFooter { PublicUploadDisabledView() } }.scrollIndicators(.hidden)
        case .document(let page):
            ScrollView { pageContentWithSiteFooter { DocumentPageView(page: page) } }.scrollIndicators(.hidden)
        case .motion:
            ScrollView { pageContentWithSiteFooter { MotionExperienceView() } }.scrollIndicators(.hidden)
        case .showcase:
            ScrollView { pageContentWithSiteFooter { ShowcasePageView() } }.scrollIndicators(.hidden)
        }
    }

    private func pageContentWithSiteFooter<Content: View>(
        bottomPadding: CGFloat = 40,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, pageContentHorizontalPadding)
                .padding(.top, model.isScoreFocused && isPracticeRoute ? 0 : basePageTopPadding)
                .padding(.bottom, bottomPadding)
                .frame(maxWidth: model.isScoreFocused && isPracticeRoute ? .infinity : pageContentMaxWidth)
                .frame(maxWidth: .infinity, alignment: .top)
            if !model.isScoreFocused {
                MIMISiteFooter()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RouteScrollPositionTracker(model: model))
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
        HStack(spacing: 24) {
            Button { model.navigate(.home) } label: {
                HStack(spacing: 9) {
                    Text("M")
                        .font(MIMITheme.displayFont(size: 13, weight: .semibold))
                        .foregroundStyle(MIMITheme.paper)
                        .frame(width: 32, height: 32)
                        .background(MIMITheme.ink, in: Circle())
                    Text("MIMI Guitar")
                        .font(MIMITheme.proseFont(size: 18, weight: .bold))
                        .tracking(-0.4)
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
                        .font(MIMITheme.proseFont(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MIMITheme.navigationBorder, lineWidth: 1))
                }
                .font(MIMITheme.bodyFont(size: 12, weight: .medium))
                .foregroundStyle(MIMITheme.navigationMuted)
                .padding(.horizontal, 12)
                .frame(minWidth: 176, idealWidth: 208, maxWidth: 208, minHeight: 44)
                .background(MIMITheme.navigationSearch.opacity(0.8), in: Capsule())
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
                    .font(MIMITheme.proseFont(size: 13, weight: .bold))
                    .foregroundStyle(MIMITheme.navigationBrown)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .frame(minHeight: 32)
                    .background(MIMITheme.navigationSegment.opacity(0.8), in: Capsule())
                    .overlay(Capsule().stroke(MIMITheme.navigationBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(MIMITheme.navigationPaper.opacity(0.9))
            }
        }
        .overlay(Capsule().stroke(MIMITheme.navigationOutline, lineWidth: 1))
        .shadow(color: Color(hex: 0x503C1E).opacity(0.06), radius: 12, x: 0, y: 4)
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
        HStack(spacing: 4) {
            ForEach(links, id: \.0) { label, route in
                Button { model.navigate(route) } label: {
                    HStack(spacing: 5) {
                        if label == "制谱工坊 PRO" {
                            Text("制谱工坊")
                            Text("PRO")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(isActive(route) ? MIMITheme.warmGold : MIMITheme.warmGold.opacity(0.18), in: Capsule())
                        } else {
                            Text(label)
                        }
                    }
                    .font(MIMITheme.proseFont(size: 12, weight: navigationFontWeight(label, route: route)))
                    .foregroundStyle(isActive(route) ? Color(hex: 0xFBFAF7) : MIMITheme.navigationBrown)
                    .padding(.horizontal, ["我的练习", "我的谱", "备份"].contains(label) ? 10 : 16)
                    .frame(minHeight: 44)
                    .background {
                        if isActive(route) {
                            if motionPolicy.allowsSpatialMotion {
                                Capsule()
                                    .fill(MIMITheme.navigationInk)
                                    .matchedGeometryEffect(id: "selected-navigation-route", in: selectionNamespace)
                            } else {
                                Capsule()
                                    .fill(MIMITheme.navigationInk)
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
        .background(MIMITheme.navigationSegment.opacity(0.75), in: Capsule())
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
                .font(MIMITheme.proseFont(size: 12, weight: .semibold))
                .foregroundStyle(MIMITheme.navigationInk)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
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
    private var motionPolicy: MIMIMotionPolicy {
        .resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }
    private var shouldShow: Bool {
        guard playback.isActive, let activeItem = controller.activeItem, !model.isScoreFocused else { return false }
        if case .score(let routeID) = model.route, routeID == activeItem.id { return false }
        return true
    }

    init(controller: NativeAuditionController) {
        self.controller = controller
        _auditionState = StateObject(wrappedValue: AuditionItemViewState(controller: controller))
    }

    var body: some View {
        Group {
            if shouldShow, let item = controller.activeItem {
                HStack(spacing: 12) {
                    Button { model.navigate(.score(id: item.id)); model.openCatalogItem(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(playback.activeItemTitle).font(MIMITheme.bodyFont(size: 13, weight: .semibold)).lineLimit(1)
                            Text(playback.activeItemArtist).font(.system(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                        }
                        .frame(maxWidth: 170, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    if playback.isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: playback.isPlaying ? "waveform" : "music.note").foregroundStyle(MIMITheme.darkGold) }
                    Text(playback.statusMessage)
                        .font(.system(size: 11)).foregroundStyle(MIMITheme.mutedInk).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { controller.toggle(item: item) } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 34, height: 34)
                            .foregroundStyle(.white)
                            .background(MIMITheme.ink, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Button { controller.pause() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MIMITheme.mutedInk).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("停止试听")
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .frame(width: 470, height: 58)
                .mimiCard(radius: 18, fill: MIMITheme.paperWhite, shadowOpacity: 0.12)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
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
