import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// 跨平台色彩与系统事件适配层，支持 macOS、iPadOS 与 iOS 在 Xcode 下统一编译与渲染
enum MIMIPlatformColor {
    static var separator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #elseif os(iOS)
        Color(uiColor: .separator)
        #else
        Color.gray.opacity(0.3)
        #endif
    }

    static var secondarySystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(red: 0.965, green: 0.948, blue: 0.914)
        #endif
    }

    static var tertiarySystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .tertiarySystemBackground)
        #else
        Color(red: 0.984, green: 0.976, blue: 0.957)
        #endif
    }
}

enum MIMISystemNotification {
    static var appWillResignActive: Notification.Name {
        #if os(macOS)
        NSApplication.didResignActiveNotification
        #elseif os(iOS)
        UIApplication.willResignActiveNotification
        #else
        Notification.Name("MIMIAppWillResignActive")
        #endif
    }

    static var appWillSleep: Notification.Name {
        #if os(macOS)
        NSWorkspace.willSleepNotification
        #elseif os(iOS)
        UIApplication.didEnterBackgroundNotification
        #else
        Notification.Name("MIMIAppWillSleep")
        #endif
    }
}
