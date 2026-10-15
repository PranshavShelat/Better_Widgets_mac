import AppKit
import SwiftUI

@main
struct BetterWidgetsMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments

        // `--diagnose <file>` writes permission and Arrange status. Launch it with `open -n`
        // so macOS checks the app's own permissions, not the terminal's.
        if let index = args.firstIndex(of: "--diagnose"), args.indices.contains(index + 1) {
            let report = """
            accessibility: \(AccessibilityPermission.isGranted)
            desktop widgets: \(DesktopObstacles.desktopWidgets().count)
            desktop icons: \(DesktopObstacles.desktopIcons().count)
            """
            try? report.write(toFile: args[index + 1], atomically: true, encoding: .utf8)
            return
        }
        if args.contains("--selftest") {
            SelfTest.run()
            return
        }

        let app = NSApplication.shared
        let delegate: NSApplicationDelegate
        if let index = args.firstIndex(of: "--snapshot"), args.indices.contains(index + 1) {
            delegate = SnapshotDelegate(output: args[index + 1],
                                        city: args.indices.contains(index + 2) ? args[index + 2] : nil,
                                        style: args.indices.contains(index + 3) ? args[index + 3] : "wallpaper")
        } else {
            delegate = AppDelegate()
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Borderless, transparent panel that hosts one card on the desktop.
final class WidgetPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        // .stationary keeps cards visible when you click the wallpaper to show the desktop.
        // MissionControlObserver hides them during Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }

    /// Keep the top edge fixed when the card grows or shrinks.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var rect = frameRect
        if frame.size != .zero, frameRect.size != frame.size, frameRect.origin == frame.origin {
            rect.origin.y = frame.maxY - frameRect.height
        }
        super.setFrame(rect, display: flag)
    }
}

/// The settings that affect windows, read inside observation tracking.
private struct WindowState: Equatable {
    var enabled: Set<WidgetModule>
    var editMode: Bool
    var level: WindowLevelMode
    var lockPosition: Bool
    var clickThrough: Bool
    var appearance: AppearanceMode
    var refreshInterval: Double
    var hideInMissionControl: Bool

    init(_ s: WidgetSettings) {
        enabled = s.enabledModules
        editMode = s.editMode
        level = s.windowLevel
        lockPosition = s.lockPosition
        clickThrough = s.clickThrough
        appearance = s.appearance
        refreshInterval = s.refreshInterval
        hideInMissionControl = s.hideInMissionControl
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = WidgetSettings()
    private let system = SystemMonitor()
    private let processes = ProcessMonitor()
    private let weather = WeatherService()

    private var panels: [WidgetModule: WidgetPanel] = [:]
    private var moveObservers: [WidgetModule: NSObjectProtocol] = [:]
    private var toolbar: NSPanel?
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var appliedInterval: Double = 0
    private var widgetsHidden = false
    private var missionControl: MissionControlObserver?
    private var missionControlActive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        system.settings = settings
        processes.settings = settings
        weather.settings = settings

        NotificationCenter.default.addObserver(forName: .openWidgetSettings, object: nil, queue: .main) { [weak self] note in
            let tab = (note.object as? String).flatMap(SettingsTab.init(rawValue:))
            MainActor.assumeIsolated {
                if let tab { self?.settings.settingsTab = tab }
                self?.showSettings()
            }
        }
        NotificationCenter.default.addObserver(forName: .arrangeWidgets, object: nil, queue: .main) { [weak self] note in
            let mode = (note.object as? String).flatMap(ArrangeMode.init(rawValue:)) ?? .grid
            MainActor.assumeIsolated { self?.arrange(mode) }
        }

        buildMainMenu()
        buildStatusItem()
        weather.start()
        observeSettings()

        // Ask for Accessibility once, so Arrange can see desktop icons.
        if !AccessibilityPermission.isGranted,
           !UserDefaults.standard.bool(forKey: "askedAccessibility") {
            UserDefaults.standard.set(true, forKey: "askedAccessibility")
            AccessibilityPermission.request()
        }

        // First launch: lay the cards out in a grid at the top-right of the screen.
        if !panels.keys.contains(where: { UserDefaults.standard.array(forKey: positionKey($0)) != nil }) {
            DispatchQueue.main.async { self.arrange(.grid, animate: false) }
        }
    }

    // MARK: Settings → windows

