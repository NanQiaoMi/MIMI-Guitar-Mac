import AppKit
import Combine
import CryptoKit
import Foundation
import ImageIO
import MIMICore
import UniformTypeIdentifiers
import WebKit

private struct NativeStudioLyricsDraftEntry: Codable {
    var projectID: String
    var trackID: String
    var text: String
    var expectedRevision: Int
    var expectedProjectUpdatedAt: Double?
    var updatedAt: Double
}

private struct NativeStudioCursorAdvance {
    let projectID: String
    let operationGeneration: Int
    let origin: StudioCursorPosition
    let targetBarIndex: Int
}

private struct NativeStudioPendingOperation {
    let operation: String
    let arguments: [String: Any]
    let cursorAdvance: NativeStudioCursorAdvance?
}

private struct NativeStudioProjectSaveRequest {
    let project: StudioProject
    let revision: Int
    let manual: Bool
    let generation: UInt64
}

private enum NativeStudioSaveQueueEntry {
    case project(NativeStudioProjectSaveRequest, deferred: Bool)
    case operation(@MainActor () async -> Void)
}

private struct NativeStudioDraftToken: Equatable {
    let projectID: String
    let generation: UInt64
    let contentRevision: Int
    let operationSequence: UInt64
}

@MainActor
final class NativeStudioAsyncGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: value)
    }
}

private enum NativeStudioWaitError: LocalizedError {
    case timedOut
    case javascriptTimedOut

    var errorDescription: String? {
        switch self {
        case .timedOut: return "等待本地草稿写入超时。"
        case .javascriptTimedOut: return "工坊引擎未及时返回导出结果。"
        }
    }
}

private enum NativeStudioDraftValue {
    case project(StudioProject)
    case lyrics([NativeStudioLyricsDraftEntry])
    case removed
}

struct NativeStudioShortcutInfo: Codable, Identifiable {
    let key: String
    let desc: String
    let category: String
    let keyCombos: [String]?
    let searchTerms: String?
    var id: String { key }
}

@MainActor
final class NativeStudioModel: ObservableObject {
    private static let automaticSaveIdleDelayNanoseconds: UInt64 = 450_000_000
    private static let automaticSaveMaximumDelayNanoseconds: UInt64 = 1_800_000_000

    @Published var project: StudioProject?
    @Published var savedProjects: [StudioProject] = []
    @Published var draftProjects: [StudioProject] = []
    @Published var cursor = StudioCursorPosition(trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1)
    @Published var selectedTrack = 0
    @Published var isDirty = false
    @Published var isPlaying = false
    @Published var isBooted = false
    let playbackPosition = StudioPlaybackPosition()
    var currentTick: Double { playbackPosition.currentTick }
    var endTick: Double { playbackPosition.endTick }
    @Published var status = "正在打开本地工坊…"
    @Published private(set) var didLoadInitialDataSuccessfully = false
    @Published var engineError: String?
    @Published var conversionWarnings: [String] = []
    @Published var lyricDraft = ""
    @Published private(set) var lyricTargetProjectID: String?
    @Published private(set) var lyricTargetTrackID: String?
    @Published private(set) var lyricExpectedRevision = 0
    @Published private(set) var lyricExpectedProjectUpdatedAt: Double?
    @Published private(set) var contentRevision = 0
    @Published var chordMode = false
    @Published var showingClearLyricsAlert = false
    @Published var shortcutQuery = ""
    @Published var shortcutCategory = "all"
    @Published private(set) var shortcutResults: [NativeStudioShortcutInfo] = []
    @Published var pendingDeleteID: String?
    @Published var showingDeleteAlert = false
    @Published var showingLeaveAlert = false
    @Published var pendingNavigationScoreID: String?
    @Published var isBusy = false

    let contentRoot: URL
    let personalStore: PersonalStore
    let onOpenPractice: (String) -> Void
    let onPersonalDataChanged: () -> Void
    let onStudioFileConsumed: () -> Void
    weak var webView: WKWebView?

    private var personalRevision = 0
    private var savedUpdatedAt: Double?
    private var projectVersions: [String: Double] = [:]
    private var persistedContentRevisions: [String: Int] = [:]
    private let draftIO = NativeStudioDraftIO.shared
    private var draftGenerationByProject: [String: UInt64] = [:]
    private var latestDraftTokenByProject: [String: NativeStudioDraftToken] = [:]
    private var draftIndexGeneration: UInt64 = 0
    private var lyricsDraftSequence: UInt64 = 0
    private var projectSaveTail: Task<Void, Never>?
    private var projectSaveWorkerGeneration: UInt64 = 0
    private var projectSaveQueue: [NativeStudioSaveQueueEntry] = []
    private var automaticSaveFirstQueuedAt: UInt64?
    private var automaticSaveLastQueuedAt: UInt64?
    private var automaticSaveDebounceGeneration: UInt64 = 0
    private var automaticSaveDebounceTask: Task<Void, Never>?
    private var studioGeneration: UInt64 = 0
    private var canvasSubmissionGeneration: UInt64 = 0
    private var projectOpenRequestGeneration: UInt64 = 0
    private var sourceOriginalBytes: Data?
    private var sourceFileName = ""
    @Published var linkedPracticeScoreID: String?
    private var undoStack: [StudioProject] = []
    private var redoStack: [StudioProject] = []
    private var pendingOperations: [NativeStudioPendingOperation] = []
    private var applyingOperation = false
    private var operationGeneration = 0
    private var isPreparingForWebViewTeardown = false
    private var isPreparingForProjectReplacement = false
    private var pendingEditorCommandIDs = Set<UUID>()
    private var discardPendingEditsForTeardown = false
    private var departureDraftFlush: (id: UUID, webViewID: ObjectIdentifier?, projectID: String?, studioGeneration: UInt64, task: Task<Bool, Never>)?
    private var activePreviewToken: UUID?
    private var hasLoaded = false
    private var pendingClone: CatalogItem?
    private var pendingCloneScore: PersonalScore?
    private var pendingImportURL: URL?
    private var pendingProjectID: String?
    private var pendingOpenProject: StudioProject?
    private var lyricDrafts: [String: NativeStudioLyricsDraftEntry] = [:]

    init(contentRoot: URL, personalStore: PersonalStore, onOpenPractice: @escaping (String) -> Void, onPersonalDataChanged: @escaping () -> Void, onStudioFileConsumed: @escaping () -> Void = {}, cloneFrom: CatalogItem? = nil, cloneFromScore: PersonalScore? = nil, importURL: URL? = nil, projectID: String? = nil, openProject: StudioProject? = nil) {
        self.contentRoot = contentRoot
        self.personalStore = personalStore
        self.onOpenPractice = onOpenPractice
        self.onPersonalDataChanged = onPersonalDataChanged
        self.onStudioFileConsumed = onStudioFileConsumed
        pendingClone = cloneFrom
        pendingCloneScore = cloneFromScore
        pendingImportURL = importURL
        pendingProjectID = projectID
        pendingOpenProject = openProject
    }

    func connect(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        if self.webView != nil {
            // A replaced view may never call back. Retire its queue and command IDs so
            // the new view cannot inherit an indefinitely busy editor state.
            let wasReplacingProject = isPreparingForProjectReplacement
            invalidatePendingOperations()
            pendingEditorCommandIDs.removeAll()
            projectOpenRequestGeneration &+= 1
            isPreparingForProjectReplacement = false
            if wasReplacingProject { isBusy = false }
        }
        invalidatePreview(releaseAudioFocus: true)
        if let pending = departureDraftFlush {
            pending.task.cancel()
            departureDraftFlush = nil
        }
        self.webView = webView
        isPreparingForWebViewTeardown = false
        discardPendingEditsForTeardown = false
        isBooted = false
    }

