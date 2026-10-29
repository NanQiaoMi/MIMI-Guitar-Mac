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
            .sink { [weak self] value in
                Task { @MainActor [weak self] in self?.snapshot = value }
            }
            .store(in: &cancellables)

        if tracksClock {
            Publishers.CombineLatest3(controller.$activeItem.map { $0?.id }.removeDuplicates(), controller.$currentTime, controller.$endTime)
                .filter { values in itemID.map { $0 == values.0 } ?? (values.0 != nil) }
                .map { AuditionPlaybackClock(currentTime: max(0, $0.1), endTime: max(0, $0.2)) }
                .removeDuplicates()
                .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
                .sink { [weak self] value in
                    Task { @MainActor [weak self] in self?.clock = value }
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
                    Task { @MainActor [weak self] in self?.activeNotes = notes }
                }
                .store(in: &cancellables)
        }
    }
}