    private func observeSettings() {
        let state = withObservationTracking {
            WindowState(settings)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
        apply(state)
    }

    private func apply(_ state: WindowState) {
        // Create / remove card windows.
        for module in WidgetModule.allCases {
            if state.enabled.contains(module), panels[module] == nil {
                createPanel(for: module)
            } else if !state.enabled.contains(module), let panel = panels.removeValue(forKey: module) {
                panel.orderOut(nil)
                if let observer = moveObservers.removeValue(forKey: module) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }

        let level: NSWindow.Level = if state.editMode {
            .floating
        } else {
            switch state.level {
            // Above Finder's desktop icons (which would swallow clicks), below normal windows.
            case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            case .normal: .normal
            case .floating: .floating
            }
        }
        let appearance: NSAppearance? = switch state.appearance {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
        for panel in panels.values {
            panel.level = level
            panel.isMovable = state.editMode || !state.lockPosition
            panel.ignoresMouseEvents = state.clickThrough && !state.editMode
            panel.appearance = appearance
            if !widgetsHidden && !missionControlActive { panel.orderFrontRegardless() }
        }

        if state.editMode { showToolbar() } else { toolbar?.orderOut(nil) }

        if state.hideInMissionControl, missionControl == nil {
            missionControl = MissionControlObserver { [weak self] active in self?.setMissionControlActive(active) }
            missionControl?.start()
        } else if !state.hideInMissionControl, let observer = missionControl {
            observer.stop()
            missionControl = nil
            setMissionControlActive(false)
        }

        if state.refreshInterval != appliedInterval {
            appliedInterval = state.refreshInterval
            system.start(interval: state.refreshInterval)
            processes.start(interval: state.refreshInterval)
        }
    }

    private func createPanel(for module: WidgetModule) {
        let host = NSHostingView(rootView: CardHost(module: module)
            .environment(settings)
            .environment(system)
            .environment(processes)
            .environment(weather))
        let panel = WidgetPanel(contentView: host)
        panel.setContentSize(host.fittingSize)

        if let saved = UserDefaults.standard.array(forKey: positionKey(module)) as? [Double], saved.count == 2,
           NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSPoint(x: saved[0] + 40, y: saved[1] - 40)) }) {
            panel.setFrameOrigin(NSPoint(x: saved[0], y: saved[1] - panel.frame.height))
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - panel.frame.width / 2, y: screen.midY - panel.frame.height / 2))
        }

        moveObservers[module] = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, weak panel] _ in
            guard let panel else { return }
            MainActor.assumeIsolated { self?.savePosition(module, panel) }
        }
        panels[module] = panel
        if !widgetsHidden && !missionControlActive { panel.orderFrontRegardless() }
    }

    /// Takes the cards off screen entirely while Mission Control is open.
    private func setMissionControlActive(_ active: Bool) {
        missionControlActive = active
        for panel in panels.values {
            if active {
                panel.orderOut(nil)
            } else if !widgetsHidden {
                panel.orderFrontRegardless()
            }
        }
    }

    // MARK: Positions

    private func positionKey(_ module: WidgetModule) -> String { "position.\(module.rawValue)" }

    private func savePosition(_ module: WidgetModule, _ panel: NSWindow) {
        UserDefaults.standard.set([Double(panel.frame.minX), Double(panel.frame.maxY)], forKey: positionKey(module))
    }

    /// Places cards in free space, never over desktop widgets or desktop icons. If they don't
    /// fit, shrinks them evenly, and as a last resort hides the last cards in the Modules order.
    private func arrange(_ mode: ArrangeMode, animate: Bool = true) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        let obstacles = DesktopObstacles.current()
        let pad = cardWindowPadding
        let modules = settings.moduleOrder.filter { panels[$0] != nil }
        // Current card sizes, including each card's own scale.
        let sizes = modules.map { module -> CGSize in
            let frame = panels[module]?.frame ?? .zero
            return CGSize(width: frame.width - 2 * pad, height: frame.height - 2 * pad)
        }
        let scales = modules.map { settings.scale(for: $0) }
        let minScale = WidgetSettings.scaleRange.lowerBound

        // Shrink in 10% steps until everything fits or cards reach their minimum size.
        var factor = 1.0
        var rects: [CGRect?] = []
        while true {
            rects = CardLayout.place(sizes: sizes.map { CGSize(width: $0.width * factor, height: $0.height * factor) },
                                     in: area, obstacles: obstacles, gap: settings.cardSpacing, mode: mode)
            let canShrink = zip(scales, rects).contains { scale, _ in scale * (factor - 0.1) >= minScale - 0.001 }
            if rects.allSatisfy({ $0 != nil }) || !canShrink { break }
            factor -= 0.1
        }

        var hiddenModules: [WidgetModule] = []
        for (index, module) in modules.enumerated() {
            guard let panel = panels[module] else { continue }
            if factor < 1 { settings.setScale(scales[index] * factor, for: module) }
            if let rect = rects[index] {
                // A new scale resizes the window later; it keeps its top-left corner, so that's what we place.
                let frame = rect.insetBy(dx: -pad, dy: -pad)
                panel.setFrame(frame, display: true, animate: animate)
                savePosition(module, panel)
            } else {
                hiddenModules.append(module)
            }
        }

        if hiddenModules.isEmpty {
            settings.arrangeNotice = factor < 1 ? "Cards were shrunk to \(Int(factor * 100))% to fit around your desktop." : nil
        } else {
            for module in hiddenModules { settings.setEnabled(module, false) }
            settings.arrangeNotice = "Not enough free space — hid " +
                hiddenModules.map(\.title).formatted(.list(type: .and)) + ". Add them back below."
            settings.editMode = true
        }
    }

    // MARK: Edit toolbar

    private func showToolbar() {
        if toolbar == nil {
            let host = NSHostingView(rootView: EditToolbar().environment(settings))
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host
            toolbar = panel
        }
        guard let toolbar, let host = toolbar.contentView, let screen = NSScreen.main?.visibleFrame else { return }
        toolbar.setContentSize(host.fittingSize)
        toolbar.setFrameOrigin(NSPoint(x: screen.midX - toolbar.frame.width / 2, y: screen.minY + 24))
        toolbar.orderFrontRegardless()
    }

    // MARK: Menus

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                           accessibilityDescription: "Better Widgets")
        let menu = NSMenu()
        menu.addItem(item("Edit Widgets…", #selector(toggleEditMode), "e"))
        let widgetsItem = NSMenuItem(title: "Widgets", action: nil, keyEquivalent: "")
        let widgetsMenu = NSMenu()
        widgetsMenu.delegate = self
        widgetsItem.submenu = widgetsMenu
        menu.addItem(widgetsItem)
        let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
        let arrangeMenu = NSMenu()
        for mode in ArrangeMode.allCases {
            let entry = item(mode.title, #selector(arrangeFromMenu(_:)), "")
            entry.representedObject = mode.rawValue
            arrangeMenu.addItem(entry)
        }
        arrangeItem.submenu = arrangeMenu
        menu.addItem(arrangeItem)
        menu.addItem(item("Show / Hide Widgets", #selector(toggleWidgets), "h"))
        menu.addItem(item("Toggle Click-Through", #selector(toggleClickThrough), "t"))
        menu.addItem(item("Refresh Weather", #selector(refreshWeather), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), ","))
        menu.addItem(item("Quit Better Widgets", #selector(quit), "q"))
        statusItem.menu = menu
    }

    private func buildMainMenu() {
        // No visible menu bar, but this enables ⌘C, ⌘V, ⌘A and ⌘W in the Settings window.
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(appItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Better Widgets Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView()
                .environment(settings)
                .environment(system)
                .environment(weather))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Rebuilds the Widgets submenu with a checkmark per visible card.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for module in settings.moduleOrder {
            let entry = item(module.title, #selector(toggleModule(_:)), "")
            entry.representedObject = module.rawValue
            entry.state = settings.isEnabled(module) ? .on : .off
            entry.image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: nil)
            menu.addItem(entry)
        }
    }

    @objc private func toggleModule(_ sender: NSMenuItem) {
        guard let module = (sender.representedObject as? String).flatMap(WidgetModule.init(rawValue:)) else { return }
        settings.setEnabled(module, !settings.isEnabled(module))
    }

    @objc private func toggleEditMode() {
        settings.editMode.toggle()
    }

    @objc private func arrangeFromMenu(_ sender: NSMenuItem) {
        arrange((sender.representedObject as? String).flatMap(ArrangeMode.init(rawValue:)) ?? .grid)
    }

    @objc private func toggleWidgets() {
        widgetsHidden.toggle()
        for panel in panels.values {
            if widgetsHidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
    }

    @objc private func toggleClickThrough() {
        settings.clickThrough.toggle()
    }

    @objc private func refreshWeather() {
        weather.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
