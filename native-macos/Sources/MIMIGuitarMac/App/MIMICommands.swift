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

        CommandGroup(after: .textEditing) {
            Button("全站搜索与跳转…") {
                model.presentCommandPalette()
            }
            .keyboardShortcut("f", modifiers: [.command])
        }

        CommandMenu("播放") {
            Section {
                Button(model.isScoreFocused ? "退出全屏阅谱" : "全屏阅谱") {
                    model.toggleScoreFullscreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!model.canToggleScoreFullscreen)

                Button("播放或暂停") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.TogglePlayback"), object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canToggleScoreFullscreen && model.auditionController.activeItem == nil)

                Button("停止") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.StopPlayback"), object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.canToggleScoreFullscreen && model.auditionController.activeItem == nil)
            }

            Section {
                Button("快退 5 秒") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.Player.SeekBackward"), object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!model.canToggleScoreFullscreen)

                Button("快进 5 秒") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.Player.SeekForward"), object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!model.canToggleScoreFullscreen)

                Button("上一小节") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.Player.PreviousBar"), object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
                .disabled(!model.canToggleScoreFullscreen)

                Button("下一小节") {
                    NotificationCenter.default.post(name: Notification.Name("MIMI.Player.NextBar"), object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.option])
                .disabled(!model.canToggleScoreFullscreen)
            }
        }

        CommandMenu("显示") {
            Button("放大曲谱") {
                NotificationCenter.default.post(name: Notification.Name("MIMI.Player.ZoomIn"), object: nil)
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(!model.canToggleScoreFullscreen)

            Button("缩小曲谱") {
                NotificationCenter.default.post(name: Notification.Name("MIMI.Player.ZoomOut"), object: nil)
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(!model.canToggleScoreFullscreen)

            Button("实际大小 (100%)") {
                NotificationCenter.default.post(name: Notification.Name("MIMI.Player.ZoomReset"), object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(!model.canToggleScoreFullscreen)
        }

        CommandMenu("导航") {
            Button("返回上一页") { model.navigateBack() }
                .keyboardShortcut("[", modifiers: [.command])
                .disabled(!model.canNavigateBack)
            Button("前往下一页") { model.navigateForward() }
                .keyboardShortcut("]", modifiers: [.command])
                .disabled(!model.canNavigateForward)
            Divider()
            Group {
                Button("首页") { model.navigate(.home) }
                    .keyboardShortcut("0", modifiers: [.command])
                Button("吉他谱") { model.navigate(.catalog(.guitar)) }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("尤克里里") { model.navigate(.catalog(.ukulele)) }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("制谱工坊 PRO") { model.navigate(.studio) }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("专栏文章") { model.navigate(.articles) }
                    .keyboardShortcut("4", modifiers: [.command])
            }
            Group {
                Button("我的练习") { model.navigate(.practice(scoreID: nil)) }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("我的谱") { model.navigate(.library) }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("备份") { model.navigate(.dataSettings) }
                    .keyboardShortcut("7", modifiers: [.command])
            }
        }
    }
}
