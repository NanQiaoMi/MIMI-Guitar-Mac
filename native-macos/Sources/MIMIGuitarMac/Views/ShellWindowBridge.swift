import AppKit
import Combine
import SwiftUI

enum RouteTransitionIntent: Equatable {
    case peer
    case drillDown
    case pop
    case workspaceEnter
    case workspaceExit
    case crossFade
    case none
}

enum RouteTransitionClassifier {
    static func isTopTab(_ route: NativeRoute) -> Bool {
        switch route {
        case .home, .catalog, .catalogQuery, .articles, .practice, .library, .dataSettings:
            return true
        default:
            return false
        }
    }

    static func isScoreDetail(_ route: NativeRoute) -> Bool {
        if case .score = route { return true }
        return false
    }

    static func isStudio(_ route: NativeRoute) -> Bool {
        switch route {
        case .studio, .studioClone, .studioScore, .studioProject:
            return true
        default:
            return false
        }
    }

    static func classify(from oldRoute: NativeRoute, to newRoute: NativeRoute) -> RouteTransitionIntent {
        guard oldRoute != newRoute else { return .none }

        // Drill-down to score detail
        if isScoreDetail(newRoute) && !isScoreDetail(oldRoute) {
            return .drillDown
        }

        // Return from score detail
        if isScoreDetail(oldRoute) && !isScoreDetail(newRoute) {
            return .pop
        }

        // Studio workspace enter
        if isStudio(newRoute) && !isStudio(oldRoute) {
            return .workspaceEnter
        }

        // Studio workspace exit
        if isStudio(oldRoute) && !isStudio(newRoute) {
            return .workspaceExit
        }

        // Top peer tabs
        if isTopTab(oldRoute) && isTopTab(newRoute) {
            return .peer
        }

        return .crossFade
    }
}

@MainActor
final class MainWindowTransitionState: ObservableObject {
    @Published private(set) var activeRoute: NativeRoute = .home
    @Published private(set) var outgoingRoute: NativeRoute? = nil

    @Published private(set) var incomingOpacity: Double = 1.0
    @Published private(set) var incomingScale: CGFloat = 1.0
    @Published private(set) var incomingOffset: CGFloat = 0

    @Published private(set) var outgoingOpacity: Double = 1.0
    @Published private(set) var outgoingScale: CGFloat = 1.0
    @Published private(set) var outgoingOffset: CGFloat = 0

    @Published private(set) var currentIntent: RouteTransitionIntent = .none
    @Published private(set) var isTransitioning = false

    @Published private(set) var snapshot: NSImage? = nil
    @Published private(set) var snapshotOpacity: Double = 1.0

    private weak var anchorView: NSView?
    private var policy: MIMIMotionPolicy = .full
    private var transitionGeneration = 0

    func setAnchorView(_ view: NSView?) {
        anchorView = view
    }

    func updatePolicy(_ policy: MIMIMotionPolicy) {
        guard self.policy != policy else { return }
        self.policy = policy
        if policy == .off {
            clear()
        }
    }

    func initialize(with initialRoute: NativeRoute, policy: MIMIMotionPolicy) {
        self.policy = policy
        self.activeRoute = initialRoute
        self.outgoingRoute = nil
        self.isTransitioning = false
        resetValues()
    }

