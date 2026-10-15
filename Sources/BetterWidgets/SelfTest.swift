import AppKit

/// `BetterWidgets --selftest [city]` prints one round of every data source, without any UI.
enum SelfTest {
    static func run() {
        print("CPU:", SystemReader.cpuBrand())
        let before = SystemReader.cpuTicks()
        let sampler = ProcessSampler()
        _ = sampler.sample(limit: 5)
        Thread.sleep(forTimeInterval: 1)
        let after = SystemReader.cpuTicks()
        var busy = 0.0, total = 0.0
        for (a, b) in zip(before, after) {
            let used = Double(b.user &- a.user) + Double(b.system &- a.system) + Double(b.nice &- a.nice)
            busy += used
            total += used + Double(b.idle &- a.idle)
        }
        print("  cores: \(after.count), usage: \(formatPercent(total > 0 ? busy / total : 0))")

        let memory = SystemReader.memory()
        print("Memory: \(formatBytes(memory.used)) / \(formatBytes(memory.total)) — app \(formatBytes(memory.app)), wired \(formatBytes(memory.wired)), compressed \(formatBytes(memory.compressed)), cached \(formatBytes(memory.cached)), swap \(formatBytes(memory.swapUsed))")

        for volume in SystemReader.volumes(includeExternal: true) {
            print("Volume: \(volume.name) — \(formatBytes(UInt64(volume.free), style: .file)) free of \(formatBytes(UInt64(volume.total), style: .file))")
        }

        let snapshot = sampler.sample(limit: 5)
        print("Processes: \(snapshot.total) readable")
        for entry in snapshot.entries.sorted(by: { $0.cpu > $1.cpu }).prefix(5) {
            print(String(format: "  %-28@ %6.1f%%  %@", entry.name, entry.cpu, formatBytes(entry.memory)))
        }

        let obstacles = DesktopObstacles.current()
        print("Desktop obstacles: \(DesktopObstacles.desktopWidgets().count) widgets, \(DesktopObstacles.desktopIcons().count) icons (icons need Accessibility: \(AccessibilityPermission.isGranted))")
        if let screen = NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
            let sizes = [CGSize(width: 340, height: 230), CGSize(width: 340, height: 280), CGSize(width: 340, height: 600),
                         CGSize(width: 340, height: 450), CGSize(width: 340, height: 420), CGSize(width: 340, height: 160),
                         CGSize(width: 340, height: 420)]
            let rects = CardLayout.place(sizes: sizes, in: area, obstacles: obstacles, gap: 12, mode: .grid)
            let placed = rects.compactMap { $0 }
            let overlapsObstacle = placed.contains { rect in obstacles.contains { $0.intersects(rect) } }
            let overlapsCard = placed.indices.contains { i in placed.indices.contains { j in i < j && placed[i].intersects(placed[j]) } }
            print("Layout: placed \(placed.count)/\(sizes.count) cards; overlaps obstacle: \(overlapsObstacle); overlaps card: \(overlapsCard)")
        }

        let args = CommandLine.arguments
        let city = args.firstIndex(of: "--selftest").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "London"
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let place = try await WeatherService.geocode(city)
                let forecast = try await WeatherService.forecast(latitude: place.latitude, longitude: place.longitude, unit: .celsius)
                print("Weather: \(place.name) \(forecast.current.temperature)°C, \(WeatherCode.description(forecast.current.code)), \(forecast.daily.time.count) days, \(forecast.hourly.time.count) hours")
            } catch {
                print("Weather error:", error)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
