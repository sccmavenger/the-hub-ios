import SwiftUI

/// Toolbar bell with an unread badge. Presents the notifications center and
/// forwards taps to the host screen, which owns navigation for its role.
struct NotificationBellButton: View {
    let onOpen: (AppNotification) -> Void

    @State private var service = NotificationService.shared
    @State private var showCenter = false

    var body: some View {
        Button {
            showCenter = true
        } label: {
            Image(systemName: service.unreadCount > 0 ? "bell.badge.fill" : "bell")
                .symbolRenderingMode(service.unreadCount > 0 ? .palette : .monochrome)
                .foregroundStyle(Color.hubError, Color.hubPrimary)
                .overlay(alignment: .topTrailing) {
                    if service.unreadCount > 0 {
                        Text(service.unreadCount > 99 ? "99+" : "\(service.unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.hubError)
                            .clipShape(Capsule())
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(service.unreadCount > 0 ? "Notifications, \(service.unreadCount) unread" : "Notifications")
        .task { await service.refreshUnreadCount() }
        .sheet(isPresented: $showCenter) {
            NotificationsView { notification in
                showCenter = false
                onOpen(notification)
            }
        }
    }
}

/// The notifications list (spec §14). Tapping a row marks it read and hands
/// it to the host; swipe marks read without leaving; "Mark all read" is in
/// the toolbar. Same screen for athletes, guardians and coaches.
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    let onOpen: (AppNotification) -> Void

    @State private var service = NotificationService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hubBackground.ignoresSafeArea()
                if service.isLoading && service.notifications.isEmpty {
                    ProgressView().tint(Color.hubPrimary)
                } else if service.loadFailed && service.notifications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.hubWarning)
                        Text("Couldn't load notifications")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Button("Try Again") { Task { await service.load() } }
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.hubPrimary)
                    }
                } else if service.notifications.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.hubTextSecondary)
                        Text("You're all caught up")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Messages, saves, and alerts you've turned on show up here.")
                            .font(.subheadline)
                            .foregroundStyle(Color.hubTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List {
                        ForEach(service.notifications) { notification in
                            Button {
                                Task { await service.markRead(notification) }
                                if notification.destination?.isNavigable == true {
                                    onOpen(notification)
                                }
                            } label: {
                                NotificationRow(notification: notification)
                            }
                            .listRowBackground(Color.hubSurface)
                            .swipeActions(edge: .trailing) {
                                if !notification.isRead {
                                    Button {
                                        Task { await service.markRead(notification) }
                                    } label: {
                                        Label("Mark read", systemImage: "envelope.open")
                                    }
                                    .tint(Color.hubPrimary)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .refreshable { await service.load() }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark all read") {
                        Task { await service.markAllRead() }
                    }
                    .disabled(service.unreadCount == 0)
                }
            }
            .task { await service.load() }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.symbolName)
                .font(.system(size: 18))
                .foregroundStyle(notification.isRead ? Color.hubTextSecondary : Color.hubPrimary)
                .frame(width: 28, height: 28)
                .background(Color.hubSurfaceElevated)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(notification.isRead ? .subheadline : .subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(Self.relative(notification.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Color.hubTextSecondary)
                }
                if let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(Color.hubTextSecondary)
                        .lineLimit(3)
                }
            }

            if notification.destination?.isNavigable == true {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.hubTextSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .leading) {
            if !notification.isRead {
                Circle()
                    .fill(Color.hubPrimary)
                    .frame(width: 7, height: 7)
                    .offset(x: -14)
            }
        }
    }

    private static func relative(_ iso: String) -> String {
        guard let date = iso.asDate() else { return "" }
        if date.isToday {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.relative(presentation: .named))
    }
}
