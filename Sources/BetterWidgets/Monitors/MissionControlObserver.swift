import AppKit
import os

private let log = Logger(subsystem: "io.github.pranshavshelat.betterwidgets", category: "mission-control")

/// Reports when Mission Control opens and closes by checking the window list a few times a
/// second (no permission needed).
@MainActor
final class MissionControlObserver {
    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var active = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        log.notice("Watching for Mission Control")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if active {
            active = false
            onChange(false)
        }
    }

    private func poll() {
        let now = Self.missionControlIsOpen()
        guard now != active else { return }
        active = now
        log.notice("Mission Control \(now ? "opened" : "closed", privacy: .public)")
        onChange(now)
    }

    nonisolated static func missionControlIsOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // WindowManager windows on macOS 27:
        //   Show Desktop (click wallpaper): full-screen window on layer 18 -> keep cards
        //   Mission Control: full-screen window on layer 19 + Spaces strip on layer 14 -> hide cards
        let screens = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "WindowManager",
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return screens.contains { screen in
                let fullScreen = rect.width >= screen.width * 0.95 && rect.height >= screen.height * 0.95
                let spacesStrip = layer == 14 && rect.width >= screen.width * 0.95 && rect.height < screen.height * 0.3
                return (fullScreen && layer >= 19) || spacesStrip
            }
        }
    }
}
