import Combine
import Foundation
import MIMICore
import SwiftUI

struct AuditionPlaybackSnapshot: Equatable {
    var activeItemID: String?
    var activeItemTitle = ""
    var activeItemArtist = ""
    var isActive = false
    var isLoading = false
    var isPlaying = false
    var canPlay = false
    var statusMessage = ""
    var errorMessage: String?
    var playbackRate = 1.0
}

struct AuditionPlaybackClock: Equatable {
    var currentTime: Double = 0
    var endTime: Double = 0
}

/// Gives playback controls a deduplicated, item-scoped view of the shared controller.
/// High-frequency clock changes can be opted into and are throttled independently.
@MainActor
final class AuditionItemViewState: ObservableObject {
    @Published private(set) var snapshot = AuditionPlaybackSnapshot()
    @Published private(set) var clock = AuditionPlaybackClock()
    @Published private(set) var activeNotes: [NativeFretNote] = []

    private struct ItemIdentity: Equatable {
        let id: String
        let title: String
        let artist: String
    }

    private var cancellables = Set<AnyCancellable>()

    init(
        controller: NativeAuditionController,
        itemID: String? = nil,
        tracksClock: Bool = false,
        tracksNotes: Bool = false
    ) {
        let initialItem = controller.activeItem
        let initialActive = itemID.map { initialItem?.id == $0 } ?? (initialItem != nil)
        self.snapshot = AuditionPlaybackSnapshot(
            activeItemID: initialItem?.id,
            activeItemTitle: initialItem?.title ?? "",
            activeItemArtist: initialItem.map { $0.artist ?? "未知演奏者" } ?? "",
            isActive: initialActive,
            isLoading: initialActive && controller.isLoading,
            isPlaying: initialActive && controller.isPlaying,
            canPlay: initialActive && controller.canPlay,
            statusMessage: initialActive ? controller.statusMessage : "",
            errorMessage: initialActive ? controller.errorMessage : nil,
            playbackRate: initialActive && controller.sourceTempo > 0 ? controller.tempo / controller.sourceTempo : 1
        )
        if tracksClock && initialActive {
            self.clock = AuditionPlaybackClock(currentTime: max(0, controller.currentTime), endTime: max(0, controller.endTime))
        }
        if tracksNotes && initialActive {
            self.activeNotes = controller.activeNotes
        }

        let activeItem = controller.$activeItem
            .map { item in item.map { ItemIdentity(id: $0.id, title: $0.title, artist: $0.artist ?? "未知演奏者") } }
            .removeDuplicates()
        let playback = Publishers.CombineLatest4(
            activeItem,
            controller.$isLoading.removeDuplicates(),
            controller.$isPlaying.removeDuplicates(),
            controller.$statusMessage.removeDuplicates()
        )
        let availability = Publishers.CombineLatest4(
            controller.$canPlay.removeDuplicates(),
            controller.$errorMessage.removeDuplicates(),
            controller.$tempo.removeDuplicates(),
            controller.$sourceTempo.removeDuplicates()
        )

        Publishers.CombineLatest(playback, availability)
            .map { values in
                let playback = values.0
                let availability = values.1
                let (item, isLoading, isPlaying, statusMessage) = playback
                let (canPlay, errorMessage, tempo, sourceTempo) = availability
                let isActive = itemID.map { item?.id == $0 } ?? (item != nil)
                return AuditionPlaybackSnapshot(
                    activeItemID: item?.id,
                    activeItemTitle: item?.title ?? "",
                    activeItemArtist: item?.artist ?? "",
                    isActive: isActive,
                    isLoading: isActive && isLoading,
                    isPlaying: isActive && isPlaying,
                    canPlay: isActive && canPlay,
                    statusMessage: isActive ? statusMessage : "",
                    errorMessage: isActive ? errorMessage : nil,
                    playbackRate: isActive && sourceTempo > 0 ? tempo / sourceTempo : 1
                )
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                guard self?.snapshot != value else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.snapshot != value else { return }
                    self.snapshot = value
                }
            }
            .store(in: &cancellables)

        if tracksClock {
            Publishers.CombineLatest3(controller.$activeItem.map { $0?.id }.removeDuplicates(), controller.$currentTime, controller.$endTime)
                .filter { values in itemID.map { $0 == values.0 } ?? (values.0 != nil) }
                .map { AuditionPlaybackClock(currentTime: max(0, $0.1), endTime: max(0, $0.2)) }
                .removeDuplicates()
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] value in
                    guard self?.clock != value else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.clock != value else { return }
                        self.clock = value
                    }
                }
                .store(in: &cancellables)
        }

        if tracksNotes {
            controller.$activeItem
                .map { $0?.id }
                .removeDuplicates()
                .combineLatest(controller.$activeNotes.removeDuplicates())
                .filter { values in itemID.map { $0 == values.0 } ?? (values.0 != nil) }
                .map { $0.1 }
                .sink { [weak self] notes in
                    guard self?.activeNotes != notes else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.activeNotes != notes else { return }
                        self.activeNotes = notes
                    }
                }
                .store(in: &cancellables)
        }
    }
}

extension NativeAuditionController {
    @MainActor
    private static var viewStates = [ObjectIdentifier: [String: AuditionItemViewState]]()

    @MainActor
    func viewState(itemID: String? = nil, tracksClock: Bool = false, tracksNotes: Bool = false) -> AuditionItemViewState {
        let key = "\(itemID ?? "global")_\(tracksClock)_\(tracksNotes)"
        let controllerID = ObjectIdentifier(self)
        if let existing = Self.viewStates[controllerID]?[key] {
            return existing
        }
        let created = AuditionItemViewState(controller: self, itemID: itemID, tracksClock: tracksClock, tracksNotes: tracksNotes)
        var dict = Self.viewStates[controllerID] ?? [:]
        dict[key] = created
        Self.viewStates[controllerID] = dict
        return created
    }
}

