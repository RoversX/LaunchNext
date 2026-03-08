import Foundation

struct LayoutPresetDefinition {
    let id: String
    let slots: [LayoutPresetSlot]
}

enum LayoutPresetSlot {
    case app(bundleIdentifiers: [String], aliases: [String])
    case utilitiesFolder
}

enum LayoutPresetCatalog {
    static let utilityRootPaths: [String] = [
        "/System/Applications/Utilities",
        "/Applications/Utilities"
    ].map { URL(fileURLWithPath: $0).standardized.path }

    // Extra apps that should fall back into the "Other" folder when still unused.
    // Matching priority remains: bundle identifier/path first, alias only as final fallback.
    static let otherExtraBundleIDs: Set<String> = Set([
        "com.apple.backup.launcher",
        "com.apple.FontBook",
        "com.apple.exposelauncher",
        "com.apple.Stickies",
        "com.apple.Image_Capture",
        "com.apple.Automator",
        "com.apple.Dictionary",
        "com.apple.DictionaryApp",
        "com.apple.TextEdit",
        "com.apple.Games",
        "com.apple.gamecenter",
        "com.apple.journal",
        "com.apple.Siri",
        "com.apple.siri.launcher"
    ].map { $0.lowercased() })

    static let otherExtraAliases: [String] = [
        "Time Machine",
        "Font Book",
        "Mission Control",
        "Stickies",
        "Image Capture",
        "Automator",
        "Dictionary",
        "TextEdit",
        "Games",
        "Journal",
        "Siri"
    ]

    static let otherExtraPathSuffixes: [String] = [
        "/time machine.app",
        "/font book.app",
        "/mission control.app",
        "/stickies.app",
        "/image capture.app",
        "/automator.app",
        "/dictionary.app",
        "/textedit.app",
        "/games.app",
        "/journal.app",
        "/siri.app"
    ]

    static let macOS26Default = LayoutPresetDefinition(
        id: "macos26_default",
        slots: [
            .app(bundleIdentifiers: ["com.apple.AppStore"], aliases: ["App Store"]),
            .app(bundleIdentifiers: ["com.apple.Safari"], aliases: ["Safari"]),
            .app(bundleIdentifiers: ["com.apple.mail"], aliases: ["Mail"]),
            .app(bundleIdentifiers: ["com.apple.AddressBook"], aliases: ["Contacts", "Address Book"]),
            .app(bundleIdentifiers: ["com.apple.iCal"], aliases: ["Calendar", "iCal"]),
            .app(bundleIdentifiers: ["com.apple.reminders"], aliases: ["Reminders"]),
            .app(bundleIdentifiers: ["com.apple.Notes"], aliases: ["Notes"]),

            .app(bundleIdentifiers: ["com.apple.FaceTime"], aliases: ["FaceTime"]),
            .app(bundleIdentifiers: ["com.apple.MobileSMS"], aliases: ["Messages"]),
            .app(bundleIdentifiers: ["com.apple.Maps"], aliases: ["Maps"]),
            .app(bundleIdentifiers: ["com.apple.findmy"], aliases: ["Find My", "FindMy"]),
            .app(bundleIdentifiers: ["com.apple.PhotoBooth"], aliases: ["Photo Booth", "PhotoBooth"]),
            .app(bundleIdentifiers: ["com.apple.Photos"], aliases: ["Photos"]),
            .app(bundleIdentifiers: ["com.apple.Music"], aliases: ["Music"]),

            .app(bundleIdentifiers: ["com.apple.podcasts"], aliases: ["Podcasts"]),
            .app(bundleIdentifiers: ["com.apple.TV"], aliases: ["TV", "Apple TV"]),
            .app(bundleIdentifiers: ["com.apple.VoiceMemos"], aliases: ["Voice Memos", "VoiceMemos"]),
            .app(bundleIdentifiers: ["com.apple.iWork.Keynote"], aliases: ["Keynote"]),
            .app(bundleIdentifiers: ["com.apple.weather"], aliases: ["Weather"]),
            .app(bundleIdentifiers: ["com.apple.news"], aliases: ["News"]),
            .app(bundleIdentifiers: ["com.apple.stocks"], aliases: ["Stocks"]),

            .app(bundleIdentifiers: ["com.apple.iBooksX"], aliases: ["Books", "iBooks"]),
            .app(bundleIdentifiers: ["com.apple.clock"], aliases: ["Clock"]),
            .app(bundleIdentifiers: ["com.apple.calculator"], aliases: ["Calculator"]),
            .app(bundleIdentifiers: ["com.apple.freeform"], aliases: ["Freeform"]),
            .app(bundleIdentifiers: ["com.apple.Home"], aliases: ["Home"]),
            .app(bundleIdentifiers: ["com.apple.Siri"], aliases: ["Siri"]),
            .app(bundleIdentifiers: ["com.apple.iPhoneMirroring", "com.apple.ScreenContinuity"], aliases: ["iPhone Mirroring"]),

            .app(bundleIdentifiers: ["com.apple.Passwords"], aliases: ["Passwords"]),
            .app(bundleIdentifiers: ["com.apple.systempreferences"], aliases: ["System Settings", "System Preferences"]),
            .utilitiesFolder,
            .app(bundleIdentifiers: ["com.apple.ImagePlayground"], aliases: ["Image Playground"]),
            .app(bundleIdentifiers: ["com.apple.Shazam"], aliases: ["Shazam"]),
            .app(bundleIdentifiers: ["com.apple.Games", "com.apple.gamecenter"], aliases: ["Games", "Game Center"]),
            .app(bundleIdentifiers: ["com.apple.journal"], aliases: ["Journal"])
        ]
    )
}
