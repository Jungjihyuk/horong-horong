import AppKit

@MainActor
enum AppIconManager {
    static func image(
        for style: Constants.AppIconStyle,
        bundle: Bundle = .main
    ) -> NSImage? {
        guard let url = bundle.url(
            forResource: style.resourceName,
            withExtension: "png",
            subdirectory: "overview"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    static func apply(_ style: Constants.AppIconStyle) {
        guard let image = image(for: style) else { return }
        NSApplication.shared.applicationIconImage = image
    }

    static func applyStoredSelection(defaults: UserDefaults = .standard) {
        let rawValue = defaults.string(forKey: Constants.AppStorageKey.appIcon)
            ?? Constants.defaultAppIcon
        apply(Constants.AppIconStyle.normalized(rawValue: rawValue))
    }
}
