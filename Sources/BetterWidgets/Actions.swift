import AppKit

extension Notification.Name {
    static let openWidgetSettings = Notification.Name("BetterWidgetsOpenSettings")
    /// `object` is an `ArrangeMode.rawValue`.
    static let arrangeWidgets = Notification.Name("BetterWidgetsArrange")
}

enum WidgetCommands {
    static func openSettings(tab: SettingsTab? = nil) {
        NotificationCenter.default.post(name: .openWidgetSettings, object: tab?.rawValue)
    }

    static func arrange(_ mode: ArrangeMode) {
        NotificationCenter.default.post(name: .arrangeWidgets, object: mode.rawValue)
    }
}

extension WidgetModule {
    /// What clicking the card opens.
    private var target: (bundleID: String?, url: URL?) {
        switch self {
        case .clock: ("com.apple.clock", nil)
        case .date: ("com.apple.iCal", nil)
        case .weather: ("com.apple.weather", nil)
        case .cpu, .memory: ("com.apple.ActivityMonitor", nil)
        // System Settings › General › Storage: macOS's disk-usage breakdown.
        case .disk: (nil, URL(string: "x-apple.systempreferences:com.apple.settings.Storage"))
        case .processes: (nil, nil)
        }
    }

    var openActionTitle: String? {
        switch self {
        case .clock: "Open Clock"
        case .date: "Open Calendar"
        case .weather: "Open Weather"
        case .cpu, .memory: "Open Activity Monitor"
        case .disk: "Open Storage Settings"
        case .processes: nil
        }
    }

    var canOpen: Bool { openActionTitle != nil }

    func open() {
        let target = target
        if let url = target.url {
            NSWorkspace.shared.open(url)
        } else if let bundleID = target.bundleID,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
