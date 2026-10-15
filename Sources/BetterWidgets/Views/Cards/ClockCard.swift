import SwiftUI

struct ClockCard: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        CardContainer(module: .clock) {
            Text(TimeZoneLocation.label(for: .current))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        } content: {
            HStack(spacing: 18) {
                if settings.clockStyle != .digital {
                    AnalogClock()
                        .frame(width: settings.clockStyle == .both ? 112 : 190,
                               height: settings.clockStyle == .both ? 112 : 190)
                }
                if settings.clockStyle != .analog {
                    DigitalClock(compact: settings.clockStyle == .both)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// "India" for Asia/Kolkata; "Los Angeles, United States" when a country has several zones.
enum TimeZoneLocation {
    /// Time zone identifier → ISO country code, from the system's tz database.
    private static let countries: [String: String] = {
        guard let table = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in table.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            if fields.count >= 3 { result[String(fields[2])] = String(fields[0]) }
        }
        return result
    }()

    static func label(for zone: TimeZone) -> String {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        guard let code = countries[zone.identifier],
              let country = Locale.current.localizedString(forRegionCode: code) else { return city }
        let zonesInCountry = countries.values.filter { $0 == code }.count
        return zonesInCountry > 1 ? "\(city), \(country)" : country
    }
}

private enum TimeFormat {
    static let hm12: DateFormatter = make("h:mm")
    static let hm24: DateFormatter = make("HH:mm")
    static let seconds: DateFormatter = make("ss")
    static let period: DateFormatter = make("a")

    static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }
}

struct DigitalClock: View {
    @Environment(WidgetSettings.self) private var settings
    var compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let hm = (settings.use24Hour ? TimeFormat.hm24 : TimeFormat.hm12).string(from: date)
            let seconds = TimeFormat.seconds.string(from: date)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hm)
                    .font(.system(size: compact ? 46 : 64, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())

                VStack(alignment: .leading, spacing: 0) {
                    if !settings.use24Hour {
                        Text(TimeFormat.period.string(from: date))
                            .font(.system(size: compact ? 12 : 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    if settings.showSeconds {
                        Text(seconds)
                            .font(.system(size: compact ? 18 : 24, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(settings.colors[1])
                    }
                }
            }
            .animation(.smooth(duration: 0.4), value: seconds)
            .animation(.smooth(duration: 0.6), value: hm)
        }
    }
}

struct AnalogClock: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        let colors = settings.colors
        let showSeconds = settings.showSeconds
        let smooth = settings.smoothSeconds && showSeconds
        ZStack {
            // The dial is drawn once; only the hands redraw.
            Canvas { g, size in Self.drawFace(in: &g, size: size, colors: colors) }
                .drawingGroup()
            if smooth {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    hands(date: context.date, colors: colors, showSeconds: true, smooth: true)
                }
            } else {
                TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 1)) { context in
                    hands(date: context.date, colors: colors, showSeconds: showSeconds, smooth: false)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func hands(date: Date, colors: [Color], showSeconds: Bool, smooth: Bool) -> some View {
        Canvas { g, size in
            Self.drawHands(in: &g, size: size, date: date, colors: colors, showSeconds: showSeconds, smooth: smooth)
        }
    }

    private static func geometry(_ size: CGSize) -> (radius: CGFloat, point: (Double, CGFloat) -> CGPoint) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return (radius, { angle, length in
            CGPoint(x: center.x + CGFloat(sin(angle)) * length, y: center.y - CGFloat(cos(angle)) * length)
        })
    }

    private static func drawFace(in g: inout GraphicsContext, size: CGSize, colors: [Color]) {
        let (radius, point) = geometry(size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let face = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))

        // Subtle top-lit dial with a hairline rim.
        g.fill(face, with: .linearGradient(
            Gradient(colors: [.primary.opacity(0.08), .primary.opacity(0.02)]),
            startPoint: CGPoint(x: center.x, y: center.y - radius), endPoint: CGPoint(x: center.x, y: center.y + radius)))
        let rim = Path(ellipseIn: CGRect(x: center.x - radius + 0.5, y: center.y - radius + 0.5,
                                         width: radius * 2 - 1, height: radius * 2 - 1))
        g.stroke(rim, with: .color(.primary.opacity(0.14)), lineWidth: 1)

        for i in 0..<60 {
            let angle = Double(i) / 60 * 2 * .pi
            let major = i % 5 == 0
            let outer = radius - 7
            let inner = outer - (major ? radius * 0.11 : radius * 0.045)
            var tick = Path()
            tick.move(to: point(angle, inner))
            tick.addLine(to: point(angle, outer))
            g.stroke(tick, with: .color(.primary.opacity(major ? 0.75 : 0.2)),
                     style: StrokeStyle(lineWidth: major ? 1.6 : 0.8, lineCap: .round))
        }

        if radius > 70 {
            for (index, label) in ["12", "3", "6", "9"].enumerated() {
                g.draw(Text(label).font(.system(size: radius * 0.15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary), at: point(Double(index) * .pi / 2, radius * 0.66))
            }
        }
    }

    private static func drawHands(in g: inout GraphicsContext, size: CGSize, date: Date, colors: [Color],
                                  showSeconds: Bool, smooth: Bool) {
        let (radius, point) = geometry(size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        let parts = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        var second = Double(parts.second ?? 0)
        if smooth { second += Double(parts.nanosecond ?? 0) / 1_000_000_000 }
        let minute = Double(parts.minute ?? 0) + second / 60
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60

        func hand(_ angle: Double, length: CGFloat, tail: CGFloat) -> Path {
            var path = Path()
            path.move(to: point(angle + .pi, tail))
            path.addLine(to: point(angle, length))
            return path
        }

        // Offset stroke as a cheap shadow; this layer redraws up to 30 times a second.
        let hourHand = hand(hour / 12 * 2 * .pi, length: radius * 0.5, tail: radius * 0.08)
        let minuteHand = hand(minute / 60 * 2 * .pi, length: radius * 0.74, tail: radius * 0.08)
        var shadow = g
        shadow.translateBy(x: 0, y: 1)
        shadow.stroke(hourHand, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: radius * 0.07, lineCap: .round))
        shadow.stroke(minuteHand, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: radius * 0.05, lineCap: .round))
        g.stroke(hourHand, with: .color(.primary), style: StrokeStyle(lineWidth: radius * 0.065, lineCap: .round))
        g.stroke(minuteHand, with: .color(.primary), style: StrokeStyle(lineWidth: radius * 0.045, lineCap: .round))

        if showSeconds {
            let secondHand = hand(second / 60 * 2 * .pi, length: radius * 0.84, tail: radius * 0.18)
            g.stroke(secondHand, with: .color(colors[1]), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }

        let hub = radius * 0.06
        g.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
               with: .color(colors[1]))
        g.fill(Path(ellipseIn: CGRect(x: center.x - hub / 2.5, y: center.y - hub / 2.5,
                                      width: hub / 1.25, height: hub / 1.25)), with: .color(.white))
    }
}