    func disconnect(_ webView: WKWebView, forceDiscardPending: Bool = false) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        if departureDraftFlush?.webViewID == webViewID {
            departureDraftFlush?.task.cancel()
            departureDraftFlush = nil
        }
        guard self.webView === webView else { return true }
        let hasPendingEdits = applyingOperation || !pendingOperations.isEmpty || !pendingEditorCommandIDs.isEmpty
        guard !hasPendingEdits || forceDiscardPending || discardPendingEditsForTeardown else {
            status = "工坊仍有编辑请求未完成；页面继续保留。"
            return false
        }
        if hasPendingEdits {
            invalidatePendingOperations()
            pendingEditorCommandIDs.removeAll()
            if !discardPendingEditsForTeardown {
                status = "关闭等待超时；未确认的编辑请求已结束。"
            }
        }
        if isPreparingForProjectReplacement {
            projectOpenRequestGeneration &+= 1
            isPreparingForProjectReplacement = false
            isBusy = false
            if !discardPendingEditsForTeardown {
                status = "关闭时已取消尚未完成的工程切换；已保留当前草稿。"
            }
        }
        invalidatePreview(releaseAudioFocus: false)
        isPlaying = false
        NativePlayerAudioFocus.release(self)
        isPreparingForWebViewTeardown = false
        discardPendingEditsForTeardown = false
        self.webView = nil
        isBooted = false
        return true
    }

    func prepareForWebViewTeardown(_ webView: WKWebView) async -> Bool {
        guard self.webView === webView else { return true }
        isPreparingForWebViewTeardown = true
        pausePlayback()

        let webViewID = ObjectIdentifier(webView)
        let deadline = DispatchTime.now().uptimeNanoseconds + 20_000_000_000
        let task: Task<Bool, Never>
        if let pending = departureDraftFlush,
           pending.webViewID == webViewID,
           pending.projectID == project?.id,
           pending.studioGeneration == studioGeneration {
            task = pending.task
        } else {
            if let pending = departureDraftFlush { pending.task.cancel() }
            task = startDepartureDraftFlush(webView: webView, deadline: deadline).task
        }

        let result = await awaitTask(task, until: deadline)
        guard self.webView === webView else { return true }
        if result == true { return true }

        task.cancel()
        let fallback = await persistLastConfirmedDraft(until: deadline)
        guard self.webView === webView else { return true }
        discardPendingEditsForTeardown = true
        if let record = departureDraftFlush, record.webViewID == webViewID {
            departureDraftFlush = nil
        }
        switch fallback {
        case .success:
            status = "编辑排空超时；最后确认的草稿已保留，未确认的编辑请求不会继续应用。"
        case .failure(let error):
            status = "编辑排空超时，且最后确认的草稿写入失败：\(error.localizedDescription)；将结束未确认的编辑请求。"
        }
        return true
    }

    func loadInitial() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        didLoadInitialDataSuccessfully = false
        do {
            let snapshot = try await personalStore.snapshot()
            let savedLyricsDrafts = try await draftIO.loadLyricsDrafts()
            lyricDrafts = Dictionary(savedLyricsDrafts.map { (lyricsDraftKey(projectID: $0.projectID, trackID: $0.trackID), $0) }, uniquingKeysWith: { _, newer in newer })
            personalRevision = snapshot.revision
            savedProjects = snapshot.projects.sorted { $0.updatedAt > $1.updatedAt }
            projectVersions = Dictionary(snapshot.projects.map { ($0.id, $0.updatedAt) }, uniquingKeysWith: { _, newest in newest })
            try await reloadDraftIndex()
            didLoadInitialDataSuccessfully = true
            if let pendingImportURL {
                self.pendingImportURL = nil
                openStudioFile(pendingImportURL)
            } else if let pendingClone {
                self.pendingClone = nil
                await cloneFromCatalog(pendingClone)
            } else if let pendingCloneScore {
                self.pendingCloneScore = nil
                await cloneFromPersonalScore(pendingCloneScore)
            } else if let pendingOpenProject {
                self.pendingOpenProject = nil
                openSavedProject(pendingOpenProject)
            } else if let pendingProjectID,
                      let exact = savedProjects.first(where: { $0.id == pendingProjectID }) {
                self.pendingProjectID = nil
                openSavedProject(exact)
            } else if let missingProjectID = pendingProjectID {
                self.pendingProjectID = nil
                status = "找不到指定工程：\(missingProjectID)"
            } else if let first = savedProjects.first {
                openSavedProject(first)
            } else {
                status = "创建工程，或导入 Guitar Pro、MusicXML、AlphaTex、IBE 与工坊 JSON。"
            }
        } catch {
            didLoadInitialDataSuccessfully = false
            status = "读取本地工程失败：\(error.localizedDescription)"
        }
    }

    func receive(_ message: [String: Any], from webView: WKWebView) {
        guard self.webView === webView else { return }
        guard let type = message["type"] as? String else { return }
        switch type {
        case "booted":
            isBooted = true
            searchShortcuts()
            if let project { sendProjectToCanvas(project) }
        case "ready", "loaded":
            engineError = nil
            if let tick = message["endTime"] as? NSNumber { playbackPosition.update(endTick: tick.doubleValue) }
            if let project { status = "\(project.bars.count) 小节 · \(project.tracks.count) 音轨 · \(isDirty ? "未保存草稿" : "已加载")" }
        case "renderError": engineError = message["message"] as? String
        case "cursor":
            if let value = message["cursor"] as? [String: Any], let decoded = decodeCursor(value) {
                let track = min(decoded.trackIndex, max(0, (project?.tracks.count ?? 1) - 1))
                if cursor != decoded { cursor = decoded }
                if selectedTrack != track { selectedTrack = track }
            }
        case "playedBeat":
            if let bar = message["barIndex"] as? Int, let beat = message["beatIndex"] as? Int {
                var nextCursor = cursor
                nextCursor.barIndex = min(max(0, bar), max(0, (project?.bars.count ?? 1) - 1))
                nextCursor.beatIndex = max(0, beat)
                if cursor != nextCursor { cursor = nextCursor }
            }
        case "playback":
            let nextIsPlaying = (message["isPlaying"] as? Bool) == true
            if isPlaying != nextIsPlaying { isPlaying = nextIsPlaying }
            if !nextIsPlaying, activePreviewToken == nil { NativePlayerAudioFocus.release(self) }
        case "position":
            playbackPosition.update(
                currentTick: (message["currentTime"] as? NSNumber)?.doubleValue,
                endTick: (message["endTime"] as? NSNumber)?.doubleValue
            )
        case "shortcut": handleShortcut(message)
        default: break
        }
    }

    func createProject(instrument: String) {
        guard isBooted else { status = "工坊引擎正在启动。"; return }
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        let startingStudioGeneration = studioGeneration
        Task { @MainActor in
            guard await beginProjectReplacement(requestGeneration: requestGeneration) else { return }
            callJavaScript("return JSON.stringify(window.NativeStudioCore.createBlank(instrument))", arguments: ["instrument": instrument]) { [weak self] result in
                guard let self else { return }
                Task { @MainActor in
                    defer { self.finishProjectReplacement(requestGeneration: requestGeneration) }
                    guard requestGeneration == self.projectOpenRequestGeneration,
                          startingStudioGeneration == self.studioGeneration else { return }
                    guard case .success(let value) = result, let json = value as? String,
                          let project = Self.decodeProject(json) else {
                        self.status = "无法建立空白工程。"
                        return
                    }
                    self.install(project, sourceBytes: nil, fileName: "", linkedScoreID: nil, warnings: [])
                    if let installed = self.project { self.enqueueProjectSave(installed, revision: self.contentRevision) }
                    self.status = "已建立\(Self.instrumentLabel(instrument))工程。输入 0–24 品位，使用原谱拍号、时值和技巧工具完成编曲。"
                }
            }
        }
    }

    func cloneFromCatalog(_ item: CatalogItem) async {
        guard await waitForEngine() else { status = "工坊引擎未启动，未替换当前工程。"; return }
        guard let reference = item.scoreURL else { status = "这首曲目没有可改编的原谱文件。"; return }
        do {
            let url = try AppPaths.resolve(reference: reference, contentRoot: contentRoot)
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let sourceID = "library:\(item.id):\(Self.sha256(bytes))"
            await importBytes(bytes, fileName: "\(item.title).\(item.format)", sourceID: sourceID, sourceKind: "library", sourceTitle: item.title, sourceFormat: item.format, persistAsOriginal: true)
        } catch {
            status = "无法从曲库读取原谱：\(error.localizedDescription)"
        }
    }

    func cloneFromPersonalScore(_ score: PersonalScore) async {
        guard await waitForEngine() else { status = "工坊引擎未启动，未替换当前工程。"; return }
        do {
            let snapshot = try await personalStore.snapshot()
            let storedOriginal = score.originalAssetId.flatMap { assetID in
                snapshot.originals.first(where: { $0.assetId == assetID })
            }
            let sourceBytes: Data
            let sourceName: String
            let sourceFormat: String
            let sourceID: String
            let persistAsOriginal: Bool
            if let storedOriginal,
               let asset = try await personalStore.asset(id: storedOriginal.assetId) {
                let namedFormat = URL(fileURLWithPath: storedOriginal.fileName).pathExtension.lowercased()
                sourceBytes = asset.bytes
                sourceName = storedOriginal.fileName
                sourceFormat = namedFormat.isEmpty
                    ? (UTType(mimeType: storedOriginal.mimeType)?.preferredFilenameExtension ?? score.format)
                    : namedFormat
                sourceID = storedOriginal.id
                persistAsOriginal = false
            } else if let assetID = score.assetId,
                      let playableAsset = try await personalStore.asset(id: assetID) {
                // Without a named original reference, use the score's playable asset and give it a
                // distinct reference ID so a missing/stale original link is never overwritten.
                let fallbackFormat = score.format.lowercased().isEmpty ? "ibe" : score.format.lowercased()
                sourceBytes = playableAsset.bytes
                sourceName = score.title + "." + fallbackFormat
                sourceFormat = URL(fileURLWithPath: sourceName).pathExtension
                sourceID = "studio-playable-import:\(UUID().uuidString)"
                persistAsOriginal = true
            } else {
                status = "个人原谱与可播放附件均缺失，无法建立改编副本。"; return
            }
            let importedAssetID = Self.sha256(sourceBytes)
            let revisionBeforeImport = contentRevision
            await importBytes(sourceBytes, fileName: sourceName, sourceID: sourceID, sourceKind: "file", sourceTitle: score.title, sourceFormat: sourceFormat, persistAsOriginal: persistAsOriginal) { [weak self] in
                guard let self, self.contentRevision > revisionBeforeImport,
                      var project = self.project, project.source?.id == sourceID else { return }
                let revisionNote = "来源曲谱 revision：\(score.revision)；来源 ID：\(score.id)；原件资产：\(importedAssetID)。"
                project.importWarnings = Array(Set((project.importWarnings ?? []) + [revisionNote])).sorted()
                self.conversionWarnings = project.importWarnings ?? []
                self.recordProjectMutation(project, status: "已加入来源记录 · 正在自动保存")
            }
        } catch { status = "载入个人原谱失败：\(error.localizedDescription)" }
    }

    func importFromPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["ibe", "gp", "gp3", "gp4", "gp5", "gp6", "gp7", "gp8", "gpx", "musicxml", "xml", "tex", "alphatex", "json"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.openStudioFile(url) }
        }
    }

    func openStudioFile(_ url: URL) {
        Task { @MainActor in
            do {
                guard await waitForEngine() else { status = "工坊引擎未启动；原件未导入。"; onStudioFileConsumed(); return }
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= 30 * 1_024 * 1_024 else {
                    status = "原件为空或超过 30 MiB，未导入。"; onStudioFileConsumed(); return
                }
                let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                await importBytes(bytes, fileName: url.lastPathComponent, sourceID: UUID().uuidString, sourceKind: "file", sourceTitle: url.deletingPathExtension().lastPathComponent, sourceFormat: url.pathExtension.lowercased(), persistAsOriginal: true) { [weak self] in self?.onStudioFileConsumed() }
            } catch { status = "读取原件失败：\(error.localizedDescription)"; onStudioFileConsumed() }
        }
    }

    private func importBytes(_ bytes: Data, fileName: String, sourceID: String, sourceKind: String, sourceTitle: String, sourceFormat: String, persistAsOriginal: Bool, onComplete: (() -> Void)? = nil) async {
        guard isBooted else { status = "工坊引擎尚未就绪。"; onComplete?(); return }
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        guard await beginProjectReplacement(requestGeneration: requestGeneration) else {
            onComplete?()
            return
        }
        let completeRequest: () -> Void = { [weak self] in
            self?.finishProjectReplacement(requestGeneration: requestGeneration)
            onComplete?()
        }
        isBusy = true
        status = "正在解码原件并建立可编辑副本…"
        let base64 = bytes.base64EncodedString()
        callJavaScript("return await window.NativeStudio.importBytes(base64, fileName, sourceId)", arguments: ["base64": base64, "fileName": fileName, "sourceId": sourceID]) { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard case .success(let value) = result, let json = value as? String,
                      let data = json.data(using: .utf8),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.isBusy = false
                    self.status = Self.messageFromImport(result) ?? "导入解析失败，原有工程仍保留。"
                    completeRequest()
                    return
                }
                if let importError = root["__studioImportError"] as? String, !importError.isEmpty {
                    self.isBusy = false
                    self.status = "导入失败：\(importError)"
                    completeRequest()
                    return
                }
                guard let projectJSON = try? JSONSerialization.data(withJSONObject: (root["project"] as? [String: Any]) ?? [:]),
                      var imported = try? JSONDecoder().decode(StudioProject.self, from: projectJSON) else {
                    self.isBusy = false
                    self.status = "导入解析失败，原有工程仍保留。"
                    completeRequest()
                    return
                }
                let warnings = root["warnings"] as? [String] ?? imported.importWarnings ?? []
                imported.source = StudioSource(kind: sourceKind, id: sourceID, fileName: fileName, format: sourceFormat, title: sourceTitle)
                imported.importWarnings = warnings
                imported.updatedAt = Self.nowMilliseconds()
                if persistAsOriginal {
                    self.persistImportedOriginalProject(imported, sourceBytes: bytes, fileName: fileName, sourceFormat: sourceFormat, warnings: warnings, requestGeneration: requestGeneration, onComplete: completeRequest)
                } else {
                    await self.waitForProjectSaves()
                    guard requestGeneration == self.projectOpenRequestGeneration else {
                        self.isBusy = false
                        completeRequest()
                        return
                    }
                    self.isBusy = false
                    self.install(imported, sourceBytes: nil, fileName: "", linkedScoreID: nil, warnings: warnings)
                    self.status = warnings.isEmpty ? "已载入个人原谱的可编辑副本。" : "已载入可编辑副本。请检查下方 \(warnings.count) 条转换说明。"
                    completeRequest()
                }
            }
        }
    }

    private func waitForEngine() async -> Bool {
        for _ in 0..<200 {
            if isBooted { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return isBooted
    }

    private func persistImportedOriginalProject(_ imported: StudioProject, sourceBytes: Data, fileName: String, sourceFormat: String, warnings: [String], requestGeneration: UInt64, onComplete: (() -> Void)?) {
        status = "正在把原文件和可编辑工程保存到个人资料…"
        Task { @MainActor in
            do {
                await waitForProjectSaves()
                guard requestGeneration == projectOpenRequestGeneration else {
                    status = "工程已变化，导入结果未替换当前工程。"
                    isBusy = false
                    onComplete?()
                    return
                }
                let before = try await personalStore.snapshot()
                let mimeType = UTType(filenameExtension: sourceFormat)?.preferredMIMEType ?? "application/octet-stream"
                let assetID = Self.sha256(sourceBytes)
                let original = OriginalReference(id: imported.source?.id ?? UUID().uuidString, fileName: fileName, mimeType: mimeType, assetId: assetID, savedAt: Self.nowMilliseconds())
                let expectedProjectVersion = before.projects.first(where: { $0.id == imported.id })?.updatedAt
                let saved = try await personalStore.saveStudioProject(
                    imported,
                    expectedUpdatedAt: expectedProjectVersion,
                    original: original,
                    originalAsset: PersonalAsset(id: assetID, bytes: sourceBytes, mimeType: mimeType)
                )
                guard requestGeneration == projectOpenRequestGeneration else {
                    status = "导入数据已保存，但当前工程已变化；未替换当前编辑内容。"
                    isBusy = false
                    onComplete?()
                    return
                }
                personalRevision = saved.revision
                savedProjects = saved.projects.sorted { $0.updatedAt > $1.updatedAt }
                let linkedScoreID = Self.linkedProjectScore(in: saved, projectID: imported.id)?.id
                install(imported, sourceBytes: sourceBytes, fileName: fileName, linkedScoreID: linkedScoreID, warnings: warnings)
                isDirty = false
                persistedContentRevisions[imported.id] = contentRevision
                removeDraftFile(id: imported.id)
                status = warnings.isEmpty
                    ? "原件与工坊工程已保存；点击“更新练习副本”后才会生成可播放版本。"
                    : "原件与工坊工程已保存。请核对 \(warnings.count) 条转换说明。"
                onPersonalDataChanged()
            } catch {
                status = "导入保存失败，当前工程未被替换；原文件仍在原位置，可重试：\(error.localizedDescription)"
            }
            isBusy = false
            onComplete?()
        }
    }

    func openSavedProject(_ value: StudioProject) {
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        Task { @MainActor in
            guard await beginProjectReplacement(requestGeneration: requestGeneration) else { return }
            defer { finishProjectReplacement(requestGeneration: requestGeneration) }
            do {
                guard requestGeneration == projectOpenRequestGeneration else { return }
                let snapshot = try await personalStore.snapshot()
                guard requestGeneration == projectOpenRequestGeneration else { return }
                guard let fresh = snapshot.projects.first(where: { $0.id == value.id }) else { status = "这个工程已被删除。"; return }
                personalRevision = snapshot.revision
                savedUpdatedAt = fresh.updatedAt
                projectVersions[fresh.id] = fresh.updatedAt
                linkedPracticeScoreID = Self.linkedProjectScore(in: snapshot, projectID: fresh.id)?.id
                install(fresh, sourceBytes: nil, fileName: fresh.source?.fileName ?? "", linkedScoreID: linkedPracticeScoreID, warnings: fresh.importWarnings ?? [])
                isDirty = false
                persistedContentRevisions[fresh.id] = contentRevision
                status = "已载入草稿箱工程：\(fresh.title)"
            } catch { status = "载入工程失败：\(error.localizedDescription)" }
        }
    }

    func openProject(id: String) {
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        Task { @MainActor in
            do {
                let snapshot = try await personalStore.snapshot()
                guard requestGeneration == projectOpenRequestGeneration else { return }
                guard let exact = snapshot.projects.first(where: { $0.id == id }) else {
                    status = "找不到指定工程：\(id)"; return
                }
                personalRevision = snapshot.revision
                savedProjects = snapshot.projects.sorted { $0.updatedAt > $1.updatedAt }
                openSavedProject(exact)
            } catch { status = "读取指定工程失败：\(error.localizedDescription)" }
        }
    }

    func openDraft(_ draft: StudioProject) {
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        let startingDraftGeneration = draftGenerationByProject[draft.id] ?? 0
        Task { @MainActor in
            guard await beginProjectReplacement(requestGeneration: requestGeneration) else { return }
            defer { finishProjectReplacement(requestGeneration: requestGeneration) }
            guard requestGeneration == projectOpenRequestGeneration,
                  startingDraftGeneration == (draftGenerationByProject[draft.id] ?? 0) else { return }
            guard let diskDraft = await draftIO.loadProjectDraft(id: draft.id) else {
                guard requestGeneration == projectOpenRequestGeneration,
                      startingDraftGeneration == (draftGenerationByProject[draft.id] ?? 0) else { return }
                status = "草稿已删除或损坏，未替换当前工程。"
                return
            }
            guard requestGeneration == projectOpenRequestGeneration,
                  startingDraftGeneration == (draftGenerationByProject[draft.id] ?? 0) else { return }
            var latestDraft = diskDraft.updatedAt >= draft.updatedAt ? diskDraft : draft
            if let current = project, current.id == draft.id, current.updatedAt >= latestDraft.updatedAt {
                latestDraft = current
            }
            install(latestDraft, sourceBytes: nil, fileName: latestDraft.source?.fileName ?? "", linkedScoreID: nil, warnings: latestDraft.importWarnings ?? [])
            isDirty = true
            status = "已从本地草稿箱恢复；保存时会做版本比较。"
        }
    }

    func openDraftFile(_ url: URL) {
        projectOpenRequestGeneration &+= 1
        let requestGeneration = projectOpenRequestGeneration
        Task { @MainActor in
            guard await beginProjectReplacement(requestGeneration: requestGeneration) else { return }
            defer { finishProjectReplacement(requestGeneration: requestGeneration) }
            guard let draft = await draftIO.loadProject(at: url) else {
                guard requestGeneration == projectOpenRequestGeneration else { return }
                status = "草稿损坏，未替换当前工程。"
                return
            }
            guard requestGeneration == projectOpenRequestGeneration else { return }
            install(draft, sourceBytes: nil, fileName: draft.source?.fileName ?? "", linkedScoreID: nil, warnings: draft.importWarnings ?? [])
            isDirty = true
            status = "已从本地草稿箱恢复；保存时会做版本比较。"
        }
    }

    private func install(_ value: StudioProject, sourceBytes: Data?, fileName: String, linkedScoreID: String?, warnings: [String]) {
        pausePlayback()
        invalidatePendingOperations()
        studioGeneration &+= 1
        draftGenerationByProject[value.id, default: 0] &+= 1
        project = value
        sourceOriginalBytes = sourceBytes
        sourceFileName = fileName
        linkedPracticeScoreID = linkedScoreID
        savedUpdatedAt = savedProjects.first(where: { $0.id == value.id })?.updatedAt
        if let savedUpdatedAt { projectVersions[value.id] = savedUpdatedAt }
        else { projectVersions.removeValue(forKey: value.id) }
        conversionWarnings = warnings
        selectedTrack = 0
        cursor = StudioCursorPosition(trackIndex: 0, barIndex: 0, beatIndex: 0, stringIndex: 1)
        undoStack.removeAll(); redoStack.removeAll(); pendingOperations.removeAll()
        isDirty = true
        contentRevision += 1
        sendProjectToCanvas(value)
        persistLocalDraft(value)
        lyricDraft = ""
    }

    func apply(_ operation: String, arguments: [String: Any] = [:]) {
        enqueueOperation(operation, arguments: arguments)
    }

    func insertBarAtCursorAndAdvance() {
        guard let project, project.bars.indices.contains(cursor.barIndex) else {
            status = "请先选择有效的小节。"
            return
        }
        let origin = cursor
        enqueueOperation(
            "insertBar",
            arguments: ["afterBarIndex": origin.barIndex],
            cursorAdvance: NativeStudioCursorAdvance(
                projectID: project.id,
                operationGeneration: operationGeneration,
                origin: origin,
                targetBarIndex: origin.barIndex + 1
            )
        )
    }

    private func enqueueOperation(
        _ operation: String,
        arguments: [String: Any] = [:],
        cursorAdvance: NativeStudioCursorAdvance? = nil
    ) {
        guard !isPreparingForWebViewTeardown, !isPreparingForProjectReplacement else {
            status = isPreparingForWebViewTeardown ? "工坊正在关闭；当前编辑队列已锁定。" : "工程切换正在完成；当前编辑队列已锁定。"
            return
        }
        guard project != nil else { status = "请先新建或导入工程。"; return }
        let defaults: [String: Any] = [
            "trackIndex": selectedTrack,
            "barIndex": cursor.barIndex,
            "beatIndex": cursor.beatIndex,
            "stringIndex": cursor.stringIndex,
        ]
        pendingOperations.append(NativeStudioPendingOperation(
            operation: operation,
            arguments: arguments.merging(defaults) { existing, _ in existing },
            cursorAdvance: cursorAdvance
        ))
        drainOperations()
    }

    private func drainOperations() {
        guard !applyingOperation, let sourceWebView = webView,
              let pending = pendingOperations.first,
              let project, let object = Self.jsObject(project) else { return }
        applyingOperation = true
        let generation = operationGeneration
        let sourceWebViewID = ObjectIdentifier(sourceWebView)
        let expectedStudioGeneration = studioGeneration
        let projectID = project.id
        callJavaScript("return JSON.stringify(window.NativeStudioCore.applyOperation(project, operation, args))", arguments: ["project": object, "operation": pending.operation, "args": pending.arguments]) { [weak self] result in
            guard let self else { return }
            guard self.webView.map(ObjectIdentifier.init) == sourceWebViewID,
                  self.studioGeneration == expectedStudioGeneration,
                  self.operationGeneration == generation,
                  self.project?.id == projectID else { return }
            guard !self.pendingOperations.isEmpty else { self.applyingOperation = false; return }
            self.applyingOperation = false
            self.pendingOperations.removeFirst()
            guard case .success(let value) = result, let json = value as? String, let next = Self.decodeProject(json) else {
                self.status = "编辑未应用；当前谱面与本地草稿仍保留。"
                self.drainOperations(); return
            }
            if next != project {
                self.undoStack = Array((self.undoStack + [project]).suffix(100))
                self.redoStack.removeAll()
                self.recordProjectMutation(next, status: "未保存更改 · \(next.title)")
                if let advance = pending.cursorAdvance,
                   self.operationGeneration == advance.operationGeneration,
                   self.project?.id == advance.projectID,
                   self.cursor == advance.origin,
                   self.project?.bars.indices.contains(advance.targetBarIndex) == true {
                    self.setCursor(bar: advance.targetBarIndex, beat: 0)
                }
            }
            self.drainOperations()
        }
    }

    func undo() {
        guard !isPreparingForWebViewTeardown, !isPreparingForProjectReplacement else { return }
        guard let previous = undoStack.popLast(), let current = project else { return }
        invalidatePendingOperations()
        redoStack = Array((redoStack + [current]).suffix(100))
        recordProjectMutation(previous, status: "已撤销 · 正在自动保存")
    }

    func redo() {
        guard !isPreparingForWebViewTeardown, !isPreparingForProjectReplacement else { return }
        guard let next = redoStack.popLast(), let current = project else { return }
        invalidatePendingOperations()
        undoStack = Array((undoStack + [current]).suffix(100))
        recordProjectMutation(next, status: "已重做 · 正在自动保存")
    }

    func save() {
        guard let project else { status = "没有可保存的工程。"; return }
        let expectedProjectID = project.id
        let expectedGeneration = studioGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForEditorIdle() else {
                self.status = "编辑仍在应用；当前没有启动手动保存，请稍后重试。"
                return
            }
            guard self.studioGeneration == expectedGeneration,
                  let latest = self.project, latest.id == expectedProjectID else {
                self.status = "工程已切换；当前没有启动手动保存。"
                return
            }
            self.enqueueProjectSave(latest, revision: self.contentRevision, manual: true)
        }
    }

    func reloadLatestAfterSavingDraft() async {
        guard let project else { return }
        let expectedProjectID = project.id
        let expectedGeneration = studioGeneration
        guard await waitForEditorIdle(),
              studioGeneration == expectedGeneration,
              let latest = self.project, latest.id == expectedProjectID else {
            status = "编辑仍在应用或工程已切换；草稿仍保留。"
            return
        }
        if isDirty {
            let result = await persistLocalDraftAndWait(latest)
            guard case .success = result else {
                status = "当前草稿未能写入，未重新载入工程。"
                return
            }
        }
        do {
            await waitForProjectSaves()
            guard studioGeneration == expectedGeneration, self.project?.id == expectedProjectID else {
                status = "工程已切换；草稿仍保留。"
                return
            }
            let snapshot = try await personalStore.snapshot()
            personalRevision = snapshot.revision
            savedProjects = snapshot.projects.sorted { $0.updatedAt > $1.updatedAt }
            if let saved = snapshot.projects.first(where: { $0.id == expectedProjectID }) { openSavedProject(saved) }
            else { status = "最新快照中没有此工程。草稿仍保留。" }
        } catch { status = "重新读取失败：\(error.localizedDescription)；草稿仍保留。" }
    }

    func requestDeleteProject(_ id: String) { pendingDeleteID = id; showingDeleteAlert = true }

    func deleteProjectConfirmed() {
        guard let id = pendingDeleteID else { return }
        Task { @MainActor in
            do {
                await waitForProjectSaves()
                let snapshot = try await personalStore.snapshot()
                let selected = snapshot.projects.first(where: { $0.id == id })
                let result = try await personalStore.deleteProject(id: id, expectedUpdatedAt: selected?.updatedAt, expectedRevision: snapshot.revision)
                personalRevision = result.revision
                savedProjects = result.projects.sorted { $0.updatedAt > $1.updatedAt }
                projectVersions.removeValue(forKey: id)
                persistedContentRevisions.removeValue(forKey: id)
                if project?.id == id { project = nil; isDirty = false; linkedPracticeScoreID = nil; status = "工程已删除。" }
                onPersonalDataChanged()
            } catch { status = "删除失败：\(error.localizedDescription)" }
        }
    }

    func deleteLocalDraft(_ id: String) {
        removeDraftFile(id: id)
        if project?.id == id { isDirty = false }
        status = "已删除本地草稿文件。"
    }

    func export(format: String) {
        guard let project, isBooted else { status = "谱面尚未准备好导出。"; return }
        let projectID = project.id
        let generation = studioGeneration
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForEditorIdle(),
                  self.studioGeneration == generation,
                  let latest = self.project, latest.id == projectID,
                  let object = Self.jsObject(latest) else {
                self.isBusy = false
                self.status = "编辑仍在应用，或工程已切换；请等待后重新导出。"
                return
            }
            self.callJavaScript("return await window.NativeStudio.exportBytes(project, format)", arguments: ["project": object, "format": format]) { [weak self] result in
                guard let self else { return }
                self.isBusy = false
                guard self.studioGeneration == generation, self.project?.id == projectID else {
                    self.status = "工程已切换；导出结果未打开。"
                    return
                }
                guard case .success(let value) = result, let base64 = value as? String, let bytes = Data(base64Encoded: base64) else {
                    self.status = "导出失败：\(Self.resultMessage(result))"; return
                }
                let ext: String = format == "tex" ? "tex" : format
                self.saveDataPanel(bytes, extension: ext, mime: format == "json" ? .json : (format == "tex" ? .plainText : .data))
            }
        }
    }

    func exportPDF() {
        guard webView != nil, let project, isBooted, !isBusy else { return }
        let projectID = project.id
        let expectedGeneration = studioGeneration
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForEditorIdle(), self.studioGeneration == expectedGeneration,
                  let latest = self.project, latest.id == projectID,
                  let object = Self.jsObject(latest) else {
                self.isBusy = false
                self.status = "编辑仍在应用，或工程已切换；请等待后重新导出。"
                return
            }
            self.callJavaScript("return await window.NativeStudio.exportPdfPages(project)", arguments: ["project": object]) { [weak self] result in
                guard let self else { return }
                guard self.studioGeneration == expectedGeneration, self.project?.id == projectID else {
                    self.isBusy = false
                    self.status = "工程已切换；PDF 导出结果未打开。"
                    return
                }
                guard case .success(let value) = result,
                      let json = value as? String,
                      let jsonData = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let pages = object["pages"] as? [String],
                      let width = object["widthPoints"] as? Double,
                      let height = object["heightPoints"] as? Double else {
                    self.isBusy = false
                    self.status = "分页 PDF 导出失败：\(Self.resultMessage(result))"
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = Self.makePDF(pageImages: pages, width: width, height: height)
                    DispatchQueue.main.async {
                        self.isBusy = false
                        guard self.studioGeneration == expectedGeneration, self.project?.id == projectID else {
                            self.status = "工程已切换；PDF 导出结果未打开。"
                            return
                        }
                        guard let data else { self.status = "分页 PDF 页面图像无效，未生成文件。"; return }
                        self.saveDataPanel(data, extension: "pdf", mime: .pdf)
                    }
                }
            }
        }
    }

    func exportPNG() {
        guard webView != nil, let project, isBooted, !isBusy else { return }
        let projectID = project.id
        let expectedGeneration = studioGeneration
        isBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForEditorIdle(), self.studioGeneration == expectedGeneration,
                  let latest = self.project, latest.id == projectID,
                  let object = Self.jsObject(latest) else {
                self.isBusy = false
                self.status = "编辑仍在应用，或工程已切换；请等待后重新导出。"
                return
            }
            self.callJavaScript("return await window.NativeStudio.exportPngData(project)", arguments: ["project": object]) { [weak self] result in
                guard let self else { return }
                self.isBusy = false
                guard self.studioGeneration == expectedGeneration, self.project?.id == projectID else {
                    self.status = "工程已切换；PNG 导出结果未打开。"
                    return
                }
                guard case .success(let value) = result,
                      let base64 = value as? String,
                      let data = Data(base64Encoded: base64),
                      data.starts(with: [0x89, 0x50, 0x4E, 0x47]) else {
                    self.status = "PNG 导出失败：\(Self.resultMessage(result))"
                    return
                }
                self.saveDataPanel(data, extension: "png", mime: .data)
            }
        }
    }

    private func waitForEditorIdle() async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 15_000_000_000
        while isPreparingForProjectReplacement || isPreparingForWebViewTeardown ||
              applyingOperation || !pendingOperations.isEmpty || !pendingEditorCommandIDs.isEmpty {
            if Task.isCancelled || DispatchTime.now().uptimeNanoseconds >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func waitForPendingEditorCommands() async -> Bool {
        await waitForEditorWork(until: DispatchTime.now().uptimeNanoseconds + 15_000_000_000)
    }

    private func waitForEditorWork(until deadline: UInt64) async -> Bool {
        while applyingOperation || !pendingOperations.isEmpty || !pendingEditorCommandIDs.isEmpty {
            if Task.isCancelled || DispatchTime.now().uptimeNanoseconds >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func waitForEditorWorkDuringDeparture(until deadline: UInt64) async -> Bool {
        while isPreparingForProjectReplacement || applyingOperation || !pendingOperations.isEmpty || !pendingEditorCommandIDs.isEmpty {
            if Task.isCancelled || DispatchTime.now().uptimeNanoseconds >= deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    private func beginProjectReplacement(requestGeneration: UInt64) async -> Bool {
        guard requestGeneration == projectOpenRequestGeneration else { return false }
        guard !isPreparingForWebViewTeardown else {
            status = "工坊正在关闭；当前没有切换工程。"
            return false
        }
        isPreparingForProjectReplacement = true
        let expectedStudioGeneration = studioGeneration
        let expectedProjectID = project?.id

        guard await waitForPendingEditorCommands() else {
            cancelProjectReplacement(requestGeneration: requestGeneration, status: "编辑仍在应用；工程未切换，请稍后重试。")
            return false
        }
        guard projectReplacementIsCurrent(requestGeneration, generation: expectedStudioGeneration, projectID: expectedProjectID) else {
            cancelProjectReplacement(requestGeneration: requestGeneration, status: "工程已变化；未执行这次切换。")
            return false
        }

        if let latest = project, isDirty {
            let revision = contentRevision
            let result = await persistLocalDraftAndWait(latest)
            guard projectReplacementIsCurrent(requestGeneration, generation: expectedStudioGeneration, projectID: expectedProjectID),
                  contentRevision == revision else {
                cancelProjectReplacement(requestGeneration: requestGeneration, status: "工程已变化；未执行这次切换。")
                return false
            }
            guard case .success = result else {
                cancelProjectReplacement(requestGeneration: requestGeneration, status: "当前草稿未能写入，工程未切换。")
                return false
            }
        }

        flushPendingAutomaticSaves()
        await waitForProjectSaves()
        guard projectReplacementIsCurrent(requestGeneration, generation: expectedStudioGeneration, projectID: expectedProjectID) else {
            cancelProjectReplacement(requestGeneration: requestGeneration, status: "工程已变化；未执行这次切换。")
            return false
        }

        if let latest = project, isDirty {
            let revision = contentRevision
            let result = await persistLocalDraftAndWait(latest)
            guard projectReplacementIsCurrent(requestGeneration, generation: expectedStudioGeneration, projectID: expectedProjectID),
                  contentRevision == revision else {
                cancelProjectReplacement(requestGeneration: requestGeneration, status: "工程已变化；未执行这次切换。")
                return false
            }
            guard case .success = result else {
                cancelProjectReplacement(requestGeneration: requestGeneration, status: "最新草稿未能写入，工程未切换。")
                return false
            }
        }
        return requestGeneration == projectOpenRequestGeneration
    }

    private func projectReplacementIsCurrent(_ requestGeneration: UInt64, generation: UInt64, projectID: String?) -> Bool {
        requestGeneration == projectOpenRequestGeneration &&
        generation == studioGeneration &&
        project?.id == projectID
    }

    private func cancelProjectReplacement(requestGeneration: UInt64, status message: String) {
        guard requestGeneration == projectOpenRequestGeneration else { return }
        isPreparingForProjectReplacement = false
        status = message
    }

    private func finishProjectReplacement(requestGeneration: UInt64) {
        guard requestGeneration == projectOpenRequestGeneration else { return }
        isPreparingForProjectReplacement = false
    }

    private func persistLocalDraftAndWait(_ value: StudioProject, timeoutNanoseconds: UInt64 = 5_000_000_000) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            let gate = NativeStudioAsyncGate<Result<Void, Error>>(continuation)
            gate.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard !Task.isCancelled else { return }
                gate.resume(returning: .failure(NativeStudioWaitError.timedOut))
            }
            persistLocalDraft(value) { result, _ in
                Task { @MainActor in gate.resume(returning: result) }
            }
        }
    }

    private func awaitTask(_ task: Task<Bool, Never>, until deadline: UInt64) async -> Bool? {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadline > now else { task.cancel(); return nil }
        return await withCheckedContinuation { continuation in
            let gate = NativeStudioAsyncGate<Bool?>(continuation)
            gate.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: deadline - now)
                guard !Task.isCancelled else { return }
                task.cancel()
                gate.resume(returning: nil)
            }
            Task { @MainActor in
                gate.resume(returning: await task.value)
            }
        }
    }

    private func persistLastConfirmedDraft(until deadline: UInt64) async -> Result<Void, Error> {
        guard let latest = project, isDirty else { return .success(()) }
        let remaining = deadline > DispatchTime.now().uptimeNanoseconds
            ? deadline - DispatchTime.now().uptimeNanoseconds
            : 0
        guard remaining > 0 else { return .failure(NativeStudioWaitError.timedOut) }
        return await persistLocalDraftAndWait(latest, timeoutNanoseconds: remaining)
    }

    private nonisolated static func makePDF(pageImages: [String], width: Double, height: Double) -> Data? {
        guard !pageImages.isEmpty, width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        for encoded in pageImages {
            guard let bytes = Data(base64Encoded: encoded),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                context.closePDF()
                return nil
            }
            context.beginPDFPage(nil)
            context.draw(image, in: mediaBox)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    func printScore() {
        guard let webView else { return }
        webView.evaluateJavaScript("document.body.classList.add('print-mode')")
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.run()
        webView.evaluateJavaScript("document.body.classList.remove('print-mode')")
    }

    func saveAsPracticeCopy() {
        guard let project else { status = "请先选择工程。"; return }
        guard isBooted else { status = "工程还不能生成可播放副本。"; return }
        let projectID = project.id
        let expectedGeneration = studioGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.waitForEditorIdle(),
                  self.studioGeneration == expectedGeneration,
                  let latest = self.project, latest.id == projectID else {
                self.status = "编辑仍在应用，或工程已切换；练习副本未生成。"
                return
            }
            let expectedContentRevision = self.contentRevision
            let originalBytes = self.sourceOriginalBytes
            let originalName = self.sourceFileName
            let warnings = self.conversionWarnings
            self.isBusy = true
            self.enqueueSerialProjectOperation { [weak self] in
                guard let self else { return }
                let expectedProjectUpdatedAt = self.projectVersions[projectID]
                do {
                    let playable = try await self.exportPlayableBytes(latest)
                    await self.persistPracticeCopy(
                        latest,
                        playableBytes: playable,
                        expectedContentRevision: expectedContentRevision,
                        expectedProjectUpdatedAt: expectedProjectUpdatedAt,
                        originalBytes: originalBytes,
                        originalName: originalName,
                        warnings: warnings
                    )
                } catch {
                    self.isBusy = false
                    self.status = "生成可播放 IBE 失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func persistPracticeCopy(
        _ value: StudioProject,
        playableBytes: Data,
        expectedContentRevision: Int,
        expectedProjectUpdatedAt: Double?,
        originalBytes sourceBytes: Data?,
        originalName sourceName: String,
        warnings: [String]
    ) async {
        do {
            let snapshot = try await personalStore.snapshot()
            guard snapshot.projects.first(where: { $0.id == value.id })?.updatedAt == expectedProjectUpdatedAt else {
                throw PersonalStoreError.recordConflict("工坊工程已在其他页面更新；练习副本未保存，请重新载入后再试。")
            }
            let playableID = Self.sha256(playableBytes)
            let now = Self.nowMilliseconds()
            var persistedProject = value
            persistedProject.updatedAt = max(now, max(value.updatedAt + 1, (expectedProjectUpdatedAt ?? -1) + 1))
            let originalScore = snapshot.scores.first(where: {
                $0.id == value.source?.id || $0.projectId == value.id || ($0.source == "project" && $0.sourceId == value.id)
            })
            let sourceAssetID = originalScore?.originalAssetId ?? originalScore?.assetId
            let existingOriginal = snapshot.originals.first(where: { $0.id == value.source?.id })
                ?? snapshot.originals.first(where: { $0.assetId == sourceAssetID })

            let originalReference: OriginalReference
            let originalAsset: PersonalAsset
            if let sourceBytes {
                let hash = Self.sha256(sourceBytes)
                if let existingOriginal, existingOriginal.assetId == hash {
                    originalReference = existingOriginal
                    originalAsset = PersonalAsset(id: hash, bytes: sourceBytes, mimeType: existingOriginal.mimeType)
                } else {
                    if existingOriginal != nil {
                        throw PersonalStoreError.recordConflict("原件引用已指向其他内容；为避免覆盖原始文件，练习副本未保存。")
                    }
                    let fileName = sourceName.isEmpty ? (value.source?.fileName ?? "\(value.title).json") : sourceName
                    let extensionName = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                    let mimeType = UTType(filenameExtension: extensionName)?.preferredMIMEType ?? "application/octet-stream"
                    let referenceID = value.source?.id ?? "studio-original:\(value.id)"
                    originalReference = OriginalReference(id: referenceID, fileName: fileName, mimeType: mimeType, assetId: hash, savedAt: now)
                    originalAsset = PersonalAsset(id: hash, bytes: sourceBytes, mimeType: mimeType)
                }
            } else if let existingOriginal {
                guard let storedAsset = try await personalStore.asset(id: existingOriginal.assetId) else {
                    throw PersonalStoreError.assetMissing(existingOriginal.assetId)
                }
                originalReference = existingOriginal
                originalAsset = storedAsset
            } else if let sourceAssetID {
                guard let storedAsset = try await personalStore.asset(id: sourceAssetID) else {
                    throw PersonalStoreError.assetMissing(sourceAssetID)
                }
                let fileName = value.source?.fileName ?? "\(value.title).\(originalScore?.format ?? "ibe")"
                let extensionName = URL(fileURLWithPath: fileName).pathExtension.lowercased()
                let mimeType = UTType(filenameExtension: extensionName)?.preferredMIMEType ?? "application/octet-stream"
                originalReference = OriginalReference(
                    id: value.source?.id ?? "studio-original:\(value.id)",
                    fileName: fileName,
                    mimeType: mimeType,
                    assetId: storedAsset.id,
                    savedAt: now
                )
                originalAsset = storedAsset
            } else {
                let bytes = try JSONEncoder().encode(value)
                let hash = Self.sha256(bytes)
                let fileName = "\(value.title).json"
                originalReference = OriginalReference(
                    id: value.source?.id ?? "studio-original:\(value.id)",
                    fileName: fileName,
                    mimeType: "application/json",
                    assetId: hash,
                    savedAt: now
                )
                originalAsset = PersonalAsset(id: hash, bytes: bytes, mimeType: "application/json")
            }

            let practiceScore = PersonalScore(
                id: "project:\(value.id)",
                source: "project",
                sourceId: value.id,
                revision: playableID,
                title: value.title,
                artist: value.artist,
                category: Self.categoryForTracks(value),
                format: "ibe",
                assetId: playableID,
                originalAssetId: originalReference.assetId,
                projectId: value.id,
                warnings: warnings.isEmpty ? nil : warnings,
                createdAt: now,
                updatedAt: persistedProject.updatedAt
            )
            let saved = try await personalStore.saveStudioProject(
                persistedProject,
                expectedUpdatedAt: expectedProjectUpdatedAt,
                original: originalReference,
                originalAsset: originalAsset,
                practiceScore: practiceScore,
                practiceAsset: PersonalAsset(id: playableID, bytes: playableBytes, mimeType: "application/octet-stream"),
                addToPractice: true
            )
            guard let savedPracticeScore = saved.scores.first(where: { $0.projectId == value.id || ($0.source == "project" && $0.sourceId == value.id) }) else {
                throw PersonalStoreError.recordConflict("练习副本已提交，但没有找到关联曲谱记录。")
            }
            personalRevision = saved.revision
            savedProjects = saved.projects.sorted { $0.updatedAt > $1.updatedAt }
            let savedProject = saved.projects.first(where: { $0.id == value.id }) ?? persistedProject
            if let storedVersion = saved.projects.first(where: { $0.id == value.id })?.updatedAt {
                projectVersions[value.id] = storedVersion
                if project?.id == value.id { savedUpdatedAt = storedVersion }
            }
            persistedContentRevisions[value.id] = max(persistedContentRevisions[value.id] ?? Int.min, expectedContentRevision)
            if project?.id == value.id { linkedPracticeScoreID = savedPracticeScore.id }
            isBusy = false
            onPersonalDataChanged()

            if contentRevision == expectedContentRevision, project?.id == value.id {
                project = savedProject
                status = "已更新练习副本；原件保存在个人原件库，可打开播放页开始练习。"
                isDirty = false
                removeDraftFile(id: value.id)
                onOpenPractice(savedPracticeScore.id)
            } else if let latest = project, latest.id == value.id {
                status = "练习副本已更新到提交版本；期间新增的编辑仍保留在本地草稿中。"
                isDirty = true
                persistLocalDraft(latest)
            }
        } catch {
            isBusy = false
            status = "练习副本未完成，原工程和本地草稿均保留：\(error.localizedDescription)"
        }
    }

    private func enqueueProjectSave(_ value: StudioProject, revision: Int, manual: Bool = false) {
        let request = NativeStudioProjectSaveRequest(
            project: value,
            revision: revision,
            manual: manual,
            generation: studioGeneration
        )

        if manual {
            flushPendingAutomaticSaves(startWorker: false)
            if let lastIndex = projectSaveQueue.indices.last,
               case .project(let previous, _) = projectSaveQueue[lastIndex],
               previous.project.id == value.id,
               previous.generation == request.generation,
               !previous.manual,
               previous.revision <= revision {
                projectSaveQueue[lastIndex] = .project(request, deferred: false)
            } else {
                projectSaveQueue.append(.project(request, deferred: false))
            }
        } else {
            let now = DispatchTime.now().uptimeNanoseconds
            var canCoalesce = false
            if let lastIndex = projectSaveQueue.indices.last,
               case .project(let previous, let wasDeferred) = projectSaveQueue[lastIndex],
               !previous.manual,
               previous.project.id == value.id,
               previous.generation == request.generation {
                projectSaveQueue[lastIndex] = .project(request, deferred: wasDeferred)
                canCoalesce = true
                if wasDeferred {
                    automaticSaveFirstQueuedAt = automaticSaveFirstQueuedAt ?? now
                    automaticSaveLastQueuedAt = now
                    scheduleAutomaticSaveFlush()
                }
            }
            if !canCoalesce {
                projectSaveQueue.append(.project(request, deferred: true))
                automaticSaveFirstQueuedAt = automaticSaveFirstQueuedAt ?? now
                automaticSaveLastQueuedAt = now
                scheduleAutomaticSaveFlush()
            }
        }
        startProjectSaveWorkerIfNeeded()
    }

    private func enqueueSerialProjectOperation(_ operation: @escaping @MainActor () async -> Void) {
        flushPendingAutomaticSaves(startWorker: false)
        projectSaveQueue.append(.operation(operation))
        startProjectSaveWorkerIfNeeded()
    }

    private func scheduleAutomaticSaveFlush() {
        guard let firstQueuedAt = automaticSaveFirstQueuedAt,
              let lastQueuedAt = automaticSaveLastQueuedAt else { return }
        automaticSaveDebounceGeneration &+= 1
        let debounceGeneration = automaticSaveDebounceGeneration
        let idleDeadline = lastQueuedAt &+ Self.automaticSaveIdleDelayNanoseconds
        let maximumDeadline = firstQueuedAt &+ Self.automaticSaveMaximumDelayNanoseconds
        let deadline = min(idleDeadline, maximumDeadline)
        let now = DispatchTime.now().uptimeNanoseconds
        let delay = deadline > now ? deadline - now : 0
        automaticSaveDebounceTask?.cancel()
        automaticSaveDebounceTask = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard let self, !Task.isCancelled,
                  debounceGeneration == self.automaticSaveDebounceGeneration else { return }
            self.flushPendingAutomaticSaves()
        }
    }

    private func flushPendingAutomaticSaves(startWorker: Bool = true) {
        automaticSaveDebounceGeneration &+= 1
        automaticSaveDebounceTask?.cancel()
        automaticSaveDebounceTask = nil
        automaticSaveFirstQueuedAt = nil
        automaticSaveLastQueuedAt = nil

        for index in projectSaveQueue.indices {
            if case .project(let request, true) = projectSaveQueue[index] {
                projectSaveQueue[index] = .project(request, deferred: false)
            }
        }
        if startWorker { startProjectSaveWorkerIfNeeded() }
    }

    private func startProjectSaveWorkerIfNeeded() {
        guard projectSaveTail == nil, canStartProjectSaveWorker else { return }
        projectSaveWorkerGeneration &+= 1
        let workerGeneration = projectSaveWorkerGeneration
        projectSaveTail = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainProjectSaveQueue(workerGeneration: workerGeneration)
        }
    }

    private func drainProjectSaveQueue(workerGeneration: UInt64) async {
        while let first = projectSaveQueue.first {
            if case .project(_, true) = first { break }
            let next = projectSaveQueue.removeFirst()
            switch next {
            case .project(let request, _):
                await persistEditedProject(request)
            case .operation(let operation):
                await operation()
            }
        }
        guard workerGeneration == projectSaveWorkerGeneration else { return }
        projectSaveTail = nil
        if canStartProjectSaveWorker { startProjectSaveWorkerIfNeeded() }
    }

    private var canStartProjectSaveWorker: Bool {
        guard let first = projectSaveQueue.first else { return false }
        if case .project(_, true) = first { return false }
        return true
    }

    private func waitForProjectSaves() async {
        while true {
            flushPendingAutomaticSaves()
            guard let worker = projectSaveTail else {
                if projectSaveQueue.isEmpty { return }
                startProjectSaveWorkerIfNeeded()
                continue
            }
            await worker.value
        }
    }

    private func persistEditedProject(_ request: NativeStudioProjectSaveRequest) async {
        let value = request.project
        let revision = request.revision
        let manual = request.manual
        guard request.generation == studioGeneration, project?.id == value.id else { return }
        if (persistedContentRevisions[value.id] ?? Int.min) >= revision {
            if manual, project?.id == value.id, contentRevision == revision {
                isDirty = false
                status = "已保存到本地草稿箱：\(value.title)"
            }
            return
        }

        let expectedUpdatedAt = projectVersions[value.id]
        do {
            let snapshot = try await personalStore.snapshot()
            guard request.generation == studioGeneration, project?.id == value.id else { return }
            guard manual || contentRevision == revision else { return }
            guard snapshot.projects.first(where: { $0.id == value.id })?.updatedAt == expectedUpdatedAt else {
                throw PersonalStoreError.recordConflict("工坊工程已在其他页面更新；本次自动保存未覆盖该版本，请重新载入后再编辑。")
            }
            let linkedScore = Self.linkedProjectScore(in: snapshot, projectID: value.id)
            var persistedProject = value
            persistedProject.updatedAt = max(Self.nowMilliseconds(), max(value.updatedAt + 1, (expectedUpdatedAt ?? -1) + 1))

            let saved: PersonalData
            if let linkedScore {
                let bytes = try await exportPlayableBytes(persistedProject)
                guard request.generation == studioGeneration, project?.id == value.id else { return }
                guard manual || contentRevision == revision else { return }
                let assetID = Self.sha256(bytes)
                let warnings = value.importWarnings.flatMap { $0.isEmpty ? nil : $0 } ?? linkedScore.warnings
                let practiceScore = PersonalScore(
                    id: "project:\(value.id)",
                    source: "project",
                    sourceId: value.id,
                    revision: assetID,
                    title: value.title,
                    artist: value.artist,
                    category: Self.categoryForTracks(value),
                    format: "ibe",
                    assetId: assetID,
                    originalAssetId: linkedScore.originalAssetId,
                    projectId: value.id,
                    warnings: warnings,
                    createdAt: linkedScore.createdAt,
                    updatedAt: persistedProject.updatedAt
                )
                saved = try await personalStore.saveStudioProject(
                    persistedProject,
                    expectedUpdatedAt: expectedUpdatedAt,
                    practiceScore: practiceScore,
                    practiceAsset: PersonalAsset(id: assetID, bytes: bytes, mimeType: "application/octet-stream")
                )
            } else {
                guard request.generation == studioGeneration, project?.id == value.id else { return }
                saved = try await personalStore.saveStudioProject(persistedProject, expectedUpdatedAt: expectedUpdatedAt)
            }

            personalRevision = saved.revision
            savedProjects = saved.projects.sorted { $0.updatedAt > $1.updatedAt }
            let savedValue = saved.projects.first(where: { $0.id == value.id }) ?? persistedProject
            projectVersions[value.id] = savedValue.updatedAt
            savedUpdatedAt = project?.id == value.id ? savedValue.updatedAt : savedUpdatedAt
            persistedContentRevisions[value.id] = max(persistedContentRevisions[value.id] ?? Int.min, revision)
            if project?.id == value.id { linkedPracticeScoreID = Self.linkedProjectScore(in: saved, projectID: value.id)?.id }

            if project?.id == value.id, contentRevision == revision {
                project = savedValue
                if isDirty { isDirty = false }
                removeDraftFile(id: value.id)
                if manual { status = "已保存到本地草稿箱：\(value.title)" }
                else { status = "已自动保存：\(value.title)" }
            } else if project?.id == value.id {
                if !isDirty { isDirty = true }
                if let latest = project { persistLocalDraft(latest) }
                if manual { status = "已保存提交版本；期间新增的修改仍保留在本地草稿中。" }
            }
            onPersonalDataChanged()
        } catch {
            if project?.id == value.id {
                if !isDirty { isDirty = true }
                if let latest = project { persistLocalDraft(latest) }
                let failureStatus = manual ? "手动保存失败" : "自动保存失败"
                status = "\(failureStatus)，修改仍在本地草稿中：\(error.localizedDescription)"
            }
        }
    }

    private func exportPlayableBytes(_ value: StudioProject) async throws -> Data {
        guard let object = Self.jsObject(value) else { throw StudioBridgeError.invalidProject }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<Data, Error>, Never>) in
            let gate = NativeStudioAsyncGate<Result<Data, Error>>(continuation)
            gate.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { return }
                gate.resume(returning: .failure(NativeStudioWaitError.javascriptTimedOut))
            }
            callJavaScript("return await window.NativeStudio.exportBytes(project, 'ibe')", arguments: ["project": object]) { result in
                guard case .success(let value) = result,
                      let encoded = value as? String,
                      let bytes = Data(base64Encoded: encoded) else {
                    Task { @MainActor in
                        gate.resume(returning: .failure(StudioBridgeError.exportFailed(Self.resultMessage(result))))
                    }
                    return
                }
                Task { @MainActor in gate.resume(returning: .success(bytes)) }
            }
        }
        return try result.get()
    }

    private static func linkedProjectScore(in data: PersonalData, projectID: String) -> PersonalScore? {
        data.scores.first(where: { $0.id == "project:\(projectID)" })
            ?? data.scores.first(where: { ($0.source == "project" && $0.sourceId == projectID) || $0.projectId == projectID })
    }

    private func recordProjectMutation(_ value: StudioProject, status: String) {
        var next = value
        let priorVersion = max(max(value.updatedAt, project?.id == value.id ? (project?.updatedAt ?? value.updatedAt) : value.updatedAt), projectVersions[value.id] ?? -1)
        next.updatedAt = max(Self.nowMilliseconds(), priorVersion + 1)
        project = next
        contentRevision += 1
        if !isDirty { isDirty = true }
        if self.status != status { self.status = status }
        persistLocalDraft(next)
        sendProjectToCanvas(next)
        enqueueProjectSave(next, revision: contentRevision)
    }

    private func invalidatePendingOperations() {
        operationGeneration &+= 1
        pendingOperations.removeAll()
        applyingOperation = false
    }

    func togglePlayback() {
        if isPlaying { pausePlayback(); return }
        invalidatePreview(releaseAudioFocus: false)
        NativePlayerAudioFocus.claim(self) { [weak self] in self?.handleAudioFocusLoss() }
        callJavaScript("window.NativeStudio.playback('play')")
    }

    func pausePlayback() {
        invalidatePreview(releaseAudioFocus: false)
        callJavaScript("window.NativeStudio.playback('pause')")
        isPlaying = false
        NativePlayerAudioFocus.release(self)
    }

    func stopPlayback() {
        invalidatePreview(releaseAudioFocus: true)
        callJavaScript("window.NativeStudio.playback('stop')")
        playbackPosition.update(currentTick: 0)
        isPlaying = false
        NativePlayerAudioFocus.release(self)
        setCursor(bar: 0, beat: 0)
    }

    func seekToCursor() {
        callJavaScript("window.NativeStudio.seek(barIndex, beatIndex)", arguments: ["barIndex": cursor.barIndex, "beatIndex": cursor.beatIndex])
    }

    func searchShortcuts() {
        guard isBooted else { return }
        callJavaScript("return JSON.stringify(window.NativeStudioCore.searchShortcuts(query, category))", arguments: [
            "query": shortcutQuery,
            "category": shortcutCategory,
        ]) { [weak self] result in
            guard let self, case .success(let value) = result, let json = value as? String,
                  let data = json.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([NativeStudioShortcutInfo].self, from: data) else { return }
            self.shortcutResults = entries
        }
    }

    func previewSelectedNote() {
        guard let track = currentTrack else { return }
        startPreview(
            "return window.NativeStudio.previewNote(track, stringIndex, fret)",
            arguments: ["track": Self.jsObject(track) ?? [:], "stringIndex": cursor.stringIndex, "fret": selectedFret],
            failureLabel: "音符试听"
        )
    }

    func previewChord(_ notes: [[String: Int]], program: Int? = nil) {
        guard let track = currentTrack, !notes.isEmpty else { return }
        var trackObject = Self.jsObject(track) ?? [:]
        if let program { trackObject["program"] = program }
        startPreview(
            "return window.NativeStudio.previewChord(track, notes, program)",
            arguments: ["track": trackObject, "notes": notes, "program": program as Any? ?? NSNull()],
            failureLabel: "和弦试听"
        )
    }

    private func startPreview(_ script: String, arguments: [String: Any], failureLabel: String) {
        guard webView != nil else {
            status = "\(failureLabel)失败：工坊页面尚未就绪。"
            return
        }
        if isPlaying { pausePlayback() }
        else { invalidatePreview(releaseAudioFocus: false) }

        let token = UUID()
        activePreviewToken = token
        NativePlayerAudioFocus.claim(self) { [weak self] in self?.handleAudioFocusLoss() }
        let pendingStatus = "正在\(failureLabel)…"
        status = pendingStatus
        callJavaScript(script, arguments: arguments) { [weak self] result in
            guard let self, self.activePreviewToken == token else { return }
            self.activePreviewToken = nil
            if self.status == pendingStatus {
                switch result {
                case .success:
                    self.status = "试听完成。"
                case .failure(let error):
                    self.status = "\(failureLabel)失败：\(error.localizedDescription)"
                }
            }
            NativePlayerAudioFocus.release(self)
        }
    }

    private func invalidatePreview(releaseAudioFocus: Bool) {
        activePreviewToken = nil
        callJavaScript("window.NativeGuitarAudio && window.NativeGuitarAudio.cancel()")
        if releaseAudioFocus { NativePlayerAudioFocus.release(self) }
    }

    private func handleAudioFocusLoss() {
        invalidatePreview(releaseAudioFocus: false)
        callJavaScript("window.NativeStudio && window.NativeStudio.playback('pause')")
        isPlaying = false
    }

    @Published var selectedFret = 0

    var currentTrack: StudioTrack? {
        guard let project, project.tracks.indices.contains(selectedTrack) else { return nil }
        return project.tracks[selectedTrack]
    }

    var currentBar: StudioBar? {
        guard let project, project.bars.indices.contains(cursor.barIndex) else { return nil }
        return project.bars[cursor.barIndex]
    }

    var currentBeat: StudioBeat? {
        guard let bar = currentBar, let track = currentTrack else { return nil }
        let beats = bar.trackBeats[track.id] ?? []
        return beats.indices.contains(cursor.beatIndex) ? beats[cursor.beatIndex] : nil
    }

    var activeTechniques: Set<String> {
        guard let note = currentBeat?.notes.first(where: { $0.string == cursor.stringIndex }) else { return [] }
        var active = Set<String>()
        if note.tie == true { active.insert("tie") }
        if note.hammerPull == true { active.insert("hammerPull") }
        if note.slide == true { active.insert("slide") }
        if note.bend == true { active.insert("bend") }
        if note.harmonic == true { active.insert("harmonic") }
        if note.palmMute == true { active.insert("palmMute") }
        if note.dead == true { active.insert("dead") }
        if note.vibrato == true { active.insert("vibrato") }
        return active
    }

    func downloadOriginalSource() {
        guard let currentProject = project, let source = currentProject.source else {
            status = "当前工程没有导入原始文件。"
            return
        }
        isBusy = true
        Task { @MainActor in
            do {
                let snapshot = try await personalStore.snapshot()
                let linkedScore = snapshot.scores.first(where: { $0.id == source.id })
                    ?? snapshot.scores.first(where: { $0.projectId == currentProject.id })
                let storedOriginal = snapshot.originals.first(where: { $0.id == source.id })
                guard let assetID = storedOriginal?.assetId ?? linkedScore?.originalAssetId,
                      let asset = try await personalStore.asset(id: assetID) else {
                    throw PersonalStoreError.assetMissing(source.id)
                }
                isBusy = false
                saveDataPanel(asset.bytes, extension: URL(fileURLWithPath: source.fileName).pathExtension, mime: .data, suggestedName: source.fileName)
            } catch {
                isBusy = false
                status = "下载原始文件失败：\(error.localizedDescription)"
            }
        }
    }

    func chooseTrack(_ index: Int) {
        guard let project, project.tracks.indices.contains(index) else { return }
        selectedTrack = index
        cursor.trackIndex = index
        cursor.stringIndex = min(cursor.stringIndex, max(1, project.tracks[index].tuning.count))
        sendCursor()
    }

    func setCursor(bar: Int? = nil, beat: Int? = nil, string: Int? = nil) {
        guard let project else { return }
        if let bar { cursor.barIndex = min(max(0, bar), max(0, project.bars.count - 1)) }
        if let beat {
            let beats = project.bars[cursor.barIndex].trackBeats[project.tracks[selectedTrack].id] ?? []
            cursor.beatIndex = min(max(0, beat), max(0, beats.count - 1))
        }
        if let string { cursor.stringIndex = min(max(1, string), max(1, currentTrack?.tuning.count ?? 6)) }
        sendCursor()
    }

    func enterFret(_ fret: Int, string: Int) {
        guard let track = currentTrack else { return }
        selectedFret = min(24, max(0, fret))
        setCursor(string: min(max(1, string), max(1, track.tuning.count)))
        apply("fret", arguments: ["stringIndex": cursor.stringIndex, "fret": selectedFret])
        previewSelectedNote()
        if !chordMode { advanceCursor() }
    }

    func handleShortcut(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        if let value = message["cursor"] as? [String: Any], let decoded = decodeCursor(value) {
            cursor = decoded; selectedTrack = min(decoded.trackIndex, max(0, (project?.tracks.count ?? 1) - 1))
        }
        switch action {
        case "save": save()
        case "undo": undo()
        case "redo": redo()
        case "playPause": togglePlayback()
        case "fret": selectedFret = message["fret"] as? Int ?? 0; apply("fret", arguments: ["fret": selectedFret]); previewSelectedNote(); if !chordMode { advanceCursor() }
        case "duration": apply("duration", arguments: ["duration": message["duration"] as? Int ?? 4])
        case "insertBar": insertBarAtCursorAndAdvance()
        case "insertBeat": apply("insertBeat")
        case "deleteBeat": apply("deleteBeat")
        case "deleteNote": apply("deleteNote")
        case "dot": apply("dot")
        case "triplet": apply("triplet")
        case "rest": apply("rest")
        case "technique": apply("technique", arguments: ["technique": message["technique"] as? String ?? "tie"])
        default: break
        }
    }

    var lyricsTargetMatchesCurrentProject: Bool {
        guard let project, let lyricTargetProjectID else { return false }
        return project.id == lyricTargetProjectID
    }

    var lyricsTargetMatchesRevision: Bool {
        guard let project, lyricExpectedRevision == contentRevision,
              let lyricExpectedProjectUpdatedAt else { return false }
        return project.updatedAt == lyricExpectedProjectUpdatedAt
    }

    var lyricWordCount: Int {
        let range = NSRange(lyricDraft.startIndex..<lyricDraft.endIndex, in: lyricDraft)
        let expression = try? NSRegularExpression(pattern: "[\\u4e00-\\u9fa5]|[a-zA-Z0-9'’]+")
        return expression?.numberOfMatches(in: lyricDraft, range: range) ?? 0
    }

    var lyricAvailablePositions: Int {
        guard let project, let trackID = lyricTargetTrackID else { return 0 }
        return project.bars.flatMap { $0.trackBeats[trackID] ?? [] }
            .filter { !$0.isRest && !$0.notes.isEmpty }.count
    }

    var lyricExistingCount: Int {
        guard let project, let trackID = lyricTargetTrackID else { return 0 }
        return project.bars.flatMap { $0.trackBeats[trackID] ?? [] }
            .filter { !($0.lyrics ?? "").isEmpty }.count
    }

    func beginLyricsSession() {
        guard let project, project.tracks.indices.contains(selectedTrack) else { return }
        loadLyricsTarget(project: project, track: project.tracks[selectedTrack])
    }

    func updateLyricsDraft(_ value: String) {
        lyricDraft = value
        persistCurrentLyricsDraft()
    }

    func persistCurrentLyricsDraft() {
        guard let project, let lyricTargetProjectID, let lyricTargetTrackID,
              project.id == lyricTargetProjectID,
              project.tracks.contains(where: { $0.id == lyricTargetTrackID }) else { return }
        let key = lyricsDraftKey(projectID: lyricTargetProjectID, trackID: lyricTargetTrackID)
        lyricDrafts[key] = NativeStudioLyricsDraftEntry(
            projectID: lyricTargetProjectID,
            trackID: lyricTargetTrackID,
            text: lyricDraft,
            expectedRevision: lyricExpectedRevision,
            expectedProjectUpdatedAt: lyricExpectedProjectUpdatedAt,
            updatedAt: Self.nowMilliseconds()
        )
        saveLyricsDrafts()
    }

    func switchLyricsTarget(to trackIndex: Int) {
        guard let project, project.tracks.indices.contains(trackIndex) else { return }
        persistCurrentLyricsDraft()
        selectedTrack = trackIndex
        cursor.trackIndex = trackIndex
        cursor.stringIndex = min(cursor.stringIndex, max(1, project.tracks[trackIndex].tuning.count))
        sendCursor()
        loadLyricsTarget(project: project, track: project.tracks[trackIndex])
    }

    func discardCurrentLyricsDraftAndReload() {
        guard let project, let lyricTargetProjectID, let lyricTargetTrackID else { return }
        lyricDrafts.removeValue(forKey: lyricsDraftKey(projectID: lyricTargetProjectID, trackID: lyricTargetTrackID))
        saveLyricsDrafts()
        if project.id == lyricTargetProjectID,
           let track = project.tracks.first(where: { $0.id == lyricTargetTrackID }) {
            lyricExpectedRevision = contentRevision
            lyricExpectedProjectUpdatedAt = project.updatedAt
            lyricDraft = collectLyrics(in: project, trackID: track.id)
        } else if project.tracks.indices.contains(selectedTrack) {
            loadLyricsTarget(project: project, track: project.tracks[selectedTrack])
        }
        status = "已丢弃该目标的未应用歌词草稿，并重新载入工程歌词。"
    }

    func alignLyrics() { applyLyrics(kind: "align") }

    func clearLyricsConfirmed() {
        showingClearLyricsAlert = false
        applyLyrics(kind: "clear")
    }

    private func applyLyrics(kind: String) {
        guard !isPreparingForWebViewTeardown, !isPreparingForProjectReplacement else {
            persistCurrentLyricsDraft()
            status = "工程正在切换或关闭；歌词文本已保留。"
            return
        }
        guard let project, let projectID = lyricTargetProjectID, let trackID = lyricTargetTrackID else {
            status = "请选择歌词目标音轨。"; return
        }
        guard project.id == projectID, project.tracks.contains(where: { $0.id == trackID }) else {
            persistCurrentLyricsDraft()
            status = "歌词目标工程或音轨已变化；草稿仍按原目标保留。"; return
        }
        guard lyricExpectedRevision == contentRevision else {
            persistCurrentLyricsDraft()
            status = "工程在歌词编辑期间发生变化。草稿已保留，请重载歌词后再应用。"; return
        }
        if kind == "align", lyricWordCount == 0 { status = "请输入至少一个有效歌词字词。"; return }
        if kind == "align", lyricWordCount > lyricAvailablePositions {
            status = "歌词有 \(lyricWordCount) 个字词，但当前音轨只有 \(lyricAvailablePositions) 个可用发声音符拍位。"; return
        }
        guard let sourceWebView = webView,
              let object = Self.jsObject(project) else { status = "无法读取当前工程。"; return }
        let sourceWebViewID = ObjectIdentifier(sourceWebView)
        let expectedGeneration = studioGeneration
        let expectedProjectID = project.id
        let command: [String: Any] = [
            "kind": kind,
            "projectId": projectID,
            "trackId": trackID,
            "expectedRevision": lyricExpectedRevision,
            "text": lyricDraft,
        ]
        let commandID = UUID()
        pendingEditorCommandIDs.insert(commandID)
        callJavaScript("return JSON.stringify(window.NativeStudioCore.applyLyricsCommand(project, revision, command))", arguments: [
            "project": object,
            "revision": contentRevision,
            "command": command,
        ]) { [weak self] result in
            guard let self else { return }
            self.pendingEditorCommandIDs.remove(commandID)
            guard self.webView.map(ObjectIdentifier.init) == sourceWebViewID,
                  self.studioGeneration == expectedGeneration,
                  self.project?.id == expectedProjectID else { return }
            guard case .success(let value) = result, let json = value as? String,
                  let next = Self.decodeProject(json) else {
                if case .failure(let error) = result { self.status = "歌词未应用：\(error.localizedDescription)；草稿已保留。" }
                else { self.status = "歌词未应用；草稿已保留。" }
                self.persistCurrentLyricsDraft()
                return
            }
            self.undoStack = Array((self.undoStack + [project]).suffix(100))
            self.redoStack.removeAll()
            self.recordProjectMutation(next, status: "歌词已修改 · 正在自动保存")
            self.lyricExpectedRevision = self.contentRevision
            self.lyricExpectedProjectUpdatedAt = self.project?.updatedAt
            if kind == "align" {
                self.lyricDrafts.removeValue(forKey: self.lyricsDraftKey(projectID: projectID, trackID: trackID))
                self.lyricDraft = ""
                self.status = "歌词已按中文单字与英文词吸附到发声音符。"
            } else {
                self.persistCurrentLyricsDraft()
                self.status = "已清空目标音轨已写入歌词；文本草稿仍保留。"
            }
            self.saveLyricsDrafts()
        }
    }

    private func loadLyricsTarget(project: StudioProject, track: StudioTrack) {
        let key = lyricsDraftKey(projectID: project.id, trackID: track.id)
        lyricTargetProjectID = project.id
        lyricTargetTrackID = track.id
        if let draft = lyricDrafts[key] {
            lyricExpectedProjectUpdatedAt = draft.expectedProjectUpdatedAt ?? project.updatedAt
            lyricExpectedRevision = lyricExpectedProjectUpdatedAt == project.updatedAt ? contentRevision : draft.expectedRevision
            lyricDraft = draft.text
        } else {
            lyricExpectedRevision = contentRevision
            lyricExpectedProjectUpdatedAt = project.updatedAt
            lyricDraft = collectLyrics(in: project, trackID: track.id)
        }
    }

    private func collectLyrics(in project: StudioProject, trackID: String) -> String {
        project.bars.flatMap { $0.trackBeats[trackID] ?? [] }
            .compactMap { beat in
                guard let lyrics = beat.lyrics, !lyrics.isEmpty else { return nil }
                return lyrics
            }.joined(separator: " ")
    }

    private func lyricsDraftKey(projectID: String, trackID: String) -> String { "\(projectID)\u{1f}\(trackID)" }

    private func saveLyricsDrafts() {
        lyricsDraftSequence &+= 1
        let requestedSequence = lyricsDraftSequence
        let token = NativeStudioDraftToken(
            projectID: "__studio_lyrics_drafts__",
            generation: 0,
            contentRevision: Int(truncatingIfNeeded: requestedSequence),
            operationSequence: NativeStudioDraftIO.nextOperationSequence()
        )
        draftIO.enqueueLyricsDrafts(Array(lyricDrafts.values), token: token) { [weak self] result, _ in
            guard let self, self.lyricsDraftSequence == requestedSequence,
                  case .failure(let error) = result else { return }
            self.status = "歌词草稿写入失败：\(error.localizedDescription)；当前文本仍留在窗口。"
        }
    }

    func handlePreviewFromCanvas() {
        guard let beat = currentBeat, !beat.isRest, !beat.notes.isEmpty else { return }
        togglePlayback()
    }

    func leave() {
        flushPendingAutomaticSaves()
        pausePlayback()
        guard isDirty, let project else { return }
        showingLeaveAlert = false
        let record: (id: UUID, webViewID: ObjectIdentifier?, projectID: String?, studioGeneration: UInt64, task: Task<Bool, Never>)
        if let pending = departureDraftFlush,
           pending.webViewID == webView.map(ObjectIdentifier.init),
           pending.projectID == project.id,
           pending.studioGeneration == studioGeneration {
            record = pending
        } else {
            departureDraftFlush?.task.cancel()
            record = startDepartureDraftFlush(
                webView: webView,
                deadline: DispatchTime.now().uptimeNanoseconds + 20_000_000_000
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await record.task.value
            guard self.departureDraftFlush?.id == record.id else { return }
            if succeeded {
                if !self.isPreparingForWebViewTeardown { self.showingLeaveAlert = true }
            } else {
                self.status = "编辑仍在应用或本地草稿写入失败；离开前请重试。"
            }
        }
    }

    func persistDraftBeforeLeave(_ value: StudioProject) {
        flushPendingAutomaticSaves()
        guard let current = project, current.id == value.id else {
            status = "工程已切换；原工程草稿仍保留。"
            return
        }
        let record: (id: UUID, webViewID: ObjectIdentifier?, projectID: String?, studioGeneration: UInt64, task: Task<Bool, Never>)
        if let pending = departureDraftFlush,
           pending.webViewID == webView.map(ObjectIdentifier.init),
           pending.projectID == current.id,
           pending.studioGeneration == studioGeneration {
            record = pending
        } else {
            departureDraftFlush?.task.cancel()
            record = startDepartureDraftFlush(
                webView: webView,
                deadline: DispatchTime.now().uptimeNanoseconds + 20_000_000_000
            )
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await record.task.value
            guard self.departureDraftFlush?.id == record.id else { return }
            if succeeded {
                self.showingLeaveAlert = false
                self.status = "已将未保存更改保留在本地草稿箱。"
            } else {
                self.status = "编辑仍在应用或本地草稿写入失败；当前文本仍留在窗口。"
            }
        }
    }

    private func startDepartureDraftFlush(webView: WKWebView?, deadline: UInt64) -> (id: UUID, webViewID: ObjectIdentifier?, projectID: String?, studioGeneration: UInt64, task: Task<Bool, Never>) {
        let id = UUID()
        let webViewID = webView.map(ObjectIdentifier.init)
        let initialProjectID = project?.id
        let initialStudioGeneration = studioGeneration
        let task = Task { @MainActor [weak self, weak webView] () -> Bool in
            guard let self else { return false }
            guard self.departureDraftFlush?.id == id,
                  !Task.isCancelled else { return false }
            if let webViewID {
                guard let expectedWebView = webView, self.webView === expectedWebView,
                      ObjectIdentifier(expectedWebView) == webViewID else { return false }
            }

            guard await self.waitForEditorWorkDuringDeparture(until: min(deadline, DispatchTime.now().uptimeNanoseconds + 15_000_000_000)) else {
                self.status = "编辑排空超时；当前文本仍留在窗口。"
                return false
            }
            guard self.departureDraftFlush?.id == id,
                  !Task.isCancelled else { return false }
            if let webViewID {
                guard let expectedWebView = webView, self.webView === expectedWebView,
                      ObjectIdentifier(expectedWebView) == webViewID else { return false }
            }

            for attempt in 0..<2 {
                guard let latest = self.project else { return true }
                guard self.isDirty else { return true }
                let expectedGeneration = self.studioGeneration
                let expectedProjectID = latest.id
                let revision = self.contentRevision
                let remaining = deadline > DispatchTime.now().uptimeNanoseconds
                    ? deadline - DispatchTime.now().uptimeNanoseconds
                    : 0
                guard remaining > 0 else {
                    self.status = "本地草稿写入超时；当前文本仍留在窗口。"
                    return false
                }
                let result = await self.persistLocalDraftAndWait(latest, timeoutNanoseconds: min(5_000_000_000, remaining))
                guard self.departureDraftFlush?.id == id,
                      !Task.isCancelled else { return false }
                guard self.studioGeneration == expectedGeneration,
                      self.project?.id == expectedProjectID else {
                    self.status = "工程已变化；草稿仍保留在当前窗口。"
                    return false
                }
                guard case .success = result else {
                    if case .failure(let error) = result {
                        self.status = "本地草稿尚未写入：\(error.localizedDescription)"
                    }
                    return false
                }
                if self.contentRevision == revision { return true }
                if attempt == 1 {
                    self.status = "写入期间工程又有变化；较早草稿已保留，离开前请再次保存。"
                    return false
                }
            }
            return false
        }
        let record = (
            id: id,
            webViewID: webViewID,
            projectID: initialProjectID,
            studioGeneration: initialStudioGeneration,
            task: task
        )
        departureDraftFlush = record
        return record
    }

    func openPractice(_ id: String) { onOpenPractice(id) }

    private func advanceCursor() {
        guard let project, let track = currentTrack else { return }
        let beatCount = project.bars[cursor.barIndex].trackBeats[track.id]?.count ?? 0
        if cursor.beatIndex + 1 < beatCount { setCursor(beat: cursor.beatIndex + 1) }
        else if cursor.barIndex + 1 < project.bars.count { setCursor(bar: cursor.barIndex + 1, beat: 0) }
        else { insertBarAtCursorAndAdvance() }
    }

    private func sendCursor() {
        callJavaScript("window.NativeStudio.setCursor(cursor)", arguments: ["cursor": ["trackIndex": cursor.trackIndex, "barIndex": cursor.barIndex, "beatIndex": cursor.beatIndex, "stringIndex": cursor.stringIndex]])
    }

    private func sendProjectToCanvas(_ value: StudioProject) {
        guard isBooted, let target = webView else { return }
        guard let object = Self.jsObject(value) else { return }
        canvasSubmissionGeneration &+= 1
        let targetID = ObjectIdentifier(target)
        let expectedSubmission = canvasSubmissionGeneration
        let expectedGeneration = studioGeneration
        let expectedProjectID = value.id
        callJavaScript(
            "const studio = window.NativeStudio; if (!studio || typeof studio.setProject !== 'function') throw new Error('工坊谱面接口尚未就绪。'); const result = studio.setProject(project); if (!result || result.accepted !== true) throw new Error('工坊未接受当前工程。'); return result;",
            arguments: ["project": object]
        ) { [weak self] result in
            guard let self,
                  let currentWebView = self.webView,
                  ObjectIdentifier(currentWebView) == targetID,
                  self.canvasSubmissionGeneration == expectedSubmission,
                  self.studioGeneration == expectedGeneration,
                  self.project?.id == expectedProjectID else { return }
            switch result {
            case .success(let value):
                guard (value as? [String: Any])?["accepted"] as? Bool == true else {
                    let message = "工坊谱面提交失败：引擎未确认接收当前工程。"
                    if self.engineError != message { self.engineError = message }
                    return
                }
            case .failure(let error):
                let message = "工坊谱面提交失败：\(error.localizedDescription)"
                if self.engineError != message { self.engineError = message }
            }
        }
    }

    private func callJavaScript(_ script: String, arguments: [String: Any] = [:], completion: ((Result<Any, Error>) -> Void)? = nil) {
        guard let webView else { completion?(.failure(StudioBridgeError.notReady)); return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page, completionHandler: { result in
            DispatchQueue.main.async { completion?(result) }
        })
    }

    private func persistLocalDraft(_ value: StudioProject, completion: ((Result<Void, Error>, NativeStudioDraftToken) -> Void)? = nil) {
        let token = nextDraftToken(projectID: value.id, contentRevision: contentRevision)
        latestDraftTokenByProject[value.id] = token
        let barrier: ((Result<Void, Error>, NativeStudioDraftToken) -> Void)?
        if let completion {
            barrier = { result, persistedToken in completion(result, persistedToken) }
        } else {
            barrier = nil
        }
        draftIO.enqueueProjectDraft(value, token: token, onPersist: { [weak self] result, writtenToken in
            guard let self, self.latestDraftTokenByProject[writtenToken.projectID] == writtenToken else { return }
            switch result {
            case .success(.project(let savedProject)):
                self.upsertDraftProject(savedProject)
            case .failure(let error):
                self.status = "本地自动草稿写入失败：\(error.localizedDescription)"
            case .success(.lyrics(_)), .success(.removed):
                break
            }
        }, onBarrier: barrier)
    }

    private func removeDraftFile(id: String) {
        draftGenerationByProject[id, default: 0] &+= 1
        let token = nextDraftToken(projectID: id, contentRevision: contentRevision)
        latestDraftTokenByProject[id] = token
        draftIO.enqueueRemoveProjectDraft(id: id, token: token) { [weak self] result, writtenToken in
            guard let self, self.latestDraftTokenByProject[writtenToken.projectID] == writtenToken else { return }
            switch result {
            case .success:
                let remainingDrafts = self.draftProjects.filter { $0.id != id }
                if self.draftProjects != remainingDrafts { self.draftProjects = remainingDrafts }
            case .failure(let error):
                self.status = "删除本地草稿失败：\(error.localizedDescription)"
            }
        }
    }

    private func reloadDraftIndex() async throws {
        let requestedGeneration = draftIndexGeneration
        let loadedDrafts = try await draftIO.loadAllProjectDrafts()
        let loaded = loadedDrafts.sorted { $0.updatedAt > $1.updatedAt }
        guard requestedGeneration == draftIndexGeneration else { return }
        if draftProjects != loaded { draftProjects = loaded }
    }

    private func nextDraftToken(projectID: String, contentRevision: Int) -> NativeStudioDraftToken {
        draftIndexGeneration &+= 1
        return NativeStudioDraftToken(
            projectID: projectID,
            generation: draftGenerationByProject[projectID] ?? 0,
            contentRevision: contentRevision,
            operationSequence: NativeStudioDraftIO.nextOperationSequence()
        )
    }

    private func upsertDraftProject(_ value: StudioProject) {
        var updated = draftProjects
        if let index = draftProjects.firstIndex(where: { $0.id == value.id }) {
            guard updated[index] != value else { return }
            updated[index] = value
        } else {
            updated.append(value)
        }
        updated.sort { $0.updatedAt > $1.updatedAt }
        if draftProjects != updated { draftProjects = updated }
    }

    private func saveDataPanel(_ data: Data, extension fileExtension: String, mime: UTType, suggestedName: String? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [mime]
        panel.nameFieldStringValue = suggestedName ?? "\(project?.title ?? "乐谱工程").\(fileExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try data.write(to: url, options: .atomic); DispatchQueue.main.async { self?.status = "已导出：\(url.lastPathComponent)" } }
            catch { DispatchQueue.main.async { self?.status = "写入导出文件失败：\(error.localizedDescription)" } }
        }
    }

    private func handleImportFailure(_ error: Error) { isBusy = false; status = "导入失败；原有工程和草稿未替换：\(error.localizedDescription)" }

    private static func jsObject<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private static func decodeProject(_ json: String) -> StudioProject? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StudioProject.self, from: data)
    }

    private func decodeCursor(_ object: [String: Any]) -> StudioCursorPosition? {
        guard let t = object["trackIndex"] as? Int, let b = object["barIndex"] as? Int, let beat = object["beatIndex"] as? Int, let string = object["stringIndex"] as? Int else { return nil }
        return StudioCursorPosition(trackIndex: t, barIndex: b, beatIndex: beat, stringIndex: string)
    }

    private static func messageFromImport(_ result: Result<Any, Error>) -> String? {
        if case .failure(let error) = result {
            return "导入失败：\(javascriptExceptionMessage(error) ?? error.localizedDescription)"
        }
        return nil
    }

    private static func javascriptExceptionMessage(_ error: Error) -> String? {
        let cocoaError = error as NSError
        for key in ["WKJavaScriptExceptionMessage", "JavaScriptExceptionMessage"] {
            if let message = cocoaError.userInfo[key] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let line = (cocoaError.userInfo["WKJavaScriptExceptionLineNumber"] as? NSNumber)?.intValue
                let column = (cocoaError.userInfo["WKJavaScriptExceptionColumnNumber"] as? NSNumber)?.intValue
                if let line, let column { return "\(message) (第 \(line) 行，第 \(column) 列)" }
                if let line { return "\(message) (第 \(line) 行)" }
                return message
            }
        }
        if let underlying = cocoaError.userInfo[NSUnderlyingErrorKey] as? Error,
           let message = javascriptExceptionMessage(underlying) {
            return message
        }
        return nil
    }

    private static func resultMessage(_ result: Result<Any, Error>) -> String {
        if case .failure(let error) = result { return error.localizedDescription }
        return "本地序列化器未返回内容。"
    }

    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func nowMilliseconds() -> Double { Date().timeIntervalSince1970 * 1000 }
    private static func instrumentLabel(_ value: String) -> String { ["guitar": "吉他", "ukulele": "尤克里里", "bass": "贝斯", "band": "乐队"].first(where: { $0.key == value })?.value ?? "吉他" }
    private static func personalFormatForImport(_ value: String) -> String {
        let format = value.lowercased()
        if format == "ibe" { return "ibe" }
        if format == "xhe" { return "xhe" }
        if format.hasPrefix("gp") { return "gp" }
        return "ibe"
    }
    private static func categoryForTracks(_ project: StudioProject) -> String {
        let name = project.tracks.first?.name.lowercased() ?? ""
        if name.contains("贝斯") || name.contains("bass") { return "bass" }
        if name.contains("尤克里里") || name.contains("ukulele") { return "ukulele" }
        return "guitar"
    }
}

