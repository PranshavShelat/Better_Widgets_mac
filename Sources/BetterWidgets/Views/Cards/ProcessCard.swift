import SwiftUI

struct ProcessCard: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(ProcessMonitor.self) private var monitor

    var body: some View {
        @Bindable var settings = settings
        let entries = monitor.top(by: settings.processSort, count: settings.processCount)
        let maxValue = entries.map { settings.processSort == .cpu ? $0.cpu : Double($0.memory) }.max() ?? 1

        CardContainer(module: .processes) {
            GlowSegmentedControl(selection: $settings.processSort, colors: settings.colors,
                                 selectedText: settings.theme.accentForeground)
        } content: {
            VStack(spacing: 4) {
                ForEach(entries) { entry in
                    ProcessRow(entry: entry, maxValue: max(maxValue, settings.processSort == .cpu ? 25 : 1))
                }
            }

            HStack {
                Text("\(monitor.totalCount) processes")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    Label("Activity Monitor", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.colors[1])
            }
        }
    }
}

/// Capsule segmented control with a sliding thumb.
private struct GlowSegmentedControl: View {
    @Binding var selection: ProcessSort
    let colors: [Color]
    let selectedText: Color
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProcessSort.allCases) { option in
                let selected = option == selection
                Text(option.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? selectedText : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if selected {
                            Capsule()
                                .fill(colors[1])
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selection = option }
                    }
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
}

private struct ProcessRow: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(ProcessMonitor.self) private var monitor
    let entry: ProcessEntry
    let maxValue: Double
    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        let sortByCPU = settings.processSort == .cpu
        let primary = sortByCPU ? String(format: "%.1f%%", entry.cpu) : formatBytes(entry.memory)
        let secondary = sortByCPU ? formatBytes(entry.memory) : String(format: "%.1f%%", entry.cpu)
        let fraction = (sortByCPU ? entry.cpu : Double(entry.memory)) / maxValue

        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(monitor.displayName(for: entry))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(secondary)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Text(primary)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                }
                ProgressCapsule(value: fraction, colors: settings.colors, height: 4)
            }
            if settings.allowQuit, hovering || confirming {
                quitButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contextMenu {
            Text("\(monitor.displayName(for: entry)) — PID \(entry.pid)")
            Divider()
            Button("Quit") { monitor.terminate(entry, force: false) }
            Button("Force Quit") { monitor.terminate(entry, force: true) }
            Divider()
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(entry.pid)", forType: .string)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = monitor.icon(for: entry) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    @ViewBuilder
    private var quitButton: some View {
        if confirming {
            Button {
                monitor.terminate(entry, force: false)
                confirming = false
            } label: {
                Text("Quit")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xFF375F).gradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .task {
                try? await Task.sleep(for: .seconds(3))
                confirming = false
            }
        } else {
            Button { confirming = true } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Quit \(monitor.displayName(for: entry))")
        }
    }
}
