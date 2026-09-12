import Foundation
import Supabase

// Replace these with values from:
// Supabase Dashboard → Project Settings → API
let supabase = SupabaseClient(
    supabaseURL: URL(string: Secrets.supabaseURL)!,
    supabaseKey: Secrets.supabaseAnonKey
)

enum Secrets {
    static let supabaseURL = "https://fnlufxhznqclpajyadcc.supabase.co"
    static let supabaseAnonKey = "sb_publishable_f7sNQNdrw2sj8_sslhabOw_piq-h48b"
}
