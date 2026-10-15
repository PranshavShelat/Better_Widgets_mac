import Foundation
import Darwin
import Observation

struct CoreTicks: Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct MemorySnapshot: Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0

    /// Matches Activity Monitor's "Memory Used".
    var used: UInt64 { app + wired + compressed }
    var free: UInt64 { total > used + cached ? total - used - cached : 0 }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct VolumeInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let total: Int64
    let free: Int64
    let isInternal: Bool
    let isRoot: Bool

    var used: Int64 { max(total - free, 0) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

/// Thin wrappers over Mach / sysctl APIs. Safe to call from any thread.
enum SystemReader {
    static let host = mach_host_self()

    static func cpuTicks() -> [CoreTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            let base = i * stride
            return CoreTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    static func memory() -> MemorySnapshot {
        var snapshot = MemorySnapshot(total: ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return snapshot }

        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)

        let anonymous = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        snapshot.app = (anonymous > purgeable ? anonymous - purgeable : 0) * page
        snapshot.wired = UInt64(stats.wire_count) * page
        snapshot.compressed = UInt64(stats.compressor_page_count) * page
        snapshot.cached = (UInt64(stats.external_page_count) + purgeable) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
        }
        return snapshot
    }

    static func volumes(includeExternal: Bool) -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }

        var result: [VolumeInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isRoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            if !isRoot {
                guard includeExternal,
                      values.volumeIsBrowsable != false,
                      !url.path.hasPrefix("/System/Volumes") else { continue }
            }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            let free = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            result.append(VolumeInfo(
                id: url.path,
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                total: total,
                free: free,
                isInternal: values.volumeIsInternal ?? isRoot,
                isRoot: isRoot
            ))
        }
        return result.sorted { $0.isRoot && !$1.isRoot }
    }

    static func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "CPU" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "CPU" }
        return String(cString: buffer)
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : [0, 0, 0]
    }
}

@Observable
@MainActor
final class SystemMonitor {
    static let historyLength = 60

    var cpuTotal = 0.0
    var cpuUser = 0.0
    var cpuSystem = 0.0
    var coreUsage: [Double] = []
    var cpuHistory: [Double] = []
    var memory = MemorySnapshot()
    var memoryHistory: [Double] = []
    var volumes: [VolumeInfo] = []
    var loadAverage: [Double] = [0, 0, 0]
    var uptime: TimeInterval = 0

    let cpuName = SystemReader.cpuBrand()
    let coreCount = ProcessInfo.processInfo.activeProcessorCount

    @ObservationIgnored weak var settings: WidgetSettings?
    @ObservationIgnored private var previousTicks: [CoreTicks] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastDiskSample = Date.distantPast

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

    func refreshDisks() {
        let includeExternal = settings?.showAllVolumes ?? true
        lastDiskSample = Date()
        Task.detached(priority: .utility) {
            let volumes = SystemReader.volumes(includeExternal: includeExternal)
            await MainActor.run { self.volumes = volumes }
        }
    }

    private func tick() {
        sampleCPU()
        memory = SystemReader.memory()
        append(&memoryHistory, memory.fraction)
        loadAverage = SystemReader.loadAverage()
        uptime = ProcessInfo.processInfo.systemUptime
        if Date().timeIntervalSince(lastDiskSample) > 20 { refreshDisks() }
    }

    private func sampleCPU() {
        let ticks = SystemReader.cpuTicks()
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count, !ticks.isEmpty else { return }

        var user = 0.0, system = 0.0, all = 0.0
        var cores: [Double] = []
        cores.reserveCapacity(ticks.count)
        for (old, new) in zip(previousTicks, ticks) {
            let u = Double(new.user &- old.user) + Double(new.nice &- old.nice)
            let s = Double(new.system &- old.system)
            let i = Double(new.idle &- old.idle)
            let t = u + s + i
            cores.append(t > 0 ? (u + s) / t : 0)
            user += u
            system += s
            all += t
        }
        coreUsage = cores
        cpuUser = all > 0 ? user / all : 0
        cpuSystem = all > 0 ? system / all : 0
        cpuTotal = cpuUser + cpuSystem
        append(&cpuHistory, cpuTotal)
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }
}
