import SwiftUI

struct CPUCard: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let colors = usageColors(system.cpuTotal, theme: settings.colors, alerts: settings.alertColors)
        CardContainer(module: .cpu) {
            Text("\(system.cpuName) · \(system.coreCount) cores")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } content: {
            HStack(spacing: 18) {
                GaugeRing(value: system.cpuTotal, colors: colors, lineWidth: 8) {
                    VStack(spacing: -2) {
                        Text(formatPercent(system.cpuTotal))
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: system.cpuTotal)
                        Text("LOAD")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(spacing: 7) {
                    LegendDot(color: colors[0], label: "User", value: formatPercent(system.cpuUser))
                    LegendDot(color: colors[colors.count - 1], label: "System", value: formatPercent(system.cpuSystem))
                    LegendDot(color: .gray, label: "Idle", value: formatPercent(max(0, 1 - system.cpuTotal)))
                    LegendDot(color: .white.opacity(0.6), label: "Load avg",
                              value: system.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "))
                    LegendDot(color: .white.opacity(0.3), label: "Uptime", value: uptimeString(system.uptime))
                }
            }

            if settings.showCoreBars, !system.coreUsage.isEmpty {
                CoreBars(values: system.coreUsage, colors: settings.colors, alerts: settings.alertColors)
                    .frame(height: 38)
            }

            if settings.showCPUHistory {
                Sparkline(values: system.cpuHistory, colors: colors)
                    .frame(height: 44)
            }
        }
    }

    private func uptimeString(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(mins)m"
    }
}

private struct CoreBars: View {
    var values: [Double]
    var colors: [Color]
    var alerts: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: values.count > 16 ? 2 : 4) {
            ForEach(values.indices, id: \.self) { index in
                let value = values[index]
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: usageColors(value, theme: colors, alerts: alerts).reversed(),
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(height: max(4, geometry.size.height * value))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: value)
            }
        }
    }
}

struct MemoryCard: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        let memory = system.memory
        let colors = usageColors(memory.fraction, theme: settings.colors, alerts: settings.alertColors)
        let palette = settings.colors
        CardContainer(module: .memory) {
            Text("\(formatBytes(memory.total)) total")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        } content: {
            HStack(spacing: 18) {
                GaugeRing(value: memory.fraction, colors: colors, lineWidth: 8) {
                    VStack(spacing: -2) {
                        Text(formatPercent(memory.fraction))
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: memory.fraction)
                        Text("USED")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 6) {
                    Text(formatBytes(memory.used))
                        .font(.system(size: 26, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("of \(formatBytes(memory.total)) in use")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            SegmentBar(segments: [
                Segment(id: "app", value: Double(memory.app), color: palette[0]),
                Segment(id: "wired", value: Double(memory.wired), color: palette[1]),
                Segment(id: "compressed", value: Double(memory.compressed), color: palette[2]),
                Segment(id: "cached", value: Double(memory.cached), color: .gray.opacity(0.6)),
                Segment(id: "free", value: Double(memory.free), color: .clear),
            ])
            .animation(.spring(response: 0.6), value: memory.used)

            Grid(horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    LegendDot(color: palette[0], label: "App", value: formatBytes(memory.app))
                    LegendDot(color: palette[1], label: "Wired", value: formatBytes(memory.wired))
                }
                GridRow {
                    LegendDot(color: palette[2], label: "Compressed", value: formatBytes(memory.compressed))
                    LegendDot(color: .gray, label: "Cached", value: formatBytes(memory.cached))
                }
                GridRow {
                    LegendDot(color: .primary.opacity(0.25), label: "Swap", value: formatBytes(memory.swapUsed))
                    LegendDot(color: .clear, label: "Free", value: formatBytes(memory.free))
                }
            }

            if settings.showMemoryHistory {
                Sparkline(values: system.memoryHistory, colors: colors)
                    .frame(height: 40)
            }
        }
    }
}

struct DiskCard: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        CardContainer(module: .disk) {
            Button { system.refreshDisks() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } content: {
            if system.volumes.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }
            VStack(spacing: 14) {
                ForEach(system.volumes) { volume in
                    VolumeRow(volume: volume)
                }
            }
        }
    }
}

private struct VolumeRow: View {
    @Environment(WidgetSettings.self) private var settings
    let volume: VolumeInfo

    var body: some View {
        let colors = usageColors(volume.fraction, theme: settings.colors, alerts: settings.alertColors)
        HStack(spacing: 14) {
            GaugeRing(value: volume.fraction, colors: colors, lineWidth: 7) {
                Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(colors[1])
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text(formatPercent(volume.fraction))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ProgressCapsule(value: volume.fraction, colors: colors, height: 7)
                HStack {
                    Label(formatBytes(UInt64(volume.used), style: .file) + " used", systemImage: "circle.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatBytes(UInt64(volume.free), style: .file) + " free")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 10, design: .rounded))
                .labelStyle(DotLabelStyle(color: colors[1]))
            }
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            configuration.title
        }
    }
}
