import AppKit
import SwiftUI

/// `BetterWidgets --snapshot out.png [city] [wallpaper|blur|transparent]` renders the live cards
/// to a PNG for screenshots. Glass can't be captured off screen, so it uses the Black style.
@MainActor
final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    private let settings = WidgetSettings()
    private let system = SystemMonitor()
    private let processes = ProcessMonitor()
    private let weather = WeatherService()
    private let output: String
    private let style: String

    init(output: String, city: String?, style: String = "wallpaper") {
        self.output = output
        self.style = style
        super.init()
        settings.cardStyle = .tinted
        settings.theme = .mono
        processes.excludedNames = ["betterwidgets"]
        if let city {
            Task {
                if let place = try? await WeatherService.geocode(city) {
                    settings.locationName = place.name
                    settings.latitude = place.latitude
                    settings.longitude = place.longitude
                    weather.refresh()
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        system.settings = settings
        processes.settings = settings
        weather.settings = settings
        system.start(interval: 1)
        processes.start(interval: 1)
        weather.refresh()
        // Long enough for the history graphs to fill in a bit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { self.render() }
    }

    private func render() {
        let columns: [[WidgetModule]] = [[.clock, .weather], [.cpu, .memory], [.date, .disk, .processes]]
        let view = HStack(alignment: .top, spacing: 0) {
            ForEach(columns, id: \.self) { column in
                VStack(spacing: -cardWindowPadding * 2 + self.settings.cardSpacing) {
                    ForEach(column) { CardHost(module: $0) }
                }
            }
        }
        .padding(30)
            .environment(settings)
            .environment(system)
            .environment(processes)
            .environment(weather)
            .background { backdrop }
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.colorMode = .nonLinear
        renderer.isOpaque = style != "transparent"
        if let image = renderer.cgImage,
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: output))
            print("Wrote \(output)")
        } else {
            print("Render failed")
        }
        NSApp.terminate(nil)
    }

    @ViewBuilder
    private var backdrop: some View {
        switch style {
        case "transparent":
            Color.clear
        case "blur":
            // Soft, out-of-focus colour fields, like a heavily blurred wallpaper.
            ZStack {
                Color(hex: 0x0A0A0D)
                Ellipse().fill(Color(hex: 0x4A5D8C)).frame(width: 1000, height: 620).blur(radius: 160).offset(x: -420, y: -260)
                Ellipse().fill(Color(hex: 0x6E4A7E)).frame(width: 760, height: 560).blur(radius: 170).offset(x: 460, y: -180)
                Ellipse().fill(Color(hex: 0x2F6F73)).frame(width: 900, height: 560).blur(radius: 170).offset(x: 120, y: 380)
                Ellipse().fill(Color(hex: 0x8C6A4E).opacity(0.7)).frame(width: 600, height: 420).blur(radius: 160).offset(x: -520, y: 420)
            }
        default:
            // A dark, softly lit sample wallpaper.
            ZStack {
                LinearGradient(colors: [Color(hex: 0x1A1B20), Color(hex: 0x0B0B0E)],
                               startPoint: .top, endPoint: .bottom)
                Ellipse().fill(Color(hex: 0x5B6B8C).opacity(0.55)).frame(width: 900, height: 420)
                    .blur(radius: 140).offset(x: -260, y: -260)
                Ellipse().fill(Color(hex: 0x8C6B5B).opacity(0.35)).frame(width: 700, height: 380)
                    .blur(radius: 150).offset(x: 360, y: 360)
            }
        }
    }
}
