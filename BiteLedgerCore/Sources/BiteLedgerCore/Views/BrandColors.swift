import SwiftUI

/// Bundle-aware named color helpers for shared views in BiteLedgerCore.
///
/// Shared views must use these extensions — NOT bare `Color("Name")`.
/// `Color("Name")` without a bundle parameter resolves from the main app bundle only;
/// it will NOT fall through to the Core package bundle.
///
/// App-specific views continue to use `Color("Name")` from the main bundle (unchanged).
public extension Color {
    static let brandAccent     = Color("BrandAccent",     bundle: .module)
    static let brandPrimary    = Color("BrandPrimary",    bundle: .module)
    static let surfaceCard     = Color("SurfaceCard",     bundle: .module)
    static let surfaceElevated = Color("SurfaceElevated", bundle: .module)
    static let surfacePrimary  = Color("SurfacePrimary",  bundle: .module)
    static let textPrimary     = Color("TextPrimary",     bundle: .module)
    static let textSecondary   = Color("TextSecondary",   bundle: .module)
    static let textTertiary    = Color("TextTertiary",    bundle: .module)
    static let dividerSubtle   = Color("DividerSubtle",   bundle: .module)
}
