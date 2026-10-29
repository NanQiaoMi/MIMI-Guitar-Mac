import AppKit
import Combine
import Foundation
import MIMICore
import SwiftUI

/// Serializes all score and audition playback in the native app. The callback
/// is invoked before a new owner begins, so two AlphaTab synths cannot overlap.
@MainActor
enum NativePlayerAudioFocus {
    private static var ownerID: ObjectIdentifier?
    private static var ownerDidLoseFocus: (() -> Void)?

    static func claim(_ owner: AnyObject, onLoss: @escaping () -> Void) {
        let nextID = ObjectIdentifier(owner)
        if ownerID == nextID {
            ownerDidLoseFocus = onLoss
            return
        }
        let previousLoss = ownerDidLoseFocus
        ownerID = nextID
        ownerDidLoseFocus = onLoss
        previousLoss?()
    }

    static func release(_ owner: AnyObject) {
        guard ownerID == ObjectIdentifier(owner) else { return }
        ownerID = nil
        ownerDidLoseFocus = nil
    }

    static func pauseCurrent(except owner: AnyObject? = nil) {
        if let owner, ownerID == ObjectIdentifier(owner) { return }
        let callback = ownerDidLoseFocus
        ownerID = nil
        ownerDidLoseFocus = nil
        callback?()
    }
}

@MainActor
final class NativeAuditionController: ObservableObject {
    @Published private(set) var activeItem: CatalogItem?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var endTime: Double = 0
    @Published private(set) var activeNotes: [NativeFretNote] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var tempo: Double = 80
    @Published private(set) var sourceTempo: Double = 80
    @Published private(set) var statusMessage = ""
    @Published private(set) var canPlay = false
    @Published private(set) var previewDuration: TimeInterval?
    @Published private(set) var previewElapsed: TimeInterval = 0
    @Published private(set) var previewExpired = false
    @Published fileprivate var hostModel: NativePlayerModel?
#if MIMI_RUNTIME_DIAGNOSTICS
    var runtimeDiagnosticHostModel: NativePlayerModel? { hostModel }
#endif

    private var cancellables = Set<AnyCancellable>()
    private var previewTimer: Timer?
    private var lastPreviewTick: TimeInterval?
    private var pendingSynchronization: DispatchWorkItem?
    private var pendingSynchronizationID: UUID?
    private var pendingSynchronizationHostID: ObjectIdentifier?
    private var contentRoot: URL?
    private weak var personalStore: PersonalStore?

    init() {}

    /// Called once by the hidden window-level host. The actual notation engine
    /// stays in a scoped local WKWebView; all user-facing chrome remains native.
    func attachHost(contentRoot: URL, personalStore: PersonalStore) {
        if hostModel != nil, self.contentRoot == contentRoot, self.personalStore === personalStore { return }
        if hostModel != nil { detachHost() }
        self.contentRoot = contentRoot
        self.personalStore = personalStore
        let player = NativePlayerModel(
            item: nil,
            personalScore: nil,
            contentRoot: contentRoot,
            personalStore: personalStore,
            importedFileURL: nil,
            mode: .player
        )
        player.setNativeViewVisible(true)
        hostModel = player
        observe(player)
        synchronize(from: player)
    }

    func detachHost() {
        pause()
        cancellables.removeAll()
        cancelPendingSynchronization()
        hostModel?.setNativeViewVisible(false)
        hostModel = nil
        contentRoot = nil
        personalStore = nil
    }

    func play(item: CatalogItem) {
        begin(item: item, previewDuration: nil)
    }

    func toggle(item: CatalogItem, previewDuration: TimeInterval? = nil) {
        if activeItem?.id == item.id {
            guard let hostModel else { return }
            if isPlaying {
                hostModel.pausePlayback()
                return
            }
            if isLoading {
                hostModel.closeAudition()
                stopPreviewTimer(reset: true)
                activeItem = nil
                statusMessage = "已取消试听"
                return
            }
            begin(item: item, previewDuration: previewDuration, reload: false)
            return
        }
        begin(item: item, previewDuration: previewDuration)
    }

    /// The compact status bar uses this action to stop and dismiss audition.
    func pause() {
        hostModel?.closeAudition()
        NativePlayerAudioFocus.release(self)
        stopPreviewTimer(reset: true)
        activeItem = nil
        isLoading = false
        isPlaying = false
        canPlay = false
        currentTime = 0
        endTime = 0
        activeNotes = []
        errorMessage = nil
        statusMessage = "已停止试听"
    }

    func seek(toRatio ratio: Double) {
        guard canPlay, ratio.isFinite else { return }
        hostModel?.seek(toRatio: ratio)
    }

    func setTempo(_ bpm: Double) {
        guard let hostModel, hostModel.canPlay, bpm.isFinite else { return }
        hostModel.tempo = min(hostModel.tempoRange.upperBound, max(hostModel.tempoRange.lowerBound, bpm))
        hostModel.applyTempo()
        synchronize(from: hostModel)
    }

