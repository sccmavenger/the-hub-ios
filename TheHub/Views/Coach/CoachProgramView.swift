import SwiftUI
import Auth

/// Program tab (spec §11, D16/D22): the verified program, a switcher when the
/// coach holds several, the active staff roster (names, titles, roles — no
/// contact details), the coach's own membership, and account actions.
struct CoachProgramView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var programs = CoachProgramService.shared
    @State private var staff: [ProgramStaffMember] = []
    @State private var staffFailed = false
    @State private var showSwitcher = false

    private var programId: String? { programs.selectedContext?.programId }

    var body: some View {
        ZStack {
            Color.hubBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if let context = programs.selectedContext {
                        ProgramCardView(context: context, isCurrent: true)
                        if programs.canSwitch {
                            Button {
                                showSwitcher = true
                            } label: {
                                Label("Switch program (\(programs.contexts.count) verified)", systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .background(Color.hubSurface)
                            .foregroundStyle(Color.hubPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        staffCard
                        membershipCard(context)
                    } else {
                        CoachAccessUnavailableView()
                            .padding(.vertical, 24)
                    }
                    accountCard
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .refreshable { await loadStaff() }
        }
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.large)
        .task(id: programId) { await loadStaff() }
        .sheet(isPresented: $showSwitcher) { CoachProgramSwitcherView() }
    }

    private var staffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Staff")
                    .font(.headline)
                    .foregroundStyle(Color.hubPrimary)
                Spacer()
                Text(staff.count == 1 ? "1 verified" : "\(staff.count) verified")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            if staffFailed {
                Text("Couldn't load the roster. Pull to refresh.")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
            }
            ForEach(staff) { member in
                HStack(alignment: .top, spacing: 12) {
                    Text(initials(member.displayName))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.hubPrimary.opacity(0.6))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            if member.isMe {
                                Text("You")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Color.hubPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.hubPrimary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        let role = [member.title, member.roleDisplayName].compactMap { $0 }.joined(separator: " · ")
                        if !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(Color.hubTextSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            Text("Verified staff share this program's recruiting board. Suspended or former staff don't appear here and lose access immediately.")
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func membershipCard(_ context: CoachProgramContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your membership")
                .font(.headline)
                .foregroundStyle(Color.hubPrimary)
            row("Title", context.title ?? "—")
            row("Role", context.roleDisplayName ?? "—")
            if let verified = context.verifiedAt {
                row("Verified", verified.asFormattedDate(style: .long))
            }
            Text("Changing schools or roles? Contact \(HubSupport.email) and we'll update your verified membership.")
                .font(.caption2)
                .foregroundStyle(Color.hubTextSecondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                AccountView()
            } label: {
                HStack {
                    Label("Account & Legal", systemImage: "person.crop.circle")
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                }
            }
            Divider().background(Color.hubBorder)
            Button(role: .destructive) {
                Task { await authViewModel.signOut() }
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.hubSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Color.hubTextSecondary).frame(width: 80, alignment: .leading)
            Text(value).font(.subheadline).foregroundStyle(.white)
            Spacer()
        }
    }

    private func loadStaff() async {
        guard let programId else { staff = []; return }
        do {
            staff = try await CoachWorkspaceService.shared.staff(programId: programId)
            staffFailed = false
        } catch {
            staffFailed = staff.isEmpty
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return (first + last).uppercased()
    }
}
