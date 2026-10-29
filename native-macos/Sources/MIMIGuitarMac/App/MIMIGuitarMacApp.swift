import SwiftUI

@main
struct MIMIGuitarMacApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("mimi.appearance") private var appearance = "system"

    var body: some Scene {
        Window("MIMI Guitar", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
                .frame(minWidth: 980, minHeight: 620)
                .task {
                    MIMIFontRegistry.registerBundledFonts()
                    model.bootstrap()
                }
        }
        .defaultSize(width: 1320, height: 820)
        .commands {
            SidebarCommands()
            MIMICommands(model: model)
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
                .frame(width: 580, height: 540)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
