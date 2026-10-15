import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Warning colors when a metric runs hot, otherwise the theme colors.
func usageColors(_ value: Double, theme: [Color], alerts: Bool) -> [Color] {
    guard alerts else { return theme }
    // Three stops, like every theme (views use colors[0...2]).
    if value > 0.9 { return [Color(hex: 0xFF8A80), Color(hex: 0xFF5F57), Color(hex: 0xFF453A)] }
    return theme
}

func formatBytes(_ bytes: UInt64, style: ByteCountFormatter.CountStyle = .memory) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = style
    formatter.allowedUnits = [.useMB, .useGB, .useTB]
    return formatter.string(fromByteCount: Int64(clamping: bytes))
}

func formatPercent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
}

// MARK: - Card chrome

struct CardContainer<Accessory: View, Content: View>: View {
    @Environment(WidgetSettings.self) private var settings
    let module: WidgetModule
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: module.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.colors[1])
                Text(module.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground(hovering: hovering))
        .animation(.easeOut(duration: 0.2), value: hovering)
        .onHover { hovering = $0 }
    }
}

extension CardContainer where Accessory == EmptyView {
    init(module: WidgetModule, @ViewBuilder content: () -> Content) {
        self.module = module
        self.accessory = EmptyView()
        self.content = content()
    }
}

struct CardBackground: ViewModifier {
    @Environment(WidgetSettings.self) private var settings
    var hovering: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
        // Hairline edge, brighter at the top.
        let decorated = content
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [.white.opacity(hovering ? 0.32 : 0.2), .white.opacity(0.03), .white.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 0.75)
            }

        // No drop shadow: it would be re-blurred on every content update (e.g. each clock tick).
        switch settings.cardStyle {
        case .glass:
            if #available(macOS 26.0, *) {
                decorated
                    .glassEffect(.regular, in: shape)
            } else {
                decorated
                    .background(.ultraThinMaterial, in: shape)
            }
        case .frosted:
            decorated
                .background(.regularMaterial, in: shape)
        case .tinted:
            decorated
                .background(Color.black.opacity(0.92), in: shape)
        }
    }
}

// MARK: - Gauges & charts

struct GaugeRing<Center: View>: View {
    var value: Double
    var colors: [Color]
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        let clamped = min(max(value, 0.002), 1)
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                // Solid stroke: a conic gradient is redrawn on the CPU every animation frame.
                .stroke(colors[1], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: clamped)
    }
}

/// Smooth area chart for the history graphs.
struct Sparkline: View {
    var values: [Double]
    var colors: [Color]
    var capacity = SystemMonitor.historyLength

    var body: some View {
        Canvas { context, size in
            // Baseline grid
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * fraction
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(grid, with: .color(.primary.opacity(0.06)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }

            guard values.count > 1 else { return }
            let step = size.width / CGFloat(max(capacity - 1, 1))
            let startX = size.width - step * CGFloat(values.count - 1)
            let points = values.enumerated().map { index, value in
                CGPoint(x: startX + CGFloat(index) * step,
                        y: size.height - CGFloat(min(max(value, 0), 1)) * (size.height - 3) - 1.5)
            }
            let line = smoothPath(points)

            var area = line
            area.addLine(to: CGPoint(x: points.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: points[0].x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [colors[1].opacity(0.22), colors[2].opacity(0.0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

            let stroke = GraphicsContext.Shading.linearGradient(
                Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            context.stroke(line, with: stroke, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            let last = points.last!
            context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(.white))
        }
    }
}

/// Smooth curve through the points that never overshoots the data.
func smoothPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 2 else {
        points.dropFirst().forEach { path.addLine(to: $0) }
        return path
    }
    for i in 1..<points.count {
        let previous = points[i - 1], current = points[i]
        let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
        if i == 1 { path.addLine(to: mid) } else { path.addQuadCurve(to: mid, control: previous) }
    }
    path.addLine(to: points.last!)
    return path
}

struct Segment: Identifiable {
    let id: String
    let value: Double
    let color: Color
}

/// Stacked capsule bar (e.g. memory composition).
struct SegmentBar: View {
    var segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color.gradient)
                        .frame(width: max(0, geometry.size.width * segment.value / total - 2))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Capsule progress bar.
struct ProgressCapsule: View {
    var value: Double
    var colors: [Color]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}

struct LegendDot: View {
    var color: Color
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 2)
            Text(value).monospacedDigit().fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.system(size: 11, design: .rounded))
    }
}

struct Chip: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical)
            Text(text).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}
