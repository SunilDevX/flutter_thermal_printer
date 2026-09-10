import AppKit
import ApplicationServices

/// Metadata for installed macOS print queues, independent of their transport.
enum PrinterDiscovery {
    static func metadataByName() -> [String: [String: String]] {
        var unmanagedList: Unmanaged<CFArray>?
        guard PMServerCreatePrinterList(nil, &unmanagedList) == noErr,
              let list = unmanagedList?.takeRetainedValue() else {
            return [:]
        }

        var result: [String: [String: String]] = [:]
        for index in 0..<CFArrayGetCount(list) {
            // PrintCore stores opaque PMPrinter references in this CFArray.
            let printer = unsafeBitCast(CFArrayGetValueAtIndex(list, index), to: PMPrinter.self)
            guard let name = PMPrinterGetName(printer)?.takeUnretainedValue(),
                  let queueName = PMPrinterGetID(printer)?.takeUnretainedValue() else {
                continue
            }
            var metadata = ["queueName": queueName as String]
            var unmanagedURI: Unmanaged<CFURL>?
            if PMPrinterCopyDeviceURI(printer, &unmanagedURI) == noErr,
               let uri = unmanagedURI?.takeRetainedValue() {
                metadata["deviceUri"] = (uri as URL).absoluteString
            }
            result[name as String] = metadata
        }
        return result
    }
}
