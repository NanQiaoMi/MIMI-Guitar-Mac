import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { return }
        let url = URL(fileURLWithPath: first)
        DispatchQueue.main.async { [weak self] in
            self?.model?.routeImportedFile(url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let first = urls.first else { return }
        DispatchQueue.main.async { [weak self] in
            if first.isFileURL {
                self?.model?.routeImportedFile(first)
            } else {
                self?.model?.openURL(first)
            }
        }
    }
}

@main
struct MIMIGuitarMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("mimi.appearance") private var appearance = "system"

    var body: some Scene {
        Window("MIMI Guitar", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .preferredColorScheme(preferredColorScheme)
                .frame(minWidth: 980, minHeight: 620)
                .task {
                    appDelegate.model = model
                    MIMIFontRegistry.registerBundledFonts()
                    model.bootstrap()
                }
        }
        .defaultSize(width: 1320, height: 820)
        .handlesExternalEvents(matching: Set(["*"]))
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
