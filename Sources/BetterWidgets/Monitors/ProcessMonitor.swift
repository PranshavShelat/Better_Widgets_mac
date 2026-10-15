import AppKit
import Darwin
import Observation

struct ProcessEntry: Identifiable, Sendable, Equatable {
    let pid: pid_t
    let name: String
    /// Percent of one core (100 = one full core), like Activity Monitor.
    let cpu: Double
    /// Physical footprint in bytes, like Activity Monitor's "Memory" column.
    let memory: UInt64
    var id: pid_t { pid }
}

struct ProcessSnapshot: Sendable {
    var entries: [ProcessEntry] = []
    var total = 0
}

/// Samples per-process CPU time and memory via libproc. Without root, only the current
/// user's processes are readable, which are also the ones the user can quit.
final class ProcessSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: [pid_t: UInt64] = [:]
    private var lastTime: UInt64 = 0
    private var names: [pid_t: String] = [:]
    private let numer: UInt64
    private let denom: UInt64

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        numer = UInt64(timebase.numer)
        denom = UInt64(max(timebase.denom, 1))
    }

    func sample(limit: Int) -> ProcessSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsed = lastTime == 0 ? 0 : now &- lastTime
        lastTime = now

        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return ProcessSnapshot() }

        var rows: [(pid: pid_t, cpu: Double, memory: UInt64)] = []
        var next: [pid_t: UInt64] = [:]
        rows.reserveCapacity(count)

        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }

            // ri_*_time are in Mach absolute time units (ticks on Apple silicon).
            let cpuNanos = (info.ri_user_time &+ info.ri_system_time) * numer / denom
            next[pid] = cpuNanos
            var cpu = 0.0
            if elapsed > 0, let old = previous[pid], cpuNanos >= old {
                cpu = Double(cpuNanos - old) / Double(elapsed) * 100
            }
            rows.append((pid, cpu, info.ri_phys_footprint))
        }
        previous = next
        names = names.filter { next[$0.key] != nil }

        let topCPU = rows.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let topMemory = rows.sorted { $0.memory > $1.memory }.prefix(limit)
        var seen = Set<pid_t>()
        var entries: [ProcessEntry] = []
        for row in topCPU + topMemory where seen.insert(row.pid).inserted {
            entries.append(ProcessEntry(pid: row.pid, name: name(for: row.pid), cpu: row.cpu, memory: row.memory))
        }
        return ProcessSnapshot(entries: entries, total: count)
    }

    private func name(for pid: pid_t) -> String {
        if let cached = names[pid] { return cached }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        var name = String(cString: buffer)
        if name.isEmpty {
            var path = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
                name = URL(fileURLWithPath: String(cString: path)).lastPathComponent
            }
        }
        if name.isEmpty { name = "pid \(pid)" }
        names[pid] = name
        return name
    }
}

@Observable
@MainActor
final class ProcessMonitor {
    var entries: [ProcessEntry] = []
    var totalCount = 0

    @ObservationIgnored weak var settings: WidgetSettings?
    /// Lowercased name fragments to hide from the list (used for screenshots).
    @ObservationIgnored var excludedNames: [String] = []
    @ObservationIgnored private let sampler = ProcessSampler()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var appInfo: [pid_t: (name: String?, icon: NSImage?)] = [:]

    func start(interval: TimeInterval) {
        timer?.invalidate()
        tick()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func top(by sort: ProcessSort, count: Int) -> [ProcessEntry] {
        let sorted = switch sort {
        case .cpu: entries.sorted { $0.cpu > $1.cpu }
        case .memory: entries.sorted { $0.memory > $1.memory }
        }
        return Array(sorted.prefix(count))
    }

    func displayName(for entry: ProcessEntry) -> String {
        info(for: entry.pid).name ?? entry.name
    }

    func icon(for entry: ProcessEntry) -> NSImage? {
        info(for: entry.pid).icon
    }

    @discardableResult
    func terminate(_ entry: ProcessEntry, force: Bool) -> Bool {
        if let app = NSRunningApplication(processIdentifier: entry.pid) {
            return force ? app.forceTerminate() : app.terminate()
        }
        return kill(entry.pid, force ? SIGKILL : SIGTERM) == 0
    }

    private func info(for pid: pid_t) -> (name: String?, icon: NSImage?) {
        if let cached = appInfo[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        let value = (name: app?.localizedName, icon: app?.icon)
        appInfo[pid] = value
        return value
    }

    private func tick() {
        guard !busy, settings?.isEnabled(.processes) ?? true else { return }
        busy = true
        let sampler = sampler
        Task.detached(priority: .utility) {
            let snapshot = sampler.sample(limit: 30)
            await MainActor.run {
                self.busy = false
                self.entries = snapshot.entries.filter { entry in
                    !self.excludedNames.contains { entry.name.lowercased().contains($0) }
                }
                self.totalCount = snapshot.total
                let live = Set(snapshot.entries.map(\.pid))
                self.appInfo = self.appInfo.filter { live.contains($0.key) }
            }
        }
    }
}
