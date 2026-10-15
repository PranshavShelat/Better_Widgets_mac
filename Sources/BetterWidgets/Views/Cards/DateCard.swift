import SwiftUI

struct DateCard: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        CardContainer(module: .date) {
            TimelineView(.everyMinute) { context in
                let date = context.date
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekday(date).uppercased())
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(settings.theme == .mono ? Color(hex: 0xFF453A) : settings.colors[1])
                        Text(headline(date))
                            .font(.system(size: settings.dateStyle == .numeric ? 40 : 56, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(subtitle(date))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        if settings.showWeekNumber {
                            let calendar = Calendar.current
                            Text("Week \(calendar.component(.weekOfYear, from: date)) · Day \(calendar.ordinality(of: .day, in: .year, for: date) ?? 0)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                    }
                    if settings.showCalendar {
                        Spacer(minLength: 0)
                        MiniCalendar(date: date, colors: settings.colors, todayText: settings.theme.accentForeground)
                    }
                }
            }
        }
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(settings.dateStyle == .full ? .wide : .abbreviated))
    }

    private func headline(_ date: Date) -> String {
        settings.dateStyle == .numeric
            ? date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
            : date.formatted(.dateTime.day())
    }

    private func subtitle(_ date: Date) -> String {
        switch settings.dateStyle {
        case .full: date.formatted(.dateTime.month(.wide).year())
        case .compact: date.formatted(.dateTime.month(.abbreviated).year())
        case .numeric: date.formatted(.dateTime.year())
        }
    }
}

struct MiniCalendar: View {
    let date: Date
    let colors: [Color]
    let todayText: Color

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let orderedSymbols = Array(symbols[first...] + symbols[..<first])
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let lead = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let today = calendar.component(.day, from: date)
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }

        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                ForEach(0..<7, id: \.self) { column in
                    Text(orderedSymbols[column])
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 14)
                }
            }
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let day = column < rows[row].count ? rows[row][column] : nil
                        let weekday = (column + calendar.firstWeekday - 1) % 7 + 1
                        let weekend = weekday == 1 || weekday == 7
                        Group {
                            if let day {
                                Text("\(day)")
                                    .font(.system(size: 10, weight: day == today ? .bold : .medium, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(day == today ? todayText
                                                     : Color.primary.opacity(weekend ? 0.45 : 0.8))
                                    .background {
                                        if day == today {
                                            Circle()
                                                .fill(colors[1])
                                                .frame(width: 19, height: 19)
                                        }
                                    }
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 20, height: 17)
                    }
                }
            }
        }
    }
}
