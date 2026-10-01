import SwiftUI

/// Rule attribution: official source link, bylaw/reference, effective and
/// last-verified dates, rule version (spec §20). Shown under every rendered
/// decision so users can see *why* The Hub reached a result. Only a short
/// plain-English summary is stored server-side; the link goes to the
/// governing body's own document.
struct RecruitingRuleSourceView: View {
    let decision: RecruitingDecision

    var body: some View {
        if decision.sourceLink != nil || decision.lastVerifiedDate != nil || decision.sourceReference != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let url = decision.sourceLink {
                    Link(destination: url) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(decision.sourceTitle ?? "Official source")
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel("Open official source: \(decision.sourceTitle ?? "governing body document")")
                }

                if let reference = decision.sourceReference {
                    Text(reference)
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                }

                if let meta = Self.metaLine(for: decision) {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
        }
    }

    /// "In effect since Aug 1, 2026 · Last verified Sep 30, 2026 · Rule v1"
    static func metaLine(for decision: RecruitingDecision) -> String? {
        var parts: [String] = []
        if let from = decision.effectiveFrom {
            parts.append("In effect since \(from.asFormattedDate())")
        }
        if let verified = decision.lastVerifiedDate {
            parts.append("Last verified \(verified.formatted(date: .abbreviated, time: .omitted))")
        }
        if let version = decision.ruleVersion {
            parts.append("Rule v\(version)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
