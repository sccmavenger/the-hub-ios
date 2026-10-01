import SwiftUI

/// A photo for the fullscreen pager, independent of the row type it came from.
nonisolated struct HubPhotoItem: Identifiable, Equatable, Sendable {
    let id: String
    let path: String?
    let legacyURL: String?
    let caption: String?

    init(_ photo: CoachPhoto) {
        id = photo.id
        path = photo.storagePath
        legacyURL = nil
        caption = photo.caption
    }

    init(_ photo: AthletePhoto) {
        id = photo.id
        path = photo.storagePath
        legacyURL = photo.url
        caption = photo.caption
    }
}

/// Fullscreen photo pager: swipe horizontally, captions below, close button.
struct HubPhotoPager: View {
    let items: [HubPhotoItem]
    let initialIndex: Int
    @State private var index = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    VStack(spacing: 12) {
                        HubRemoteImage(path: item.path, legacyURL: item.legacyURL, contentMode: .fit) {
                            ProgressView().tint(Color.hubTextSecondary)
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let caption = item.caption, !caption.isBlank {
                            Text(caption)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, Color.hubSurfaceElevated)
            }
            .padding()
            .accessibilityLabel("Close photo viewer")
        }
        .onAppear { index = min(max(initialIndex, 0), max(items.count - 1, 0)) }
    }
}

/// Wrapping-free chip row for short tags (position, class, measurables).
struct HubChipRow: View {
    let chips: [String]
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.hubSurfaceElevated)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }
}
