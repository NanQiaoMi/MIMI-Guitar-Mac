import AppKit
import MIMICore
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var coordinator: BackupCoordinator?
    @State private var v1Preview: PersonalBackupV1Preview?
    @State private var v2Preview: PersonalBackupV2Preview?
    @State private var isBusy = false
    @State private var progress = ""
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var restoreTask: Task<Void, Never>?

    private var data: PersonalData { model.personalSnapshot }
    private var entityCount: Int {
        data.scores.count + data.favorites.count + data.practiceItems.count + data.practiceFragments.count + data.resumes.count + data.sessions.count + data.projects.count + data.originals.count + data.history.count
    }
    private var referencedAssetCount: Int {
        var ids = Set<String>()
        for score in data.scores {
            if let a = score.assetId { ids.insert(a) }
            if let o = score.originalAssetId { ids.insert(o) }
        }
        for orig in data.originals {
            ids.insert(orig.assetId)
        }
        return ids.count
    }
    private var store: PersonalStore? { model.personalStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaperPageHeader(eyebrow: "本设备个人资料", title: "数据与备份", subtitle: "查看本设备资料、导出完整备份，或先校验备份内容再合并恢复。")
            if let notice { PaperNotice(text: notice) }
            if let errorMessage { PaperNotice(text: errorMessage, error: true) }
            if isBusy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(progress.isEmpty ? "正在处理个人资料…" : progress).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }.padding(12).mimiCard(radius: 12, fill: MIMITheme.paperWhite, shadowOpacity: 0.02) }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    PaperSectionTitle(title: "本机资料状态", detail: "SQLite 个人资料与曲库快照分开保存在 Application Support 中。")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        dataMetric("个人曲谱", data.scores.count, "music.note.list")
                        dataMetric("收藏", data.favorites.count, "heart")
                        dataMetric("待练 / 归档", data.practiceItems.count, "metronome")
                        dataMetric("练习会话", data.sessions.count, "clock")
                        dataMetric("工坊工程", data.projects.count, "square.grid.3x3.square")
                        dataMetric("练习片段", data.practiceFragments.count, "point.topleft.down.curvedto.point.bottomright.up")
                        dataMetric("播放断点", data.resumes.count, "bookmark")
                        dataMetric("浏览历史", data.history.count, "clock.arrow.circlepath")
                    }
                    HStack { Label("Revision \(data.revision)", systemImage: "number"); Spacer(); Label("\(referencedAssetCount) 份引用附件", systemImage: "paperclip"); Spacer(); Label(data.migrationCompleted ? "本机资料已就绪" : "迁移未完成", systemImage: data.migrationCompleted ? "checkmark.circle" : "exclamationmark.triangle") }
                        .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(data.migrationCompleted ? MIMITheme.mutedInk : MIMITheme.terracotta)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    PaperSectionTitle(title: "v1 JSON 备份", detail: "兼容原站单文件格式，包含完整个人实体与所有引用附件。")
                    HStack(spacing: 10) {
                        Button("生成完整 v1 JSON…", action: exportV1).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy || !data.migrationCompleted)
                        Text("最多 64 MiB；单附件 30 MiB、附件合计 927 MiB、最多 500 份附件与 10,000 个资料实体。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "v2 长期分卷备份", detail: "每卷负载最多 8 MiB；全部卷由 MIMI2VOL 头、分块和 SHA-256 校验。")
                    HStack(spacing: 10) {
                        Button("生成 v2 备份文件夹…", action: exportV2).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy || !data.migrationCompleted)
                        Text("最多 128 卷，总文件大小不超过 1 GiB；生成后清单与卷文件都会写入所选位置下的新文件夹。")
                            .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "校验并恢复 v1", detail: "先选择一个完整 JSON 文件并验证 schema、摘要、清单、附件及实体上限。预览不会改变本机资料。")
                    HStack(spacing: 10) {
                        Button("选择并校验 JSON 备份…", action: previewV1).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy)
                        if v1Preview != nil { Button("取消预览") { v1Preview = nil }.buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy) }
                    }
                    if let preview = v1Preview {
                        backupPreview(title: "v1 完整性校验通过", revision: preview.expectedRevision, scoreCount: preview.data.scores.count, attachmentCount: preview.assets.count, fileSize: preview.fileSize, detail: "Schema \(preview.manifest.schemaVersion) · \(preview.data.favorites.count) 收藏 · \(preview.data.practiceItems.count) 练习条目 · \(preview.data.sessions.count) 会话 · \(preview.data.projects.count) 工程")
                        HStack { Button("合并并恢复此备份", action: restoreV1).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy); Text("恢复会将这份通过校验的快照合并到当前资料，遇到冲突由存储层保留可恢复的双方记录。") .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())

            GroupBox {
                VStack(alignment: .leading, spacing: 13) {
                    PaperSectionTitle(title: "校验并恢复 v2 分卷", detail: "先选择一份 JSON 清单，再选择同一备份的全部二进制卷。卷顺序不限；缺卷、混卷或损坏都会拒绝预览。")
                    HStack(spacing: 10) {
                        Button("选择清单与全部分卷…", action: previewV2).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy)
                        if v2Preview != nil { Button("取消预览并清理暂存", action: cancelV2Preview).buttonStyle(PaperSecondaryButtonStyle()).disabled(isBusy) }
                    }
                    if let preview = v2Preview {
                        backupPreview(title: "v2 全部卷校验通过", revision: preview.expectedRevision, scoreCount: preview.data.scores.count, attachmentCount: preview.assetCount, fileSize: preview.fileSize, detail: "Schema \(preview.manifest.schemaVersion) · \(preview.volumeCount) 卷 · \(preview.data.favorites.count) 收藏 · \(preview.data.practiceItems.count) 练习条目 · \(preview.data.sessions.count) 会话 · \(preview.data.projects.count) 工程")
                        HStack { Button("合并并恢复此备份", action: restoreV2).buttonStyle(PaperProminentButtonStyle()).disabled(isBusy); Text("暂存附件须全部通过长度与 SHA-256 校验后，才会用单个事务提交。") .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.groupBoxStyle(PaperGroupBoxStyle())
            Text("备份只包含本机个人资料，不读取浏览器 IndexedDB 或浏览器 localStorage。请保留原备份文件；原生资料目录：\(model.userDataDirectory?.path ?? "初始化后显示")")
                .font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.mutedInk).textSelection(.enabled)
        }
        .onAppear { model.refreshPersonalData(); if let store { coordinator = BackupCoordinator(store: store) } }
        .onChange(of: model.personalSnapshot.revision) { _ in if let store { coordinator = BackupCoordinator(store: store) } }
        .onDisappear { restoreTask?.cancel() }
    }

    private func dataMetric(_ title: String, _ count: Int, _ symbol: String) -> some View {
        HStack(spacing: 9) { Image(systemName: symbol).foregroundStyle(MIMITheme.darkGold); VStack(alignment: .leading, spacing: 2) { Text(title).font(.system(size: 10)).foregroundStyle(MIMITheme.mutedInk); Text(count.formatted()).font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(MIMITheme.ink) } }
            .padding(11).frame(maxWidth: .infinity, alignment: .leading).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(MIMITheme.softBorder, lineWidth: 1))
    }
    private func backupPreview(title: String, revision: Int, scoreCount: Int, attachmentCount: Int, fileSize: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "checkmark.seal.fill").font(MIMITheme.bodyFont(size: 13, weight: .semibold)).foregroundStyle(MIMITheme.green)
            Text(detail).font(MIMITheme.bodyFont(size: 11)).foregroundStyle(MIMITheme.bodyInk)
            Text("\(scoreCount) 份曲谱 · \(attachmentCount) 份附件 · \(String(format: "%.2f", Double(fileSize) / 1_048_576)) MiB · 预览基于本机 revision \(revision)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(MIMITheme.mutedInk)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xEEF5ED), in: RoundedRectangle(cornerRadius: 12))
    }

    private func exportV1() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "MIMI-Personal-Backup-v1.json"; panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        runTask("正在验证个人资料并生成 v1 JSON…") {
            let bytes = try await coordinator.exportV1()
            try bytes.write(to: destination, options: .atomic)
            await MainActor.run { notice = "完整 v1 备份已写入：\(destination.path)"; NSWorkspace.shared.activateFileViewerSelecting([destination]) }
        }
    }
    private func exportV2() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSOpenPanel(); panel.title = "选择 v2 备份保存位置"; panel.prompt = "选择此文件夹"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        runTask("正在生成 v2 清单和分卷文件…") {
            let output = try await coordinator.exportV2(to: directory)
            await MainActor.run { notice = "v2 备份已写入 \(output.manifestURL.deletingLastPathComponent().path)，包含清单和 \(output.volumeURLs.count) 卷（\(String(format: "%.2f", Double(output.totalFileBytes) / 1_048_576)) MiB）。"; NSWorkspace.shared.activateFileViewerSelecting([output.manifestURL]) }
        }
    }
    private func previewV1() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let panel = NSOpenPanel(); panel.title = "选择 v1 JSON 个人资料备份"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runTask("正在验证 JSON 摘要、实体和完整附件…") {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= PersonalBackupLimits.maximumV1BackupBytes else { throw PersonalBackupError.invalid("JSON 备份超过 64 MiB 上限，未读取或恢复。") }
            let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            let preview = try await coordinator.previewV1(bytes)
            await MainActor.run { v1Preview = preview; v2Preview = nil; notice = nil }
        }
    }
    private func previewV2() {
        guard let coordinator else { errorMessage = "本地资料尚未就绪。"; return }
        let manifestPanel = NSOpenPanel(); manifestPanel.title = "选择 v2 备份 JSON 清单"; manifestPanel.allowedContentTypes = [.json]; manifestPanel.canChooseDirectories = false; manifestPanel.allowsMultipleSelection = false
        guard manifestPanel.runModal() == .OK, let manifestURL = manifestPanel.url else { return }
        let volumePanel = NSOpenPanel(); volumePanel.title = "选择此清单对应的全部 MIMI2VOL 分卷"; volumePanel.allowedContentTypes = [UTType(filenameExtension: "mibak2") ?? .data]; volumePanel.canChooseDirectories = false; volumePanel.allowsMultipleSelection = true
        guard volumePanel.runModal() == .OK, !volumePanel.urls.isEmpty else { return }
        runTask("正在逐卷校验版本、长度和 SHA-256…") {
            let metadata = try FileManager.default.attributesOfItem(atPath: manifestURL.path)
            guard let size = metadata[.size] as? NSNumber, size.intValue <= PersonalBackupLimits.maximumManifestBytes else { throw PersonalBackupError.invalid("v2 JSON 清单超过 64 MiB 上限。") }
            let bytes = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            let preview = try await coordinator.previewV2(manifest: bytes, volumeURLs: volumePanel.urls)
            await MainActor.run { v2Preview = preview; v1Preview = nil; notice = nil }
        }
    }
    private func restoreV1() {
        guard let coordinator, let preview = v1Preview else { return }
        runTask("正在以 revision \(preview.expectedRevision) 合并完整 v1 备份…") {
            _ = try await coordinator.restoreV1(preview, expectedRevision: preview.expectedRevision)
            await MainActor.run { v1Preview = nil; notice = "v1 备份已通过完整校验并合并提交；本机资料已更新。"; model.refreshPersonalData() }
        }
    }
    private func restoreV2() {
        guard let coordinator, let preview = v2Preview else { return }
        runTask("正在提交 v2 备份事务…") {
            _ = try await coordinator.restoreV2(preview, expectedRevision: preview.expectedRevision)
            await MainActor.run { v2Preview = nil; notice = "v2 备份已通过全部卷校验并合并提交；本机资料已更新。"; model.refreshPersonalData() }
        }
    }
    private func cancelV2Preview() {
        guard let coordinator, let preview = v2Preview else { v2Preview = nil; return }
        runTask("正在取消预览并清理暂存附件…") {
            try await coordinator.cancelV2Preview(preview)
            await MainActor.run { v2Preview = nil; notice = "v2 预览已取消，暂存附件已清理；本机资料未改变。" }
        }
    }
    private func runTask(_ status: String, operation: @escaping () async throws -> Void) {
        restoreTask?.cancel(); isBusy = true; progress = status; errorMessage = nil; notice = nil
        restoreTask = Task { @MainActor in
            defer { isBusy = false; progress = "" }
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