private final class NativeStudioDraftIO {
    static let shared = NativeStudioDraftIO()
    private static let sequenceLock = NSLock()
    private static var globalSequence: UInt64 = 0

    static func nextOperationSequence() -> UInt64 {
        sequenceLock.lock()
        globalSequence &+= 1
        let sequence = globalSequence
        sequenceLock.unlock()
        return sequence
    }

    fileprivate typealias PersistNotification = (Result<NativeStudioDraftValue, Error>, NativeStudioDraftToken) -> Void
    fileprivate typealias BarrierCompletion = (Result<Void, Error>, NativeStudioDraftToken) -> Void

    private struct Barrier {
        let targetSequence: UInt64
        let completion: BarrierCompletion
    }

    private struct Job {
        enum Content {
            case project(StudioProject)
            case lyrics([NativeStudioLyricsDraftEntry])
            case removeProject
        }

        let key: String
        let token: NativeStudioDraftToken
        let content: Content
        let notification: PersistNotification?
        let barriers: [Barrier]
    }

    private let queue = DispatchQueue(label: "com.mimi.guitar.mac.studio-drafts", qos: .utility)
    private let lock = NSLock()
    private var pending: [String: Job] = [:]
    private var latestSequenceByKey: [String: UInt64] = [:]
    private var drainScheduled = false
    private var cachedDraftsDirectory: URL?
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private var terminationObserver: NSObjectProtocol?

