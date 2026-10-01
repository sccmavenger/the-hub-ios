import SwiftUI
import Auth

/// NCAA Journey — grade-aware guidance through the NCAA eligibility process.
/// The Hub tracks self-reported progress and links to official NCAA workflows;
/// the Eligibility Center remains the authority on certification, so every
/// derived value is labeled as an estimate.
struct NCAAJourneyView: View {
    let athlete: Athlete

    @State private var readiness: NCAAReadiness
    @State private var isLoading: Bool
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var gpaText = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var gpaFocused: Bool

    // Recruiting Rules Engine decisions (backend-evaluated; see
    // RecruitingRulesService). Re-fetched when the intended division changes.
    @State private var coachMessagesStatus: RecruitingStatusLoad = .loading
    @State private var athleteOutreachStatus: RecruitingStatusLoad = .loading

    init(athlete: Athlete, readiness: NCAAReadiness? = nil) {
        self.athlete = athlete
        _readiness = State(initialValue: readiness ?? .empty(athleteId: athlete.id))
        _isLoading = State(initialValue: readiness == nil)
    }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if let loadError {
                // A failed fetch must never fall through to the editable empty
                // state — the first edit would overwrite saved progress.
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.hubWarning)
                    Text("Couldn't load your progress")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try Again") {
                        isLoading = true
                        self.loadError = nil
                        Task { await loadIfNeeded() }
                    }
                    .bold()
                    .foregroundStyle(Color.hubPrimary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        disclaimerBanner
                        if let saveError {
                            saveErrorBanner(saveError)
                        }
                        // The division pills sit ABOVE everything that depends on
                        // them (hero, timeline, rules, GPA minimums), so changing
                        // the division only re-lays-out content below the finger
                        // and the page no longer jumps (TestFlight feedback 2026-10-01).
                        divisionPicker
                        nextStepHero
                        timelineCard
                        recruitingCommunicationCard
                        academicReadinessCard
                        progressCard
                        footerNote
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                // The decimal pad has no return key, so without this (and the
                // Done accessory below) the GPA keyboard could not be
                // dismissed and covered the toggles underneath it.
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("NCAA Journey")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { gpaFocused = false }
                    .foregroundStyle(Color.hubPrimary)
            }
        }
        .task { await loadIfNeeded() }
        .task(id: readiness.intendedDivision) { await loadRecruitingStatus() }
        .onChange(of: readiness) {
            guard !isLoading else { return }
            scheduleSave()
        }
        .onChange(of: gpaText) { commitGPAText() }
    }

    // MARK: - Grade derivation

    /// School years run July–June, so from July onward we count the upcoming year.
    private var grade: Int? {
        guard let gradYear = athlete.gradYear else { return nil }
        let components = Calendar.current.dateComponents([.year, .month], from: .now)
        guard let year = components.year, let month = components.month else { return nil }
        let schoolYearEnd = month >= 7 ? year + 1 : year
        return 12 - (gradYear - schoolYearEnd)
    }

    private var gradeLabel: String? {
        guard let grade else { return nil }
        switch grade {
        case ..<9: return "Middle school"
        case 9: return "Freshman"
        case 10: return "Sophomore"
        case 11: return "Junior"
        case 12: return "Senior"
        default: return "Post-grad"
        }
    }

    // MARK: - Timeline model

    private enum StepState { case done, current, upcoming }

    private struct TimelineStep: Identifiable {
        let id: String
        let state: StepState
        let when: String
        let title: String
        let detail: String
        var badge: String?
        var link: (label: String, url: URL)?
    }

    private var isD1orD2Track: Bool {
        readiness.intendedDivision == .d1 || readiness.intendedDivision == .d2
    }

    private var timelineSteps: [TimelineStep] {
        var steps: [TimelineStep] = []
        var currentAssigned = false
        let gradeNow = grade ?? 0
        let isD3 = readiness.intendedDivision == .d3

        func state(done: Bool, startGrade: Int, informational: Bool = false) -> StepState {
            if done { return .done }
            if !informational && !currentAssigned && gradeNow >= startGrade {
                currentAssigned = true
                return .current
            }
            return .upcoming
        }

        steps.append(TimelineStep(
            id: "core",
            state: state(done: readiness.coreCoursesCompleted > 0 || gradeNow > 9, startGrade: 9),
            when: "Freshman year",
            title: "Start NCAA-approved core courses",
            detail: readiness.coreCoursesCompleted > 0
                ? "You've logged \(readiness.coreCoursesCompleted). Keep checking new classes against your school's approved list."
                : "Check every class against your school's NCAA-approved course list.",
            link: ("What counts as a core course?", Compliance.coreCoursesURL)
        ))

        steps.append(TimelineStep(
            id: "account",
            state: state(done: readiness.ecAccountStatus != .notStarted, startGrade: 10),
            when: "Sophomore year",
            title: "Create your free NCAA Profile Page",
            detail: "The NCAA recommends registering by sophomore year. It's free and takes about 30–45 minutes.",
            link: ("How registration works", Compliance.registrationInfoURL)
        ))

        // Coach-contact timing is no longer a timeline step: it is action-
        // specific and evaluated by the backend Recruiting Rules Engine. See
        // recruitingCommunicationCard below.

        if isD3 {
            steps.append(TimelineStep(
                id: "d3id",
                state: state(done: readiness.ecAccountStatus != .notStarted, startGrade: 12),
                when: "Senior year",
                title: "Get your free NCAA ID",
                detail: "Starting with the 2026-27 school year, all D3 enrollees need an NCAA ID. D3 doesn't require certification — each school sets its own academic standards.",
                link: ("Division III requirements", Compliance.divisionIIIEligibilityURL)
            ))
        } else {
            steps.append(TimelineStep(
                id: "cert",
                state: state(
                    done: readiness.ecAccountStatus == .certification && readiness.transcriptSent,
                    startGrade: 11
                ),
                when: "Junior year",
                title: "Upgrade to a Certification account",
                detail: "Required for official visits and D1/D2 offers. Then have your counselor send your transcript after junior year.",
                link: ("Certification vs. Profile Page accounts", Compliance.accountTypesURL)
            ))

            steps.append(TimelineStep(
                id: "finalcert",
                state: state(done: readiness.finalCertRequested, startGrade: 12),
                when: "Senior year",
                title: "Request final amateurism certification",
                detail: "Opens April 1\(athlete.gradYear.map { ", \(String($0))" } ?? "") for fall enrollees. Answer the amateurism questions in your account first.",
                link: ("How to request it (PDF)", Compliance.amateurismGuideURL)
            ))
        }

        return steps
    }

    // MARK: - Next action

    private struct NextAction {
        let title: String
        let body: String
        let markDone: (() -> Void)?
    }

    private var nextAction: NextAction {
        let currentId = timelineSteps.first { $0.state == .current }?.id

        switch currentId {
        case "core":
            return NextAction(
                title: "Log your NCAA core courses",
                body: "Check your classes against your school's approved list on the NCAA site, then record how many you've completed in the progress section below.",
                markDone: nil
            )
        case "account":
            if (grade ?? 0) >= 11 && isD1orD2Track {
                return NextAction(
                    title: "Create your NCAA Certification account",
                    body: "As a \(gradeLabel?.lowercased() ?? "junior") aiming for \(readiness.intendedDivision.rawValue), go straight to the Academic & Athletics Certification account — it's required for official visits and offers.",
                    markDone: { readiness.ecAccountStatus = .certification }
                )
            }
            return NextAction(
                title: "Create your free NCAA Profile Page",
                body: "It takes about 30–45 minutes and puts you in the NCAA's system. You can upgrade it to a Certification account junior year — you don't pay anything today.",
                markDone: { readiness.ecAccountStatus = .profilePage }
            )
        case "cert":
            if readiness.ecAccountStatus != .certification {
                return NextAction(
                    title: "Upgrade to a Certification account",
                    body: "Your free Profile Page won't cut it for D1/D2 official visits or offers — transition it to an Academic & Athletics Certification account.",
                    markDone: { readiness.ecAccountStatus = .certification }
                )
            }
            return NextAction(
                title: "Ask your counselor to send your transcript",
                body: "After junior year, your counselor uploads your official transcript through the NCAA High School Portal. Ask them — you can't do this step yourself.",
                markDone: { readiness.transcriptSent = true }
            )
        case "finalcert":
            return NextAction(
                title: "Request final amateurism certification",
                body: "Log in to your Eligibility Center account and submit the request — available April 1 or later for fall enrollees. The NCAA can't finalize until you ask.",
                markDone: { readiness.finalCertRequested = true }
            )
        case "d3id":
            return NextAction(
                title: "Get your free NCAA ID",
                body: "All D3 enrollees need an NCAA ID starting with the 2026-27 school year. Create the free Profile Page account to get yours.",
                markDone: { readiness.ecAccountStatus = .profilePage }
            )
        default:
            return NextAction(
                title: "You're on track — keep it up",
                body: "Keep your grades up and check any new classes against your school's NCAA-approved course list.",
                markDone: nil
            )
        }
    }

    // MARK: - Disclaimer

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.hubPrimary)
            Text("This is a planning tool. Only the NCAA Eligibility Center makes your official eligibility decision.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.hubPrimary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
    }

    // MARK: - Do this next

    private var nextStepHero: some View {
        let action = nextAction

        return VStack(alignment: .leading, spacing: 10) {
            Text("DO THIS NEXT")
                .font(.caption.bold())
                .foregroundStyle(Color.hubPrimary)
                .kerning(1)

            Text(action.title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(action.body)
                .font(.subheadline)
                .foregroundStyle(Color.hubTextSecondary)

            Link(destination: Compliance.eligibilityCenterURL) {
                HStack {
                    Text("Open NCAA Eligibility Center")
                        .font(.subheadline.bold())
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.hubPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let markDone = action.markDone {
                Button {
                    markDone()
                } label: {
                    Text("I already did this")
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubPrimary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.hubPrimary.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Timeline

    private var timelineCard: some View {
        let steps = timelineSteps

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Your Recruiting Timeline")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                if let gradYear = athlete.gradYear, let gradeLabel {
                    Text("Class of \(String(gradYear)) · \(gradeLabel)")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            .padding(.bottom, 10)

            if athlete.gradYear == nil {
                Text("Add your graduation year on the Profile tab to personalize this timeline.")
                    .font(.caption)
                    .foregroundStyle(Color.hubWarning)
                    .padding(.bottom, 10)
            }

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                timelineRow(step: step, last: index == steps.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func timelineRow(step: TimelineStep, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                switch step.state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.hubSuccess)
                case .current:
                    Image(systemName: "circle.circle.fill")
                        .foregroundStyle(Color.hubPrimary)
                case .upcoming:
                    Image(systemName: "circle")
                        .foregroundStyle(Color.hubTextSecondary)
                }
                if !last {
                    Rectangle()
                        .fill(Color.hubBorder)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text((step.state == .current ? "Now — \(step.when)" : step.when).uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(step.state == .current ? Color.hubPrimary : Color.hubTextSecondary)
                        .kerning(0.5)
                    if let badge = step.badge {
                        Text(badge)
                            .font(.caption2.bold())
                            .foregroundStyle(Color.hubWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.hubWarning.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(step.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(step.state == .upcoming ? Color.hubTextSecondary : .white)
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                if let link = step.link {
                    Link(destination: link.url) {
                        HStack(spacing: 4) {
                            Text(link.label)
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Color.hubPrimary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.bottom, last ? 0 : 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Recruiting communication (Recruiting Rules Engine)

    /// Division the engine is asked about. "Unsure" shows D1, the most
    /// common question, and says so.
    private var recruitingDivision: String {
        switch readiness.intendedDivision {
        case .d1, .unsure: "D1"
        case .d2: "D2"
        case .d3: "D3"
        }
    }

    /// Action-specific recruiting status from the backend evaluator (spec §17).
    /// Coach messaging and athlete outreach are separate rows on purpose;
    /// neither implies anything about calls, visits or in-person contact.
    private var recruitingCommunicationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recruiting Communication")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                Text("NCAA \(recruitingDivision)")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.hubPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.hubPrimary.opacity(0.15))
                    .clipShape(Capsule())
            }

            if readiness.intendedDivision == .unsure {
                Text("Showing NCAA D1 rules. Pick a division below to change.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }

            RecruitingStatusView(title: "Coach recruiting messages", load: coachMessagesStatus)

            Divider().background(Color.hubBorder)

            AthleteOutreachStatusView(load: athleteOutreachStatus)

            if let gender = SportGender(rawValue: athlete.sportGender ?? "") {
                let calendar = Compliance.d1Calendar(gender: gender)
                Link(destination: calendar.url) {
                    HStack(spacing: 4) {
                        Text("Open the D1 \(gender == .mens ? "men's" : "women's") basketball recruiting calendar (PDF)")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color.hubPrimary)
                }
            }

            Text(Compliance.actionSpecificNote)
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
            Text(Compliance.rulesEngineDisclaimer)
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func loadRecruitingStatus() async {
        // Keep the previous decision on screen while the new division's rule
        // loads: collapsing to a spinner changed the card height and made the
        // page lurch under the division pills.
        if case .loaded = coachMessagesStatus {} else { coachMessagesStatus = .loading }
        if case .loaded = athleteOutreachStatus {} else { athleteOutreachStatus = .loading }
        let division = recruitingDivision
        let service = RecruitingRulesService.shared
        async let coach = service.load(
            athleteId: athlete.id,
            action: .coachSendRecruitingElectronicCorrespondence,
            governingBody: "NCAA",
            division: division
        )
        async let outreach = service.load(
            athleteId: athlete.id,
            action: .athleteSendIntroMessage,
            governingBody: "NCAA",
            division: division
        )
        let (coachResult, outreachResult) = await (coach, outreach)
        coachMessagesStatus = coachResult
        athleteOutreachStatus = outreachResult
    }

    // MARK: - Division

    private var divisionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where do you want to play?")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)

            HStack(spacing: 8) {
                ForEach(NCAAReadiness.Division.allCases, id: \.self) { division in
                    Button {
                        readiness.intendedDivision = division
                    } label: {
                        Text(division.rawValue)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(readiness.intendedDivision == division ? Color.hubPrimary : Color.hubSurfaceElevated)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }

            Text("Everything below adjusts to the division you pick. D3 skips certification but still needs a free NCAA ID.")
                .font(.caption)
                .foregroundStyle(Color.hubTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Academic readiness

    private var gpaMinimum: Double? {
        switch readiness.intendedDivision {
        case .d1: 2.3
        case .d2: 2.2
        case .d3, .unsure: nil
        }
    }

    private var academicReadinessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Academic Readiness")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                provenanceChip("Estimated")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("NCAA core courses")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(readiness.coreCoursesCompleted) of 16")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                ProgressView(value: Double(readiness.coreCoursesCompleted), total: 16)
                    .tint(Color.hubPrimary)
                if let pace = paceText {
                    Text(pace.text)
                        .font(.caption)
                        .foregroundStyle(pace.onPace ? Color.hubSuccess : Color.hubWarning)
                }
            }

            if let gpa = readiness.estimatedCoreGpa {
                let minimum = gpaMinimum
                let meets = minimum.map { gpa >= $0 } ?? true
                readinessRow(
                    icon: meets ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    iconColor: meets ? .hubSuccess : .hubWarning,
                    title: "Estimated core GPA: \(gpa.formatted(.number.precision(.fractionLength(2))))",
                    detail: minimum.map {
                        "\(readiness.intendedDivision.rawValue) minimum is \($0.formatted(.number.precision(.fractionLength(1)))). Only NCAA-approved core courses count, so this is an estimate until your counselor confirms."
                    } ?? "D1 minimum is 2.3; D2 is 2.2. Only NCAA-approved core courses count."
                )
            }

            if readiness.intendedDivision != .d3 {
                readinessRow(
                    icon: "calendar",
                    iconColor: .hubPrimary,
                    title: "10/7 checkpoint: before senior year",
                    detail: "D1 requires 10 core courses (7 in English, math or science) completed before your 7th semester."
                        + (readiness.coreCoursesCompleted < 10 ? " You need \(10 - readiness.coreCoursesCompleted) more." : " You're there.")
                )
            }

            Link(destination: Compliance.approvedCourseSearchURL) {
                HStack(spacing: 4) {
                    Text("Find your school's NCAA-approved course list")
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.bold())
                .foregroundStyle(Color.hubPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var paceText: (text: String, onPace: Bool)? {
        guard let grade, (9...12).contains(grade) else { return nil }
        let remaining = max(0, 16 - readiness.coreCoursesCompleted)
        if remaining == 0 { return ("All 16 core courses logged.", true) }

        let expectedByNow = 4 * (grade - 9)
        let yearsLeft = max(1, 13 - grade)
        let perYear = Int((Double(remaining) / Double(yearsLeft)).rounded(.up))
        if readiness.coreCoursesCompleted >= expectedByNow {
            return ("On pace — about \(perYear) per year gets you to 16 by graduation.", true)
        }
        return ("A bit behind — you'd need about \(perYear) per year to reach 16. Talk to your counselor.", false)
    }

    private func readinessRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
        }
    }

    // MARK: - Progress editor

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Update Your Progress")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                provenanceChip("Self-reported")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("NCAA account")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                Picker("NCAA account", selection: $readiness.ecAccountStatus) {
                    Text("None yet").tag(NCAAReadiness.AccountStatus.notStarted)
                    Text("Profile Page").tag(NCAAReadiness.AccountStatus.profilePage)
                    Text("Certification").tag(NCAAReadiness.AccountStatus.certification)
                }
                .pickerStyle(.segmented)
            }

            Stepper(value: $readiness.coreCoursesCompleted, in: 0...16) {
                HStack {
                    Text("Core courses done")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(readiness.coreCoursesCompleted)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.hubPrimary)
                        .padding(.trailing, 8)
                }
            }

            HStack {
                Text("Estimated core GPA")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                TextField("e.g. 3.2", text: $gpaText)
                    .keyboardType(.decimalPad)
                    .focused($gpaFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.hubSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
            }

            Toggle("Amateurism questions answered", isOn: $readiness.amateurismDone)
            Toggle("Transcript sent by counselor", isOn: $readiness.transcriptSent)
            Toggle("Final certification requested", isOn: $readiness.finalCertRequested)
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .tint(Color.hubPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("Course counts and GPA are estimates based on what you and your family entered — not an NCAA eligibility determination. Always confirm with your counselor and the NCAA Eligibility Center.")
            .font(.caption2)
            .foregroundStyle(Color.hubTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: - Shared

    private func provenanceChip(_ label: String) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(Color.hubWarning)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.hubWarning.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Data

    private func loadIfNeeded() async {
        guard isLoading else {
            if gpaText.isEmpty, let gpa = readiness.estimatedCoreGpa {
                gpaText = gpa.formatted(.number.precision(.fractionLength(2)))
            }
            return
        }
        do {
            // nil row = new athlete with no saved progress yet (legit empty);
            // a thrown error = we don't know, so show the retry state instead
            // of an empty form that would overwrite real data on first edit.
            if let row = try await AthleteService.shared.fetchNCAAReadiness(athleteId: athlete.id) {
                readiness = row
            }
            loadError = nil
            if let gpa = readiness.estimatedCoreGpa {
                gpaText = gpa.formatted(.number.precision(.fractionLength(2)))
            }
        } catch {
            loadError = "Check your connection and try again. Your saved progress is safe."
        }
        isLoading = false
    }

    private func commitGPAText() {
        let cleaned = gpaText.replacingOccurrences(of: ",", with: ".")
        if cleaned.isEmpty {
            readiness.estimatedCoreGpa = nil
        } else if let value = Double(cleaned), (0...5).contains(value) {
            readiness.estimatedCoreGpa = value
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = readiness
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await AthleteService.shared.upsertNCAAReadiness(snapshot)
                saveError = nil
            } catch {
                saveError = "Your latest change couldn't be saved."
            }
        }
    }

    private func saveErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hubWarning)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Button("Retry") { scheduleSave() }
                .font(.caption.bold())
                .foregroundStyle(Color.hubPrimary)
        }
        .padding(12)
        .background(Color.hubWarning.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// NCAA Journey entry from the More menu — loads the user's athlete first.
struct NCAAJourneyRootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    @State private var athlete: Athlete?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.hubPrimary)
            } else if let athlete {
                NCAAJourneyView(athlete: athlete)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.hubTextSecondary)
                    Text("No profile yet")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("The NCAA Journey is tied to an athlete profile. Create one from the Profile tab.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hubTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .navigationTitle("NCAA Journey")
        .task {
            defer { isLoading = false }
            guard let userId = authViewModel.session?.user.id.uuidString else { return }
            athlete = try? await AthleteService.shared.fetchManagedAthletes(userId: userId).first
        }
    }
}

#Preview {
    NavigationStack {
        NCAAJourneyView(
            athlete: Athlete(
                id: "preview",
                userId: "preview",
                fullName: "Jordan Example",
                bio: nil,
                dateOfBirth: nil,
                profilePhotoUrl: nil,
                highSchool: "Example High School",
                gradYear: 2029,
                gpa: 3.1,
                satScore: nil,
                actScore: nil,
                heightInches: 73,
                weightLbs: nil,
                position: "PG",
                jerseyNumber: nil,
                sportGender: "mens",
                instagramHandle: nil,
                tiktokHandle: nil,
                intendedMajor: nil,
                hometown: nil,
                state: nil,
                zipCode: nil,
                latitude: nil,
                longitude: nil,
                ncaaId: nil,
                isPublished: true,
                guardianConsentAt: nil,
                guardianConsentEmail: nil,
                guardianConsentName: nil,
                createdAt: "",
                updatedAt: ""
            ),
            readiness: NCAAReadiness(
                athleteId: "preview",
                intendedDivision: .d1,
                ecAccountStatus: .notStarted,
                coreCoursesCompleted: 5,
                estimatedCoreGpa: 3.1,
                transcriptSent: false,
                amateurismDone: false,
                finalCertRequested: false,
                source: "self_reported",
                createdAt: nil,
                updatedAt: nil
            )
        )
    }
    .preferredColorScheme(.dark)
}
