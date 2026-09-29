import AppKit
import CruftlessCore
import SwiftUI

public enum DesignTokens {
    public static let dyldCacheCommand = "sudo rm -rf /Library/Developer/CoreSimulator/Caches/dyld"

    public static func tierWord(for tier: Tier, locationId: String = "") -> String {
        if let androidWord = androidStorageWord(for: locationId) {
            return androidWord
        }
        return switch tier {
        case .regen:
            "Regenerates"
        case .judgment:
            switch locationId {
            case LocationCatalog.swiftPMCache.id, LocationCatalog.simulatorRuntimes.id: "Needs re-download"
            case LocationCatalog.simulatorDevices.id: "Holds app data"
            case LocationCatalog.codingAssistant.id: "Holds history"
            default: "Needs reinstall"
            }
        case .irreversible:
            "Not recoverable"
        case .reveal:
            "Show in Finder only"
        case .info:
            "Needs sudo"
        }
    }

    private static func androidStorageWord(for locationId: String) -> String? {
        switch locationId {
        case LocationCatalog.gradleCaches.id:
            "Risk review required"
        case LocationCatalog.androidStudioSystem.id, LocationCatalog.androidSDK.id,
            LocationCatalog.androidAVDs.id:
            "Read only"
        default:
            nil
        }
    }

    /// Tier tints resolve per appearance, so a light/dark switch while the popover is open repaints correctly.
    public static func tierColor(for tier: Tier) -> Color {
        switch tier {
        case .regen:
            Color(nsColor: .dynamic(light: 0x1F8A3D, dark: 0x5CD97A))
        case .judgment:
            Color(nsColor: .dynamic(light: 0xA85F00, dark: 0xFFB340))
        case .irreversible:
            Color(nsColor: .dynamic(light: 0xC1271D, dark: 0xFF6B62))
        case .reveal, .info:
            .secondary
        }
    }

    public static func actionLabel(for tier: Tier) -> String {
        switch tier {
        case .regen, .judgment:
            "Clear"
        case .irreversible:
            "Delete"
        case .reveal:
            "Show in Finder"
        case .info:
            "Copy Command"
        }
    }
}

private extension NSColor {
    /// Resolves per appearance so a light/dark switch repaints an open popover.
    static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

/// 45° hatch marking purgeable space in the capacity strip.
public struct HatchedPurgeablePattern: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            var path = Path()
            var xPos: CGFloat = -size.height
            while xPos < size.width + size.height {
                path.move(to: CGPoint(x: xPos, y: size.height))
                path.addLine(to: CGPoint(x: xPos + size.height, y: 0))
                xPos += step
            }
            context.stroke(path, with: .color(.secondary.opacity(0.9)), lineWidth: 1.5)
        }
        .background(.quaternary)
        .clipped()
    }
}
