import SwiftUI

struct SourceTabNote {
    let string: Int
    let fret: Int
    let isRoot: Bool
}

struct SourceTabColumn {
    let chordName: String
    let notes: [SourceTabNote]
}

struct SourceMasterpiece: Identifiable {
    let id: String
    let title: String
    let artist: String
    let seal: String
    let sealColor: Color
    let key: String
    let keyDescription: String
    let difficulty: Int
    let level: String
    let levelColor: Color
    let bpm: Int
    let timeSignature: String
    let chords: [String]
    let sheetForm: Int
    let tabColumns: [SourceTabColumn]
}

struct StageMasterpiece: Identifiable {
    let id: String
    let title: String
    let artist: String
    let key: String
    let difficulty: Int
    let sheetForm: String
    let seal: String
    let chords: [String]
    let description: String
}

enum HomeMasterpieceData {
    private static func columns(_ values: [String]) -> [SourceTabColumn] {
        values.map { value in
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            let notes = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { encoded -> SourceTabNote? in
                let fields = encoded.split(separator: ":", maxSplits: 1).map(String.init)
                guard fields.count == 2, let string = Int(fields[0]) else { return nil }
                let root = fields[1].hasSuffix("*")
                let fretText = root ? String(fields[1].dropLast()) : fields[1]
                guard let fret = Int(fretText) else { return nil }
                return SourceTabNote(string: string, fret: fret, isRoot: root)
            }
            return SourceTabColumn(chordName: parts.first ?? "", notes: notes)
        }
    }

    static let rows: [SourceMasterpiece] = [
        .init(id: "1sdc49P3eKm", title: "晴天", artist: "周杰伦", seal: "晴", sealColor: Color(hex: 0xC84B31), key: "G", keyDescription: "G 调 · 原版指弹", difficulty: 2, level: "L2 初级", levelColor: Color(hex: 0x2E7D32), bpm: 80, timeSignature: "4/4 拍", chords: ["G", "Em7", "Cadd9", "D"], sheetForm: 4, tabColumns: columns(["G|6:3*,3:0,2:3,1:3", "Em7|6:0*,3:0,2:3,1:3", "Cadd9|5:3*,3:0,2:3,1:3", "D|4:0*,3:2,2:3,1:2"])),
        .init(id: "1sdiivPR3YW", title: "老男孩", artist: "筷子兄弟", seal: "老", sealColor: Color(hex: 0xA86A3D), key: "C", keyDescription: "C 调 · 原版民谣", difficulty: 1, level: "L1 入门", levelColor: Color(hex: 0x1976D2), bpm: 80, timeSignature: "4/4 拍", chords: ["C", "G", "Am", "Em"], sheetForm: 4, tabColumns: columns(["C|5:3*,3:0,2:1,1:0", "G|6:3*,3:0,2:0,1:3", "Am|5:0*,3:2,2:1,1:0", "Em|6:0*,3:0,2:0,1:0"])),
        .init(id: "1sdjKw3nhA0", title: "反方向的钟", artist: "周杰伦", seal: "钟", sealColor: Color(hex: 0x795548), key: "B", keyDescription: "B 调 · 专业指弹", difficulty: 3, level: "L3 进阶", levelColor: Color(hex: 0xE65100), bpm: 86, timeSignature: "4/4 拍", chords: ["B", "G#m", "E", "F#"], sheetForm: 4, tabColumns: columns(["B|5:2*,4:4,3:4,2:4", "G#m|6:4*,4:6,3:4,2:4", "E|6:0*,5:2,4:2,3:1", "F#|6:2*,5:4,4:4,3:3"])),
        .init(id: "1yDFAg9Z3mU", title: "后来", artist: "刘若英", seal: "后", sealColor: Color(hex: 0x00897B), key: "Eb", keyDescription: "Eb 调 · 经典独奏", difficulty: 2, level: "L2 初级", levelColor: Color(hex: 0x2E7D32), bpm: 75, timeSignature: "4/4 拍", chords: ["Eb", "Cm", "Ab", "Bb"], sheetForm: 4, tabColumns: columns(["Eb|5:6*,4:5,3:3,2:4", "Cm|5:3*,4:5,3:5,2:4", "Ab|6:4*,4:6,3:5,2:4", "Bb|5:1*,4:3,3:3,2:3"])),
        .init(id: "1sdikNKaVJg", title: "成都", artist: "赵雷", seal: "都", sealColor: Color(hex: 0x5D4037), key: "D", keyDescription: "D 调 · 民谣原版", difficulty: 2, level: "L2 初级", levelColor: Color(hex: 0x2E7D32), bpm: 76, timeSignature: "4/4 拍", chords: ["D", "Bm7", "G", "A"], sheetForm: 4, tabColumns: columns(["D|4:0*,3:2,2:3,1:2", "Bm7|5:2*,3:2,2:3,1:2", "G|6:3*,3:0,2:0,1:3", "A|5:0*,4:2,3:2,2:2"])),
        .init(id: "1sdixfUd4Vc", title: "卡农", artist: "Johann Pachelbel", seal: "卡", sealColor: Color(hex: 0x303F9F), key: "D", keyDescription: "D 调 · 古典大作", difficulty: 4, level: "L4 大师", levelColor: Color(hex: 0x6A1B9A), bpm: 80, timeSignature: "4/4 拍", chords: ["D", "A", "Bm", "F#m"], sheetForm: 2, tabColumns: columns(["D|4:0*,3:2,2:3,1:2", "A|5:0*,3:2,2:2,1:0", "Bm|5:2*,3:4,2:3,1:2", "F#m|6:2*,4:4,3:2,2:2"])),
        .init(id: "20oEfH3di0w", title: "稻香", artist: "周杰伦", seal: "稻", sealColor: Color(hex: 0xE65100), key: "G", keyDescription: "G 调 · 流行经典", difficulty: 1, level: "L1 入门", levelColor: Color(hex: 0x1976D2), bpm: 70, timeSignature: "4/4 拍", chords: ["G", "D", "Em", "C"], sheetForm: 4, tabColumns: columns(["G|6:3*,4:0,3:0,2:3", "D|4:0*,3:2,2:3,1:2", "Em|6:0*,4:2,3:0,2:0", "C|5:3*,4:2,3:0,2:1"])),
        .init(id: "1sdcWsfNEe0", title: "斑马斑马", artist: "宋冬野", seal: "斑", sealColor: Color(hex: 0x455A64), key: "G", keyDescription: "G 调 · 民谣指弹", difficulty: 2, level: "L2 初级", levelColor: Color(hex: 0x2E7D32), bpm: 65, timeSignature: "4/4 拍", chords: ["G", "D", "Em", "C"], sheetForm: 4, tabColumns: columns(["G|6:3*,3:0,2:0,1:3", "D|4:0*,3:2,2:3,1:2", "Em|6:0*,3:0,2:0,1:0", "C|5:3*,3:0,2:1,1:0"])),
        .init(id: "1yDFB6u7GnQ", title: "达尔文", artist: "林俊杰", seal: "达", sealColor: Color(hex: 0xC2185B), key: "Gb", keyDescription: "Gb 调 · 原版编曲", difficulty: 2, level: "L2 初级", levelColor: Color(hex: 0x2E7D32), bpm: 68, timeSignature: "4/4 拍", chords: ["Gb", "Db", "Ebm", "B"], sheetForm: 4, tabColumns: columns(["Gb|6:2*,4:4,3:3,2:2", "Db|5:4*,4:3,3:1,2:2", "Ebm|5:6*,4:4,3:3,2:4", "B|5:2*,4:4,3:4,2:4"])),
    ]
}