    private func begin(item: CatalogItem, previewDuration requestedDuration: TimeInterval?, reload: Bool = true) {
        guard let hostModel else {
            statusMessage = "试听引擎尚未就绪"
            return
        }
        guard !(item.scoreURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            statusMessage = "这首曲目没有可试听的原谱文件"
            return
        }

        let nextDuration: TimeInterval? = requestedDuration.map { $0 >= 45 ? 60 : 30 }
        stopPreviewTimer(reset: true)
        previewDuration = nextDuration
        previewExpired = false
        activeItem = item
        errorMessage = nil

        if reload || hostModel.item?.id != item.id {
            hostModel.closeAudition()
            hostModel.open(item: item, autoplay: true)
        } else {
            hostModel.playAudition()
        }
        statusMessage = "正在准备原谱与音源；准备时间不计入试听…"
    }

    private func observe(_ player: NativePlayerModel) {
        Publishers.Merge(
            player.objectWillChange.map { _ in () },
            player.playbackPositionChanges
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] _ in
                DispatchQueue.main.async {
                    guard let self, let player, self.hostModel === player else { return }
                    self.scheduleSynchronization(from: player)
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleSynchronization(from player: NativePlayerModel) {
        guard hostModel === player else { return }
        let hostID = ObjectIdentifier(player)
        if pendingSynchronization != nil, pendingSynchronizationHostID == hostID { return }
        cancelPendingSynchronization()

        let synchronizationID = UUID()
        let workItem = DispatchWorkItem { [weak self, weak player] in
            guard let self, self.pendingSynchronizationID == synchronizationID else { return }
            self.pendingSynchronization = nil
            self.pendingSynchronizationID = nil
            self.pendingSynchronizationHostID = nil
            guard let player,
                  self.hostModel === player,
                  ObjectIdentifier(player) == hostID else { return }
            self.synchronize(from: player)
        }
        pendingSynchronization = workItem
        pendingSynchronizationID = synchronizationID
        pendingSynchronizationHostID = hostID
        DispatchQueue.main.async(execute: workItem)
    }

    private func cancelPendingSynchronization() {
        pendingSynchronization?.cancel()
        pendingSynchronization = nil
        pendingSynchronizationID = nil
        pendingSynchronizationHostID = nil
    }

    private func synchronize(from player: NativePlayerModel) {
        if let item = player.item, activeItem != item { activeItem = item }
        let nextIsLoading = player.isLoading || player.isLoadingSound
        if isLoading != nextIsLoading { isLoading = nextIsLoading }
        if isPlaying != player.isPlaying { isPlaying = player.isPlaying }
        if currentTime != player.currentTime { currentTime = player.currentTime }
        if endTime != player.endTime { endTime = player.endTime }
        let nextActiveNotes = player.isPlaying ? player.currentBeatNotes : []
        if activeNotes != nextActiveNotes { activeNotes = nextActiveNotes }
        let nextErrorMessage = player.sourceError ?? player.playerRootError ?? player.playerError
        if errorMessage != nextErrorMessage { errorMessage = nextErrorMessage }
        if tempo != player.tempo { tempo = player.tempo }
        if sourceTempo != player.sourceTempo { sourceTempo = player.sourceTempo }
        if canPlay != player.canPlay { canPlay = player.canPlay }

        var nextStatusMessage = statusMessage
        if player.isPlaying {
            if lastPreviewTick == nil { lastPreviewTick = ProcessInfo.processInfo.systemUptime }
            if previewDuration != nil, previewTimer == nil {
                previewTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.advancePreviewClock() }
                }
            }
            let remaining = previewDuration.map { max(0, $0 - previewElapsed) }
            nextStatusMessage = remaining.map { "原谱试听 · 剩余 \(Int(ceil($0))) 秒" } ?? player.statusMessage
        } else {
            lastPreviewTick = nil
            previewTimer?.invalidate()
            previewTimer = nil
            if previewExpired {
                nextStatusMessage = "试听已结束 · 可继续播放完整曲谱"
            } else if !player.statusMessage.isEmpty {
                nextStatusMessage = player.statusMessage
            }
        }
        if statusMessage != nextStatusMessage { statusMessage = nextStatusMessage }
    }

    private func advancePreviewClock() {
        guard isPlaying, let previewDuration else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPreviewTick { previewElapsed += max(0, now - lastPreviewTick) }
        lastPreviewTick = now
        guard previewElapsed >= previewDuration else { return }
        previewExpired = true
        previewTimer?.invalidate()
        previewTimer = nil
        lastPreviewTick = nil
        hostModel?.pausePlayback()
        statusMessage = "试听已结束 · 可继续播放完整曲谱"
    }

    private func stopPreviewTimer(reset: Bool) {
        previewTimer?.invalidate()
        previewTimer = nil
        lastPreviewTick = nil
        if reset { previewElapsed = 0; previewExpired = false }
    }
}

struct NativeAuditionHost: View {
    @ObservedObject var controller: NativeAuditionController
    let contentRoot: URL
    let personalStore: PersonalStore

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let model = controller.hostModel {
                NativeAuditionPlayerMount(model: model)
            }
        }
        .frame(width: 1, height: 1)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { controller.attachHost(contentRoot: contentRoot, personalStore: personalStore) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            controller.hostModel?.setApplicationActive(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.hostModel?.setApplicationActive(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.willSleepNotification)) { _ in
            controller.pause()
        }
        .onDisappear { controller.detachHost() }
    }
}

private struct NativeAuditionPlayerMount: View {
    @ObservedObject var model: NativePlayerModel

    var body: some View {
        Group {
            if model.source != nil {
                NativePlayerWebView(model: model)
                    .id(model.webViewIdentity)
            }
        }
        .frame(width: 1_024, height: 720, alignment: .topLeading)
    }
}
