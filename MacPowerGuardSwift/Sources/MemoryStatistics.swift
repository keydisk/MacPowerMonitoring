import Foundation
import Darwin

struct MemoryStatistics {
    let usedBytes: Double
    let totalBytes: Double
    let swapUsedBytes: Double?
    var usagePercent: Double { usedBytes / totalBytes * 100 }

    static func read() -> MemoryStatistics? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else { return nil }
        // Exclude reclaimable file-backed and purgeable pages from resident app memory.
        let resident = max(0, Double(info.active_count) + Double(info.inactive_count)
                           - Double(info.external_page_count) - Double(info.purgeable_count))
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let used = min(total, (resident + Double(info.wire_count) + Double(info.compressor_page_count)) * Double(pageSize))
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        return MemoryStatistics(usedBytes: used, totalBytes: total,
                                swapUsedBytes: swapResult == 0 ? Double(swap.xsu_used) : nil)
    }
}
