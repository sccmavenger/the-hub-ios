import Foundation
import Observation
import Supabase

/// In-app notification center (spec §14, D28). Rows are read straight from
/// `notifications` under the owner RLS policy; read state goes through the
/// `mark_notifications_read` RPC so the server owns the timestamp.
@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    private(set) var notifications: [AppNotification] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var loadFailed = false

    private init() {}

    static let pageSize = 50

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await supabase
                .from("notifications")
                .select()
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value
            unreadCount = try await fetchUnreadCount()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Cheap badge refresh for toolbars; failures keep the last known count.
    func refreshUnreadCount() async {
        if let count = try? await fetchUnreadCount() {
            unreadCount = count
        }
    }

    private func fetchUnreadCount() async throws -> Int {
        try await supabase.rpc("unread_notification_count").execute().value
    }

    private struct MarkParams: Encodable {
        let p_ids: [String]?
    }

    func markRead(_ notification: AppNotification) async {
        guard !notification.isRead else { return }
        let stamp = Date().toISO8601String()
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].readAt = stamp
        }
        unreadCount = max(0, unreadCount - 1)
        do {
            try await supabase.rpc("mark_notifications_read", params: MarkParams(p_ids: [notification.id])).execute()
        } catch {
            await load()
        }
    }

    func markAllRead() async {
        let stamp = Date().toISO8601String()
        for index in notifications.indices where notifications[index].readAt == nil {
            notifications[index].readAt = stamp
        }
        unreadCount = 0
        do {
            try await supabase.rpc("mark_notifications_read", params: MarkParams(p_ids: nil)).execute()
        } catch {
            await load()
        }
    }

    /// Sign-out / account switch.
    func reset() {
        notifications = []
        unreadCount = 0
        loadFailed = false
    }
}

/// Cross-tab hand-off for notification taps that land on a different tab
/// (a saved-search alert opens Discover with that search applied).
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    private init() {}

    /// Set by the notifications center; consumed (cleared) by Discover.
    var pendingSavedSearchId: String?
}

/// Per-user preferences in `user_settings` (migration 019). One row per
/// user, created on first write; the default when no row exists is the
/// server default (previews OFF), so the UI never shows a stale "on".
@MainActor
@Observable
final class UserSettingsService {
    static let shared = UserSettingsService()
    private init() {}

    private(set) var showMessagePreviews = false
    private(set) var isLoaded = false
    private(set) var loadFailed = false

    private struct Row: Decodable {
        let showMessagePreviews: Bool
        enum CodingKeys: String, CodingKey { case showMessagePreviews = "show_message_previews" }
    }

    func load(userId: String) async {
        do {
            let rows: [Row] = try await supabase
                .from("user_settings")
                .select("show_message_previews")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            showMessagePreviews = rows.first?.showMessagePreviews ?? false
            isLoaded = true
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    func setShowMessagePreviews(_ enabled: Bool, userId: String) async throws {
        let previous = showMessagePreviews
        showMessagePreviews = enabled
        do {
            try await supabase
                .from("user_settings")
                .upsert(["user_id": AnyJSON.string(userId), "show_message_previews": .bool(enabled)], onConflict: "user_id")
                .execute()
        } catch {
            showMessagePreviews = previous
            throw error
        }
    }
}