    private init() {
        queue.setSpecific(key: queueSpecificKey, value: 1)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flushPendingSynchronously()
        }
    }

    func enqueueProjectDraft(
        _ project: StudioProject,
        token: NativeStudioDraftToken,
        onPersist: @escaping PersistNotification,
        onBarrier: BarrierCompletion? = nil
    ) {
        let barriers = onBarrier.map { [Barrier(targetSequence: token.operationSequence, completion: $0)] } ?? []
        enqueue(Job(
            key: projectKey(project.id),
            token: token,
            content: .project(project),
            notification: onPersist,
            barriers: barriers
        ))
    }

    func enqueueRemoveProjectDraft(
        id: String,
        token: NativeStudioDraftToken,
        onPersist: @escaping PersistNotification
    ) {
        enqueue(Job(
            key: projectKey(id),
            token: token,
            content: .removeProject,
            notification: onPersist,
            barriers: []
        ))
    }

    func enqueueLyricsDrafts(
        _ entries: [NativeStudioLyricsDraftEntry],
        token: NativeStudioDraftToken,
        onPersist: @escaping PersistNotification
    ) {
        enqueue(Job(
            key: "lyrics-drafts",
            token: token,
            content: .lyrics(entries),
            notification: onPersist,
            barriers: []
        ))
    }

    func loadAllProjectDrafts() async throws -> [StudioProject] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[StudioProject], Error>) in
            queue.async {
                do {
                    let directory = try self.draftsDirectory()
                    let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    var latestByProjectID: [String: (project: StudioProject, isCanonicalFile: Bool)] = [:]
                    for url in urls where url.pathExtension.lowercased() == "json" && url.lastPathComponent != "lyrics-drafts.json" {
                        let data: Data
                        do {
                            data = try Data(contentsOf: url)
                        } catch {
                            throw NativeStudioDraftIOError.projectDraftReadFailed(url.lastPathComponent, error.localizedDescription)
                        }
                        let project: StudioProject
                        do {
                            project = try JSONDecoder().decode(StudioProject.self, from: data)
                        } catch {
                            throw NativeStudioDraftIOError.projectDraftDecodeFailed(url.lastPathComponent, error.localizedDescription)
                        }
                        guard Self.isValidProjectID(project.id) else {
                            throw NativeStudioDraftIOError.invalidProjectDraftID(url.lastPathComponent)
                        }
                        let isCanonicalFile = url.lastPathComponent == Self.projectDraftFileName(id: project.id)
                        if let existing = latestByProjectID[project.id] {
                            if project.updatedAt > existing.project.updatedAt ||
                                (project.updatedAt == existing.project.updatedAt && isCanonicalFile && !existing.isCanonicalFile) {
                                latestByProjectID[project.id] = (project, isCanonicalFile)
                            }
                        } else {
                            latestByProjectID[project.id] = (project, isCanonicalFile)
                        }
                    }
                    continuation.resume(returning: latestByProjectID.values.map { $0.project })
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadLyricsDrafts() async throws -> [NativeStudioLyricsDraftEntry] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[NativeStudioLyricsDraftEntry], Error>) in
            queue.async {
                do {
                    let directory = try self.draftsDirectory()
                    let url = directory.appendingPathComponent("lyrics-drafts.json", isDirectory: false)
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        continuation.resume(returning: [])
                        return
                    }
                    let data: Data
                    do {
                        data = try Data(contentsOf: url)
                    } catch {
                        throw NativeStudioDraftIOError.lyricsDraftReadFailed(url.lastPathComponent, error.localizedDescription)
                    }
                    let entries: [NativeStudioLyricsDraftEntry]
                    do {
                        entries = try JSONDecoder().decode([NativeStudioLyricsDraftEntry].self, from: data)
                    } catch {
                        throw NativeStudioDraftIOError.lyricsDraftDecodeFailed(url.lastPathComponent, error.localizedDescription)
                    }
                    continuation.resume(returning: entries)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func loadProject(at url: URL) async -> StudioProject? {
        await withCheckedContinuation { (continuation: CheckedContinuation<StudioProject?, Never>) in
            queue.async {
                guard let data = try? Data(contentsOf: url),
                      let project = try? JSONDecoder().decode(StudioProject.self, from: data),
                      Self.isValidProjectID(project.id) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: project)
            }
        }
    }

    func loadProjectDraft(id: String) async -> StudioProject? {
        guard Self.isValidProjectID(id) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<StudioProject?, Never>) in
            queue.async {
                self.drain()
                do {
                    let directory = try self.draftsDirectory()
                    let canonicalURL = self.projectDraftURL(id: id, in: directory)
                    if let project = self.readProject(at: canonicalURL), project.id == id {
                        continuation.resume(returning: project)
                        return
                    }

                    let legacyURL = self.legacyProjectDraftURL(id: id, in: directory)
                    guard legacyURL != canonicalURL,
                          let legacyProject = self.readProject(at: legacyURL),
                          legacyProject.id == id else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // Migrate only a legacy file whose decoded ID matches this request.
                    // A sanitized filename may belong to a different project ID.
                    do {
                        let data = try JSONEncoder().encode(legacyProject)
                        try data.write(to: canonicalURL, options: .atomic)
                        try? self.removeLegacyProjectDraftIfMatching(id: id, in: directory, canonicalURL: canonicalURL)
                    } catch {
                        // The validated legacy snapshot remains usable if migration fails.
                    }
                    continuation.resume(returning: legacyProject)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func flushPendingSynchronously() {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            drain()
        } else {
            queue.sync { drain() }
        }
    }

    private func enqueue(_ job: Job) {
        lock.lock()
        let previousSequence = latestSequenceByKey[job.key] ?? 0
        guard job.token.operationSequence > previousSequence else {
            lock.unlock()
            return
        }
        latestSequenceByKey[job.key] = job.token.operationSequence

        var replacement = job
        if let previous = pending[job.key] {
            replacement = Job(
                key: job.key,
                token: job.token,
                content: job.content,
                notification: job.notification,
                barriers: previous.barriers + job.barriers
            )
        }
        pending[job.key] = replacement

        let shouldSchedule = !drainScheduled
        if shouldSchedule { drainScheduled = true }
        lock.unlock()

        if shouldSchedule { queue.async { self.drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            let jobs = pending.values.sorted { $0.token.operationSequence < $1.token.operationSequence }
            pending.removeAll()
            if jobs.isEmpty {
                drainScheduled = false
                lock.unlock()
                return
            }
            lock.unlock()

            for job in jobs { persist(job) }
        }
    }

    private func persist(_ job: Job) {
        do {
            let directory = try draftsDirectory()
            let result: Result<NativeStudioDraftValue, Error>
            switch job.content {
            case .project(let project):
                guard Self.isValidProjectID(project.id) else { throw NativeStudioDraftIOError.invalidProjectID }
                let url = projectDraftURL(id: project.id, in: directory)
                try JSONEncoder().encode(project).write(to: url, options: .atomic)
                // The new snapshot is durable before the matching legacy path is removed.
                try? removeLegacyProjectDraftIfMatching(id: project.id, in: directory, canonicalURL: url)
                result = .success(.project(project))
            case .lyrics(let entries):
                let url = directory.appendingPathComponent("lyrics-drafts.json", isDirectory: false)
                try JSONEncoder().encode(entries).write(to: url, options: .atomic)
                result = .success(.lyrics(entries))
            case .removeProject:
                let id = job.token.projectID
                let canonicalURL = projectDraftURL(id: id, in: directory)
                if FileManager.default.fileExists(atPath: canonicalURL.path) { try FileManager.default.removeItem(at: canonicalURL) }
                if Self.isValidProjectID(id) {
                    try removeLegacyProjectDraftIfMatching(id: id, in: directory, canonicalURL: canonicalURL)
                }
                result = .success(.removed)
            }
            notify(job, result: result)
        } catch {
            notify(job, result: .failure(error))
        }
    }

    private func notify(_ job: Job, result: Result<NativeStudioDraftValue, Error>) {
        lock.lock()
        let isLatest = latestSequenceByKey[job.key] == job.token.operationSequence
        lock.unlock()

        if isLatest, let notification = job.notification {
            DispatchQueue.main.async { notification(result, job.token) }
        }
        let barrierResult = result.map { _ in () }
        for barrier in job.barriers where barrier.targetSequence <= job.token.operationSequence {
            DispatchQueue.main.async { barrier.completion(barrierResult, job.token) }
        }
    }

    private func draftsDirectory() throws -> URL {
        if let cachedDraftsDirectory { return cachedDraftsDirectory }
        let root = try AppPaths.userDataDirectory().appendingPathComponent("StudioDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cachedDraftsDirectory = root
        return root
    }

    private func projectKey(_ id: String) -> String { "project:\(id)" }

    private func projectDraftURL(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent(Self.projectDraftFileName(id: id), isDirectory: false)
    }

    private func legacyProjectDraftURL(id: String, in directory: URL) -> URL {
        directory.appendingPathComponent(Self.legacySafeFileName(id) + ".json", isDirectory: false)
    }

    private func readProject(at url: URL) -> StudioProject? {
        guard let data = try? Data(contentsOf: url),
              let project = try? JSONDecoder().decode(StudioProject.self, from: data),
              Self.isValidProjectID(project.id) else { return nil }
        return project
    }

    private func removeLegacyProjectDraftIfMatching(id: String, in directory: URL, canonicalURL: URL) throws {
        let legacyURL = legacyProjectDraftURL(id: id, in: directory)
        guard legacyURL != canonicalURL,
              let legacyProject = readProject(at: legacyURL),
              legacyProject.id == id else { return }
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileManager.default.removeItem(at: legacyURL)
        }
    }

    private static func projectDraftFileName(id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return "project-\(digest).json"
    }

    private static func isValidProjectID(_ id: String) -> Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && id.count <= 512
    }

    private static func legacySafeFileName(_ value: String) -> String {
        String(value.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(100))
    }
}

private enum NativeStudioDraftIOError: Error, LocalizedError {
    case invalidProjectID
    case invalidProjectDraftID(String)
    case projectDraftReadFailed(String, String)
    case projectDraftDecodeFailed(String, String)
    case lyricsDraftReadFailed(String, String)
    case lyricsDraftDecodeFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectID:
            return "草稿工程 ID 无效。"
        case .invalidProjectDraftID(let fileName):
            return "草稿索引文件 \(fileName) 中的工程 ID 无效。"
        case .projectDraftReadFailed(let fileName, let reason):
            return "读取草稿索引文件 \(fileName) 失败：\(reason)"
        case .projectDraftDecodeFailed(let fileName, let reason):
            return "解析草稿索引文件 \(fileName) 失败：\(reason)"
        case .lyricsDraftReadFailed(let fileName, let reason):
            return "读取歌词草稿文件 \(fileName) 失败：\(reason)"
        case .lyricsDraftDecodeFailed(let fileName, let reason):
            return "解析歌词草稿文件 \(fileName) 失败：\(reason)"
        }
    }
}

private enum StudioBridgeError: Error, LocalizedError {
    case notReady
    case invalidProject
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return "工坊渲染页面尚未准备好。"
        case .invalidProject: return "无法序列化当前工坊工程。"
        case .exportFailed(let message): return message
        }
    }
}