    func transition(to newRoute: NativeRoute, policy: MIMIMotionPolicy) {
        guard newRoute != activeRoute else { return }
        self.policy = policy
        transitionGeneration += 1
        let generation = transitionGeneration

        if policy == .off {
            outgoingRoute = nil
            activeRoute = newRoute
            isTransitioning = false
            currentIntent = .none
            resetValues()
            return
        }

        let oldRoute = activeRoute
        let intent = RouteTransitionClassifier.classify(from: oldRoute, to: newRoute)
        currentIntent = intent

        outgoingRoute = oldRoute
        activeRoute = newRoute
        isTransitioning = true

        // Set initial values
        switch intent {
        case .peer, .crossFade:
            incomingOpacity = 0.0
            incomingScale = 1.0
            incomingOffset = 0
            outgoingOpacity = 1.0
            outgoingScale = 1.0
            outgoingOffset = 0

        case .drillDown:
            incomingOpacity = 0.0
            incomingScale = 1.0
            incomingOffset = policy.allowsSpatialMotion ? 16 : 0
            outgoingOpacity = 1.0
            outgoingScale = 1.0
            outgoingOffset = 0

        case .pop:
            incomingOpacity = 0.5
            incomingScale = policy.allowsSpatialMotion ? 0.98 : 1.0
            incomingOffset = 0
            outgoingOpacity = 1.0
            outgoingScale = 1.0
            outgoingOffset = 0

        case .workspaceEnter, .workspaceExit:
            incomingOpacity = 0.0
            incomingScale = 1.0
            incomingOffset = policy.allowsSpatialMotion ? -8 : 0
            outgoingOpacity = 1.0
            outgoingScale = 1.0
            outgoingOffset = 0

        case .none:
            outgoingRoute = nil
            isTransitioning = false
            resetValues()
            return
        }

        let (animation, duration) = animationParams(for: intent, policy: policy)

        withAnimation(animation) {
            switch intent {
            case .peer, .crossFade:
                self.incomingOpacity = 1.0
                self.outgoingOpacity = 0.0

            case .drillDown:
                self.incomingOpacity = 1.0
                self.incomingOffset = 0
                self.outgoingOpacity = 0.4
                if self.policy.allowsSpatialMotion {
                    self.outgoingScale = 0.98
                }

            case .pop:
                self.incomingOpacity = 1.0
                self.incomingScale = 1.0
                self.outgoingOpacity = 0.0
                if self.policy.allowsSpatialMotion {
                    self.outgoingOffset = 16
                }

            case .workspaceEnter, .workspaceExit:
                self.incomingOpacity = 1.0
                self.incomingOffset = 0
                self.outgoingOpacity = 0.0

            case .none:
                break
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            self.outgoingRoute = nil
            self.isTransitioning = false
            self.currentIntent = .none
            self.resetValues()
        }
    }

    private func animationParams(for intent: RouteTransitionIntent, policy: MIMIMotionPolicy) -> (Animation, Double) {
        switch policy {
        case .off:
            return (.easeInOut(duration: 0), 0)
        case .gentle:
            return (.easeInOut(duration: 0.14), 0.14)
        case .full:
            switch intent {
            case .peer, .crossFade:
                return (.easeInOut(duration: 0.18), 0.18)
            case .drillDown:
                return (.spring(response: 0.30, dampingFraction: 0.86), 0.28)
            case .pop:
                return (.spring(response: 0.26, dampingFraction: 0.88), 0.24)
            case .workspaceEnter, .workspaceExit:
                return (.easeInOut(duration: 0.22), 0.22)
            case .none:
                return (.easeInOut(duration: 0), 0)
            }
        }
    }

    private func resetValues() {
        incomingOpacity = 1.0
        incomingScale = 1.0
        incomingOffset = 0
        outgoingOpacity = 1.0
        outgoingScale = 1.0
        outgoingOffset = 0
    }

    func beginRouteChange() {
        // Compatibility shim: do NOT zero out opacity to prevent white flash
    }

    func finishRouteChange() {
        // Handled reactively by transition(to:policy:)
    }

    func clear() {
        transitionGeneration += 1
        isTransitioning = false
        outgoingRoute = nil
        currentIntent = .none
        resetValues()
    }
}

private struct MIMIViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var mimiViewportHeight: CGFloat? {
        get { self[MIMIViewportHeightKey.self] }
        set { self[MIMIViewportHeightKey.self] = newValue }
    }
}

