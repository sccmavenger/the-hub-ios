import SwiftUI

// Summit Hoops palette — exact port of the web app's styles.css tokens
// (black background, white text, dodger blue accent), converted from OKLCH.
extension Color {
    // Backgrounds
    static let hubBackground = Color(red: 0.028, green: 0.028, blue: 0.028)      // --background
    static let hubSurface = Color(red: 0.060, green: 0.060, blue: 0.060)         // --card
    static let hubSurfaceElevated = Color(red: 0.160, green: 0.160, blue: 0.160) // --secondary / --muted

    // Brand — dodger blue is both primary and accent on the web
    static let hubPrimary = Color(red: 0.076, green: 0.528, blue: 0.995)         // --primary / --accent
    static let hubBlue = hubPrimary

    // Text
    static let hubTextPrimary = Color(red: 0.974, green: 0.974, blue: 0.974)     // --foreground
    static let hubTextSecondary = Color(red: 0.718, green: 0.718, blue: 0.718)   // --muted-foreground

    // Borders & dividers
    static let hubBorder = Color.white.opacity(0.20)                             // --border

    // Status
    static let hubSuccess = Color(red: 0.18, green: 0.78, blue: 0.45)
    static let hubWarning = Color(red: 1.0, green: 0.65, blue: 0.0)
    static let hubError = Color(red: 0.932, green: 0.209, blue: 0.200)           // --destructive
}
