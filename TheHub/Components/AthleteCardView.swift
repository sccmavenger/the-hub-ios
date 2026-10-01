import SwiftUI

/// Discover / Board row for one athlete as a coach may see them. Shows only
/// allowlisted fields; the board badge comes from the program's own board.
struct AthleteCardView: View {
    let athlete: CoachAthleteCard
    var boardStage: PipelineStage? = nil
    var showsNextEvent = false
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HubRemoteImage(path: athlete.profilePhotoPath) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.hubTextSecondary)
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(athlete.fullName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let stage = boardStage ?? athlete.boardPipelineStage {
                        Text(stage.displayName)
                            .font(.caption2.bold())
                            .foregroundStyle(stage.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(stage.color.opacity(0.15))
                            .clipShape(Capsule())
                            .accessibilityLabel("On board: \(stage.displayName)")
                    }
                }

                Text(summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let school = athlete.schoolLine {
                    Text(school)
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    if let gpa = athlete.gpa {
                        Label(gpa.formatted(.number.precision(.fractionLength(1...2))), systemImage: "graduationcap")
                    }
                    if let miles = athlete.distanceMiles {
                        Label(miles == 0 ? "< 5 mi" : "\(miles) mi", systemImage: "location")
                    }
                    if showsNextEvent, let next = athlete.nextEventDate {
                        Label("Plays \(next.asFormattedDate())", systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
                .labelStyle(.titleAndIcon)
            }

            if let trailing {
                trailing
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// "Class of 2027 · Point Guard · 6'2\""
    private var summaryLine: String {
        [athlete.classLabel, athlete.position, athlete.heightDisplay]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
