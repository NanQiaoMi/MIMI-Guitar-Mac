import AppKit
import Combine
import Foundation
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable, Hashable {
    case allScores, guitar, ukulele, bass, favorites, queue, recent, imported, projects

    var id: String { rawValue }
    var title: String {
        switch self {
        case .allScores: return "全部曲谱"
        case .guitar: return "吉他"
        case .ukulele: return "尤克里里"
        case .bass: return "贝斯"
        case .favorites: return "收藏"
        case .queue: return "待练"
        case .recent: return "最近打开"
        case .imported: return "个人导入"
        case .projects: return "工坊工程"
        }
    }
    var symbol: String {
        switch self {
        case .allScores: return "music.note.list"
        case .guitar: return "guitars"
        case .ukulele: return "music.note"
        case .bass: return "waveform"
        case .favorites: return "heart"
        case .queue: return "text.badge.plus"
        case .recent: return "clock.arrow.circlepath"
        case .imported: return "square.and.arrow.down"
        case .projects: return "square.grid.3x3.square"
        }
    }
}

enum RankingPeriod: String, CaseIterable, Identifiable {
    case today, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "今日热门"
        case .week: return "本周飙升"
        case .month: return "本月总榜"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent, title, updated
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "最近更新"
        case .title: return "曲名"
        case .updated: return "最近打开"
        }
    }
}

private struct RouteHistoryState {
    let route: NativeRoute
    let selectedSection: LibrarySection
    let selectedLibrarySection: LibrarySection
    let searchText: String
    let searchField: CatalogSearchField
    let sort: CatalogSort
    let catalogPage: Int
    let difficulty: Int?
    let style: Int?
    let key: String?
    let tuning: String?
    let sheetForm: Int?
    let articleSearch: String
    let articleSort: CatalogArticleSort
    let articlePage: Int
    let scrollOffset: CGFloat
}

struct RouteScrollRestore: Equatable {
    let generation: Int
    let offset: CGFloat
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var contentRoot: URL?
    @Published private(set) var userDataDirectory: URL?
    @Published private(set) var catalogCount = 0
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var totalMatches = 0
    @Published private(set) var homeFeatured: [CatalogItem] = []
    @Published private(set) var homeCurated: [CatalogItem] = []
    @Published private(set) var homeMasterpieces: [CatalogItem] = []
    @Published private(set) var relatedItems: [CatalogItem] = []
    @Published private(set) var homeRankings: [CatalogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingHome = false
    @Published private(set) var isImporting = false
    @Published private(set) var bootstrapMessage: String?
    @Published private(set) var loadMessage: String?
    @Published private(set) var personalSnapshot = PersonalData()
    @Published private(set) var personalState = PersonalState()
    @Published private(set) var selectedItem: CatalogItem?
    @Published private(set) var selectedPersonalScore: PersonalScore?
    @Published private(set) var selectedImportedFileURL: URL?
    @Published private(set) var selectedImportedOriginalFileName: String?
    @Published private(set) var articles: [CatalogArticle] = []
    @Published private(set) var searchArticles: [CatalogArticle] = []
    @Published private(set) var articleTotal = 0
    @Published var articlePage = 1
    @Published private(set) var selectedArticle: CatalogArticle?
    @Published private(set) var articleListIsLoading = false
    @Published private(set) var articleListMessage: String?
    @Published private(set) var articleDetailIsLoading = false
    @Published private(set) var articleDetailMessage: String?
    @Published private(set) var remoteUser: RemoteUser?
    @Published private(set) var studioCloneSource: CatalogItem?
    @Published private(set) var studioClonePersonalScore: PersonalScore?
    @Published private(set) var studioProjectToOpen: StudioProject?
    @Published private(set) var studioLoadIsLoading = false
    @Published private(set) var studioLoadMessage: String?
    @Published private(set) var pendingStudioImportURL: URL?
    @Published private(set) var remoteFavorites: [RemoteFavorite] = []
    @Published private(set) var accountBusy = false
    @Published private(set) var articleBusy = false
    @Published private(set) var accountMessage: String?
    @Published private(set) var accountMessageIsError = false
    @Published private(set) var isShowingAlert = false
    @Published private(set) var alertTitle = ""
    @Published private(set) var alertMessage = ""
    @Published var route: NativeRoute = .home {
        willSet {
            if newValue != route { routeWillChangeHandler?() }
        }
        didSet {
            guard oldValue != route else { return }
            currentRouteScrollOffset = 0
            requestedRouteScrollRestore = nil
            if !routeSupportsScoreFocus(route), isScoreFocused { exitScoreFullscreen() }
        }
    }
    @Published var isScoreFocused = false
    @Published private(set) var isWindowFullScreen = false
    @Published private(set) var requestedRouteScrollRestore: RouteScrollRestore?
    @Published var selectedItemID: String?
    @Published var selectedSection: LibrarySection = .allScores
    @Published var searchText = ""
    @Published var searchField: CatalogSearchField = .all
    @Published var sort: CatalogSort = .popular
    @Published var catalogPage = 1
    @Published var difficultyFilter: Int?
    @Published var styleFilter: Int?
    @Published var keyFilter: String?
    @Published var tuningFilter: String?
    @Published var sheetFormFilter: Int?
    @Published var rankingPeriod: RankingPeriod = .today
    @Published var heroIndex = 0
    @Published var librarySort: LibrarySort = .recent
    @Published var librarySearch = ""
    @Published var selectedLibrarySection: LibrarySection = .queue
    @Published var requestedLibraryScrollSection: LibrarySection? = nil
    @Published var showArchivedPracticeQueueOnLibrary = false
    @Published var selectedImportCategory = "guitar"
    @Published var articleSearch = ""
    @Published var articleSort: CatalogArticleSort = .newest
    @Published var accountArea: AccountArea = .favorites
    @Published var isCommandPalettePresented = false
    @Published var commandQuery = ""
    @Published var commandDomain: SearchDomain = .all
    @Published private(set) var commandItems: [CatalogItem] = []
    @Published private(set) var commandArticles: [CatalogArticle] = []
    @Published private(set) var commandIsLoading = false
    @Published private(set) var commandError: String?
    @Published private(set) var recentSearches: [String] = []
    @Published var authAccount = ""
    @Published var authPassword = ""
    @Published var authNickname = ""
    @Published var resetPhone = ""
    @Published var resetCode = ""
    @Published var resetPasswordValue = ""
    @Published var articleTitle = ""
    @Published var articleCategory = "技巧"
    @Published var articleContent = ""
    @Published var accountServiceAddress: String

    /// One controller owns homepage audio audition. Player adds its single hidden host once in the main window.
    let auditionController = NativeAuditionController()

    private let pageSize = 90
    private let masterpieceIDs = ["1sdc49P3eKm", "1sdiivPR3YW", "1sdjKw3nhA0", "1yDFAg9Z3mU", "1sdikNKaVJg", "1sdixfUd4Vc", "20oEfH3di0w", "1sdcWsfNEe0", "1yDFB6u7GnQ"]
    private var catalogStore: CatalogStore?
    private var personalStoreValue: PersonalStore?
    private var accountClient: AccountAPIClient?
    private var didStartBootstrap = false
    private var queryGeneration = 0
    private var homeGeneration = 0
    private var articleGeneration = 0
    private var articleDetailGeneration = 0
    private var scoreLoadGeneration = 0
    private var studioLoadGeneration = 0
    private var accountGeneration = 0
    private var commandGeneration = 0
    private var publicationCache: PublishedArticleCache?
    private var publishedArticles: [CatalogArticle] = []
    private var didReportPublicationCacheError = false
    private var pendingSearch: Task<Void, Never>?
    private var routeHistory: [RouteHistoryState] = []
    private var authenticationReturnDestination: String?
    private weak var mainWindow: NSWindow?
    private var windowWasFullScreenBeforeScoreFocus: Bool?
    private var windowFullScreenTransition: Bool?
    private var requestedWindowFullScreen: Bool?
    private var fullScreenRequestGeneration = 0
    private var scoreFocusRouteScrollState: (route: NativeRoute, offset: CGFloat)?
    private var routeWillChangeHandler: (() -> Void)?
    private var currentRouteScrollOffset: CGFloat = 0
    private var routeScrollRestoreGeneration = 0

    var personalStore: PersonalStore? { personalStoreValue }
    var catalogPageCount: Int { max(1, Int(ceil(Double(totalMatches) / Double(pageSize)))) }
    var hasMoreResults: Bool { catalogPage < catalogPageCount }
    var articlePageCount: Int { max(1, Int(ceil(Double(articleTotal) / 9))) }
    var canLoadMore: Bool { hasMoreResults && !isLoading }
    var isCatalogRoute: Bool {
        switch route {
        case .catalog, .catalogQuery, .search: return true
        default: return false
        }
    }
    var catalogHeading: String {
        switch route {
        case .catalog(let category): return category.title
        case .catalogQuery(let category, _): return category.title
        case .search: return "搜索结果"
        default: return "曲库"
        }
    }
    var personalScores: [PersonalScore] { personalSnapshot.scores }
    var favoriteIDs: Set<String> { Set(personalSnapshot.favorites) }
    var practiceItems: [PracticeItem] { personalSnapshot.practiceItems.sorted { $0.order < $1.order } }
    var recentEntries: [PersonalHistoryEntry] { personalSnapshot.history.sorted { $0.time > $1.time } }
    var hasAccountSession: Bool { remoteUser != nil }

    init() {
        accountServiceAddress = UserDefaults.standard.string(forKey: "mimi.account.serviceAddress") ?? AccountAPIClient.defaultBaseURL
#if !MIMI_RUNTIME_DIAGNOSTICS
        accountClient = try? AccountAPIClient(baseURLText: accountServiceAddress)
#endif
        recentSearches = UserDefaults.standard.stringArray(forKey: "mimi.native.recentSearches") ?? []
    }

    func bootstrap() {
        guard !didStartBootstrap else { return }
        didStartBootstrap = true
        bootstrapMessage = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                guard let root = AppPaths.contentRoot() else {
                    await self?.finishBootstrap(error: "未找到应用曲谱资源。开发运行时请设置 MIMI_CONTENT_ROOT，或打开已打包的应用。")
                    return
                }
                let catalog = try CatalogStore(databaseURL: AppPaths.catalogURL(contentRoot: root))
                let directory = try AppPaths.userDataDirectory()
                let personal = try PersonalStore(directory: directory)
                let count = try await catalog.count()
                let snapshot = try await personal.snapshot()
                await self?.finishBootstrap(contentRoot: root, dataDirectory: directory, catalog: catalog, personal: personal, count: count, snapshot: snapshot)
            } catch {
                await self?.finishBootstrap(error: error.localizedDescription)
            }
        }
    }

    func retryBootstrap() {
        didStartBootstrap = false
        bootstrap()
    }

