import Foundation
import Supabase

// Replace these with values from:
// Supabase Dashboard → Project Settings → API
let supabase = SupabaseClient(
    supabaseURL: URL(string: Secrets.supabaseURL)!,
    supabaseKey: Secrets.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            // Opt in to the SDK's upcoming behavior (supabase-swift #822): the
            // stored session is emitted as the initial auth event even if it has
            // expired, instead of after a refresh attempt. AuthViewModel skips
            // expired sessions, so sign-in state is never shown from a dead token.
            // Also silences the runtime warning the UI tests were logging.
            emitLocalSessionAsInitialSession: true
        )
    )
)

enum Secrets {
    static let supabaseURL = "https://fnlufxhznqclpajyadcc.supabase.co"
    static let supabaseAnonKey = "sb_publishable_f7sNQNdrw2sj8_sslhabOw_piq-h48b"
}