struct MainWindowBridge: NSViewRepresentable {
    let model: AppModel
    var transition: MainWindowTransitionState? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, transition: transition)
    }

    func makeNSView(context: Context) -> MainWindowBridgeView {
        let view = MainWindowBridgeView()
        let coordinator = context.coordinator
        let transitionState = transition
        view.onWindowChange = { [weak coordinator] window in
            coordinator?.attach(window)
        }
        view.onAttach = { [weak coordinator, weak transitionState] view in
            transitionState?.setAnchorView(view)
            coordinator?.attach(view.window)
        }
        view.onAttach?(view)
        return view
    }

    func updateNSView(_ nsView: MainWindowBridgeView, context: Context) {
        nsView.onAttach?(nsView)
        context.coordinator.attach(nsView.window)
    }

    static func dismantleNSView(_ nsView: MainWindowBridgeView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        nsView.onAttach = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private let model: AppModel
        private weak var transition: MainWindowTransitionState?
        private weak var observedWindow: NSWindow?
        private var didEnterObserver: NSObjectProtocol?
        private var didExitObserver: NSObjectProtocol?
        private var willEnterObserver: NSObjectProtocol?
        private var willExitObserver: NSObjectProtocol?
        private var occlusionObserver: NSObjectProtocol?
        private var miniaturizeObserver: NSObjectProtocol?
        private var deminiaturizeObserver: NSObjectProtocol?
        private var appHideObserver: NSObjectProtocol?
        private var appUnhideObserver: NSObjectProtocol?
        private var appearanceObserver: NSObjectProtocol?

        init(model: AppModel, transition: MainWindowTransitionState? = nil) {
            self.model = model
            self.transition = transition
        }

        func attach(_ window: NSWindow?) {
            guard observedWindow !== window else { return }
            removeObservers()
            observedWindow = window
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert([.fullSizeContentView, .miniaturizable])
            window.isMovableByWindowBackground = false
            window.backgroundColor = .dynamic(lightHex: 0xFBFAF6, darkHex: 0x1E1B18)
            updateWindowAppearance(window)
            model.attachMainWindow(window)

            handleOcclusionChange(window)

            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let window else { return }
                    self?.handleOcclusionChange(window)
                }
            }

            miniaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let window else { return }
                    self?.handleOcclusionChange(window)
                }
            }

            deminiaturizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didDeminiaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let window else { return }
                    self?.handleOcclusionChange(window)
                }
            }

            appHideObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.model.windowOcclusionDidChange(true)
                }
            }

            appUnhideObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didUnhideNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let window else { return }
                    self?.handleOcclusionChange(window)
                }
            }

            appearanceObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak window] _ in
                guard let window else { return }
                Task { @MainActor [weak self] in
                    self?.updateWindowAppearance(window)
                }
            }

            willEnterObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.windowFullScreenWillChange(true) }
            }
            willExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.windowFullScreenWillChange(false) }
            }
            didEnterObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.windowFullScreenDidChange(true) }
            }
            didExitObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.model.windowFullScreenDidChange(false) }
            }
        }

        private func handleOcclusionChange(_ window: NSWindow) {
            let isOccluded = window.isMiniaturized || !window.occlusionState.contains(.visible)
            model.windowOcclusionDidChange(isOccluded)
        }

        private func updateWindowAppearance(_ window: NSWindow) {
            let pref = UserDefaults.standard.string(forKey: "mimi.appearance") ?? "system"
            switch pref {
            case "light":
                window.appearance = NSAppearance(named: .aqua)
            case "dark":
                window.appearance = NSAppearance(named: .darkAqua)
            default:
                window.appearance = nil
            }
        }

        func detach() {
            removeObservers()
            observedWindow = nil
            transition?.setAnchorView(nil)
        }

        private func removeObservers() {
            if let didEnterObserver { NotificationCenter.default.removeObserver(didEnterObserver) }
            if let didExitObserver { NotificationCenter.default.removeObserver(didExitObserver) }
            if let willEnterObserver { NotificationCenter.default.removeObserver(willEnterObserver) }
            if let willExitObserver { NotificationCenter.default.removeObserver(willExitObserver) }
            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
            if let miniaturizeObserver { NotificationCenter.default.removeObserver(miniaturizeObserver) }
            if let deminiaturizeObserver { NotificationCenter.default.removeObserver(deminiaturizeObserver) }
            if let appHideObserver { NotificationCenter.default.removeObserver(appHideObserver) }
            if let appUnhideObserver { NotificationCenter.default.removeObserver(appUnhideObserver) }
            if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
            didEnterObserver = nil
            didExitObserver = nil
            willEnterObserver = nil
            willExitObserver = nil
            occlusionObserver = nil
            miniaturizeObserver = nil
            deminiaturizeObserver = nil
            appHideObserver = nil
            appUnhideObserver = nil
            appearanceObserver = nil
        }
    }
}

final class MainWindowBridgeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?
    var onAttach: ((NSView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
        onAttach?(self)
    }

    override var isFlipped: Bool { true }
}

struct RouteScrollPositionTracker: NSViewRepresentable {
    let model: AppModel
    var route: NativeRoute? = nil

    func makeNSView(context: Context) -> RouteScrollTrackingView {
        let view = RouteScrollTrackingView()
        view.model = model
        view.trackedRoute = route ?? model.route
        view.bindIfAvailable()
        return view
    }

    func updateNSView(_ nsView: RouteScrollTrackingView, context: Context) {
        nsView.model = model
        let currentTracked = route ?? model.route
        nsView.trackedRoute = currentTracked
        nsView.bindIfAvailable()
        if model.route == currentTracked {
            nsView.restoreIfRequested()
        }
    }

