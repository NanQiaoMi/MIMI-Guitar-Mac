import AppKit
import MIMICore
import SwiftUI

struct ScopedStudioProject: Identifiable {
    let project: StudioProject
    let namespace: String

    var id: String { "\(namespace):\(project.id)" }
}

enum NativeStudioDockTab: String, CaseIterable, Identifiable {
    case workbench
    case mixer

    var id: String { rawValue }
    var title: String { self == .workbench ? "工作台" : "调音台" }
    var symbol: String { self == .workbench ? "guitars" : "slider.horizontal.3" }
}

struct NativeStudioStableRegion<Key: Equatable, Content: View>: View, Equatable {
    let key: Key
    private let contentProvider: () -> Content

    init(key: Key, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        contentProvider = content
    }

    static func == (lhs: NativeStudioStableRegion<Key, Content>, rhs: NativeStudioStableRegion<Key, Content>) -> Bool {
        lhs.key == rhs.key
    }

    var body: some View { contentProvider() }
}

struct NativeStudioMetadataEditorState: Equatable {
    let projectID: String
    let title: String
    let artist: String
    let album: String?
    let words: String?
    let music: String?
    let tabber: String?
    let key: String
    let tempo: Int
    let numerator: Int
    let denominator: Int
    let selectedTrack: Int
    let selectedTrackCapo: Int?
    let isPlaying: Bool
    let isDirty: Bool
    let isBooted: Bool
    let barCount: Int
    let trackCount: Int
    let source: StudioSource?

    init(_ project: StudioProject, selectedTrack: Int, isPlaying: Bool, isDirty: Bool, isBooted: Bool) {
        projectID = project.id
        title = project.title
        artist = project.artist
        album = project.album
        words = project.words
        music = project.music
        tabber = project.tabber
        key = project.key
        tempo = project.initialTempo
        numerator = project.timeSignatureNumerator
        denominator = project.timeSignatureDenominator
        self.selectedTrack = selectedTrack
        selectedTrackCapo = project.tracks.indices.contains(selectedTrack) ? project.tracks[selectedTrack].capo : nil
        self.isPlaying = isPlaying
        self.isDirty = isDirty
        self.isBooted = isBooted
        barCount = project.bars.count
        trackCount = project.tracks.count
        source = project.source
    }
}

struct NativeStudioFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let widthLimit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + horizontalSpacing + size.width > widthLimit {
                widestRow = max(widestRow, x)
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }
            if x > 0 { x += horizontalSpacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, x)
        return CGSize(width: widthLimit.isFinite ? widthLimit : widestRow, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + horizontalSpacing + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            if x > bounds.minX { x += horizontalSpacing }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }

}

struct NativeStudioTrackSelectorState: Equatable {
    let projectID: String
    let tracks: [StudioTrack]
    let selectedTrack: Int
    let isPlaying: Bool
}

struct NativeStudioTrackInspectorState: Equatable {
    let projectID: String
    let track: StudioTrack
    let trackCount: Int
}

struct NativeStudioBeatTimingState: Equatable {
    let duration: Int
    let dot: Bool
    let triplet: Bool
}

struct NativeStudioBarInspectorState: Equatable {
    let projectID: String
    let barID: String
    let index: Int
    let numerator: Int
    let denominator: Int
    let tempo: Double?
    let section: String?
    let repeatStart: Bool?
    let repeatEnd: Bool?
    let repeatCount: Int?
    let volta: Int?
    let selectedTrackID: String
    let beatTiming: [NativeStudioBeatTimingState]

    init(projectID: String, bar: StudioBar, selectedTrackID: String) {
        self.projectID = projectID
        barID = bar.id
        index = bar.index
        numerator = bar.timeSignatureNumerator
        denominator = bar.timeSignatureDenominator
        tempo = bar.tempo
        section = bar.section
        repeatStart = bar.repeatStart
        repeatEnd = bar.repeatEnd
        repeatCount = bar.repeatCount
        volta = bar.volta
        self.selectedTrackID = selectedTrackID
        beatTiming = (bar.trackBeats[selectedTrackID] ?? []).map {
            NativeStudioBeatTimingState(duration: $0.duration, dot: $0.dot, triplet: $0.triplet)
        }
    }

}

struct NativeStudioChordLibraryState: Equatable {
    let projectID: String
    let track: StudioTrack
    let root: String
    let search: String
    let input: String
}

struct NativeStudioLyricsInspectorState: Equatable {
    let projectID: String
    let trackID: String
    let lyrics: String?
}

struct NativeStudioWarningsInspectorState: Equatable {
    let warnings: [String]
}

struct NativeStudioLinkedPracticeInspectorState: Equatable {
    let projectID: String
    let linkedID: String
}


struct NativeGMProgramRow: Identifiable {
    let program: Int
    let name: String
    let family: String
    var id: Int { program }
}

struct StudioMetadataDraft {}

