import AppKit
import LuminaCore

extension AppIconStyle {
    var assetName: String {
        switch self {
        case .blue: "LuminaIconBlue"
        case .pink: "LuminaIconPink"
        case .purple: "LuminaIconPurple"
        }
    }

    var localizedName: String {
        switch self {
        case .blue: NSLocalizedString("Blue", comment: "Blue app icon")
        case .pink: NSLocalizedString("Pink", comment: "Pink app icon")
        case .purple: NSLocalizedString("Purple", comment: "Purple app icon")
        }
    }
}
