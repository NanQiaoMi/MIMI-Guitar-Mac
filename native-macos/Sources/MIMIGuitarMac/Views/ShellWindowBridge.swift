import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class MainWindowTransitionState: ObservableObject {
    @Published private(set) var snapshot: NSImage?
    @Published private(set) var snapshotOpacity = 1.0
    @Published private(set) var incomingOpacity = 1.0
    @Published private(set) var incomingOffset: CGFloat = 0

    private weak var anchorView: NSView?
    private var policy: MIMIMotionPolicy = .full
    private var transitionGeneration = 0
    private var isTransitioning = false

    func setAnchorView(_ view: NSView?) {
        anchorView = view
    }

    func updatePolicy(_ policy: MIMIMotionPolicy) {
        guard self.policy != policy else { return }
        self.policy = policy
        if policy == .off {
            clear()
        } else if isTransitioning {
            finishRouteChange()
        }
    }

    func beginRouteChange() {
        transitionGeneration += 1
        isTransitioning = policy != .off
        guard policy != .off else {
            clear()
            return
        }
        let image = captureCurrentPage()
        snapshot = image
        snapshotOpacity = 1
        incomingOpacity = 0
        incomingOffset = policy.pageOffset
    }

    func finishRouteChange() {
        let generation = transitionGeneration
        let duration = policy.pageDuration
        guard duration > 0, policy.pageAnimation != nil else {
            clear()
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.transitionGeneration == generation else { return }
            withAnimation(self.policy.pageAnimation) {
                if self.snapshot != nil {
                    self.snapshotOpacity = 0
                }
                self.incomingOpacity = 1
                self.incomingOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.transitionGeneration == generation else { return }
                self.clear()
            }
        }
    }

    func clear() {
        transitionGeneration += 1
        isTransitioning = false
        snapshot = nil
        snapshotOpacity = 1
        incomingOpacity = 1
        incomingOffset = 0
    }

    private func captureCurrentPage() -> NSImage? {
        guard let anchorView, let window = anchorView.window, let contentView = window.contentView else { return nil }
        let rect = anchorView.convert(anchorView.bounds, to: contentView)
        // WebKit draws in a separate process. cacheDisplay cannot capture that
        // surface; use the incoming transition rather than show an empty score.
        guard !containsVisibleWebSurface(contentView, intersecting: rect, in: contentView) else { return nil }
        guard rect.width > 0, rect.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        contentView.cacheDisplay(in: rect, to: bitmap)
        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func containsVisibleWebSurface(_ view: NSView, intersecting rect: NSRect, in root: NSView) -> Bool {
        guard !view.isHidden, view.alphaValue > 0.01 else { return false }
        if view is WKWebView {
            let visible = view.convert(view.visibleRect, to: root).intersection(rect)
            if visible.width > 2, visible.height > 2 { return true }
        }
        return view.subviews.contains { containsVisibleWebSurface($0, intersecting: rect, in: root) }
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
    let transition: MainWindowTransitionState

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

        init(model: AppModel, transition: MainWindowTransitionState) {
            self.model = model
            self.transition = transition
        }

        func attach(_ window: NSWindow?) {
            guard observedWindow !== window else { return }
            removeObservers()
            observedWindow = window
            guard let window else { return }
            model.attachMainWindow(window)
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
            didEnterObserver = nil
            didExitObserver = nil
            willEnterObserver = nil
            willExitObserver = nil
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

    func makeNSView(context: Context) -> RouteScrollTrackingView {
        let view = RouteScrollTrackingView()
        view.model = model
        view.trackedRoute = model.route
        view.bindIfAvailable()
        return view
    }

    func updateNSView(_ nsView: RouteScrollTrackingView, context: Context) {
        nsView.model = model
        nsView.trackedRoute = model.route
        nsView.bindIfAvailable()
        nsView.restoreIfRequested()
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
    private var boundsObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private var pendingRestoreTimeout: DispatchWorkItem?
    private var pendingRestoreGeneration: Int?
    private var lastRestoreGeneration = -1
    private var pendingBind: DispatchWorkItem?
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
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recordOffset()
                self?.restoreIfRequested()
            }
        }
        if let documentView = scrollView.documentView {
            documentFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restoreIfRequested() }
            }
        }
        recordOffset()
        restoreIfRequested()
    }

    func stopObserving() {
        pendingBind?.cancel()
        pendingBind = nil
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        if let documentFrameObserver { NotificationCenter.default.removeObserver(documentFrameObserver) }
        pendingRestoreTimeout?.cancel()
        pendingRestoreTimeout = nil
        pendingRestoreGeneration = nil
        boundsObserver = nil
        documentFrameObserver = nil
        observedScrollView = nil
    }

    func restoreIfRequested(forceClamp: Bool = false) {
        guard let request = model?.requestedRouteScrollRestore,
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: timeout)
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
            guard let self, let scrollView else { return }
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            self.recordOffset()
            self.model?.acknowledgeRouteScrollRestore(request.generation)
        }
    }

    private func recordOffset() {
        guard let scrollView = observedScrollView, let documentView = scrollView.documentView else { return }
        let visible = scrollView.documentVisibleRect
        let bounds = documentView.bounds
        let offset = documentView.isFlipped
            ? visible.minY - bounds.minY
            : bounds.maxY - visible.maxY
        guard let trackedRoute else { return }
        model?.updateCurrentRouteScrollOffset(max(0, offset), for: trackedRoute)
    }
}
