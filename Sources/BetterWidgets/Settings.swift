import SwiftUI
import Observation

// MARK: - Option types

enum SettingsTab: String {
    case appearance, modules, clock, weather, system, window
}

enum WidgetModule: String, CaseIterable, Identifiable {
    case clock, date, weather, cpu, memory, disk, processes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Clock"
        case .date: "Calendar"
        case .weather: "Weather"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Storage"
        case .processes: "Task Manager"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock.fill"
        case .date: "calendar"
        case .weather: "cloud.sun.fill"
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .disk: "internaldrive.fill"
        case .processes: "list.bullet.rectangle.fill"
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case glacier, aurora, sunset, ocean, neon, forest, ember, mono

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Light accents (Mono) need dark text on top of them.
    var accentForeground: Color { self == .mono ? .black : .white }

    var colors: [Color] {
        switch self {
        case .glacier: [Color(hex: 0xA8C8FF), Color(hex: 0x6E9BFF), Color(hex: 0x8B85F5)]
        case .aurora: [Color(hex: 0x00F5A0), Color(hex: 0x00D9F5), Color(hex: 0x7B61FF)]
        case .sunset: [Color(hex: 0xFFD452), Color(hex: 0xFF5E62), Color(hex: 0xC644FC)]
        case .ocean: [Color(hex: 0x6FE3FF), Color(hex: 0x3A8DFF), Color(hex: 0x6A5AE0)]
        case .neon: [Color(hex: 0x4CC9F0), Color(hex: 0xF72585), Color(hex: 0x7209B7)]
        case .forest: [Color(hex: 0xD4FC79), Color(hex: 0x56C26A), Color(hex: 0x11998E)]
        case .ember: [Color(hex: 0xFFE259), Color(hex: 0xFFA751), Color(hex: 0xFF512F)]
        case .mono: [Color(hex: 0xFFFFFF), Color(hex: 0xE5E5EA), Color(hex: 0x8E8E93)]
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CardStyle: String, CaseIterable, Identifiable {
    case glass, frosted, tinted
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .frosted: "Frosted"
        case .tinted: "Black"
        }
    }
}

enum ArrangeMode: String, CaseIterable, Identifiable {
    case grid, column, row
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .column: "rectangle.split.1x2"
        case .row: "rectangle.split.3x1"
        }
    }
}

enum WindowLevelMode: String, CaseIterable, Identifiable {
    case desktop, normal, floating
    var id: String { rawValue }
    var title: String {
        switch self {
        case .desktop: "On Desktop (behind windows)"
        case .normal: "Normal Window"
        case .floating: "Always on Top"
        }
    }
}

enum ClockStyle: String, CaseIterable, Identifiable {
    case digital, analog, both
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DateStyle: String, CaseIterable, Identifiable {
    case full, compact, numeric
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var title: String { self == .celsius ? "Celsius (°C)" : "Fahrenheit (°F)" }
}

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu, memory
    var id: String { rawValue }
    var title: String { self == .cpu ? "CPU" : "Memory" }
}

// MARK: - Persistence helpers

private func load<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
    UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
}
private func load(_ key: String, _ fallback: Bool) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
}
private func load(_ key: String, _ fallback: Double) -> Double {
    UserDefaults.standard.object(forKey: key) as? Double ?? fallback
}
private func load(_ key: String, _ fallback: Int) -> Int {
    UserDefaults.standard.object(forKey: key) as? Int ?? fallback
}
private func load(_ key: String, _ fallback: String) -> String {
    UserDefaults.standard.string(forKey: key) ?? fallback
}
private func loadModules(_ key: String) -> [WidgetModule]? {
    (UserDefaults.standard.array(forKey: key) as? [String])?.compactMap(WidgetModule.init(rawValue:))
}
private func save(_ key: String, _ value: Any) {
    UserDefaults.standard.set(value, forKey: key)
}

private var localeUses24Hour: Bool {
    !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true)
}

// MARK: - Settings model

@Observable
final class WidgetSettings {
    // Appearance
    var theme = load("theme", Theme.mono) { didSet { save("theme", theme.rawValue) } }
    var appearance = load("appearance", AppearanceMode.dark) { didSet { save("appearance", appearance.rawValue) } }
    var cardStyle = load("cardStyle", CardStyle.tinted) { didSet { save("cardStyle", cardStyle.rawValue) } }
    var cornerRadius = load("cornerRadius", 24.0) { didSet { save("cornerRadius", cornerRadius) } }
    var cardWidth = load("cardWidth", 340.0) { didSet { save("cardWidth", cardWidth) } }
    var cardSpacing = load("cardSpacing", 12.0) { didSet { save("cardSpacing", cardSpacing) } }
    var alertColors = load("alertColors", true) { didSet { save("alertColors", alertColors) } }
    /// Per-card scale by module (1 = normal). See `scale(for:)`.
    var cardScales: [String: Double] = (UserDefaults.standard.dictionary(forKey: "cardScales") as? [String: Double]) ?? [:] {
        didSet { save("cardScales", cardScales) }
    }

