import SwiftUI

/// Transparent margin around each card in its window, for the edit-mode buttons and shadows.
let cardWindowPadding: CGFloat = 30

/// The card view for a module, without any window chrome.
struct WidgetCard: View {
    let module: WidgetModule

    var body: some View {
        switch module {
        case .clock: ClockCard()
        case .date: DateCard()
        case .weather: WeatherCard()
        case .cpu: CPUCard()
        case .memory: MemoryCard()
        case .disk: DiskCard()
        case .processes: ProcessCard()
        }
    }
}

/// Root view of one card's window: click to open, drag, resize and edit-mode controls.
struct CardHost: View {
    @Environment(WidgetSettings.self) private var settings
    let module: WidgetModule
    @State private var hovering = false
    @State private var resizeStart: Double?

    var body: some View {
        let editing = settings.editMode
        let scale = settings.scale(for: module)
        let radius = settings.cornerRadius * scale
        ScaledLayout(scale: scale) {
            WidgetCard(module: module)
                .frame(width: settings.cardWidth)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onTapGesture {
            if !editing && module.canOpen { module.open() }
        }
        .help(editing ? "" : module.openActionTitle ?? "")
        .overlay {
            if editing {
                RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: settings.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if editing {
                Button {
                    withAnimation { settings.setEnabled(module, false) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color(hex: 0x3A3A3C), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .offset(x: -9, y: -9)
                .help("Remove \(module.title)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if editing || (hovering && !settings.lockPosition) || resizeStart != nil {
                resizeHandle(scale: scale)
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .padding(cardWindowPadding)
        .fixedSize()
        .gesture(WindowDragGesture(), including: editing || !settings.lockPosition ? .all : .subviews)
        .environment(\.colorScheme, settings.colorScheme ?? .dark)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: editing)
        .contextMenu {
            if let title = module.openActionTitle {
                Button(title) { module.open() }
            }
            Button(editing ? "Done Editing" : "Edit Widgets…") { settings.editMode.toggle() }
            Menu("Size") {
                ForEach([("Small", 0.8), ("Medium", 1.0), ("Large", 1.25), ("Extra Large", 1.5)], id: \.0) { name, value in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { settings.setScale(value, for: module) }
                    } label: {
                        if abs(scale - value) < 0.01 { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            Button("Remove \(module.title)") { settings.setEnabled(module, false) }
            Menu("Arrange") {
                ForEach(ArrangeMode.allCases) { mode in
                    Button(mode.title) { WidgetCommands.arrange(mode) }
                }
            }
            Menu("Theme") {
                ForEach(Theme.allCases) { theme in
                    Button(theme.title) { settings.theme = theme }
                }
            }
            Divider()
            Button("Settings…") { WidgetCommands.openSettings() }
        }
    }
}

extension CardHost {
    /// Corner grip that scales the card. Uses window coordinates, which stay put while the
    /// window grows because the panel keeps its top-left corner fixed.
    private func resizeHandle(scale: Double) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Color(hex: 0x3A3A3C), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .offset(x: 9, y: 9)
            .contentShape(Circle())
            .help("Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = resizeStart ?? scale
                        if resizeStart == nil { resizeStart = scale }
                        let base = settings.cardWidth * start
                        let delta = (drag.translation.width + drag.translation.height) / 2
                        settings.setScale(start * (base + delta) / base, for: module)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }
}

/// Lays out its child at natural size but reports the scaled size, so a child drawn with
/// `.scaleEffect(scale, anchor: .topLeading)` fills exactly that space.
struct ScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let natural = child.sizeThatFits(.unspecified)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(child.sizeThatFits(.unspecified)))
    }
}

/// Bar shown in edit mode: add hidden cards, auto-arrange, finish editing.
struct EditToolbar: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        let hidden = WidgetModule.allCases.filter { !settings.isEnabled($0) }
        VStack(spacing: 8) {
            if let notice = settings.arrangeNotice {
                Label(notice, systemImage: "rectangle.dashed")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if hidden.isEmpty {
                    Label("Drag cards anywhere", systemImage: "hand.draw")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    ForEach(hidden) { module in
                        Button {
                            withAnimation { settings.setEnabled(module, true) }
                        } label: {
                            Label(module.title, systemImage: "plus")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().frame(height: 20)

                Text("Arrange")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                ForEach(ArrangeMode.allCases) { mode in
                    Button { WidgetCommands.arrange(mode) } label: {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 24)
                            .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Arrange as \(mode.title.lowercased())")
                }

                Divider().frame(height: 20)

                Button {
                    settings.editMode = false
                    settings.arrangeNotice = nil
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(settings.theme.accentForeground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(settings.colors[1], in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(ToolbarBackground(shape: settings.arrangeNotice == nil
                                    ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))))
        .padding(20)
        .fixedSize()
        .environment(\.colorScheme, settings.colorScheme ?? .dark)
    }
}

private struct ToolbarBackground: ViewModifier {
    let shape: AnyShape

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
        }
    }
}
