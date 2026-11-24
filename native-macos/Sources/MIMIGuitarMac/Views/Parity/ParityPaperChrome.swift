import MIMICore
import SwiftUI

struct PaperPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(2.6).foregroundStyle(Color(hex: 0x8A7151))
            Text(title).font(MIMITheme.displayFont(size: 44, weight: .medium)).tracking(-0.88).foregroundStyle(MIMITheme.ink)
            Text(subtitle).font(MIMITheme.bodyFont(size: 15)).foregroundStyle(MIMITheme.mutedInk)
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 760, alignment: .leading)
        }
    }
}

struct PaperNotice: View {
    let text: String
    var error = false
    var body: some View {
        Label(text, systemImage: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(MIMITheme.bodyFont(size: 13, weight: .medium))
            .foregroundStyle(error ? Color(hex: 0x9F3828) : Color(hex: 0x2E6B47))
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background((error ? Color(hex: 0xFCEFEB) : Color(hex: 0xEEF5ED)), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct PaperSectionTitle: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(MIMITheme.displayFont(size: 18, weight: .medium)).tracking(-0.18).foregroundStyle(MIMITheme.ink)
            if let detail { Text(detail).font(MIMITheme.bodyFont(size: 12)).foregroundStyle(MIMITheme.mutedInk) }
        }
    }
}


struct PaperProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 37).background(MIMITheme.ink.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PaperSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: .medium)).foregroundStyle(MIMITheme.bodyInk)
            .padding(.horizontal, 14).frame(minHeight: 37).background(MIMITheme.paperWhite, in: Capsule())
            .overlay(Capsule().stroke(MIMITheme.softBorder, lineWidth: 1)).opacity(configuration.isPressed ? 0.7 : 1)
    }
}


struct PaperGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) { configuration.label; configuration.content }
            .padding(18).background(MIMITheme.paperWhite, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(MIMITheme.softBorder, lineWidth: 1))
    }
}


struct PaperPageTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(MIMITheme.bodyFont(size: 12, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .white : MIMITheme.bodyInk).padding(.horizontal, 14).frame(height: 36)
            .background(selected ? MIMITheme.ink.opacity(configuration.isPressed ? 0.8 : 1) : .clear, in: Capsule())
    }
}
