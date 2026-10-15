import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        TabView(selection: $settings.settingsTab) {
            AppearanceTab().tabItem { Label("Appearance", systemImage: "paintpalette") }.tag(SettingsTab.appearance)
            ModulesTab().tabItem { Label("Modules", systemImage: "square.stack.3d.up") }.tag(SettingsTab.modules)
            ClockTab().tabItem { Label("Clock & Date", systemImage: "clock") }.tag(SettingsTab.clock)
            WeatherTab().tabItem { Label("Weather", systemImage: "cloud.sun") }.tag(SettingsTab.weather)
            SystemTab().tabItem { Label("System", systemImage: "cpu") }.tag(SettingsTab.system)
            WindowTab().tabItem { Label("Window", systemImage: "macwindow") }.tag(SettingsTab.window)
        }
        .frame(width: 580, height: 560)
    }
}

private struct AppearanceTab: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                    ForEach(Theme.allCases) { theme in
                        Button { settings.theme = theme } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 38, height: 38)
                                    .overlay {
                                        if settings.theme == theme {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(theme.accentForeground)
                                                .shadow(radius: 2)
                                        }
                                    }
                                Text(theme.title).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Cards") {
                Picker("Material", selection: $settings.cardStyle) {
                    ForEach(CardStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Corner radius") { Slider(value: $settings.cornerRadius, in: 8...36) }
                Toggle("Turn red when usage is above 90%", isOn: $settings.alertColors)
            }
            Section("Layout") {
                LabeledContent("Card width") {
                    HStack {
                        Slider(value: $settings.cardWidth, in: 280...480, step: 10)
                        Text("\(Int(settings.cardWidth)) pt").monospacedDigit().frame(width: 52)
                    }
                }
                LabeledContent("Auto-arrange spacing") { Slider(value: $settings.cardSpacing, in: 0...40) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModulesTab: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(Array(settings.moduleOrder.enumerated()), id: \.element) { index, module in
                    HStack(spacing: 10) {
                        Image(systemName: module.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(settings.theme.accentForeground)
                            .frame(width: 24, height: 24)
                            .background(LinearGradient(colors: settings.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(module.title)
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(index == 0)
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(index == settings.moduleOrder.count - 1)
                        Toggle("", isOn: Binding(
                            get: { settings.isEnabled(module) },
                            set: { settings.setEnabled(module, $0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Show or hide cards. Arrange places them in this order.")
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard settings.moduleOrder.indices.contains(target) else { return }
        withAnimation { settings.moduleOrder.swapAt(index, target) }
    }
}

private struct ClockTab: View {
    @Environment(WidgetSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Time") {
                Picker("Clock style", selection: $settings.clockStyle) {
                    ForEach(ClockStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("24-hour time", isOn: $settings.use24Hour)
                Toggle("Show seconds", isOn: $settings.showSeconds)
                Toggle("Smooth sweeping second hand", isOn: $settings.smoothSeconds)
                    .disabled(!settings.showSeconds || settings.clockStyle == .digital)
            }
            Section("Date") {
                Picker("Format", selection: $settings.dateStyle) {
                    ForEach(DateStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Month calendar", isOn: $settings.showCalendar)
                Toggle("Week & day number", isOn: $settings.showWeekNumber)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WeatherTab: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(WeatherService.self) private var weather
    @State private var query = ""
    @State private var results: [WeatherService.Place] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.useCurrentLocation) {
                    Label("Use my current location", systemImage: "location.fill")
                }
                .onChange(of: settings.useCurrentLocation) { weather.refresh() }

                if !settings.useCurrentLocation {
                    LabeledContent("Selected city") {
                        Text(settings.locationName.isEmpty ? "None" : settings.locationName)
                            .foregroundStyle(settings.locationName.isEmpty ? .secondary : .primary)
                    }
                    TextField("Search", text: $query, prompt: Text("Type a city, e.g. Mumbai or Paris, France"))
                    if searching {
                        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    } else if let searchError {
                        Text(searchError).foregroundStyle(.red).font(.caption)
                    } else if !query.isEmpty && results.isEmpty {
                        Text("No matches").foregroundStyle(.secondary).font(.caption)
                    }
                    ForEach(results) { place in
                        Button { select(place) } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(place.name)
                                    if !place.detail.isEmpty {
                                        Text(place.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if place.name == settings.locationName,
                                   abs(place.latitude - settings.latitude) < 0.01 {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                LabeledContent("Status") {
                    switch weather.status {
                    case .needsCity: Text("Choose a location").foregroundStyle(.secondary)
                    case .loading: ProgressView().controlSize(.small)
                    case .ready:
                        Text("\(weather.locationName) · updated \(weather.updatedAt?.formatted(date: .omitted, time: .shortened) ?? "")")
                            .foregroundStyle(.secondary)
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Weather data by Open-Meteo.com (CC BY 4.0). Only the search text and coordinates are sent. Refreshes every 15 minutes.")
            }
            Section("Display") {
                Picker("Units", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: settings.temperatureUnit) { weather.refresh() }
                Toggle("Hourly forecast graph", isOn: $settings.showHourly)
                Toggle("5-day forecast", isOn: $settings.showDaily)
            }
        }
        .formStyle(.grouped)
        .task(id: query) {
            // Debounced live search.
            let text = query.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { results = []; searchError = nil; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            do {
                let found = try await WeatherService.search(text)
                guard !Task.isCancelled else { return }
                results = Array(found.prefix(8))
                searchError = nil
            } catch {
                if !Task.isCancelled { searchError = error.localizedDescription }
            }
        }
    }

    private func select(_ place: WeatherService.Place) {
        settings.locationName = place.name
        settings.latitude = place.latitude
        settings.longitude = place.longitude
        settings.useCurrentLocation = false
        query = ""
        results = []
        weather.refresh()
    }
}

private struct SystemTab: View {
    @Environment(WidgetSettings.self) private var settings
    @Environment(SystemMonitor.self) private var system

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Sampling") {
                Picker("Refresh every", selection: $settings.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("3 seconds").tag(3.0)
                    Text("5 seconds").tag(5.0)
                }
            }
            Section("CPU & Memory") {
                Toggle("Per-core bars", isOn: $settings.showCoreBars)
                Toggle("CPU history graph", isOn: $settings.showCPUHistory)
                Toggle("Memory history graph", isOn: $settings.showMemoryHistory)
            }
            Section("Storage") {
                Toggle("Include external volumes", isOn: $settings.showAllVolumes)
                    .onChange(of: settings.showAllVolumes) { system.refreshDisks() }
            }
            Section("Task Manager") {
                Stepper("Show \(settings.processCount) processes", value: $settings.processCount, in: 3...15)
                Picker("Sort by", selection: $settings.processSort) {
                    ForEach(ProcessSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Allow quitting processes (hover → ✕ → confirm)", isOn: $settings.allowQuit)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WindowTab: View {
    @Environment(WidgetSettings.self) private var settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Placement") {
                Picker("Level", selection: $settings.windowLevel) {
                    ForEach(WindowLevelMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Lock positions (move only in Edit mode)", isOn: $settings.lockPosition)
                Toggle("Click-through (ignore mouse)", isOn: $settings.clickThrough)
                Toggle("Hide in Mission Control", isOn: $settings.hideInMissionControl)
            }
            Section("Arrange") {
                LabeledContent("Auto-arrange") {
                    HStack {
                        ForEach(ArrangeMode.allCases) { mode in
                            Button { WidgetCommands.arrange(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                        }
                    }
                }
                if !accessibilityGranted {
                    HStack {
                        Text("Allow Accessibility so Arrange can avoid your desktop files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow…") { AccessibilityPermission.request() }
                    }
                }
                Button("Edit Widgets…") { settings.editMode = true }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // Notice when access is granted in System Settings while this tab is open.
            while !Task.isCancelled {
                accessibilityGranted = AccessibilityPermission.isGranted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
