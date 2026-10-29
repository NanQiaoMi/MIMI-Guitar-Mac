import SwiftUI

struct MIMICommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("导入曲谱…") {
                model.openImportPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])
            .disabled(model.isImporting)
        }

        CommandMenu("播放") {
            Button(model.isScoreFocused ? "退出全屏阅谱" : "全屏阅谱") {
                model.toggleScoreFullscreen()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!model.canToggleScoreFullscreen)

            Button("播放或暂停") {
                NotificationCenter.default.post(name: Notification.Name("MIMI.TogglePlayback"), object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.canToggleScoreFullscreen)

            Button("停止") {
                NotificationCenter.default.post(name: Notification.Name("MIMI.StopPlayback"), object: nil)
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!model.canToggleScoreFullscreen)
        }

        CommandMenu("导航") {
            Button("返回上一页") { model.navigateBack() }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!model.canNavigateBack)
            Button("首页") { model.navigate(.home) }
        }
    }
}
