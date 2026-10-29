import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    private var selection: Binding<LibrarySection?> {
        Binding(
            get: { model.selectedSection },
            set: { section in
                if let section {
                    model.selectSection(section)
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("曲库") {
                row(.allScores)
                row(.guitar)
                row(.ukulele)
            }

            Section("我的曲谱") {
                row(.favorites)
                row(.queue)
                row(.recent)
            }

            Section("本应用") {
                Button { model.navigate(.document(.about)) } label: {
                    Label("关于 MIMI Guitar", systemImage: "info.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("本地曲库")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(model.catalogCount.formatted()) 首曲谱")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func row(_ section: LibrarySection) -> some View {
        Label(section.title, systemImage: section.symbol)
            .tag(section)
    }
}