enum HomeMasterpieceStageData {
    static let rows: [StageMasterpiece] = [
        .init(id: "1sdc49P3eKm", title: "晴天", artist: "周杰伦", key: "G", difficulty: 2, sheetForm: "指弹谱", seal: "晴", chords: ["G", "Em7", "Cadd9", "D"], description: "华语乐坛青春图腾，经典前奏原版指弹，前奏滑音与和弦分解极其优美。"),
        .init(id: "1sdiivPR3YW", title: "老男孩", artist: "筷子兄弟", key: "C", difficulty: 1, sheetForm: "指弹谱", seal: "老", chords: ["C", "G", "Am", "F"], description: "指弹经典入门圣经，旋律线条深情动人，适合新手第一首完整攻克的指弹金曲。"),
        .init(id: "1sdjKw3nhA0", title: "反方向的钟", artist: "周杰伦", key: "B", difficulty: 3, sheetForm: "专业弹唱", seal: "钟", chords: ["B", "G#m", "E", "F#"], description: "时空倒流感编曲，经典吉他分解和弦与切音节奏，高级吉他手进阶必练。"),
        .init(id: "1yDFAg9Z3mU", title: "后来", artist: "刘若英", key: "Eb", difficulty: 2, sheetForm: "指弹独奏", seal: "后", chords: ["Eb", "Cm", "Ab", "Bb"], description: "温暖治愈的经典旋律，高音区泛音与琶音交织，细腻触弦质感拉满。"),
    ]
}

enum HomeSearchPlaceholder {
    static let values = [
        "搜索曲谱、歌手名、或输入和弦（如 G Em7 Cadd9）...",
        "试试搜索：周杰伦《晴天》指弹独奏谱...",
        "试试搜索：筷子兄弟《老男孩》原版吉他谱...",
        "试试搜索：赵雷《我记得》民谣弹唱谱...",
        "试试搜索：古典名作《卡农》专业级总谱...",
        "试试搜索：蔡健雅《Letting Go》原版吉他谱...",
    ]
}
