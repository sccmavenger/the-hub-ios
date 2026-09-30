import Foundation

/// NCAA reference material and non-rule helper copy.
///
/// Recruiting *rules* (who may contact whom, and when) are NOT here. They
/// live in Supabase (`recruiting_rules`, supabase/010–013) and are evaluated
/// server-side; the app renders `RecruitingDecision` values via
/// `RecruitingRulesService`. This file must never grow a date or a division
/// comparison again.
enum Compliance {
    static let divisions = ["D1", "D2", "D3", "NAIA", "JUCO"]

    /// Displayed wherever college crest logos appear (only while the
    /// `college_logos_enabled` admin flag is on). College names, logos and
    /// marks belong to their institutions; we show them purely to identify
    /// schools, and this notice disclaims ownership and affiliation.
    static let trademarkNotice =
        "College names and logos are the property of their respective institutions. The Hub claims no ownership and is not affiliated with, sponsored by, or endorsed by any college, university, conference, or the NCAA. Logos are shown only to help you identify schools."

    /// Product policy: athletes may always reach out from The Hub.
    static let athleteOutreachNote =
        "You may contact college coaches at any age or grade. NCAA rules limit when coaches may send you recruiting messages — not when you may contact them."

    /// Shown wherever rules-engine decisions render (spec §1.8).
    static let rulesEngineDisclaimer =
        "Rules-based guidance from official sources, matched to your profile. The Hub is not the NCAA and does not make eligibility or compliance determinations. Rules change and can depend on facts The Hub doesn't know — confirm with the governing body or your school's compliance office."

    /// Different recruiting activities follow different rules (spec §30).
    static let actionSpecificNote =
        "Each recruiting activity — messages, calls, in-person contact, visits — follows its own rule and dates. One opening doesn't open the others."

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

    // MARK: - Divisions without engine rules

    /// Divisions/associations the engine has no sourced rule for yet. The
    /// Colleges card shows the legacy note below for these (product decision
    /// 2026-09-30: keep until the coach-experience spec lands). These notes are
    /// general orientation, not verified rules — see docs/TECH-DEBT.md.
    static let divisionsWithoutEngineRules = ["D3", "NAIA", "JUCO"]

    static func divisionNote(_ division: String) -> String? {
        switch division {
        case "D3":
            "NCAA D3 has no national start date for coach contact. Off-campus contact is still limited by NCAA rules, so ask the coach."
        case "NAIA":
            "The NAIA is a separate association and does not use the NCAA calendar; contact is not limited by a national start date."
        case "JUCO":
            "Junior colleges are governed by the NJCAA, not the NCAA, and have no national start date for contact."
        default:
            nil
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
}
