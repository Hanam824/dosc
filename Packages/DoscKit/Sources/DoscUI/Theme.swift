import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

extension Color {
    /// A color that switches between light and dark mode.
    public init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
            self.init(
                uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
            self.init(
                nsColor: NSColor(name: nil) {
                    $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
                })
        #endif
    }

    /// A color from six hex digits like `d73a4a` (with or without `#`); gray when invalid.
    public init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8b949e
        self.init(
            red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255)
    }
}

#if canImport(UIKit)
    extension UIColor {
        convenience init(rgb: UInt32) {
            self.init(
                red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        }
    }
#else
    extension NSColor {
        convenience init(rgb: UInt32) {
            self.init(
                red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
        }
    }
#endif

/// Colors in the style of GitHub's Primer design system, for light and dark mode.
public enum Palette {
    public static let fgDefault = Color(light: 0x1f2328, dark: 0xe6edf3)
    public static let fgMuted = Color(light: 0x59636e, dark: 0x9198a1)
    public static let canvasDefault = Color(light: 0xffffff, dark: 0x0d1117)
    public static let canvasSubtle = Color(light: 0xf6f8fa, dark: 0x151b23)
    public static let border = Color(light: 0xd1d9e0, dark: 0x3d444d)
    public static let accent = Color(light: 0x0969da, dark: 0x4493f8)
    public static let open = Color(light: 0x1a7f37, dark: 0x3fb950)
    public static let closed = Color(light: 0xd1242f, dark: 0xf85149)
    public static let done = Color(light: 0x8250df, dark: 0xab7df8)
    public static let neutral = Color(light: 0x59636e, dark: 0x9198a1)
    public static let attention = Color(light: 0x9a6700, dark: 0xd29922)

    public static let additionBackground = Color(light: 0xdafbe1, dark: 0x12261e)
    public static let additionNumberBackground = Color(light: 0xaceebb, dark: 0x1b4721)
    public static let deletionBackground = Color(light: 0xffebe9, dark: 0x25171c)
    public static let deletionNumberBackground = Color(light: 0xffcecb, dark: 0x542426)
    public static let hunkBackground = Color(light: 0xddf4ff, dark: 0x131d2e)

    /// The colored squares on the Home screen, as in the GitHub app.
    public static let homeIssues = Color(light: 0x1a7f37, dark: 0x238636)
    public static let homePulls = Color(light: 0x0969da, dark: 0x1f6feb)
    public static let homeRepos = Color(light: 0x8250df, dark: 0x8957e5)
    public static let homeStarred = Color(light: 0xbf8700, dark: 0xbb8009)
    public static let homeActivity = Color(light: 0xbc4c00, dark: 0xdb6d28)
    public static let homeOrgs = Color(light: 0xcf222e, dark: 0xda3633)
}

/// Colors for the languages most often shown on repository rows (from GitHub's linguist).
public enum LanguageColor {
    public static func color(for language: String) -> Color {
        let table: [String: String] = [
            "Swift": "F05138", "Kotlin": "A97BFF", "Java": "b07219", "JavaScript": "f1e05a",
            "TypeScript": "3178c6", "Python": "3572A5", "Go": "00ADD8", "Rust": "dea584",
            "Ruby": "701516", "C": "555555", "C++": "f34b7d", "C#": "178600", "Objective-C": "438eff",
            "PHP": "4F5D95", "Shell": "89e051", "HTML": "e34c26", "CSS": "663399", "Dart": "00B4AB",
            "Vue": "41b883", "Lua": "000080", "Nix": "7e7eff", "Dockerfile": "384d54", "Scala": "c22d40",
            "Elixir": "6e4a7e", "Haskell": "5e5086", "Jupyter Notebook": "DA5B0B", "Makefile": "427819",
        ]
        return Color(hex: table[language] ?? "8b949e")
    }
}