    static func dismantleNSView(_ nsView: RouteScrollTrackingView, coordinator: ()) {
        nsView.stopObserving()
        nsView.model = nil
    }
}

final class RouteScrollTrackingView: NSView {
    weak var model: AppModel?
    var trackedRoute: NativeRoute?
    private weak var observedScrollView: NSScrollView?
    private var endLiveScrollObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private var pendingRestoreTimeout: DispatchWorkItem?
    private var pendingRestoreGeneration: Int?
    private var lastRestoreGeneration = -1
    private var pendingBind: DispatchWorkItem?
    private var lastRecordedOffset: CGFloat = -1
    private var bindAttempts = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bindAttempts = 0
        bindIfAvailable()
        restoreIfRequested()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        bindAttempts = 0
        bindIfAvailable()
    }

    func bindIfAvailable() {
        guard let scrollView = enclosingScrollView else {
            guard window != nil, superview != nil, pendingBind == nil, bindAttempts < 8 else { return }
            bindAttempts += 1
            let retry = DispatchWorkItem { [weak self] in
                self?.pendingBind = nil
                self?.bindIfAvailable()
            }
            pendingBind = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: retry)
            return
        }
        pendingBind?.cancel()
        pendingBind = nil
        bindAttempts = 0
        guard observedScrollView !== scrollView else { return }
        stopObserving()
        observedScrollView = scrollView

        // Capture scroll offset when user finishes live scrolling without per-frame main-thread notifications
        endLiveScrollObserver = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.recordOffset()
        }

        recordOffset()
        restoreIfRequested()
    }

    func stopObserving() {
        recordOffset()
        pendingBind?.cancel()
        pendingBind = nil
        if let endLiveScrollObserver { NotificationCenter.default.removeObserver(endLiveScrollObserver) }
        detachDocumentFrameObserver()
        pendingRestoreTimeout?.cancel()
        pendingRestoreTimeout = nil
        pendingRestoreGeneration = nil
        endLiveScrollObserver = nil
        observedScrollView = nil
    }

    private func attachDocumentFrameObserver(for documentView: NSView) {
        // Disabled to prevent _NSDetectedLayoutRecursion and hitching during layout passes
    }

    private func detachDocumentFrameObserver() {
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        observedScrollView?.documentView?.postsFrameChangedNotifications = false
    }

    func restoreIfRequested(forceClamp: Bool = false) {
        guard let model, let trackedRoute, model.route == trackedRoute,
              let request = model.requestedRouteScrollRestore,
              request.generation != lastRestoreGeneration,
              let scrollView = observedScrollView,
              let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let documentBounds = documentView.bounds
        let visibleHeight = clipView.bounds.height
        let maximumOffset = max(0, documentBounds.height - visibleHeight)
        if request.offset > maximumOffset + 1, !forceClamp {
            if pendingRestoreGeneration != request.generation {
                pendingRestoreTimeout?.cancel()
                pendingRestoreGeneration = request.generation
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, self.pendingRestoreGeneration == request.generation else { return }
                    self.pendingRestoreTimeout = nil
                    self.pendingRestoreGeneration = nil
                    self.restoreIfRequested(forceClamp: true)
                }
                pendingRestoreTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: timeout)
            }
            return
        }
        pendingRestoreTimeout?.cancel()
        pendingRestoreTimeout = nil
        pendingRestoreGeneration = nil
        lastRestoreGeneration = request.generation
        let offset = min(max(0, request.offset), maximumOffset)
        let targetY = documentView.isFlipped
            ? documentBounds.minY + offset
            : documentBounds.maxY - visibleHeight - offset
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self, let scrollView, self.model?.route == self.trackedRoute else { return }
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            self.recordOffset()
            self.model?.acknowledgeRouteScrollRestore(request.generation)
        }
    }

    private func recordOffset() {
        guard let scrollView = observedScrollView, let documentView = scrollView.documentView else { return }
        guard let trackedRoute, model?.route == trackedRoute else { return }
        let visible = scrollView.documentVisibleRect
        let bounds = documentView.bounds
        let offset = documentView.isFlipped
            ? visible.minY - bounds.minY
            : bounds.maxY - visible.maxY
        let clamped = max(0, offset)
        if abs(clamped - lastRecordedOffset) < 1.0 { return }
        lastRecordedOffset = clamped
        model?.updateCurrentRouteScrollOffset(clamped, for: trackedRoute)
    }
}
