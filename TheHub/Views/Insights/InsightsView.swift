import SwiftUI
import Auth

/// Insights — who's looking at the profile and how strong it is.
/// Ported from the web app's /insights screen.
struct InsightsView: View {
    let athlete: Athlete

    @State private var views: [AthleteProfileView] = []
    @State private var bookmarkCount = 0
    @State private var videoCount = 0
    @State private var photoCount = 0
    @State private var eventCount = 0
    @State private var hasContact = false
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if loadFailed {
                LoadErrorState { await load() }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        statGrid
                        weeklyChart
                        uniqueProgramsCard
                        completenessCard
                        recentViewsList
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            async let views = AthleteService.shared.fetchProfileViews(athleteId: athlete.id)
            async let bookmarks = AthleteService.shared.fetchBookmarks(athleteId: athlete.id)
            async let videos = AthleteService.shared.fetchVideos(athleteId: athlete.id)
            async let photos = AthleteService.shared.fetchPhotos(athleteId: athlete.id)
            async let events = AthleteService.shared.fetchEvents(athleteId: athlete.id)
            async let contact = AthleteService.shared.fetchContact(athleteId: athlete.id)

            self.views = try await views
            self.bookmarkCount = try await bookmarks.count
            self.videoCount = try await videos.count
            self.photoCount = try await photos.count
            self.eventCount = try await events.count
            self.hasContact = (try await contact) != nil
            loadFailed = false
        } catch {
            // Zeroed stats after a network failure look like lost recruiting
            // activity — show the retry state instead.
            loadFailed = true
        }
        isLoading = false
    }

    private func viewCount(inLastDays days: Double, coachOnly: Bool = false) -> Int {
        let cutoff = Date.now.addingTimeInterval(-days * 86_400)
        return views.count {
            (!coachOnly || $0.viewerRole == "coach")
                && ($0.createdAt.asDate() ?? .distantPast) > cutoff
        }
    }

    // MARK: - Stats

    private var statGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statTile("\(viewCount(inLastDays: 7))", "Views this week")
                statTile("\(viewCount(inLastDays: 7, coachOnly: true))", "Coach views this week")
            }
            HStack(spacing: 12) {
                statTile("\(viewCount(inLastDays: 30))", "Views (30 days)")
                statTile("\(bookmarkCount)", "Coach bookmarks")
            }
        }
        .padding(.top, 8)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Chart

    private var weeklyChart: some View {
        let buckets: [Int] = (0..<8).map { weeksBack in
            let newest = Date.now.addingTimeInterval(Double(-weeksBack * 7) * 86_400)
            let oldest = newest.addingTimeInterval(-7 * 86_400)
            return views.count {
                guard let date = $0.createdAt.asDate() else { return false }
                return date > oldest && date <= newest
            }
        }.reversed().map { $0 }
        let peak = max(buckets.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Last 8 Weeks")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucketCount in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.hubPrimary)
                            .frame(height: max(4, CGFloat(bucketCount) / CGFloat(peak) * 88))
                        Text("\(bucketCount)")
                            .font(.caption2)
                            .foregroundStyle(Color.hubTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Programs

    private var uniqueProgramsCard: some View {
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        let programs = Set(
            views
                .filter { $0.viewerRole == "coach" && ($0.createdAt.asDate() ?? .distantPast) > cutoff }
                .map { $0.viewerLabel ?? "College program" }
        ).sorted()

        return Group {
            if !programs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(programs.count) college programs viewed this profile in the last 30 days")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(programs.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.hubSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Completeness

    private var completenessCard: some View {
        let items = ProfileCompleteness.items(
            athlete: athlete,
            videoCount: videoCount,
            photoCount: photoCount,
            eventCount: eventCount,
            hasContact: hasContact
        )
        let score = ProfileCompleteness.score(items: items)
        let tone = ProfileCompleteness.tone(score: score)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile Strength")
                        .font(.headline)
                        .foregroundStyle(Color.hubPrimary)
                    Text(tone.label)
                        .font(.caption)
                        .foregroundStyle(tone.isPositive ? Color.hubSuccess : Color.hubWarning)
                }
                Spacer()
                Text("\(score)%")
                    .font(.title2.bold())
                    .foregroundStyle(Color.hubPrimary)
            }

            ProgressView(value: Double(score), total: 100)
                .tint(Color.hubPrimary)

            let missing = items.filter { !$0.done }.sorted { $0.weight > $1.weight }
            ForEach(missing.prefix(3)) { item in
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.hubPrimary)
                    Text(item.label)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("+\(item.weight)")
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Recent views

    private var recentViewsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Views")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            if views.isEmpty {
                Text("No views yet — publish your profile so coaches can find you.")
                    .font(.subheadline)
                    .foregroundStyle(Color.hubTextSecondary)
            }

            ForEach(views.prefix(40)) { view in
                HStack {
                    Image(systemName: icon(for: view.viewerRole))
                        .foregroundStyle(Color.hubPrimary)
                        .frame(width: 28)
                    Text(label(for: view))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text(view.createdAt.asFormattedDate())
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func label(for view: AthleteProfileView) -> String {
        switch view.viewerRole {
        case "coach": "College coach — \(view.viewerLabel ?? "program not listed")"
        case "admin": "The Hub staff"
        case "athlete": "Another athlete"
        default: "Public visitor"
        }
    }

    private func icon(for role: String) -> String {
        switch role {
        case "coach": "graduationcap"
        case "admin": "shield"
        case "athlete": "figure.basketball"
        default: "person"
        }
    }
}

/// Insights entry from the More menu — loads the user's athlete first.
struct InsightsRootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var athlete: Athlete?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if let athlete {
                InsightsView(athlete: athlete)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.hubTextSecondary)
                    Text("No profile yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Insights are tied to an athlete profile. Create one from the Profile tab.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .navigationTitle("Insights")
        .task {
            defer { isLoading = false }
            guard let userId = authViewModel.session?.user.id.uuidString else { return }
            athlete = try? await AthleteService.shared.fetchManagedAthletes(userId: userId).first
        }
    }
}
