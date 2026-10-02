import SwiftUI
import Kingfisher

/// A 1080×1350 (4:5, Instagram-friendly) image of an athlete's public
/// headline, rendered on device for the share sheet (TestFlight feedback
/// 2026-10-01: "profiles should be shareable"). Profiles have no public web
/// page — only approved coaches can open one — so the share is an image plus
/// text, never a link into the app's private data. Contains only fields the
/// athlete already publishes on the preview header (no contact, DOB, or scores).
struct ProfileShareCard: View {
    let athlete: Athlete
    let photo: UIImage?

    static let size = CGSize(width: 1080, height: 1350)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.10, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)

            VStack(spacing: 36) {
                Spacer(minLength: 40)

                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.hubSurfaceElevated
                            Image(systemName: "person.fill")
                                .font(.system(size: 220))
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                }
                .frame(width: 440, height: 440)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.hubPrimary, lineWidth: 10))

                Text(athlete.fullName)
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 60)

                if !schoolLine.isEmpty {
                    Text(schoolLine)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 80)
                }

                chipRows

                Spacer()

                HStack(spacing: 16) {
                    Image(systemName: "basketball.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.hubPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The Hub by SummitHoops")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Recruiting profiles seen by verified college coaches · thehubsh.net")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                }
                .padding(.bottom, 64)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var schoolLine: String {
        [athlete.highSchool, [athlete.hometown, athlete.state].compactMap(\.self).joined(separator: ", ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private var chips: [String] {
        [
            athlete.position,
            athlete.gradYear.map { "Class of \($0)" },
            athlete.heightDisplay,
            athlete.weightLbs.map { "\($0) lbs" },
            athlete.jerseyNumber.map { "#\($0)" },
            athlete.gpa.map { "GPA \($0.formatted(.number.precision(.fractionLength(1...2))))" },
        ].compactMap(\.self)
    }

    /// Two centered rows of pills (max six chips) — a flow layout isn't needed at a fixed size.
    private var chipRows: some View {
        let items = Array(chips.prefix(6))
        let split = (items.count + 1) / 2
        return VStack(spacing: 18) {
            ForEach([Array(items.prefix(split)), Array(items.dropFirst(split))], id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(row, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

/// Renders the card off-screen and loads the profile photo through the same
/// signed-URL path the app uses elsewhere.
enum ProfileShare {
    static func photo(for athlete: Athlete) async -> UIImage? {
        var url: URL?
        if let path = athlete.profilePhotoPath {
            url = await MediaService.shared.url(for: path)
        }
        if url == nil, let legacy = athlete.profilePhotoUrl {
            url = URL(string: legacy)
        }
        guard let url else { return nil }
        return await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: url) { result in
                continuation.resume(returning: try? result.get().image)
            }
        }
    }

    @MainActor
    static func render(athlete: Athlete, photo: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: ProfileShareCard(athlete: athlete, photo: photo))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(ProfileShareCard.size)
        return renderer.uiImage
    }

    static func message(for athlete: Athlete) -> String {
        let details = [athlete.position, athlete.gradYear.map { "Class of \($0)" }, athlete.highSchool]
            .compactMap { $0 }.joined(separator: " · ")
        return "\(athlete.fullName)\(details.isEmpty ? "" : " — \(details)"). Recruiting profile on The Hub by SummitHoops: https://thehubsh.net/"
    }
}

#Preview("Share card") {
    ProfileShareCard(
        athlete: Athlete(
            id: "p", userId: "p", fullName: "Jalen Brooks", bio: nil, dateOfBirth: nil, profilePhotoUrl: nil,
            highSchool: "Summit Prep Academy", gradYear: 2027, gpa: 3.6, satScore: nil, actScore: nil,
            heightInches: 74, weightLbs: 175, position: "Point Guard", jerseyNumber: "3", sportGender: "mens",
            instagramHandle: nil, tiktokHandle: nil, intendedMajor: nil, hometown: "Chesterfield", state: "MO",
            zipCode: nil, latitude: nil, longitude: nil, ncaaId: nil, isPublished: true,
            guardianConsentAt: nil, guardianConsentEmail: nil, guardianConsentName: nil, createdAt: "", updatedAt: ""
        ),
        photo: nil
    )
    .scaleEffect(0.3)
    .frame(width: 324, height: 405)
}
