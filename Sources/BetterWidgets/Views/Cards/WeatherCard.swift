import SwiftUI

struct WeatherCard: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(WeatherService.self) private var weather

    var body: some View {
        CardContainer(module: .weather) {
            if weather.status == .ready || weather.status == .loading {
                Button { weather.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh weather")
            }
        } content: {
            switch weather.status {
            case .needsCity:
                VStack(spacing: 10) {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(settings.colors[1])
                    Text("Choose a location to see the forecast.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button {
                            settings.useCurrentLocation = true
                            weather.refresh()
                        } label: { Label("Use My Location", systemImage: "location.fill") }
                        Button("Choose City…") { WidgetCommands.openSettings(tab: .weather) }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            case .failed(let message):
                placeholder(symbol: "exclamationmark.icloud.fill", message: message)
            case .loading where weather.current == nil:
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }.frame(height: 80)
            default:
                if let current = weather.current { loaded(current) }
            }
        }
    }

    private func placeholder(symbol: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(settings.colors[1])
            Text(message)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Weather Settings…") { WidgetCommands.openSettings(tab: .weather) }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func loaded(_ current: WeatherService.Current) -> some View {
        let unit = weather.unit == .fahrenheit ? "mph" : "km/h"
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: WeatherCode.symbol(current.code, isDay: current.isDay))
                    .modifier(WeatherSymbolStyle())
                    .font(.system(size: 42))
                    .frame(width: 60)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(current.temperature.rounded()))°")
                        .font(.system(size: 46, weight: .thin, design: .rounded))
                        .contentTransition(.numericText())
                    Text(WeatherCode.description(current.code))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Label(weather.locationName, systemImage: "location.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let today = weather.days.first {
                        Text("H \(Int(today.high.rounded()))°  L \(Int(today.low.rounded()))°")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text("Feels \(Int(current.apparent.rounded()))°")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Chip(symbol: "humidity.fill", text: "\(Int(current.humidity))%")
                Chip(symbol: "wind", text: "\(Int(current.wind.rounded())) \(unit)")
                if let sunrise = weather.sunrise, let sunset = weather.sunset {
                    let showSunset = Date() > sunrise && Date() < sunset
                    Chip(symbol: showSunset ? "sunset.fill" : "sunrise.fill",
                         text: shortTime(showSunset ? sunset : sunrise))
                }
            }

            if settings.showHourly, weather.hours.count > 1 {
                HourlyStrip(hours: Array(weather.hours.prefix(8)), timeZone: weather.timeZone,
                            colorFor: { temperatureColors($0, $0)[0] })
            }

            if settings.showDaily, !weather.days.isEmpty {
                DailyList(days: Array(weather.days.prefix(5)), timeZone: weather.timeZone,
                          colors: temperatureColors)
            }
        }
    }

    private func shortTime(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = weather.timeZone
        return date.formatted(style)
    }

    /// Cold blue → warm red gradient, independent of unit.
    private func temperatureColors(_ low: Double, _ high: Double) -> [Color] {
        if settings.theme == .mono { return [Color.white.opacity(0.45), Color.white] }
        func celsius(_ t: Double) -> Double { weather.unit == .fahrenheit ? (t - 32) * 5 / 9 : t }
        func color(_ t: Double) -> Color {
            switch celsius(t) {
            case ..<0: Color(hex: 0x8EC5FF)
            case ..<10: Color(hex: 0x5AC8FA)
            case ..<18: Color(hex: 0x64D2A0)
            case ..<25: Color(hex: 0xFFD60A)
            case ..<32: Color(hex: 0xFF9F0A)
            default: Color(hex: 0xFF453A)
            }
        }
        return [color(low), color(high)]
    }
}

private struct HourlyStrip: View {
    let hours: [WeatherService.Hour]
    let timeZone: TimeZone
    let colorFor: (Double) -> Color

    var body: some View {
        let temps = hours.map(\.temperature)
        let low = temps.min() ?? 0, high = temps.max() ?? 1
        let span = max(high - low, 1)
        let colors = [colorFor(low), colorFor(high)]

        VStack(spacing: 4) {
            Canvas { g, size in
                let step = size.width / CGFloat(hours.count)
                let points = hours.enumerated().map { index, hour in
                    CGPoint(x: step * (CGFloat(index) + 0.5),
                            y: 6 + (size.height - 12) * CGFloat(1 - (hour.temperature - low) / span))
                }
                let line = smoothPath(points)
                var area = line
                area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
                area.addLine(to: CGPoint(x: points[0].x, y: size.height))
                area.closeSubpath()
                g.fill(area, with: .linearGradient(Gradient(colors: [colors[1].opacity(0.18), .clear]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: colors.reversed()), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
                g.stroke(line, with: shading, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                for point in points {
                    g.fill(Path(ellipseIn: CGRect(x: point.x - 1.75, y: point.y - 1.75, width: 3.5, height: 3.5)), with: .color(.white))
                }
            }
            .frame(height: 34)

            HStack(spacing: 0) {
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 3) {
                        Text("\(Int(hour.temperature.rounded()))°")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                            .modifier(WeatherSymbolStyle())
                            .font(.system(size: 13))
                            .frame(height: 16)
                        Text(index == 0 ? "Now" : label(hour.date))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func label(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .narrow))
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

private struct DailyList: View {
    let days: [WeatherService.Day]
    let timeZone: TimeZone
    let colors: (Double, Double) -> [Color]

    var body: some View {
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        let span = max(high - low, 1)

        VStack(spacing: 7) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 8) {
                    Text(index == 0 ? "Today" : weekday(day.date))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .frame(width: 42, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .modifier(WeatherSymbolStyle())
                        .font(.system(size: 13))
                        .frame(width: 20)
                    Text(day.precipitation.map { $0 >= 20 ? "\($0)%" : "" } ?? "")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 32, alignment: .leading)
                    Text("\(Int(day.low.rounded()))°")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { geometry in
                        let start = (day.low - low) / span
                        let end = (day.high - low) / span
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: colors(day.low, day.high), startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, geometry.size.width * (end - start)))
                                .offset(x: geometry.size.width * start)
                        }
                    }
                    .frame(height: 5)
                    Text("\(Int(day.high.rounded()))°")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 30, alignment: .leading)
                }
            }
        }
    }

    private func weekday(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Full-color weather symbols, or quiet monochrome ones in the Mono theme.
private struct WeatherSymbolStyle: ViewModifier {
    @Environment(WidgetSettings.self) private var settings

    func body(content: Content) -> some View {
        content.symbolRenderingMode(settings.theme == .mono ? .hierarchical : .multicolor)
    }
}
