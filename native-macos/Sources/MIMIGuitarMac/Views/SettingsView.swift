import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mimi.appearance") private var appearance = "system"
    @AppStorage("mimi.motion.preference") private var motionPreference = "system"
    @State private var accountAddress = ""

    private var motionPolicy: MIMIMotionPolicy {
        MIMIMotionPolicy.resolve(preference: motionPreference, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(MIMITheme.displayFont(size: 26, weight: .bold))
                .foregroundStyle(MIMITheme.ink)

            Form {
                Section("外观与动效") {
                    Picker("外观", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Picker("动效", selection: $motionPreference) {
                        ForEach(MIMIMotionPreference.allCases) { value in Text(value.title).tag(value.rawValue) }
                    }
                    Text(motionPolicy.summary)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("本地曲库") {
                    LabeledContent("曲谱数量") {
                        Text(model.catalogCount == 0 ? "尚未载入" : "\(model.catalogCount.formatted()) 首")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("播放器与制谱工坊") {
                        Text("使用随包曲谱、AlphaTab 播放器与音源资源")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("本机个人资料") {
                    LabeledContent("存储方式") {
                        Text("仅保存在本机应用支持目录")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("导入文件限制") {
                        Text("单文件最大 30 MiB")
                            .foregroundStyle(.secondary)
                    }
                    if let directory = model.userDataDirectory {
                        HStack {
                            Text("数据目录")
                            Spacer()
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                        }
                    }
                    HStack(spacing: 12) {
                        Button("我的谱") { model.navigate(.library) }
                        Button("继续练习") { model.navigate(.practice(scoreID: nil)) }
                        Button("数据与备份") { model.navigate(.dataSettings) }
                    }
                }

                Section("账号服务") {
                    TextField("HTTPS 服务地址（本机开发可用 http://127.0.0.1）", text: $accountAddress)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("保存服务地址") { model.configureAccountService(accountAddress) }
                        Text("HTTPS 为默认要求；明文 HTTP 仅接受 localhost、严格 IPv4 loopback 或 ::1。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = model.accountMessage {
                        Text(message).font(.caption).foregroundStyle(model.accountMessageIsError ? Color.red : Color.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("关于 MIMI Guitar")
                    .font(MIMITheme.bodyFont(size: 13, weight: .semibold))
                Spacer()
                Button("帮助中心") { model.navigate(.document(.help)) }
                Button("授权说明") { model.navigate(.document(.licenses)) }
            }
            .padding(.horizontal, 6)
        }
        .padding(20)
        .background(MIMITheme.paper.ignoresSafeArea())
        .onAppear { accountAddress = model.accountServiceAddress }
    }
}
