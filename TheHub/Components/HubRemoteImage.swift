import SwiftUI
import Kingfisher

/// Protected athlete media. Resolves a storage `path` to a short-lived signed
/// URL through `MediaService`, falling back to a legacy stored URL for rows
/// written before supabase/015. Kingfisher's cache key is the *path*, so a
/// re-signed URL hits the same cached bytes.
///
/// Usage mirrors the old `KFImage(...).placeholder{}.resizable().scaledToFill()`
/// chain; add `.frame` / `.clipShape` after it as before.
struct HubRemoteImage<Placeholder: View>: View {
    let path: String?
    let legacyURL: String?
    let contentMode: SwiftUI.ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var media = MediaService.shared
    @State private var resolved: URL?

    init(
        path: String?,
        legacyURL: String? = nil,
        contentMode: SwiftUI.ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.path = path
        self.legacyURL = legacyURL
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        KFImage(source: source)
            .placeholder { placeholder() }
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .task(id: "\(path ?? "")|\(legacyURL ?? "")") {
                await resolve()
            }
    }

    private var source: Source? {
        guard let resolved else { return nil }
        return .network(KF.ImageResource(downloadURL: resolved, cacheKey: path ?? resolved.absoluteString))
    }

    private func resolve() async {
        if let path, !path.isEmpty {
            if let signed = await media.url(for: path) {
                resolved = signed
                return
            }
        }
        // No path (pre-015 row) or signing refused: legacy URL if any, else placeholder.
        resolved = legacyURL.flatMap { URL(string: $0) }
    }
}