    // Window
    var windowLevel = load("windowLevel", WindowLevelMode.desktop) { didSet { save("windowLevel", windowLevel.rawValue) } }
    var lockPosition = load("lockPosition", false) { didSet { save("lockPosition", lockPosition) } }
    var clickThrough = load("clickThrough", false) { didSet { save("clickThrough", clickThrough) } }
    var hideInMissionControl = load("hideInMissionControl", true) { didSet { save("hideInMissionControl", hideInMissionControl) } }

    // Modules
    var moduleOrder: [WidgetModule] = {
        let saved = loadModules("moduleOrder") ?? []
        return saved + WidgetModule.allCases.filter { !saved.contains($0) }
    }() { didSet { save("moduleOrder", moduleOrder.map(\.rawValue)) } }

    var enabledModules: Set<WidgetModule> = Set(loadModules("enabledModules") ?? WidgetModule.allCases) {
        didSet { save("enabledModules", enabledModules.map(\.rawValue)) }
    }

    // Clock & date
    var clockStyle = load("clockStyle", ClockStyle.both) { didSet { save("clockStyle", clockStyle.rawValue) } }
    var use24Hour = load("use24Hour", localeUses24Hour) { didSet { save("use24Hour", use24Hour) } }
    var showSeconds = load("showSeconds", true) { didSet { save("showSeconds", showSeconds) } }
    var smoothSeconds = load("smoothSeconds", true) { didSet { save("smoothSeconds", smoothSeconds) } }
    var dateStyle = load("dateStyle", DateStyle.full) { didSet { save("dateStyle", dateStyle.rawValue) } }
    var showCalendar = load("showCalendar", true) { didSet { save("showCalendar", showCalendar) } }
    var showWeekNumber = load("showWeekNumber", true) { didSet { save("showWeekNumber", showWeekNumber) } }

    // Weather
    /// Chosen place (empty name = not set). Ignored when `useCurrentLocation` is on.
    var locationName = load("locationName", "") { didSet { save("locationName", locationName) } }
    var latitude = load("latitude", 0.0) { didSet { save("latitude", latitude) } }
    var longitude = load("longitude", 0.0) { didSet { save("longitude", longitude) } }
    var useCurrentLocation = load("useCurrentLocation", false) { didSet { save("useCurrentLocation", useCurrentLocation) } }
    var temperatureUnit = load(
        "temperatureUnit",
        Locale.current.measurementSystem == .us ? TemperatureUnit.fahrenheit : .celsius
    ) { didSet { save("temperatureUnit", temperatureUnit.rawValue) } }
    var showHourly = load("showHourly", true) { didSet { save("showHourly", showHourly) } }
    var showDaily = load("showDaily", true) { didSet { save("showDaily", showDaily) } }

    // System
    var refreshInterval = load("refreshInterval", 2.0) { didSet { save("refreshInterval", refreshInterval) } }
    var showCoreBars = load("showCoreBars", true) { didSet { save("showCoreBars", showCoreBars) } }
    var showCPUHistory = load("showCPUHistory", true) { didSet { save("showCPUHistory", showCPUHistory) } }
    var showMemoryHistory = load("showMemoryHistory", true) { didSet { save("showMemoryHistory", showMemoryHistory) } }
    var showAllVolumes = load("showAllVolumes", true) { didSet { save("showAllVolumes", showAllVolumes) } }
    var processCount = load("processCount", 6) { didSet { save("processCount", processCount) } }
    var processSort = load("processSort", ProcessSort.cpu) { didSet { save("processSort", processSort.rawValue) } }
    var allowQuit = load("allowQuit", true) { didSet { save("allowQuit", allowQuit) } }

    // Session state (not saved)
    /// Cards float above windows and show their edit controls.
    var editMode = false
    /// Message from the last Arrange, shown in the edit bar.
    var arrangeNotice: String?
    var settingsTab = SettingsTab.appearance

    // MARK: Helpers

    static let scaleRange = 0.6...1.8

    var colors: [Color] { theme.colors }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    func scale(for module: WidgetModule) -> Double { cardScales[module.rawValue] ?? 1 }

    func setScale(_ scale: Double, for module: WidgetModule) {
        cardScales[module.rawValue] = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    func isEnabled(_ module: WidgetModule) -> Bool { enabledModules.contains(module) }

    func setEnabled(_ module: WidgetModule, _ on: Bool) {
        if on { enabledModules.insert(module) } else { enabledModules.remove(module) }
    }
}
