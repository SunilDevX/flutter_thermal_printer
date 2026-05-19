import Cocoa
import FlutterMacOS
import IOUSBHost
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib
import Foundation
import CoreFoundation
import AppKit
import ApplicationServices

public class FlutterThermalPrinterPlugin: NSObject, FlutterPlugin  , FlutterStreamHandler{
    
    private var eventSink: FlutterEventSink?
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events;
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_thermal_printer", binaryMessenger: registrar.messenger)
        let instance = FlutterThermalPrinterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        let eventChannel =  FlutterEventChannel(name: "flutter_thermal_printer/events", binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "getUsbDevicesList":
            result(getAllPrinters()) // Changed from getAllUsbDevice() to getAllPrinters()
        case "connect":
            let args = call.arguments as? [String: Any]
            let printerName = args?["name"] as? String // Using vendorId field to pass printer name for compatibility
            let printerId = args?["productId"] as? String // Using productId field to pass printer ID for compatibility
            result(connectPrinter(printerName: printerName!, printerId: printerId!))
        case "printText":
            let args = call.arguments as? [String: Any]
            let printerName = args?["name"] as? String ?? ""
            let printerId = args?["productId"] as? String ?? ""
            let data = args?["data"] as? Array<Int> ??  []
            let path = args?["path"] as? String ?? ""
            let success = printData(printerName: printerName, printerId: printerId, data: data, path: path)
            result(success)
        case "isConnected":
            let args = call.arguments as? [String: Any]
            let printerName = args?["name"] as? String ?? ""
            let printerId = args?["productId"] as? String ?? ""
            result(connectPrinter(printerName: printerName, printerId: printerId))
        case "disconnect":
            let args = call.arguments as? [String: Any]
            let printerName = args?["vendorId"] as? String ?? ""
            let printerId = args?["productId"] as? String ?? ""
            result(disconnectPrinter(printerName: printerName, printerId: printerId))
        case "convertimage":
            let args = call.arguments as? [String: Any]
            let imageData = args?["path"] as? Array<Int> ?? []
            result(imageData)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - New Printer-based Implementation
    
    public func getAllPrinters() -> [[String:Any]] {
        var printers: [[String:Any]] = []
        
        // Get all available printers using NSPrinter
        let availablePrinters = NSPrinter.printerNames
        
        for (index, printerName) in availablePrinters.enumerated() {
            if let printer = NSPrinter(name: printerName) {
                // Create a printer device with same format as USB device
                let printerDevice = PrinterDevice(
                    id: UInt64(index), // Use index as unique ID
                    vendorId: UInt16(hashString(printerName) % 65535), // Generate vendorId from printer name hash
                    productId: UInt16((index + 1) * 1000), // Generate unique productId
                    name: printerName,
                    locationId: UInt32(index + 1000), // Generate locationId
                    vendorName: printer.name, // Use printer type as vendor name
                    serialNr: nil // Printers typically don't expose serial numbers via NSPrinter,
                    
                )
                printers.append(printerDevice.toDictionary())
            }
        }
        
        return printers
    }
    
    // Helper function to generate consistent hash from string
    private func hashString(_ string: String) -> Int {
        var hash = 0
        for char in string.utf8 {
            hash = hash &* 31 &+ Int(char)
        }
        return abs(hash)
    }
    
    // MARK: - Printer Connection and Printing Methods
    
    public func connectPrinter(printerName: String, printerId: String) -> Bool {
        // Check if printer exists and is available 
        let availablePrinters = NSPrinter.printerNames
        let isConnected = availablePrinters.contains(printerName)
        return isConnected
    }
    
    public func disconnectPrinter(printerName: String, printerId: String) -> Bool {
        // For printers, there's no persistent connection to disconnect
        print("Disconnect called for Printer: \(printerName), ID: \(printerId)")
        return true
    }
    
    public func printData(printerName: String, printerId: String, data: Array<Int>, path: String) -> Bool {
        guard let printer = NSPrinter(name: printerName) else {
            print("Printer not found: \(printerName)")
            return false
        }
        
        // Convert Int array to Data
        let dataArray = data.map { UInt8($0 & 0xFF) }
        let printData = Data(dataArray)
        
        return sendDataToPrinter(printer: printer, data: printData)
    }
    
    private func sendDataToPrinter(printer: NSPrinter, data: Data) -> Bool {
        // Create print operation
        let printInfo = NSPrintInfo()
        printInfo.printer = printer
        printInfo.paperSize = NSMakeSize(288, 3276) // 80mm thermal paper width (288 points), flexible height
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.orientation = .portrait
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        
        // For thermal printers, we'll try multiple approaches to send raw data
        return printRawDataWithMultipleMethods(printer: printer, data: data)
    }
    
    private func printRawDataWithMultipleMethods(printer: NSPrinter, data: Data) -> Bool {
        print("Attempting to print \(data.count) bytes to printer: \(printer.name)")
        
        // Use only CUPS method for printing
        if let success = tryPrintWithCups(printer: printer, data: data) {
            print("Successfully printed using CUPS method")
            return success
        }
        
        print("CUPS printing method failed for printer: \(printer.name)")
        return false
    }
    
    
    
    private func tryPrintWithLpr(printer: NSPrinter, data: Data) -> Bool? {
        do {
            // Create a temporary file with the print data
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thermal_print_\(UUID().uuidString).bin")
            try data.write(to: tempURL)
            
            defer {
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            // Try multiple lpr paths and check availability
            let lprPaths = ["/usr/bin/lpr", "/bin/lpr", "/usr/local/bin/lpr"]
            
            for lprPath in lprPaths {
                if FileManager.default.fileExists(atPath: lprPath) {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: lprPath)
                    process.arguments = ["-P", printer.name, "-o", "raw", tempURL.path]
                    
                    // Capture both standard output and error for better debugging
                    let errorPipe = Pipe()
                    let outputPipe = Pipe()
                    process.standardError = errorPipe
                    process.standardOutput = outputPipe
                    
                    do {
                        try process.run()
                        process.waitUntilExit()
                        
                        // Read output and error for debugging
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? ""
                        let outputString = String(data: outputData, encoding: .utf8) ?? ""
                        
                        if process.terminationStatus == 0 {
                            print("Successfully sent \(data.count) bytes to printer: \(printer.name) using \(lprPath)")
                            if !outputString.isEmpty {
                                print("lpr output: \(outputString)")
                            }
                            return true
                        } else {
                            print("Failed to print using \(lprPath) on printer: \(printer.name), exit code: \(process.terminationStatus)")
                            if !errorString.isEmpty {
                                print("lpr error: \(errorString)")
                            }
                            if !outputString.isEmpty {
                                print("lpr output: \(outputString)")
                            }
                        }
                    } catch {
                        print("Error executing \(lprPath): \(error)")
                        // Check if it's a sandbox restriction
                        if (error as NSError).code == 1 || (error as NSError).domain.contains("NSPOSIXErrorDomain") {
                            print("This might be a sandbox restriction. Trying alternative methods...")
                        }
                    }
                }
            }
            
            return false
        } catch {
            print("Error in tryPrintWithLpr: \(error)")
            return nil
        }
    }
    
    private func tryPrintWithCups(printer: NSPrinter, data: Data) -> Bool? {
        do {
            // Create a temporary file with the print data
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("thermal_print_\(UUID().uuidString).bin")
            try data.write(to: tempURL)
            
            defer {
                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            // Try using CUPS lp command with multiple possible paths
            let lpPaths = ["/usr/bin/lp", "/bin/lp", "/usr/local/bin/lp"]
            
            for lpPath in lpPaths {
                if FileManager.default.fileExists(atPath: lpPath) {
                    print("Found lp command at: \(lpPath)")
                    
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: lpPath)
                    
                    // Use comprehensive CUPS options for thermal printing
                    process.arguments = [
                        "-d", printer.name.replacingOccurrences(of: " ", with: "_"),           // Destination printer
                        "-o", "raw",                  // Send raw data without processing
                        "-o", "fit-to-page",          // Fit content to page
                        "-o", "media=Custom.80x200mm", // Set paper size for thermal printers
                        "-o", "page-top=0",           // No top margin
                        "-o", "page-bottom=0",        // No bottom margin
                        "-o", "page-left=0",          // No left margin
                        "-o", "page-right=0",         // No right margin
                        tempURL.path                  // File to print
                    ]
                    
                    // Capture both standard output and error for debugging
                    let errorPipe = Pipe()
                    let outputPipe = Pipe()
                    process.standardError = errorPipe
                    process.standardOutput = outputPipe
                    
                    do {
                        print("Executing: \(lpPath) \(process.arguments?.joined(separator: " ") ?? "")")
                        try process.run()
                        process.waitUntilExit()
                        
                        // Read output and error for debugging
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? ""
                        let outputString = String(data: outputData, encoding: .utf8) ?? ""
                        
                        if process.terminationStatus == 0 {
                            print("Successfully sent \(data.count) bytes to printer: \(printer.name) using \(lpPath)")
                            if !outputString.isEmpty {
                                print("CUPS output: \(outputString)")
                            }
                            return true
                        } else {
                            print("Failed to print using \(lpPath) on printer: \(printer.name), exit code: \(process.terminationStatus)")
                            if !errorString.isEmpty {
                                print("CUPS error: \(errorString)")
                            }
                            if !outputString.isEmpty {
                                print("CUPS output: \(outputString)")
                            }
                            
                            // Try with simpler arguments if the first attempt failed
                            return trySimpleCupsCommand(lpPath: lpPath, printer: printer, tempURL: tempURL, data: data)
                        }
                    } catch {
                        print("Error executing \(lpPath): \(error)")
                        // Check if it's a sandbox restriction
                        if (error as NSError).code == 1 || (error as NSError).domain.contains("NSPOSIXErrorDomain") {
                            print("This might be a sandbox restriction. Error details: \(error)")
                        }
                    }
                }
            }
            
            return false
        } catch {
            print("Error in tryPrintWithCups: \(error)")
            return nil
        }
    }
    
    private func trySimpleCupsCommand(lpPath: String, printer: NSPrinter, tempURL: URL, data: Data) -> Bool {
        print("Trying simplified CUPS command...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lpPath)
        
        // Use minimal arguments for compatibility
        process.arguments = ["-d", printer.name, "-o", "raw", tempURL.path]
        
        let errorPipe = Pipe()
        let outputPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = outputPipe
        
        do {
            print("Executing simplified: \(lpPath) \(process.arguments?.joined(separator: " ") ?? "")")
            try process.run()
            process.waitUntilExit()
            
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 {
                print("Successfully sent \(data.count) bytes to printer: \(printer.name) using simplified CUPS command")
                if !outputString.isEmpty {
                    print("CUPS output: \(outputString)")
                }
                return true
            } else {
                print("Simplified CUPS command also failed, exit code: \(process.terminationStatus)")
                if !errorString.isEmpty {
                    print("CUPS error: \(errorString)")
                }
                if !outputString.isEmpty {
                    print("CUPS output: \(outputString)")
                }
                return false
            }
        } catch {
            print("Error executing simplified CUPS command: \(error)")
            return false
        }
    }
    
    private func tryPrintWithNSPrintOperation(printer: NSPrinter, data: Data) -> Bool? {
        // Convert raw data to a string representation for NSPrintOperation
        // This method is less ideal for thermal printers but serves as a fallback
        
        // Create print info
        let printInfo = NSPrintInfo()
        printInfo.printer = printer
        printInfo.paperSize = NSMakeSize(288, 3276) // 80mm thermal paper width
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.orientation = .portrait
        
        // Try to interpret the data as text or create a simple view
        let textView = NSTextView()
        
        // If data appears to be text, use it directly
        if let text = String(data: data, encoding: .utf8) {
            textView.string = text
        } else {
            // For binary data, we'll try to send it as raw bytes converted to a string
            // This is not ideal but may work for some printers
            let hexString = data.map { String(format: "%02x", $0) }.joined(separator: " ")
            textView.string = "Raw data: \(hexString)"
        }
        
        // Create print operation
        let printOperation = NSPrintOperation(view: textView, printInfo: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = false
        
        // Run print operation synchronously
        let success = printOperation.run()
        
        if success {
            print("Successfully printed using NSPrintOperation to printer: \(printer.name)")
        } else {
            print("Failed to print using NSPrintOperation to printer: \(printer.name)")
        }
        
        return success
    }

    // MARK: - Legacy USB Implementation (Commented Out)
    /*
    public func getAllUsbDevice() -> [[String:Any]]{
        var devices: [[String:Any]] = []
        var matchingDict = [String: AnyObject]()
        var iterator: io_iterator_t = 0
            // Create an IOServiceMatching dictionary to match all USB devices
        matchingDict[kIOProviderClassKey as String] = "IOUSBDevice" as AnyObject
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict as CFDictionary, &iterator)
        
       if result != KERN_SUCCESS {
           print("Error: \(result)")
           return []
       }
        var device: io_object_t = IOIteratorNext(iterator)
        while device != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, 0)
            if kr == KERN_SUCCESS, let properties = properties?.takeRetainedValue() as? [String: Any] {
             
                var deviceName = properties[kUSBHostDevicePropertyProductString]
                if deviceName == nil {
                    deviceName = properties[kUSBVendorString]
                }
                let vendorId = properties[kUSBVendorID]
                let productId = properties[kUSBProductID]
                let locationId = properties[kUSBDevicePropertyLocationID]
                let vendorName = properties[kUSBVendorName]
                let serialNo = properties[kUSBSerialNumberString]
                let usbDevice = USBDevice(id: locationId as! UInt64, vendorId: vendorId as! UInt16, productId: productId as! UInt16, name: deviceName as! String, locationId: locationId as! UInt32, vendorName: vendorName as? String, serialNr: serialNo as? String)
                devices.append(usbDevice.toDictionary())
            } else {
                print("Error getting properties for device: \(kr)")
            }
             
            IOObjectRelease(device)
            device = IOIteratorNext(iterator)
        }
        return devices
    }
         
    public func connectPrinter(vendorID: String, productID: String)-> Bool{
         return findPrinter(vendorId: Int(vendorID)!, productId: Int(productID)!) != nil
    }
    
    public func disconnectPrinter(vendorID: String, productID: String) -> Bool {
        // For USB printers, there's no persistent connection to disconnect
        // The connection is established per print job
        print("Disconnect called for Vendor ID: \(vendorID), Product ID: \(productID)")
        return true
    }
    
    func findPrinter(vendorId: Int, productId: Int) -> io_service_t? {
        var iterator: io_iterator_t = 0

        // Create the matching dictionary
        guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) else {
            print("Error creating matching dictionary")
            return nil
        }

        // Set vendorId and productId in the matching dictionary
        let vendorIdNumber = NSNumber(value: vendorId)
        let productIdNumber = NSNumber(value: productId)

        // Set the Vendor ID in the dictionary
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBVendorID as CFString).toOpaque(), Unmanaged.passUnretained(vendorIdNumber).toOpaque())

        // Set the Product ID in the dictionary
        CFDictionarySetValue(matchingDict, Unmanaged.passUnretained(kUSBProductID as CFString).toOpaque(), Unmanaged.passUnretained(productIdNumber).toOpaque())

        // Get the matching services
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
        if result != KERN_SUCCESS {
            print("Error: \(result)")
            return nil
        }
        
        // Get the first matching device
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        return device
    }

    func sendBytesToPrinter(vendorId: Int, productId: Int, data: Data) -> Bool {
        guard let service = findPrinter(vendorId: vendorId, productId: productId) else {
            print("Printer not found with Vendor ID: \(vendorId), Product ID: \(productId)")
            return false
        }
        
        // For now, we'll return true to indicate the method exists and found the printer
        // The actual USB communication would require more complex IOKit implementation
        print("Found printer with Vendor ID: \(vendorId), Product ID: \(productId)")
        print("Data to print: \(data.count) bytes")
        
        // Release the service
        IOObjectRelease(service)
        
        // This is a simplified implementation that indicates success
        // In a real implementation, you would need to handle the USB communication
        return true
    }
    
    public func printData(vendorID: String, productID: String, data: Array<Int>, path: String) -> Bool {
        guard let vendorId = Int(vendorID), let productId = Int(productID) else {
            print("Invalid vendor ID or product ID")
            return false
        }
        
        // Convert Int array to Data with proper byte order
        let dataArray = data.map { UInt8($0 & 0xFF) }
        let printData = Data(dataArray)
        
        return sendBytesToPrinter(vendorId: vendorId, productId: productId, data: printData)
    }
    */
}

// USB Constants and UUIDs - Basic set for device enumeration
public let kIOUSBDeviceUserClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil, 0x9D, 0xA6, 0x9A, 0xAA, 0x2B, 0xD7, 0x11, 0xD4, 0xBA, 0xE8, 0x00, 0x60, 0x97, 0xB2, 0x1F, 0xF0)
public let kIOCFPlugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil, 0xC2, 0x44, 0xE8, 0xE0, 0x54, 0xE6, 0x11, 0xD3, 0xA9, 0x1D, 0x00, 0xC0, 0x4F, 0xC2, 0x91, 0x63)
public let kIOUSBDeviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil, 0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xd4, 0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
