import SwiftUI
import MIMICore

struct InspectorView: View {
    let item: CatalogItem?
    let importedFileURL: URL?
    let importedOriginalFileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("曲谱检查器")
                    .font(.headline)
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            Divider()
                .padding(.bottom, 14)

            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            fieldLabel("曲名")
                            Text(item.title)
                                .font(.callout.weight(.medium))
                                .textSelection(.enabled)
                        }

                        InspectorField(label: "艺术家", value: item.artist?.isEmpty == false ? item.artist! : "未知艺术家")
                        InspectorField(label: "乐器", value: categoryLabel(item.category))
                        InspectorField(label: "格式", value: item.format.uppercased())
                        InspectorField(label: "难度", value: String(item.difficulty))

                        if let bpm = item.bpm {
                            InspectorField(label: "速度", value: "\(bpm) BPM")
                        }
                        if let key = item.key, !key.isEmpty {
                            InspectorField(label: "调性", value: key)
                        }
                        InspectorField(label: "谱面类型", value: String(item.sheetForm))

                        if let importedFileURL {
                            VStack(alignment: .leading, spacing: 5) {
                                fieldLabel("导入文件")
                                Text(importedOriginalFileName ?? item.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                                Text("已复制到本应用的 Imports 文件夹")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 2)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(importedOriginalFileName ?? item.title)，已复制到本应用的 Imports 文件夹，\(importedFileURL.lastPathComponent)")
                        }

                        if let reference = item.scoreURL, !reference.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                fieldLabel("曲库资源")
                                Text(URL(fileURLWithPath: reference).lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("选择曲谱即可查看详细信息。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
    }

    private func categoryLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "guitar": return "吉他"
        case "ukulele": return "尤克里里"
        case "imported": return "导入曲谱"
        default: return value
        }
    }
}

private struct InspectorField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}
