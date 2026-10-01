import SwiftUI

/// The athlete-side "Recruiting status" card on My Colleges: outreach, then
/// coach-message status per division from the backend evaluator (D1/D2
/// engine-backed; D3/NAIA/JUCO keep the legacy orientation note, TECH-DEBT #21).
/// Extracted from `CollegeListView` so it can be previewed on its own.
struct RecruitingStatusCard: View {
    let outreach: RecruitingStatusLoad
    let d1Coach: RecruitingStatusLoad
    let d2Coach: RecruitingStatusLoad
    let gender: SportGender?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recruiting status")
                .font(.headline)
                .foregroundStyle(.white)

            AthleteOutreachStatusView(load: outreach)

            Divider().background(Color.hubBorder)

            Text("Coach recruiting messages")
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            RecruitingStatusView(title: "NCAA D1", load: d1Coach)
            RecruitingStatusView(title: "NCAA D2", load: d2Coach)

            ForEach(Compliance.divisionsWithoutEngineRules, id: \.self) { division in
                legacyDivisionRow(division)
            }

            if let gender {
                let calendar = Compliance.d1Calendar(gender: gender)
                Link(destination: calendar.url) {
                    Text(calendar.label)
                        .font(.caption)
                        .foregroundStyle(Color.hubBlue)
                        .multilineTextAlignment(.leading)
                }
            } else {
                Text("Set boys/girls basketball in your profile to see the calendar that applies to you.")
                    .font(.caption)
                    .foregroundStyle(Color.hubWarning)
            }

            Link("NCAA Eligibility Center", destination: Compliance.eligibilityCenterURL)
                .font(.caption)
                .foregroundStyle(Color.hubBlue)

            Text(Compliance.actionSpecificNote)
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)

            Text(Compliance.rulesEngineDisclaimer)
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)

            // Shown only while crest logos are switched on, since that's the
            // only time third-party marks appear on screen.
            if AppSettingsService.shared.collegeLogosEnabled {
                Text(Compliance.trademarkNotice)
                    .font(.caption2)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
        // Pin to the available width: without this the card sized itself to
        // its longest single line and the whole page could be dragged
        // sideways (TestFlight feedback 2026-09-30).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Legacy orientation row for divisions the engine has no sourced rule
    /// for. Kept verbatim by product decision (2026-09-30).
    private func legacyDivisionRow(_ division: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("NCAA \(division)".replacingOccurrences(of: "NCAA NAIA", with: "NAIA").replacingOccurrences(of: "NCAA JUCO", with: "JUCO / NJCAA"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                RecruitingStatusBadge(label: "Contact allowed", color: Color.hubSuccess)
            }
            if let note = Compliance.divisionNote(division) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Recruiting status card") {
    let prohibited = RecruitingDecision(
        status: .prohibited,
        action: RecruitingAction.coachSendRecruitingElectronicCorrespondence.rawValue,
        actor: "coach",
        reason: "Rule ncaa.d1.basketball.mens.coach.electronic_correspondence v1",
        userMessage: "Under NCAA Division I rules for men's basketball, a college program may not send you recruiting materials or electronic messages (email, texts, DMs) until June 15 after your sophomore year of high school.",
        nextPermittedAt: "2028-06-15T04:00:00Z",
        nextPermittedOn: "2028-06-15",
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
        sourceReference: "Bylaw 13.4.1.5 Exception — Men's Basketball (recruiting materials and electronic correspondence)",
        effectiveFrom: "2026-08-01",
        effectiveUntil: nil,
        lastVerifiedAt: "2026-09-29T00:00:00Z"
    )
    ScrollView {
        VStack(spacing: 16) {
            RecruitingStatusCard(outreach: .loaded(prohibited), d1Coach: .loaded(prohibited), d2Coach: .unavailable, gender: .mens)
        }
        .padding(.horizontal)
    }
    .background(Color.hubBackground)
    .preferredColorScheme(.dark)
}
