import Foundation
import Darwin
import BatteryGuardShared

/// User-process, read-only sampler. Reuses the existing status polling loop, at most every ten seconds.
@MainActor
final class SystemDiagnosticsReader {
    private var previousTicks: [UInt64]?
    private var previousUptime: TimeInterval?
    private var lastSnapshot: BGSystemSnapshot?

    func reset() { previousTicks = nil; previousUptime = nil; lastSnapshot = nil }

    func read(now: Date = Date()) -> BGSystemSnapshot {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let previousUptime, uptime - previousUptime < 10, let lastSnapshot { return lastSnapshot }
        previousUptime = uptime
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        func measurement(_ metric: BGMetric, _ value: Double?, _ source: BGMeasurementSource,
                         derived: Bool = false) -> BGMeasurement {
            BGMeasurement(metric, value: value, source: source, sampledAt: now,
                          quality: derived ? .derived : .reported)
        }
        var cpu = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        var cpuValue: Double?
        if cpuResult == KERN_SUCCESS {
            let ticks = [UInt64(cpu.cpu_ticks.0), UInt64(cpu.cpu_ticks.1), UInt64(cpu.cpu_ticks.2), UInt64(cpu.cpu_ticks.3)]
            if let previousTicks { cpuValue = BGResourceMath.cpuLoad(previous: previousTicks, current: ticks) }
            previousTicks = ticks
        } else { previousTicks = nil }

        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let used = vmResult == KERN_SUCCESS && pageResult == KERN_SUCCESS
            ? (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * Double(pageSize) : nil
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        let capacity = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        var modelBytes = [CChar](repeating: 0, count: 64)
        var modelSize = modelBytes.count
        let modelResult = modelBytes.withUnsafeMutableBytes {
            sysctlbyname("hw.model", $0.baseAddress, &modelSize, nil, 0)
        }
        let model = modelResult == 0 ? String(cString: modelBytes) : nil
        let thermal: BGThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        let result = BGSystemSnapshot(sampledAt: now, thermalState: thermal, measurements: BGBatteryMeasurements(values: [
            measurement(.cpuLoad, cpuValue, .machCPU, derived: true),
            measurement(.memoryUsed, used, .machMemory, derived: true),
            measurement(.memoryTotal, Double(ProcessInfo.processInfo.physicalMemory), .machMemory),
            measurement(.swapUsed, swapResult == 0 ? Double(swap.xsu_used) : nil, .swapUsage),
            measurement(.volumeAvailable, capacity?.volumeAvailableCapacity.map(Double.init), .volumeCapacity),
            measurement(.volumeTotal, capacity?.volumeTotalCapacity.map(Double.init), .volumeCapacity)
        ]), modelIdentifier: model)
        lastSnapshot = result
        return result
    }
}
