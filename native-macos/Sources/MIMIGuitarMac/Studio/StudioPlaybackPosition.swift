import Combine
import Foundation

@MainActor
final class StudioPlaybackPosition: ObservableObject {
    @Published private(set) var currentTick: Double = 0
    @Published private(set) var endTick: Double = 0

    func update(currentTick: Double? = nil, endTick: Double? = nil) {
        if let currentTick { self.currentTick = currentTick }
        if let endTick, self.endTick != endTick { self.endTick = endTick }
    }
}
