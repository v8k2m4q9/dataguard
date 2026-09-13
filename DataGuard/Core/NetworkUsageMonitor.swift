import Foundation
import Darwin

struct InterfaceSnapshot: Codable, Identifiable, Equatable, Sendable {
    var name: String
    var index: UInt32
    var rx: UInt64?
    var tx: UInt64?
    var addresses: [String] = []
    var id: String { name }
    // A discovery hint only. Apple does NOT guarantee BSD interface names.
    var isCellularCandidate: Bool { name.hasPrefix("pdp_ip") }
    var total: UInt64? {
        guard let rx, let tx else { return nil }
        return rx + tx
    }
}

struct NetworkUsageMonitor {
    static func snapshot() throws -> [InterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { if let head { freeifaddrs(head) } }
        var interfaces: [String: InterfaceSnapshot] = [:]
        var cursor = head
        while let pointer = cursor {
            let item = pointer.pointee
            cursor = item.ifa_next
            guard let cName = item.ifa_name else { continue }
            let name = String(cString: cName)
            var result = interfaces[name] ?? InterfaceSnapshot(name: name, index: if_nametoindex(cName))
            if let address = item.ifa_addr {
                if Int32(address.pointee.sa_family) == AF_LINK, let raw = item.ifa_data {
                    // getifaddrs supplies if_data, NOT if_data64. These counters are UInt32.
                    let counters = raw.assumingMemoryBound(to: if_data.self).pointee
                    result.rx = UInt64(counters.ifi_ibytes)
                    result.tx = UInt64(counters.ifi_obytes)
                } else if [AF_INET, AF_INET6].contains(Int32(address.pointee.sa_family)) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                                   socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        let value = String(decoding: bytes, as: UTF8.self)
                        if !result.addresses.contains(value) { result.addresses.append(value) }
                    }
                }
            }
            interfaces[name] = result
        }
        return interfaces.values.sorted { $0.name < $1.name }
    }
}
