import AppKit
import ApplicationServices

/// Things on the desktop that cards must not cover: Apple's (and other apps') desktop widgets
/// and Finder's desktop icons. All rects are in AppKit screen coordinates (origin bottom-left).
enum DesktopObstacles {
    static func current() -> [NSRect] {
        desktopWidgets() + desktopIcons()
    }

    /// Windows that live on the desktop layer: Apple's widgets ("Notification Center") or
    /// third-party desktop widgets. Readable without any permission.
    static func desktopWidgets() -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let ignoredOwners: Set<String> = ["Window Server", "Finder", "Dock", "Wallpaper", "WindowManager"]
        let screenArea = NSScreen.screens.map { $0.frame.width * $0.frame.height }.max() ?? 1

        return list.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer < 0,
                  (window[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  !ignoredOwners.contains(window[kCGWindowOwnerName as String] as? String ?? ""),
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width * rect.height < screenArea * 0.5
            else { return nil }
            return toAppKit(rect)
        }
    }

    /// Finder's desktop icons, via Accessibility (desktop scroll area → icon group → icons).
    /// Returns nothing if Accessibility access hasn't been granted.
    static func desktopIcons() -> [NSRect] {
        guard AXIsProcessTrusted(),
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return [] }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 1)

        var rects: [NSRect] = []
        for area in children(of: app) where role(of: area) == kAXScrollAreaRole as String {
            for group in children(of: area) {
                for icon in children(of: group) {
                    // The icon's frame may cover only the picture; its children include the name.
                    let frames = ([icon] + children(of: icon)).compactMap(frame(of:))
                    guard var union = frames.first else { continue }
                    for frame in frames.dropFirst() { union = union.union(frame) }
                    // Names can wrap to two lines, so always leave room for them.
                    union.size.height = max(union.height, union.width + 34)
                    rects.append(toAppKit(union).insetBy(dx: -10, dy: -10))
                }
            }
        }
        return rects
    }

    // MARK: Helpers

    /// Quartz (top-left origin, primary screen) → AppKit (bottom-left origin).
    private static func toAppKit(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }
}
