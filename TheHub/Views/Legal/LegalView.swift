import SwiftUI

/// The legal documents shown in-app.
///
/// **This text is canonical and must stay identical to the published pages**
/// (`/privacy` and `/terms` on the marketing site, mirrored in
/// `docs/legal/*.md`). Users agree to this copy at sign-up, so the app and the
/// website must not diverge — if one changes, change all three.
/// Adopted from the published site 2026-09-21.
enum LegalDocument: String, Identifiable {
    case terms
    case privacyPolicy

    var id: String { rawValue }

    /// Matches the website's heading ("Terms of Use", not "Terms of Service").
    var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .privacyPolicy: "Privacy Policy"
        }
    }

    var lastUpdated: String {
        "September 21, 2026"
    }

    var body: String {
        switch self {
        case .terms: Self.termsText
        case .privacyPolicy: Self.privacyText
        }
    }

    private static let termsText = """
    1. ABOUT THESE TERMS
    The HUB ("the Service") is a regional basketball recruiting app operated by \
    Summit Hoops. By creating an account or using the Service you agree to these \
    terms. If you do not agree, do not use the Service.

    2. WHO MAY USE THE SERVICE
    Athlete profiles may involve minors. Athletes under 13 may not create their \
    own account; a parent or legal guardian must create and manage the profile \
    and is responsible for all activity on it. College and club coaches must \
    request coach access, which is reviewed and approved by an administrator \
    before directory access is granted.

    3. YOUR CONTENT
    You keep ownership of the information, photos, and video links you post. You \
    grant Summit Hoops a non-exclusive license to display that content within the \
    Service to approved coaches and administrators for recruiting purposes. You \
    are responsible for the accuracy of measurements, academic information, and \
    schedules you submit.

    4. ACCEPTABLE USE
    • Do not impersonate another athlete, parent, coach, or institution.
    • Do not upload unlawful, harassing, hateful, or sexually explicit material.
    • Do not scrape, resell, or redistribute athlete data from the directory.
    • Do not attempt to gain access to accounts, roles, or data that are not yours.
    • Do not solicit personal contact details from a minor outside the Service.

    5. OBJECTIONABLE CONTENT, REPORTING, AND MODERATION
    There is zero tolerance for objectionable content or abusive behavior. Every \
    profile and conversation includes controls to report content and to block a \
    user. Reports are reviewed by administrators, who may hide content, restrict \
    messaging, or remove accounts. Blocking a user takes effect immediately.

    6. COACH ACCESS AND RECRUITING RULES
    Approved coaches are responsible for complying with NCAA, NAIA, NJCAA, and \
    state association contact rules. The HUB does not verify eligibility or \
    monitor recruiting contact, and approval of a coach account is not an \
    endorsement.

    7. SUSPENSION AND TERMINATION
    We may suspend or remove accounts that violate these terms or that contain \
    inaccurate or harmful content. You may delete your account at any time from \
    Account in the app.

    8. NO GUARANTEES
    The Service is provided "as is." We do not guarantee exposure, scholarship \
    offers, coach interest, or uninterrupted availability of the Service.

    9. CHANGES
    We may update these terms. Material changes will be reflected by the "last \
    updated" date above, and continued use of the Service means you accept the \
    updated terms.

    10. CONTACT
    Questions about these terms? Email info@summithoops.net.
    """

    private static let privacyText = """
    This policy explains how Summit Hoops handles personal information in The HUB \
    mobile app and on this website.

    INFORMATION WE COLLECT
    • Account details: name, email address, and the role you sign up with \
    (athlete, parent, coach, or admin).
    • Athlete profile details you enter: school, city and state, graduation year, \
    position, height and weight, jersey number, GPA and test scores, bio, \
    highlight video links, upcoming game schedule, and target schools.
    • Uploaded media: profile and action photos you choose to upload.
    • Contact details: guardian and high school coach contact information entered \
    on a profile, shown only to approved college coaches.
    • Messages: the content of messages exchanged between coaches and athlete or \
    parent accounts.
    • Approximate location: the city or postal code you enter, used to calculate \
    distance for coach searches. We do not collect continuous device GPS.
    • Safety records: reports and blocks you submit, so administrators can review \
    them.

    HOW WE USE IT
    We use this information to operate the recruiting directory: to display \
    athlete profiles to approved coaches, to let athletes and parents manage their \
    own profile, to deliver messages and notifications, to review coach access \
    requests and safety reports, and to keep accounts secure. We do not sell \
    personal information and we do not use it for third-party advertising.

    CHILDREN AND PARENT CONTROL
    Athlete profiles frequently belong to minors. Athletes under 13 cannot create \
    their own account — a parent or legal guardian must create and manage the \
    profile, and the profile cannot be published without recorded guardian \
    consent. Parents control what is published and may unpublish or delete a \
    profile at any time.

    WHO CAN SEE ATHLETE INFORMATION
    Athlete profiles are visible to signed-in, administrator-approved college \
    coaches and to administrators. Coach access is not granted automatically on \
    sign-up. Uploaded media is stored privately and served through time-limited \
    links rather than public URLs. Sensitive contact details are limited to \
    approved coaches.

    REPORTING AND BLOCKING
    Any user can report a conversation and block another user. Blocking stops \
    messages immediately. Reports are reviewed by administrators, who may hide \
    content or remove accounts. The person reported is not told who reported them.

    SERVICE PROVIDERS
    We use third-party infrastructure providers for application hosting, database, \
    authentication, email, and file storage. Highlight videos are hosted on the \
    platforms you link to (such as Hudl, YouTube, or Vimeo), and those platforms \
    have their own privacy policies. We use a public mapping service to convert a \
    city or postal code into approximate coordinates for distance search.

    RETENTION AND DELETION
    We keep profile information while the account is active. You can delete your \
    account and its data from inside the app at any time (More → Account → Delete \
    Account), or request deletion by email.

    SECURITY
    Accounts are authenticated by email and password. Database access is scoped \
    per user so a signed-in account can only read and edit records its role \
    permits, and privileged actions such as approving a coach or resolving a \
    report are verified on the server.

    YOUR CHOICES
    You decide what goes on a profile. Fields such as academics, contacts, and \
    schedule are optional and can be edited or cleared at any time, and a profile \
    can be unpublished so coaches can no longer see it.

    CONTACT
    For privacy questions or deletion requests, email info@summithoops.net.
    """
}

/// Scrollable legal document screen, presented as a sheet from sign-up and
/// from the Account screen.
struct LegalView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Last updated: \(document.lastUpdated)")
                            .font(.caption)
                            .foregroundStyle(Color.hubTextSecondary)

                        Text(document.body)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineSpacing(3)
                    }
                    .padding()
                }
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.hubPrimary)
                }
            }
        }
    }
}
