import SwiftUI

/// Reuses the full About document so the Settings window and in-app About route stay in sync.
struct AboutView: View {
    var body: some View {
        DocumentPageView(page: .about)
    }
}