#if MIMI_RUNTIME_DIAGNOSTICS
    func bootstrapRuntimeDiagnostics(contentRoot: URL, directory: URL) async throws {
        didStartBootstrap = true
        let catalog = try CatalogStore(databaseURL: AppPaths.catalogURL(contentRoot: contentRoot))
        let personal = try PersonalStore(directory: directory)
        let count = try await catalog.count()
        let snapshot = try await personal.snapshot()
        finishBootstrap(contentRoot: contentRoot, dataDirectory: directory, catalog: catalog, personal: personal, count: count, snapshot: snapshot)
    }
#endif

    private func finishBootstrap(contentRoot: URL, dataDirectory: URL, catalog: CatalogStore, personal: PersonalStore, count: Int, snapshot: PersonalData) {
        self.contentRoot = contentRoot
        userDataDirectory = dataDirectory
        publicationCache = PublishedArticleCache(directory: dataDirectory)
        catalogStore = catalog
        personalStoreValue = personal
        catalogCount = count
        apply(snapshot)
        bootstrapMessage = nil
        activate(route)
    }

    private func finishBootstrap(error: String) {
        bootstrapMessage = error
        isLoading = false
        isLoadingHome = false
        articleListIsLoading = false
        articleDetailIsLoading = false
        articleListMessage = error
        articleDetailMessage = error
        studioLoadIsLoading = false
        studioLoadMessage = error
    }

    private func apply(_ snapshot: PersonalData) {
        guard snapshot.revision >= personalSnapshot.revision else { return }
        personalSnapshot = snapshot.currentSchema
        var state = PersonalState()
        state.favoriteIDs = Set(snapshot.favorites.map { rawCatalogID($0) })
        state.queueIDs = snapshot.practiceItems.filter { $0.status != .archived }.sorted { $0.order < $1.order }.map { rawCatalogID($0.scoreId) }
        state.recentIDs = snapshot.history.sorted { $0.time > $1.time }.map(\.id)
        personalState = state
    }

    func refreshPersonalData() {
        guard let personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do { self?.apply(try await personalStoreValue.snapshot()) }
            catch { self?.presentAlert(title: "无法读取个人资料", message: error.localizedDescription) }
        }
    }

    func personalDataDidChange() { refreshPersonalData() }

    func navigate(_ next: NativeRoute) {
        let next = normalizedPracticeRoute(next)
        pushCurrentRouteState()
        if case .authenticationReturn = next {
            setRoute(next)
        } else if next == .login || next == .register, let destination = authenticationReturnDestination {
            setRoute(.authenticationReturn(destination: destination, isRegistration: next == .register))
        } else {
            setRoute(next)
        }
    }

    private func rawCatalogID(_ id: String) -> String {
        id.hasPrefix("catalog:") ? String(id.dropFirst("catalog:".count)) : id
    }

    private func normalizedPracticeRoute(_ next: NativeRoute) -> NativeRoute {
        guard case .practice(let requestedID) = next, let requestedID else { return next }
        if let score = personalSnapshot.scores.first(where: { $0.id == requestedID || ($0.source == "catalog" && $0.sourceId == rawCatalogID(requestedID)) }) {
            return .practice(scoreID: score.id)
        }
        if selectedItem?.id == requestedID { return .practice(scoreID: "catalog:\(requestedID)") }
        return next
    }

    var canNavigateBack: Bool { !routeHistory.isEmpty }

    var canToggleScoreFullscreen: Bool { routeSupportsScoreFocus(route) }

    func setRouteTransitionCaptureHandler(_ handler: (() -> Void)?) {
        routeWillChangeHandler = handler
    }

    func attachMainWindow(_ window: NSWindow) {
        mainWindow = window
        isWindowFullScreen = window.styleMask.contains(.fullScreen)
        reconcileWindowFullScreenRequest()
    }

    func windowFullScreenWillChange(_ isEntering: Bool) {
        windowFullScreenTransition = isEntering
    }

    func windowFullScreenDidChange(_ isFullScreen: Bool) {
        windowFullScreenTransition = nil
        isWindowFullScreen = isFullScreen
        if !isFullScreen, isScoreFocused, requestedWindowFullScreen != true {
            isScoreFocused = false
            windowWasFullScreenBeforeScoreFocus = nil
            restoreScrollAfterScoreFocus()
        }
        reconcileWindowFullScreenRequest()
    }

    func toggleScoreFullscreen() {
        guard canToggleScoreFullscreen else { return }
        if isScoreFocused {
            exitScoreFullscreen()
            return
        }
        let alreadyFullScreen = requestedWindowFullScreen
            ?? windowFullScreenTransition
            ?? mainWindow?.styleMask.contains(.fullScreen)
            ?? isWindowFullScreen
        windowWasFullScreenBeforeScoreFocus = alreadyFullScreen
        scoreFocusRouteScrollState = (route, currentRouteScrollOffset)
        isScoreFocused = true
        requestWindowFullScreen(true)
    }

    func exitScoreFullscreen() {
        guard isScoreFocused else { return }
        isScoreFocused = false
        let wasFullScreenBeforeFocus = windowWasFullScreenBeforeScoreFocus ?? false
        windowWasFullScreenBeforeScoreFocus = nil
        restoreScrollAfterScoreFocus()
        if !wasFullScreenBeforeFocus { requestWindowFullScreen(false) }
    }

    func handleScoreFocusEscape() {
        guard isScoreFocused, !isCommandPalettePresented, !isShowingAlert else { return }
        guard mainWindow?.attachedSheet == nil, NSApplication.shared.modalWindow == nil else { return }
        exitScoreFullscreen()
    }

    private func requestWindowFullScreen(_ isFullScreen: Bool) {
        requestedWindowFullScreen = isFullScreen
        reconcileWindowFullScreenRequest()
    }

    private func restoreScrollAfterScoreFocus() {
        guard let saved = scoreFocusRouteScrollState else { return }
        scoreFocusRouteScrollState = nil
        guard saved.route == route else { return }
        routeScrollRestoreGeneration += 1
        requestedRouteScrollRestore = RouteScrollRestore(
            generation: routeScrollRestoreGeneration, offset: saved.offset
        )
    }

    private func reconcileWindowFullScreenRequest() {
        guard let desired = requestedWindowFullScreen, let window = mainWindow,
              windowFullScreenTransition == nil else { return }
        let actual = window.styleMask.contains(.fullScreen)
        guard actual != desired else {
            requestedWindowFullScreen = nil
            return
        }
        windowFullScreenTransition = desired
        fullScreenRequestGeneration += 1
        let generation = fullScreenRequestGeneration
        window.toggleFullScreen(nil)
        // AppKit delivers didEnter/didExit after its Space animation. Keep an
        // opposite request queued until that callback instead of toggling twice.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak window] in
            guard let self, let window, self.fullScreenRequestGeneration == generation,
                  self.windowFullScreenTransition != nil else { return }
            self.windowFullScreenTransition = nil
            self.requestedWindowFullScreen = nil
            self.isWindowFullScreen = window.styleMask.contains(.fullScreen)
            if !self.isWindowFullScreen {
                self.isScoreFocused = false
                self.windowWasFullScreenBeforeScoreFocus = nil
                self.restoreScrollAfterScoreFocus()
            }
        }
    }

    func updateCurrentRouteScrollOffset(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        currentRouteScrollOffset = max(0, offset)
    }

    func updateCurrentRouteScrollOffset(_ offset: CGFloat, for trackedRoute: NativeRoute) {
        guard route == trackedRoute else { return }
        updateCurrentRouteScrollOffset(offset)
    }

    func acknowledgeRouteScrollRestore(_ generation: Int) {
        guard requestedRouteScrollRestore?.generation == generation else { return }
        requestedRouteScrollRestore = nil
    }

    private func routeSupportsScoreFocus(_ route: NativeRoute) -> Bool {
        switch route {
        case .score, .practice: return true
        default: return false
        }
    }

    func navigateBack() {
        guard let previous = routeHistory.popLast() else { return }
        setRoute(previous.route, restoring: previous)
    }

    private func pushCurrentRouteState() {
        routeHistory.append(RouteHistoryState(
            route: route, selectedSection: selectedSection, selectedLibrarySection: selectedLibrarySection, searchText: searchText, searchField: searchField,
            sort: sort, catalogPage: catalogPage, difficulty: difficultyFilter, style: styleFilter,
            key: keyFilter, tuning: tuningFilter, sheetForm: sheetFormFilter,
            articleSearch: articleSearch, articleSort: articleSort, articlePage: articlePage,
            scrollOffset: currentRouteScrollOffset
        ))
        if routeHistory.count > 60 { routeHistory.removeFirst(routeHistory.count - 60) }
    }

    private func invalidatePageLoads() {
        pendingSearch?.cancel()
        queryGeneration += 1
        articleGeneration += 1
        articleDetailGeneration += 1
        scoreLoadGeneration += 1
        studioLoadGeneration += 1
        isLoading = false
        articleListIsLoading = false
        articleDetailIsLoading = false
        studioLoadIsLoading = false
    }

    private func setRoute(_ next: NativeRoute, restoring previous: RouteHistoryState? = nil) {
        invalidatePageLoads()
        route = next
        if let previous {
            routeScrollRestoreGeneration += 1
            requestedRouteScrollRestore = RouteScrollRestore(generation: routeScrollRestoreGeneration, offset: previous.scrollOffset)
        } else {
            requestedRouteScrollRestore = nil
        }
        if case .studioClone = next {} else { studioCloneSource = nil }
        if case .studioScore = next {} else { studioClonePersonalScore = nil }
        if case .studioProject = next {} else { studioProjectToOpen = nil }
        selectedItemID = nil
        selectedItem = nil
        selectedPersonalScore = nil
        selectedImportedFileURL = nil
        selectedImportedOriginalFileName = nil
        loadMessage = nil
        studioLoadMessage = nil
        if case .catalog(let category) = next {
            searchText = ""
            searchField = .all
            difficultyFilter = nil; styleFilter = nil; keyFilter = nil; tuningFilter = nil; sheetFormFilter = nil
            catalogPage = 1
            sort = .popular
            switch category {
            case .all: selectedSection = .allScores
            case .guitar: selectedSection = .guitar
            case .ukulele: selectedSection = .ukulele
            case .bass: selectedSection = .bass
            }
        } else if case .catalogQuery(let category, let query) = next {
            selectedSection = section(for: category)
            searchText = query.value(["searchValue", "keyword"]) ?? ""
            searchField = query.value(["field"]).flatMap(CatalogSearchField.init(rawValue:)) ?? .all
            sort = catalogSort(query.value(["sort"]))
            difficultyFilter = query.value(["difficulty"]).flatMap(Int.init).flatMap { (1...5).contains($0) ? $0 : nil }
            styleFilter = query.value(["style"]).flatMap(Int.init).flatMap { [101, 102, 103, 105, 107, 109].contains($0) ? $0 : nil }
            keyFilter = query.value(["key"]).flatMap { ["C", "C#", "D", "Db", "E", "Eb", "F", "F#", "G", "G#", "A", "Ab", "B", "Bb"].contains($0) ? $0 : nil }
            tuningFilter = query.value(["tuning"]).flatMap { ["Standard", "Half-Step Down", "Drop D", "Open G", "DADGAD", "Open D"].contains($0) ? $0 : nil }
            sheetFormFilter = query.value(["sheetForm"]).flatMap(Int.init).flatMap { [1, 2, 3, 4, 7].contains($0) ? $0 : nil }
            catalogPage = safePage(query.value(["no", "page"]).flatMap(Int.init) ?? 1, size: pageSize)
        } else if case .search(let query, let domain) = next {
            searchText = query
            searchField = .all
            difficultyFilter = nil; styleFilter = nil; keyFilter = nil; tuningFilter = nil; sheetFormFilter = nil
            catalogPage = 1
            sort = .popular
            articlePage = 1
            if domain == .article { articleSort = .popular }
            switch domain {
            case .all: selectedSection = .allScores
            case .guitar: selectedSection = .guitar
            case .ukulele: selectedSection = .ukulele
            case .article: break
            }
        } else if case .articles = next {
            articleSearch = ""
            articlePage = 1
            articleSort = .newest
        } else if case .authenticationReturn(let destination, _) = next {
            authenticationReturnDestination = destination
        }
        if let previous {
            selectedSection = previous.selectedSection
            selectedLibrarySection = previous.selectedLibrarySection
            searchText = previous.searchText
            searchField = previous.searchField
            sort = previous.sort
            catalogPage = previous.catalogPage
            difficultyFilter = previous.difficulty
            styleFilter = previous.style
            keyFilter = previous.key
            tuningFilter = previous.tuning
            sheetFormFilter = previous.sheetForm
            articleSearch = previous.articleSearch
            articleSort = previous.articleSort
            articlePage = previous.articlePage
        }
        activate(next)
    }

    private func safePage(_ requested: Int, size: Int) -> Int {
        min(max(1, requested), Int.max / max(1, size))
    }

    private func section(for category: CatalogCategory) -> LibrarySection {
        switch category {
        case .all: return .allScores
        case .guitar: return .guitar
        case .ukulele: return .ukulele
        case .bass: return .bass
        }
    }

    private func catalogSort(_ raw: String?) -> CatalogSort {
        switch Int(raw ?? "") {
        case 0: return .newest
        case 2: return .difficulty
        default: return .popular
        }
    }

    /// Resolves a website-style route and applies supported query filters and page state.
    func openURL(_ url: URL) {
        guard let next = NativeRoute.resolve(url) else { return }
        navigate(next)
        applyURLParameters(url, route: next)
    }

    private func applyURLParameters(_ url: URL, route next: NativeRoute) {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ names: [String]) -> String? {
            for name in names {
                if let match = values.first(where: { $0.name == name })?.value, !match.isEmpty { return match }
            }
            return nil
        }
        if case .articles = next {
            articleSearch = value(["searchValue", "keyword", "q"]) ?? ""
            articleSort = value(["sort"]) == "hot" ? .popular : .newest
            articlePage = safePage(value(["page", "no"]).flatMap(Int.init) ?? 1, size: 9)
            loadArticles(immediately: true)
            return
        }
        guard isCatalogRoute else { return }
        if let raw = value(["difficulty"]), let number = Int(raw), (1...5).contains(number) { difficultyFilter = number }
        if let raw = value(["style"]), let number = Int(raw), [101, 102, 103, 105, 107, 109].contains(number) { styleFilter = number }
        if let raw = value(["sheetForm"]), let number = Int(raw), [1, 2, 3, 4, 7].contains(number) { sheetFormFilter = number }
        if let raw = value(["key"]), ["C", "C#", "D", "Db", "E", "Eb", "F", "F#", "G", "G#", "A", "Ab", "B", "Bb"].contains(raw) { keyFilter = raw }
        if let raw = value(["tuning"]), ["Standard", "Half-Step Down", "Drop D", "Open G", "DADGAD", "Open D"].contains(raw) { tuningFilter = raw }
        if let raw = value(["field"]), let field = CatalogSearchField(rawValue: raw) { searchField = field }
        if let raw = value(["sort"]), let number = Int(raw) {
            if case .search(_, .article) = next { articleSort = number == 1 ? .popular : .newest }
            else { sort = number == 0 ? .newest : (number == 2 ? .difficulty : .popular) }
        }
        if case .catalog = next { searchText = value(["searchValue", "keyword"]) ?? "" }
        if case .search = next { searchText = value(["searchValue", "keyword", "q"]) ?? searchText }
        if let raw = value(["no", "page"]), let number = Int(raw), number > 0 {
            if case .search(_, .article) = next { articlePage = safePage(number, size: 9) }
            else { catalogPage = safePage(number, size: pageSize) }
        }
        if isCatalogRoute { scheduleSearch(immediately: true) }
    }

    private func activate(_ next: NativeRoute) {
        guard catalogStore != nil else { return }
        switch next {
        case .home: loadHome()
        case .catalog, .catalogQuery: scheduleSearch(immediately: true)
        case .search(_, let domain):
            scheduleSearch(immediately: true)
            if domain == .article { searchArticles = [] }
        case .articles: loadArticles(immediately: true)
        case .article(let id): loadArticle(id: id)
        case .practice, .library, .dataSettings: refreshPersonalData()
        case .studioClone(let sourceID): loadStudioCloneSource(id: sourceID)
        case .studioScore(let scoreID): loadStudioClonePersonalScore(id: scoreID)
        case .studioProject(let id): loadStudioProject(id: id)
        case .account(let area): accountArea = area; loadAccount(area: area)
        case .login, .register, .resetPassword, .authenticationReturn: accountMessage = nil
        case .publishArticle: loadAccount(area: .profile)
        case .score(let id): loadScore(id: id)
        default: break
        }
    }

    private func loadStudioCloneSource(id: String) {
        studioCloneSource = nil
        studioLoadGeneration += 1
        let generation = studioLoadGeneration
        studioLoadMessage = nil
        studioLoadIsLoading = true
        guard let catalogStore else {
            if let bootstrapMessage { studioLoadMessage = bootstrapMessage; studioLoadIsLoading = false }
            return
        }
        Task { @MainActor [weak self] in
            defer { if self?.studioLoadGeneration == generation { self?.studioLoadIsLoading = false } }
            do {
                let item = try await catalogStore.item(id: id)
                guard let self, self.studioLoadGeneration == generation, self.route == .studioClone(sourceID: id) else { return }
                guard let item else { self.studioLoadMessage = "本地曲库中找不到这份曲谱。"; return }
                self.studioCloneSource = item
            } catch {
                guard let self, self.studioLoadGeneration == generation, self.route == .studioClone(sourceID: id) else { return }
                self.studioLoadMessage = error.localizedDescription
            }
        }
    }

    private func loadStudioClonePersonalScore(id: String) {
        studioClonePersonalScore = nil
        studioLoadGeneration += 1
        let generation = studioLoadGeneration
        studioLoadMessage = nil
        if let score = personalSnapshot.scores.first(where: { $0.id == id }) {
            studioClonePersonalScore = score
            studioLoadIsLoading = false
            return
        }
        studioLoadIsLoading = true
        guard let personalStoreValue else {
            if let bootstrapMessage { studioLoadMessage = bootstrapMessage; studioLoadIsLoading = false }
            return
        }
        Task { @MainActor [weak self] in
            defer { if self?.studioLoadGeneration == generation { self?.studioLoadIsLoading = false } }
            do {
                let snapshot = try await personalStoreValue.snapshot()
                guard let self, self.studioLoadGeneration == generation, self.route == .studioScore(id: id) else { return }
                self.apply(snapshot)
                guard let score = snapshot.scores.first(where: { $0.id == id }) else {
                    self.studioLoadMessage = "本机个人资料中找不到这份曲谱。"
                    return
                }
                self.studioClonePersonalScore = score
            } catch {
                guard let self, self.studioLoadGeneration == generation, self.route == .studioScore(id: id) else { return }
                self.studioLoadMessage = error.localizedDescription
            }
        }
    }

    private func loadStudioProject(id: String) {
        studioProjectToOpen = nil
        guard case .studioProject(let activeID) = route, activeID == id else { return }
        studioLoadGeneration += 1
        let generation = studioLoadGeneration
        studioLoadMessage = nil
        if let project = personalSnapshot.projects.first(where: { $0.id == id }) {
            studioProjectToOpen = project
            studioLoadIsLoading = false
            return
        }
        studioLoadIsLoading = true
        guard let personalStoreValue else {
            if let bootstrapMessage { studioLoadMessage = bootstrapMessage; studioLoadIsLoading = false }
            return
        }
        Task { @MainActor [weak self] in
            defer { if self?.studioLoadGeneration == generation { self?.studioLoadIsLoading = false } }
            do {
                let snapshot = try await personalStoreValue.snapshot()
                guard let self, self.studioLoadGeneration == generation, self.route == .studioProject(id: id) else { return }
                self.apply(snapshot)
                guard let project = snapshot.projects.first(where: { $0.id == id }) else {
                    self.studioLoadMessage = "本机资料中找不到编号为 \(id) 的工程。"
                    return
                }
                self.studioProjectToOpen = project
            } catch {
                guard let self, self.studioLoadGeneration == generation, self.route == .studioProject(id: id) else { return }
                self.studioLoadMessage = error.localizedDescription
            }
        }
    }

    func retryStudioRoute() { activate(route) }

    func selectSection(_ section: LibrarySection) {
        pushCurrentRouteState()
        invalidatePageLoads()
        selectedLibrarySection = section
        requestedLibraryScrollSection = section
        route = .library
        librarySearch = ""
        refreshPersonalData()
    }

    func showArchivedPracticeQueue() {
        showArchivedPracticeQueueOnLibrary = true
        selectSection(.queue)
    }

    func selectCatalogCategory(_ category: CatalogCategory) {
        pushCurrentRouteState()
        invalidatePageLoads()
        route = .catalog(category)
        catalogPage = 1
        switch category {
        case .all: selectedSection = .allScores
        case .guitar: selectedSection = .guitar
        case .ukulele: selectedSection = .ukulele
        case .bass: selectedSection = .bass
        }
        scheduleSearch(immediately: true)
    }

    func updateSearch() { catalogPage = 1; scheduleSearch(immediately: false) }
    func searchDidChange() { updateSearch() }
    func sortDidChange() { catalogPage = 1; scheduleSearch(immediately: true) }
    func filterDidChange() { catalogPage = 1; scheduleSearch(immediately: true) }
    func setCatalogPage(_ page: Int) {
        catalogPage = min(max(1, page), max(1, catalogPageCount))
        scheduleSearch(immediately: true)
    }

    private func scheduleSearch(immediately: Bool) {
        queryGeneration += 1
        let generation = queryGeneration
        pendingSearch?.cancel()
        if case .search(_, let domain) = route, domain == .article {
            if !immediately { articlePage = 1 }
            searchArticles = []
            articleListMessage = nil
            articleListIsLoading = true
        }
        pendingSearch = Task { @MainActor [weak self] in
            if !immediately {
                do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            }
            guard !Task.isCancelled, let self else { return }
            if case .search(_, .article) = self.route {
                await self.loadSearchArticles(generation: generation)
            } else {
                await self.loadFirstPage(generation: generation)
            }
        }
    }

    private func categoryFilter() -> String? {
        switch route {
        case .catalog(let category): return category.databaseValue
        case .catalogQuery(let category, _): return category.databaseValue
        case .search:
            switch selectedSection {
            case .guitar: return "guitar"
            case .ukulele: return "ukulele"
            case .bass: return "bass"
            default: return nil
            }
        default:
            switch selectedSection {
            case .guitar: return "guitar"
            case .ukulele: return "ukulele"
            case .bass: return "bass"
            default: return nil
            }
        }
    }

    private func loadFirstPage(generation: Int) async {
        items = []; totalMatches = 0; loadMessage = nil
        await fetchPage(offset: (catalogPage - 1) * pageSize, appending: false, generation: generation)
    }

    func loadNextPage() {
        guard canLoadMore else { return }
        setCatalogPage(catalogPage + 1)
    }

    private func fetchPage(offset: Int, appending: Bool, generation: Int) async {
        guard generation == queryGeneration, isCatalogRoute, let catalogStore else { return }
        if case .search(_, let domain) = route, domain == .article {
            items = []; totalMatches = 0; isLoading = false
            return
        }
        isLoading = true
        defer { if generation == queryGeneration { isLoading = false } }
        let query = CatalogQuery(
            text: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
            searchField: searchField,
            category: categoryFilter(),
            difficulty: difficultyFilter,
            style: styleFilter,
            key: keyFilter,
            tuning: tuningFilter,
            sheetForm: sheetFormFilter,
            sort: sort,
            limit: pageSize,
            offset: offset
        )
        do {
            let page = try await catalogStore.search(query)
            guard generation == queryGeneration else { return }
            items = appending ? items + page.items.filter { !Set(items.map(\.id)).contains($0.id) } : page.items
            totalMatches = page.total
            loadMessage = nil
            if catalogPage > catalogPageCount {
                catalogPage = catalogPageCount
                scheduleSearch(immediately: true)
            }
        } catch {
            guard generation == queryGeneration else { return }
            loadMessage = error.localizedDescription
        }
    }

    private func loadSearchArticles(generation: Int) async {
        guard let catalogStore else {
            articleListIsLoading = bootstrapMessage == nil
            articleListMessage = bootstrapMessage
            return
        }
        articleGeneration += 1
        let articleToken = articleGeneration
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageNumber = articlePage
        let articleOrder: CatalogArticleSort = articleSort
        defer { if queryGeneration == generation, articleGeneration == articleToken { articleListIsLoading = false } }
        do {
            let additional = await publicationArticles()
            let page = try await catalogStore.searchArticles(CatalogArticleQuery(text: query, sort: articleOrder, limit: 9, offset: (pageNumber - 1) * 9), including: additional)
            guard queryGeneration == generation, articleGeneration == articleToken, case .search(_, .article) = route else { return }
            searchArticles = page.articles
            articleTotal = page.total
            if articlePage > articlePageCount {
                articlePage = articlePageCount
                scheduleSearch(immediately: true)
            }
        } catch {
            guard queryGeneration == generation, articleGeneration == articleToken else { return }
            articleListMessage = error.localizedDescription
        }
    }

    private func loadHome() {
        guard let catalogStore else { return }
        homeGeneration += 1
        let generation = homeGeneration
        isLoadingHome = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                async let popularPage = catalogStore.search(CatalogQuery(sort: .popular, limit: 12, offset: 0))
                async let masterpiecePage = catalogStore.search(CatalogQuery(ids: self.masterpieceIDs, sort: .providedOrder, limit: 30, offset: 0))
                let (popular, masterpieces) = try await (popularPage, masterpiecePage)
                guard generation == self.homeGeneration else { return }
                self.homeFeatured = Array(popular.items.prefix(4))
                self.homeCurated = Array(popular.items.dropFirst(4).prefix(4))
                let map = Dictionary(uniqueKeysWithValues: masterpieces.items.map { ($0.id, $0) })
                self.homeMasterpieces = self.masterpieceIDs.compactMap { map[$0] }
                self.homeRankings = try await catalogStore.rankings(period: .today)
                self.isLoadingHome = false
            } catch {
                guard generation == self.homeGeneration else { return }
                self.isLoadingHome = false
                self.bootstrapMessage = error.localizedDescription
            }
        }
    }

    func loadRankings(for period: RankingPeriod) {
        rankingPeriod = period
        guard let catalogStore else { return }
        Task { @MainActor [weak self] in
            do {
                let apiPeriod: CatalogRankingPeriod
                switch period {
                case .today: apiPeriod = .today
                case .week: apiPeriod = .week
                case .month: apiPeriod = .month
                }
                let rows = try await catalogStore.rankings(period: apiPeriod)
                guard self?.rankingPeriod == period else { return }
                self?.homeRankings = rows
            } catch { self?.loadMessage = error.localizedDescription }
        }
    }

    func openCatalogItem(_ item: CatalogItem) {
        if case .score(let activeID) = route, activeID == item.id {} else { pushCurrentRouteState() }
        invalidatePageLoads()
        loadMessage = nil
        selectedItem = item
        selectedPersonalScore = personalSnapshot.scores.first { $0.source == "catalog" && $0.sourceId == item.id }
        selectedItemID = item.id
        selectedImportedFileURL = nil
        selectedImportedOriginalFileName = nil
        route = .score(id: item.id)
        loadRelatedItems(to: item)
        if let personalStoreValue {
            Task { @MainActor [weak self] in
                do {
                    try await personalStoreValue.recordRecent(item)
                    self?.apply(try await personalStoreValue.snapshot())
                } catch { self?.presentAlert(title: "无法更新最近打开", message: error.localizedDescription) }
            }
        }
    }

    private func loadRelatedItems(to item: CatalogItem) {
        relatedItems = []
        guard let catalogStore else { return }
        Task { @MainActor [weak self] in
            do {
                let page = try await catalogStore.search(CatalogQuery(category: item.category, sort: .popular, limit: 40, offset: 0))
                guard let self, case .score(let currentID) = self.route, currentID == item.id else { return }
                self.relatedItems = Array(page.items.filter { $0.id != item.id }.sorted { left, right in
                    let leftScore = (left.artist == item.artist ? 3 : 0) + (left.key == item.key ? 2 : 0) + (left.sheetForm == item.sheetForm ? 1 : 0) + (left.style == item.style ? 1 : 0)
                    let rightScore = (right.artist == item.artist ? 3 : 0) + (right.key == item.key ? 2 : 0) + (right.sheetForm == item.sheetForm ? 1 : 0) + (right.style == item.style ? 1 : 0)
                    return leftScore == rightScore ? left.heat > right.heat : leftScore > rightScore
                }.prefix(6))
            } catch {
                guard let self, case .score(let currentID) = self.route, currentID == item.id else { return }
                self.loadMessage = "相关曲谱暂时无法载入：\(error.localizedDescription)"
            }
        }
    }

    func selectCatalogItem(id: String?) {
        guard let id else { return }
        if let item = items.first(where: { $0.id == id }) { openCatalogItem(item); return }
        navigate(.score(id: id))
    }

    func loadScore(id: String) {
        scoreLoadGeneration += 1
        let generation = scoreLoadGeneration
        loadMessage = nil
        if let score = personalSnapshot.scores.first(where: { $0.id == id }) {
            selectedPersonalScore = score
            selectedItem = nil
            route = .score(id: id)
            isLoading = false
            return
        }
        guard let catalogStore else { return }
        isLoading = true
        Task { @MainActor [weak self] in
            defer {
                if let self, self.scoreLoadGeneration == generation, self.route == .score(id: id) { self.isLoading = false }
            }
            do {
                let item = try await catalogStore.item(id: id)
                guard let self, self.scoreLoadGeneration == generation, self.route == .score(id: id) else { return }
                guard let item else {
                    self.loadMessage = "找不到这份曲谱。它可能不在当前本地快照中，或已经从个人资料移除。"
                    return
                }
                self.openCatalogItem(item)
            } catch {
                guard let self, self.scoreLoadGeneration == generation, self.route == .score(id: id) else { return }
                self.loadMessage = error.localizedDescription
            }
        }
    }

    func openPersonalScore(_ score: PersonalScore) {
        if score.source == "catalog" {
            if route == .score(id: score.sourceId) { loadScore(id: score.sourceId) }
            else { navigate(.score(id: score.sourceId)) }
            return
        }
        if case .score(let activeID) = route, activeID == score.id {} else { pushCurrentRouteState() }
        invalidatePageLoads()
        selectedPersonalScore = score
        selectedItem = nil
        selectedItemID = score.id
        selectedImportedFileURL = nil
        selectedImportedOriginalFileName = nil
        route = .score(id: score.id)
        relatedItems = []
    }

    func isFavorite(_ item: CatalogItem) -> Bool { personalState.favoriteIDs.contains(item.id) }
    func isQueued(_ item: CatalogItem) -> Bool { personalState.queueIDs.contains(item.id) }

    func toggleFavorite(for item: CatalogItem) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                try await store.toggleFavorite(item)
                self?.apply(try await store.snapshot())
            } catch { self?.presentAlert(title: "无法更新收藏", message: error.localizedDescription) }
        }
    }

    func toggleQueue(for item: CatalogItem) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                try await store.toggleQueue(item)
                self?.apply(try await store.snapshot())
            } catch { self?.presentAlert(title: "无法更新待练列表", message: error.localizedDescription) }
        }
    }

    func setPracticeStatus(scoreID: String, status: PracticeStatus) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                self?.apply(try await store.setPracticeStatus(scoreID: scoreID, status: status))
            } catch { self?.presentAlert(title: "无法保存练习状态", message: error.localizedDescription) }
        }
    }

    func preparePracticeScore(_ scoreID: String) {
        guard let store = personalStoreValue else { return }
        let knownScore = personalSnapshot.scores.first { $0.id == scoreID || ($0.source == "catalog" && $0.sourceId == rawCatalogID(scoreID)) }
        let catalogID = knownScore?.source == "catalog" ? knownScore!.sourceId : rawCatalogID(scoreID)
        let capturedItem = selectedItem?.id == catalogID ? selectedItem : nil
        let catalog = catalogStore
        Task { @MainActor [weak self] in
            do {
                var metadata = capturedItem
                if knownScore == nil || knownScore?.source == "catalog" {
                    if metadata == nil { metadata = try await catalog?.item(id: catalogID) }
                }
                let snapshot = try await store.preparePracticeScore(scoreID: knownScore?.id ?? scoreID, catalogItem: metadata)
                guard let self else { return }
                self.apply(snapshot)
                let resolvedID = metadata.map { "catalog:\($0.id)" } ?? knownScore?.id ?? scoreID
                if case .practice(let requestedID) = self.route, requestedID == scoreID || requestedID == resolvedID {
                    self.route = .practice(scoreID: resolvedID)
                }
            } catch { self?.presentAlert(title: "无法继续练习", message: error.localizedDescription) }
        }
    }

    func updatePracticeNote(scoreID: String, note: String) {
        guard let store = personalStoreValue else { return }
        guard let expectedNote = personalSnapshot.practiceItems.first(where: { $0.scoreId == scoreID })?.note else {
            presentAlert(title: "无法保存练习备注", message: "待练条目已被移除，请刷新后重试。")
            return
        }
        Task { @MainActor [weak self] in
            do {
                self?.apply(try await store.updatePracticeNote(scoreID: scoreID, note: String(note.prefix(5000)), expectedNote: expectedNote))
            } catch { self?.presentAlert(title: "无法保存练习备注", message: error.localizedDescription) }
        }
    }

    func movePracticeScore(_ scoreID: String, offset: Int) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                self?.apply(try await store.movePracticeItem(scoreID: scoreID, direction: offset))
            } catch { self?.presentAlert(title: "无法调整练习顺序", message: error.localizedDescription) }
        }
    }

    func removePracticeScore(_ scoreID: String) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                var snapshot = try await store.snapshot()
                snapshot.practiceItems.removeAll { $0.scoreId == scoreID }
                self?.apply(try await store.commit(snapshot, expectedRevision: snapshot.revision))
            } catch { self?.presentAlert(title: "无法移出待练", message: error.localizedDescription) }
        }
    }

    func deletePrivateScore(_ score: PersonalScore) {
        guard score.source == "private", let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                var data = try await store.snapshot()
                data.scores.removeAll { $0.id == score.id }
                data.practiceItems.removeAll { $0.scoreId == score.id }
                data.practiceFragments.removeAll { $0.scoreId == score.id }
                data.resumes.removeAll { $0.scoreId == score.id }
                data.sessions.removeAll { $0.scoreId == score.id }
                data.favorites.removeAll { $0 == score.id }
                if self?.personalSnapshot.projects.contains(where: { $0.id == score.projectId }) == true {
                    // Keep project-linked score references intact; deleting it would orphan the project.
                    self?.presentAlert(title: "无法删除个人谱", message: "这份曲谱与工坊工程关联。请在工坊中处理工程与谱件。")
                    return
                }
                self?.apply(try await store.commit(data, expectedRevision: data.revision))
                self?.navigate(.library)
            } catch { self?.presentAlert(title: "无法删除个人谱", message: error.localizedDescription) }
        }
    }

    func importScoreWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入个人曲谱"
        panel.prompt = "导入到我的谱"
        panel.message = "文件保存在本机个人曲谱库，可在「我的谱」中管理。单个文件最大 30 MiB。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "xhe"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importScore(from: url)
    }

    func openImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开曲谱或工坊工程"
        panel.prompt = "打开"
        panel.message = "播放器支持 IBE、Guitar Pro 与 XHE；制谱工坊支持 IBE、Guitar Pro、MusicXML、AlphaTex 与工坊 JSON。"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "xhe", "musicxml", "xml", "tex", "alphatex", "json"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        routeImportedFile(url)
    }

    func routeImportedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let studioFormats: Set<String> = ["musicxml", "xml", "tex", "alphatex", "json"]
        if studioFormats.contains(ext) {
            openStudioFile(url)
            return
        }
        if isStudioRoute, ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx"].contains(ext) {
            openStudioFile(url)
            return
        }
        importScore(from: url)
    }

    private var isStudioRoute: Bool {
        switch route { case .studio, .studioClone, .studioScore, .studioProject: return true; default: return false }
    }

    private func openStudioFile(_ url: URL) {
        if !isStudioRoute { navigate(.studio) }
        pendingStudioImportURL = url
    }

    func consumeStudioImportURL(_ url: URL) {
        guard pendingStudioImportURL?.standardizedFileURL == url.standardizedFileURL else { return }
        pendingStudioImportURL = nil
    }

    func importScore(from sourceURL: URL) {
        guard !isImporting else { return }
        guard sourceURL.isFileURL else { presentAlert(title: "无法导入曲谱", message: "只能导入本地曲谱文件。"); return }
        let ext = sourceURL.pathExtension.lowercased()
        let accepted = ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "xhe"]
        guard accepted.contains(ext) else {
            presentAlert(title: "此文件不能导入到“我的谱”", message: "个人曲库支持 IBE、Guitar Pro 3–8 与 XHE。MusicXML、AlphaTex 和工坊 JSON 请在制谱工坊中导入；原件未改动。")
            return
        }
        guard let personalStoreValue else { presentAlert(title: "个人曲库尚未就绪", message: "请等待本地数据初始化后重试。"); return }
        isImporting = true
        let category = selectedImportCategory
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let bytes = try readScoreFile(sourceURL, maximumBytes: 30 * 1_024 * 1_024)
                let format: String = ext == "json" ? "project" : (ext.hasPrefix("gp") ? "gp" : ext)
                let warnings = ext == "xhe" ? ["XHE 原件已保留；当前显示和弦文本，不能播放音频。"] : []
                let score = try await personalStoreValue.importScore(
                    originalFileName: sourceURL.lastPathComponent,
                    originalBytes: bytes,
                    playableBytes: bytes,
                    title: sourceURL.deletingPathExtension().lastPathComponent,
                    category: category,
                    format: format,
                    warnings: warnings
                )
                await self?.finishImport(score: score)
            } catch {
                await self?.finishImport(error: error.localizedDescription)
            }
        }
    }

    private func finishImport(score: PersonalScore) {
        isImporting = false
        selectedLibrarySection = .imported
        requestedLibraryScrollSection = .imported
        selectedSection = .imported
        applyImportScoreSnapshot(score: score)
        openPersonalScore(score)
    }

    private func applyImportScoreSnapshot(score: PersonalScore) {
        guard let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do { self?.apply(try await store.snapshot()) }
            catch { self?.presentAlert(title: "无法读取导入曲谱", message: error.localizedDescription) }
        }
    }

    private func finishImport(error: String) {
        isImporting = false
        presentAlert(title: "无法导入曲谱", message: error)
    }

    func exportOriginal(_ score: PersonalScore) {
        guard let assetID = score.originalAssetId, let store = personalStoreValue else {
            presentAlert(title: "没有原件可导出", message: "这份个人谱没有保存原始文件。"); return
        }
        Task { @MainActor [weak self] in
            do {
                guard let asset = try await store.asset(id: assetID) else { throw PersonalStoreError.assetMissing(assetID) }
                guard let self = self else { return }
                let original = self.personalSnapshot.originals.first(where: { $0.assetId == assetID })
                let panel = NSSavePanel()
                panel.nameFieldStringValue = original?.fileName ?? score.title
                panel.canCreateDirectories = true
                guard panel.runModal() == .OK, let url = panel.url else { return }
                try asset.bytes.write(to: url, options: .atomic)
            } catch { self?.presentAlert(title: "无法保存原件", message: error.localizedDescription) }
        }
    }

    func openDownload(for item: CatalogItem) {
        guard let contentRoot else { return }
        guard let reference = item.scoreURL ?? item.xheURL else {
            presentAlert(title: "没有可下载的曲谱", message: "该条目没有本地曲谱文件。"); return
        }
        do {
            let url = try AppPaths.resolve(reference: reference, contentRoot: contentRoot)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else { return }
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                    try bytes.write(to: destination, options: .atomic)
                } catch {
                    await self?.presentAlert(title: "无法下载曲谱", message: error.localizedDescription)
                }
            }
        } catch { presentAlert(title: "无法下载曲谱", message: error.localizedDescription) }
    }

    func share(_ item: CatalogItem) {
        guard let url = scoreShareURL(item) else {
            presentAlert(title: "分享地址不可用", message: "请在设置中配置有效的曲谱服务地址后再分享链接。")
            return
        }
        let text = "MIMI Guitar · \(item.title)\(item.artist.map { " / \($0)" } ?? "")"
        let picker = NSSharingServicePicker(items: [text, url])
        if let window = NSApp.keyWindow, let content = window.contentView {
            picker.show(relativeTo: content.bounds, of: content, preferredEdge: .minY)
        } else {
            copyShareLink(for: item)
        }
    }

    func copyShareLink(for item: CatalogItem) {
        guard let url = scoreShareURL(item) else {
            presentAlert(title: "链接不可用", message: "请在设置中配置有效的曲谱服务地址。")
            return
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(url.absoluteString, forType: .string) {
            presentAlert(title: "曲谱链接已复制", message: "可以粘贴分享《\(item.title)》的链接。")
        } else {
            presentAlert(title: "无法复制曲谱链接", message: "剪贴板暂时不可用，请重试。")
        }
    }

    private func scoreShareURL(_ item: CatalogItem) -> URL? {
        websiteURL(section: item.category == "ukulele" ? "ukulele" : "tabs", id: item.id)
    }

    func loadArticles(immediately: Bool) {
        guard let catalogStore else {
            articleListIsLoading = bootstrapMessage == nil
            articleListMessage = bootstrapMessage
            return
        }
        articleGeneration += 1
        let generation = articleGeneration
        let query = CatalogArticleQuery(text: articleSearch, sort: articleSort, limit: 9, offset: (articlePage - 1) * 9)
        articles = []
        articleListMessage = nil
        articleListIsLoading = true
        Task { @MainActor [weak self] in
            if !immediately { try? await Task.sleep(nanoseconds: 160_000_000) }
            guard let self, generation == self.articleGeneration else { return }
            defer { if generation == self.articleGeneration { self.articleListIsLoading = false } }
            do {
                let additional = await self.publicationArticles()
                let page = try await catalogStore.searchArticles(query, including: additional)
                guard generation == self.articleGeneration, case .articles = self.route else { return }
                self.articles = page.articles
                self.articleTotal = page.total
                if self.articlePage > self.articlePageCount {
                    self.articlePage = self.articlePageCount
                    self.loadArticles(immediately: true)
                }
            } catch {
                guard generation == self.articleGeneration else { return }
                self.articleListMessage = error.localizedDescription
            }
        }
    }

    func loadArticle(id: String) {
        guard let catalogStore else {
            articleDetailIsLoading = bootstrapMessage == nil
            articleDetailMessage = bootstrapMessage
            return
        }
        articleDetailGeneration += 1
        let generation = articleDetailGeneration
        selectedArticle = nil
        articleDetailMessage = nil
        articleDetailIsLoading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if generation == self.articleDetailGeneration { self.articleDetailIsLoading = false } }
            do {
                let additional = await self.publicationArticles()
                let local = try await catalogStore.article(id: id)
                guard generation == self.articleDetailGeneration, case .article(let activeID) = self.route, activeID == id else { return }
                self.selectedArticle = additional.first { $0.id == id } ?? local
                if self.selectedArticle == nil { self.articleDetailMessage = "找不到这篇文章。它可能已被移除，或不在当前本地快照与已发布记录中。" }
            } catch {
                guard generation == self.articleDetailGeneration else { return }
                self.articleDetailMessage = error.localizedDescription
            }
        }
    }

    private func publicationArticles() async -> [CatalogArticle] {
        guard let publicationCache, let client = accountClient else { return publishedArticles }
        do {
            let stored = try await publicationCache.articles(service: client.baseURL.absoluteString)
            guard accountClient === client else { return [] }
            var merged = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            for article in publishedArticles { merged[article.id] = article }
            publishedArticles = Array(merged.values)
            return publishedArticles
        } catch {
            guard accountClient === client else { return [] }
            if !didReportPublicationCacheError {
                didReportPublicationCacheError = true
                presentAlert(title: "已发布文章缓存无法读取", message: "随包文章仍可阅读。\(error.localizedDescription)")
            }
            return publishedArticles
        }
    }

    func articleShareURL(id: String) -> URL? {
        websiteURL(section: "article", id: id)
    }

    private func websiteURL(section: String, id: String) -> URL? {
        guard let client = accountClient, !id.isEmpty, !id.contains("/"), id != ".", id != ".." else { return nil }
        return client.baseURL.appendingPathComponent(section).appendingPathComponent(id)
    }

    func configureAccountService(_ text: String) {
        do {
            let client = try AccountAPIClient(baseURLText: text)
            accountGeneration += 1
            articleGeneration += 1
            articleDetailGeneration += 1
            commandGeneration += 1
            accountClient = client
            accountServiceAddress = client.baseURL.absoluteString
            UserDefaults.standard.set(accountServiceAddress, forKey: "mimi.account.serviceAddress")
            remoteUser = nil
            remoteFavorites = []
            publishedArticles = []
            selectedArticle = nil
            didReportPublicationCacheError = false
            accountBusy = false
            articleBusy = false
            accountMessage = "服务地址已保存。"
            accountMessageIsError = false
            if case .articles = route { loadArticles(immediately: true) }
            else if case .article(let id) = route { loadArticle(id: id) }
            else if case .search(_, .article) = route { scheduleSearch(immediately: true) }
        } catch {
            accountServiceAddress = accountClient?.baseURL.absoluteString ?? AccountAPIClient.defaultBaseURL
            accountMessage = error.localizedDescription
            accountMessageIsError = true
        }
    }

    func loadAccount(area: AccountArea) {
        guard let accountClient else { return }
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                let user = try await accountClient.fetchCurrentUser()
                guard let self, self.isCurrentAccountRequest(generation, client: accountClient) else { return }
                if self.remoteUser?.id != user?.id { self.remoteFavorites = [] }
                self.remoteUser = user
                if area == .favorites, user != nil {
                    let favorites = try await accountClient.fetchLegacyFavorites()
                    guard self.isCurrentAccountRequest(generation, client: accountClient) else { return }
                    self.remoteFavorites = favorites
                } else if user == nil { self.remoteFavorites = [] }
                self.accountMessage = nil
                self.accountMessageIsError = false
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    private func beginAccountRequest() -> Int {
        accountGeneration += 1
        accountBusy = true
        accountMessage = nil
        accountMessageIsError = false
        return accountGeneration
    }

    private func isCurrentAccountRequest(_ generation: Int, client: AccountAPIClient) -> Bool {
        generation == accountGeneration && accountClient === client
    }

    func login() { authenticate(register: false) }
    func register() { authenticate(register: true) }
    private func authenticate(register: Bool) {
        guard let accountClient else { presentAlert(title: "服务地址无效", message: accountMessage ?? "请检查服务地址设置。"); return }
        guard !accountBusy else { return }
        let account = authAccount, password = authPassword, nickname = authNickname
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                let user = try register
                    ? await accountClient.register(account: account, password: password, nickname: nickname)
                    : await accountClient.login(account: account, password: password)
                guard let self, self.isCurrentAccountRequest(generation, client: accountClient) else { return }
                if self.remoteUser?.id != user.id { self.remoteFavorites = [] }
                self.remoteUser = user
                if self.authPassword == password { self.authPassword = "" }
                self.finishAuthentication()
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    private func finishAuthentication() {
        let destination = authenticationReturnDestination
        authenticationReturnDestination = nil
        while let last = routeHistory.last, isAuthenticationRoute(last.route) { routeHistory.removeLast() }
        if let destination,
           let url = URL(string: "mimi-local://route\(destination)"),
           let returnRoute = NativeRoute.resolve(url) {
            setRoute(returnRoute)
            applyURLParameters(url, route: returnRoute)
        } else if canNavigateBack {
            navigateBack()
        } else {
            setRoute(.account(.profile))
        }
    }

    private func isAuthenticationRoute(_ route: NativeRoute) -> Bool {
        switch route {
        case .login, .register, .authenticationReturn, .resetPassword: return true
        default: return false
        }
    }

    func logout() {
        guard let accountClient, !accountBusy else { return }
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                try await accountClient.logout()
                guard let self, self.isCurrentAccountRequest(generation, client: accountClient) else { return }
                self.remoteUser = nil; self.remoteFavorites = []
                self.navigate(.home)
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    func removeRemoteFavorite(_ favorite: RemoteFavorite) {
        guard let accountClient, !accountBusy else { return }
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                try await accountClient.removeLegacyFavorite(id: favorite.id)
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.remoteFavorites.removeAll { $0.id == favorite.id }
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    func migrateRemoteFavorite(_ favorite: RemoteFavorite) {
        guard let catalogStore, let store = personalStoreValue else { return }
        Task { @MainActor [weak self] in
            do {
                let item = try await catalogStore.item(id: favorite.id) ?? favorite.catalogItem
                try await store.ensureFavorite(item)
                self?.apply(try await store.snapshot())
                self?.accountMessage = "已迁入本机收藏；云端收藏仍保留。"
                self?.accountMessageIsError = false
            } catch { self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true }
        }
    }

    func publishArticle() {
        guard let accountClient else { presentAlert(title: "服务地址无效", message: accountMessage ?? "请检查服务地址设置。"); return }
        guard !articleBusy else { return }
        let title = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = articleContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = articleCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftTitle = articleTitle, draftContent = articleContent
        articleBusy = true; accountMessage = nil
        Task { @MainActor [weak self] in
            defer { if self?.accountClient === accountClient { self?.articleBusy = false } }
            do {
                let id = try await accountClient.publishArticle(title: title, category: category, content: content)
                guard let self, self.accountClient === accountClient else { return }
                let article = CatalogArticle(id: id, title: title, content: content, category: category.isEmpty ? nil : category, createdAt: ISO8601DateFormatter().string(from: Date()))
                self.publishedArticles.removeAll { $0.id == id }
                self.publishedArticles.append(article)
                if let cache = self.publicationCache {
                    do { try await cache.save(article, service: accountClient.baseURL.absoluteString) }
                    catch {
                        self.presentAlert(title: "文章已发布，离线记录保存失败", message: "服务器已接受这篇文章，请勿重复发布。当前运行仍可阅读全文。\(error.localizedDescription)")
                    }
                }
                guard self.accountClient === accountClient else { return }
                if self.articleTitle == draftTitle { self.articleTitle = "" }
                if self.articleContent == draftContent { self.articleContent = "" }
                self.accountMessageIsError = false
                self.navigate(.article(id: id))
            } catch {
                guard self?.accountClient === accountClient else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    func sendResetCode() {
        guard let accountClient else { presentAlert(title: "服务地址无效", message: accountMessage ?? "请检查服务地址设置。"); return }
        guard !accountBusy else { return }
        let phone = resetPhone
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                let message = try await accountClient.sendResetCode(phone: phone)
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = message ?? "验证码请求已返回。"; self?.accountMessageIsError = false
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    func resetPassword() {
        guard let accountClient else { presentAlert(title: "服务地址无效", message: accountMessage ?? "请检查服务地址设置。"); return }
        guard !accountBusy else { return }
        let phone = resetPhone, code = resetCode, password = resetPasswordValue
        let generation = beginAccountRequest()
        Task { @MainActor [weak self] in
            defer { if self?.isCurrentAccountRequest(generation, client: accountClient) == true { self?.accountBusy = false } }
            do {
                let message = try await accountClient.resetPassword(phone: phone, code: code, password: password)
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = message ?? "密码重置请求已返回。"; self?.accountMessageIsError = false
                if self?.resetPasswordValue == password { self?.resetPasswordValue = "" }
            } catch {
                guard self?.isCurrentAccountRequest(generation, client: accountClient) == true else { return }
                self?.accountMessage = error.localizedDescription; self?.accountMessageIsError = true
            }
        }
    }

    func searchArticlesDidChange() {
        articlePage = 1
        if case .search(_, .article) = route { scheduleSearch(immediately: false) }
        else { loadArticles(immediately: false) }
    }
    func setArticlePage(_ page: Int) {
        articlePage = min(max(1, page), articlePageCount)
        if case .search(_, .article) = route { scheduleSearch(immediately: true) }
        else { loadArticles(immediately: true) }
    }
    func articleSortDidChange() {
        articlePage = 1
        if case .search(_, .article) = route { scheduleSearch(immediately: true) }
        else { loadArticles(immediately: true) }
    }

    func presentCommandPalette() {
        commandGeneration += 1
        commandQuery = ""; commandItems = []; commandArticles = []; commandError = nil; commandIsLoading = false
        isCommandPalettePresented = true
    }
    func commandQueryDidChange() { searchCommands() }
    func commandDomainDidChange() { searchCommands() }
    private func searchCommands() {
        commandGeneration += 1
        let generation = commandGeneration
        let query = commandQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            commandItems = []; commandArticles = []; commandError = nil; commandIsLoading = false
            return
        }
        guard let catalogStore else {
            commandItems = []; commandArticles = []; commandError = "本地曲库尚未准备好，请稍后重试。"; commandIsLoading = false
            return
        }
        commandItems = []
        commandArticles = []
        commandError = nil
        commandIsLoading = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, self.commandGeneration == generation else { return }
            do {
                let includeItems = self.commandDomain != .article
                let includeArticles = self.commandDomain == .all || self.commandDomain == .article
                let category: String? = self.commandDomain == .guitar ? "guitar" : (self.commandDomain == .ukulele ? "ukulele" : nil)
                let publications: [CatalogArticle]
                if includeArticles { publications = await self.publicationArticles() }
                else { publications = [] }
                guard self.commandGeneration == generation else { return }
                async let itemPage = includeItems ? catalogStore.search(CatalogQuery(text: query, category: category, sort: .popular, limit: 8, offset: 0, includeMetadata: true)) : CatalogPage(items: [], total: 0)
                async let articlePage = includeArticles ? catalogStore.searchArticles(CatalogArticleQuery(text: query, sort: .newest, limit: 5, offset: 0), including: publications) : CatalogArticlePage(articles: [], total: 0)
                let (scores, stories) = try await (itemPage, articlePage)
                guard self.commandGeneration == generation else { return }
                self.commandItems = scores.items
                self.commandArticles = stories.articles
                self.commandIsLoading = false
            } catch {
                guard self.commandGeneration == generation else { return }
                self.commandItems = []; self.commandArticles = []; self.commandError = error.localizedDescription; self.commandIsLoading = false
            }
        }
    }

    func submitCommandSearch() {
        let text = commandQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { navigate(.catalog(.all)); isCommandPalettePresented = false; return }
        saveRecentSearch(text)
        let routeDomain: SearchDomain = commandDomain == .article ? .article : commandDomain
        navigate(.search(query: text, domain: routeDomain))
        isCommandPalettePresented = false
    }

    func saveRecentSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches = [trimmed] + recentSearches.filter { $0 != trimmed }
        recentSearches = Array(recentSearches.prefix(6))
        UserDefaults.standard.set(recentSearches, forKey: "mimi.native.recentSearches")
    }

    func useRecentSearch(_ text: String) { commandQuery = text; searchCommands() }
    func removeRecentSearch(_ text: String) { recentSearches.removeAll { $0 == text }; UserDefaults.standard.set(recentSearches, forKey: "mimi.native.recentSearches") }
    func clearRecentSearches() { recentSearches = []; UserDefaults.standard.removeObject(forKey: "mimi.native.recentSearches") }

    func presentAlert(title: String, message: String) {
        alertTitle = title; alertMessage = message; isShowingAlert = true
    }

    func dismissAlert() { isShowingAlert = false }
}

private func readScoreFile(_ url: URL, maximumBytes: Int) throws -> Data {
    let didStart = url.startAccessingSecurityScopedResource()
    defer { if didStart { url.stopAccessingSecurityScopedResource() } }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ImportFailure.notARegularFile }
    guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= maximumBytes else { throw ImportFailure.tooLarge }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard !data.isEmpty, data.count <= maximumBytes else { throw ImportFailure.tooLarge }
    return data
}

private enum ImportFailure: LocalizedError {
    case notARegularFile
    case tooLarge
    var errorDescription: String? {
        switch self {
        case .notARegularFile: return "请选择普通曲谱文件，不能选择文件夹或链接。"
        case .tooLarge: return "请选择 30 MiB 以内的非空曲谱文件；原件未写入个人资料。"
        }
    }
}
