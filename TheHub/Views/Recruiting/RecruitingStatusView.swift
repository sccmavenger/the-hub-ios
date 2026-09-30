import SwiftUI

extension RecruitingDecision {
    /// Badge tint per status. Needs-review is deliberately neutral, not a
    /// warning: it means "unknown", not "problem".
    var badgeColor: Color {
        switch status {
        case .permitted: Color.hubSuccess
        case .prohibited: Color.hubWarning
        case .permittedWithRestrictions: Color.hubPrimary
        case .needsReview: Color.hubTextSecondary
        }
    }
}

/// Capsule badge used everywhere a recruiting status appears, so Journey,
/// Colleges and Messages read the same way.
struct RecruitingStatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}

/// One recruiting action's status: title, badge, the server's plain-English
/// explanation, next date when known, a hint when the athlete's own profile
/// is what's missing, and the rule's source. Renders exactly what the
/// backend decided — no client-side interpretation.
struct RecruitingStatusView: View {
    let title: String
    let load: RecruitingStatusLoad
    var showsSource = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                badge
            }

            switch load {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.hubPrimary)
                    Text("Checking the rule…")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            case .unavailable:
                Text("Recruiting status unavailable. Check your connection and try again.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            case .loaded(let decision):
                Text(decision.userMessage)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if decision.status == .prohibited, let when = decision.nextPermittedDisplay {
                    Label("Starts \(when)", systemImage: "calendar")
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubWarning)
                }

                if let hint = decision.missingContextHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(Color.hubWarning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showsSource {
                    RecruitingRuleSourceView(decision: decision)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var badge: some View {
        switch load {
        case .loading:
            EmptyView()
        case .unavailable:
            RecruitingStatusBadge(label: "Unavailable", color: Color.hubTextSecondary)
        case .loaded(let decision):
            RecruitingStatusBadge(label: decision.badgeLabel, color: decision.badgeColor)
        }
    }
}

/// The athlete's own outreach. Sending a message from The Hub is a product
/// decision — always available — so the badge is fixed; when the engine has a
/// sourced rule for the context, its explanation and source are shown
/// underneath, otherwise the product note is.
struct AthleteOutreachStatusView: View {
    let load: RecruitingStatusLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your outreach")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                RecruitingStatusBadge(label: "You can reach out", color: Color.hubSuccess)
            }

            if case .loaded(let decision) = load, decision.status != .needsReview {
                Text(decision.userMessage)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                RecruitingRuleSourceView(decision: decision)
            } else {
                Text(Compliance.athleteOutreachNote)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let sample = RecruitingDecision(
        status: .prohibited,
        action: RecruitingAction.coachSendRecruitingElectronicCorrespondence.rawValue,
        actor: "coach",
        reason: "Rule ncaa.d1.basketball.mens.coach.electronic_correspondence v1",
        userMessage: "Under NCAA Division I rules for men's basketball, a college program may not send you recruiting materials or electronic messages until June 15 after your sophomore year of high school.",
        nextPermittedAt: "2027-06-15T04:00:00Z",
        nextPermittedOn: "2027-06-15",
        ruleTimeZone: "America/Indiana/Indianapolis",
        enforcement: .hardBlock,
        missingContext: [],
        conflict: false,
        governingBody: "NCAA",
        division: "D1",
        sport: "basketball",
        sportGender: "mens",
        contextSource: "client_supplied",
        evaluatedAt: "2026-09-30T12:00:00Z",
        ruleId: "b1b2c3d4-0002-4000-8000-000000000001",
        ruleKey: "ncaa.d1.basketball.mens.coach.electronic_correspondence",
        ruleVersion: 1,
        sourceTitle: "NCAA Division I Manual 2026-27 (LSDBi report 90008)",
        sourceUrl: "https://web3.ncaa.org/lsdbi/reports/getReport/90008",
        sourceReference: "Bylaw 13.4.1.5 Exception — Men's Basketball",
        effectiveFrom: "2026-08-01",
        effectiveUntil: nil,
        lastVerifiedAt: "2026-09-30T00:00:00Z"
    )
    VStack(spacing: 16) {
        RecruitingStatusView(title: "Coach recruiting messages", load: .loaded(sample))
        RecruitingStatusView(title: "NCAA D2", load: .unavailable)
        RecruitingStatusView(title: "NCAA D3", load: .loading)
        AthleteOutreachStatusView(load: .unavailable)
    }
    .padding()
    .background(Color.hubSurface)
    .preferredColorScheme(.dark)
}
