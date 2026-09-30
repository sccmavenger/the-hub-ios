import Foundation

/// NCAA compliance helpers — ported from the web app's compliance.ts.
/// Informational summaries of publicly published NCAA recruiting calendars;
/// every surface that renders them must also render the disclaimer.
enum Compliance {
    static let divisions = ["D1", "D2", "D3", "NAIA", "JUCO"]

    /// Displayed wherever college crest logos appear (only while the
    /// `college_logos_enabled` admin flag is on). College names, logos and
    /// marks belong to their institutions; we show them purely to identify
    /// schools, and this notice disclaims ownership and affiliation.
    static let trademarkNotice =
        "College names and logos are the property of their respective institutions. The Hub claims no ownership and is not affiliated with, sponsored by, or endorsed by any college, university, conference, or the NCAA. Logos are shown only to help you identify schools."

    static let athleteOutreachNote =
        "You may contact college coaches at any age or grade. The NCAA calendar limits when coaches may contact you — not when you may contact them."

    static let eligibilityCenterURL = URL(string: "https://web3.ncaa.org/ecwr3/")!
    static let recruitingCalendarsURL = URL(string: "https://www.ncaa.org/sports/2013/11/14/recruiting-calendars.aspx")!

    // Official NCAA reference material for the Journey timeline's "learn more" links
    static let initialEligibilityURL = URL(string: "https://www.ncaa.org/eligibility-center/initial-eligibility-requirements/")!
    /// Jumps to the "What are core courses and core-course GPA?" section
    static let coreCoursesURL = URL(string: "https://www.ncaa.org/eligibility-center/initial-eligibility-requirements/#academic-eligibility-basics")!
    static let divisionIIIEligibilityURL = URL(string: "https://www.ncaa.org/eligibility-center/initial-eligibility-requirements/division-iii/")!
    static let approvedCourseSearchURL = URL(string: "https://web3.ncaa.org/hsportal/exec/hsAction?hsActionSubmit=searchHighSchool")!
    static let registrationInfoURL = URL(string: "https://www.ncaa.org/eligibility-center/register/")!
    /// Jumps to the Certification vs. Profile Page account comparison
    static let accountTypesURL = URL(string: "https://www.ncaa.org/eligibility-center/register/#account-type")!
    // fs.ncaa.org is unreachable over https; the NCAA's S3 mirror serves this PDF
    static let amateurismGuideURL = URL(string: "https://s3.amazonaws.com/fs.ncaa.org/Docs/eligibility_center/Student_Resources/How_to_Request_Final_Amateurism_Certification.pdf")!

    static func sportGenderLabel(_ gender: SportGender) -> String {
        switch gender {
        case .mens: "boys / men's basketball"
        case .womens: "girls / women's basketball"
        }
    }

    static func disclaimer(gender: SportGender?) -> String {
        if let gender {
            return "Plain-language summary of publicly published recruiting rules for \(sportGenderLabel(gender)), based on grad year only. It does not account for dead/quiet periods, visits, transfers or state rules, and rules change each year. Always confirm with the official sources or your school's compliance office."
        }
        return "Plain-language summary of publicly published recruiting rules, based on grad year only. It does not account for sport, gender, dead/quiet periods, visits, transfers or state rules, and rules change each year. Always confirm with the official sources or your school's compliance office."
    }

    static func d1Calendar(gender: SportGender) -> (label: String, url: URL) {
        switch gender {
        case .mens:
            ("D1 men's basketball recruiting calendar (NCAA)",
             URL(string: "https://ncaaorg.s3.amazonaws.com/compliance/recruiting/calendar/2026-27/2026-27D1Rec_MBBRecruitingCalendar.pdf")!)
        case .womens:
            ("D1 women's basketball recruiting calendar (NCAA)",
             URL(string: "https://ncaaorg.s3.amazonaws.com/compliance/recruiting/calendar/2026-27/2026-27D1Rec_WBBRecruitingCalendar.pdf")!)
        }
    }

    // MARK: - Ages

    static func age(fromDOB dob: String?, on date: Date = .now) -> Int? {
        guard let dob, let birthDate = dob.asDate() else { return nil }
        let components = Calendar.current.dateComponents([.year], from: birthDate, to: date)
        return components.year
    }

    static func isUnder13(dob: String?) -> Bool {
        guard let age = age(fromDOB: dob) else { return false }
        return age < 13
    }

    static func isUnder18(dob: String?) -> Bool {
        guard let age = age(fromDOB: dob) else { return false }
        return age < 18
    }

    // MARK: - Contact windows

    struct ContactWindow: Identifiable {
        let division: String
        let opensOn: Date?
        let open: Bool
        let summary: String

        var id: String { division }
    }

    /// D1/D2 contact opens June 15 immediately preceding junior year
    /// (i.e. June 15 of gradYear − 2). D3/NAIA/JUCO have no national date.
    static func contactOpensOn(gradYear: Int?, division: String) -> Date? {
        guard let gradYear, division == "D1" || division == "D2" else { return nil }
        // Local midnight, not UTC — a UTC date renders as June 14 in US time zones
        var components = DateComponents()
        components.year = gradYear - 2
        components.month = 6
        components.day = 15
        return Calendar.current.date(from: components)
    }

    static func contactWindows(gradYear: Int?, gender: SportGender?, now: Date = .now) -> [ContactWindow] {
        divisions.map { division in
            guard let opensOn = contactOpensOn(gradYear: gradYear, division: division) else {
                let summary: String = switch division {
                case "D3":
                    "NCAA D3 has no national start date for coach contact. Off-campus contact is still limited by NCAA rules, so ask the coach."
                case "NAIA":
                    "The NAIA is a separate association and does not use the NCAA calendar; contact is not limited by a national start date."
                default:
                    "Junior colleges are governed by the NJCAA, not the NCAA, and have no national start date for contact."
                }
                return ContactWindow(division: division, opensOn: nil, open: true, summary: summary)
            }

            let open = now >= opensOn
            let when = opensOn.formatted(date: .long, time: .omitted)
            let genderClause = gender.map { " on the \(sportGenderLabel($0)) calendar" }
                ?? " that differ between men's and women's basketball"
            let summary = open
                ? "Calls, texts, emails and recruiting materials have been allowed since \(when) (June 15 before junior year). In-person contact, visits and evaluations follow separate dated periods\(genderClause)."
                : "Calls, texts, emails and recruiting materials may start \(when) (June 15 before junior year). You can still reach out to coaches before then."
            return ContactWindow(division: division, opensOn: opensOn, open: open, summary: summary)
        }
    }
}
