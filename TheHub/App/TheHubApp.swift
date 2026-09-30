import SwiftUI

@main
struct TheHubApp: App {
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .onOpenURL { url in
                    // Auth callbacks arrive two ways: the thehub:// custom
                    // scheme (fallback) or the universal link to /confirmed.
                    let isCustomScheme = url.scheme == "thehub"
                    let isUniversalLink = url.host() == "thehubsh.net" && url.path() == "/confirmed"
                    guard isCustomScheme || isUniversalLink else { return }
                    Task {
                        try? await AuthService.shared.handleAuthCallback(url)
                    }
                }
        }
    }
}
