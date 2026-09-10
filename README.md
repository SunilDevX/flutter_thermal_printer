# flutter_thermal_printer

<img src="https://res.cloudinary.com/daagzbhsu/image/upload/v1735536729/vxobf0gilq0pixfsnjw1.png" />



## Buy Me A Coffee
If you find this project helpful and want to support its development, you can buy me a coffee:

<a href="https://www.buymeacoffee.com/SunilDevX" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## Getting Started

This plugin is used to print data on thermal printers with ease across multiple platforms.

## 🎉 New Feature: USB Printing Services

> **✨ Exciting Update!** We now support **USB printing services** across multiple platforms! Connect your thermal printers directly via USB for faster, more reliable printing without the need for wireless connections.
> 
> **Supported Platforms for USB:**
> - 🤖 **Android** - Full USB support
> - 🖥️ **Windows** - Complete USB integration  
> - 🍎 **macOS** - Native USB connectivity
> 
> Experience enhanced printing performance with direct USB connections!

## Currently Supported

| Service                        | Android | iOS | macOS | Windows |
| ------------------------------ | :-----: | :-: | :---: | :-----: |
| Bluetooth                      | ✅      | ✅  | ✅    | ✅      |
| USB                            | ✅      |     | ✅    | ✅      |
| BLE                            | ✅      | ✅  | ✅    | ✅      |
| WiFi                           | ✅      | ✅  | ✅    | ✅      |

```dart
final _flutterThermalPrinterPlugin = FlutterThermalPrinter.instance;

// Enum ConnectionType
enum ConnectionType {
  BLE,
  USB,
  NETWORK,
}

// Additional Functions
// Recommended Function for getting printers
getPrinters(
  refreshDuration: Duration,
  connectionTypes: List<ConnectionType>,
) {
  // Supports WINDOWS, ANDROID , Macos for USB
  // MAC, IOS, ANDROID, WINDOWS for BLUETOOTH.
}

// Refer to Example for Complete code 
```

---

## macOS printer connection types

Installed macOS print queues are classified using their native device URI:
`usb://` is USB; `dnssd://`, `ipp://`, `ipps://`, `http://`, `https://`,
`socket://`, `lpd://`, and `smb://` are NETWORK. Unknown or missing schemes
have a null `connectionType` and display as `UNKNOWN`.

```dart
await FlutterThermalPrinter.instance.getPrinters(
  connectionTypes: [ConnectionType.USB, ConnectionType.BLE, ConnectionType.NETWORK],
);
```

The default scan includes all three types. An explicit USB-only scan excludes
network queues; a NETWORK-only scan returns installed network queues on macOS.
Unknown system queues appear when both USB and NETWORK are requested. This does
not discover uninstalled LAN printers or identify thermal/ESC/POS compatibility.

`Printer.deviceUri` preserves the destination URI and `Printer.queueName` holds
the macOS queue ID. System queues continue printing through the native macOS
backend, including `printWidget`; a Bonjour/IPPS URI is not passed to the raw
TCP network printer API. The queue's `isConnected` value still indicates that it
is installed, not that the physical printer is reachable. Other platforms retain
their existing discovery mechanisms.

## Bluetooth Services

| Feature                        | Android | iOS | macOS | Windows |
| ------------------------------ | :-----: | :-: | :---: | :-----: |
| Start scanning                 | ✅      | ✅  | ✅    | ✅      |
| Stop scanning                  | ✅      | ✅  | ✅    | ✅      |
| Connect printer                | ✅      | ✅  | ✅    | ✅      |
| Disconnect printer             | ✅      | ✅  | ✅    | ✅      |
| Print data                     | ✅      | ✅  | ✅    | ✅      |
| Print widget                   | ✅      | ✅  | ✅    | ✅      |

---

## USB Services

| Feature                        | Android | iOS | macOS | Windows |
| ------------------------------ | :-----: | :-: | :---: | :-----: |
| Start scanning                 | ✅      |     | ✅    | ✅      |
| Stop scanning                  | ✅      |     | ✅    | ✅      |
| Connect printer                | ✅      |     | ✅    | ✅      |
| Print data                     | ✅      |     | ✅    | ✅      |
| Print widget                   | ✅      |     | ✅    | ✅      |

---

## WiFi Services

| Feature                        | Android | iOS | macOS | Windows |
| ------------------------------ | :-----: | :-: | :---: | :-----: |
| Connect printer                | ✅      | ✅  | ✅    | ✅      |
| Disconnect printer             | ✅      | ✅  | ✅    | ✅      |
| Print data                     | ✅      | ✅  | ✅    | ✅      |
| Print widget                   | ✅      | ✅  | ✅    | ✅      |

---

## Printer Model Class

```dart
String? address;
String? name;
ConnectionType? connectionType;
bool? isConnected;
String? vendorId;
String? productId;
```

---

## Additional Features

### Screenshot to Printer
Easily capture and print widgets as images using the `printWidget` method.

### Image Cropping for Long Prints
Handles long data by cropping images and printing them in chunks to ensure seamless printing on devices with limited buffer capacity.

### Connection Type Validation
- Ensures `ConnectionType` compatibility and alerts when unsupported combinations are used. 

### BLE State Monitoring
Provides real-time monitoring for Bluetooth states, ensuring proactive error handling and reconnections.

### BLE Connection Configuration
Customize BLE connection behavior to optimize for different printer models:

```dart
// Global configuration (applies to all BLE connections)
FlutterThermalPrinter.instance.bleConfig =
    BleConfig(connectionStabilizationDelay: Duration(seconds: 3));

// Per-connection override for specific devices
await FlutterThermalPrinter.instance.connect(
  printer,
  connectionStabilizationDelay: Duration(seconds: 2),
);

// Default behavior (10 seconds) - no configuration needed
await FlutterThermalPrinter.instance.connect(printer);
```

| Configuration | Use Case |
|---------------|----------|
| Global config | Set once for consistent behavior across all connections |
| Per-call override | Fine-tune for specific printer models that connect faster/slower |
| Default (10s) | Backwards compatible, works with most printers |

---

## Notes and Recommendations

- **Windows & MacOS Users:** Make sure you have the XPrinter driver installed on Windows for printer compatibility.  
  Download the driver from [XPrinter Driver](https://www.xprintertech.com/drivers-2.html).

- **Cross-Platform Usage:** Ensure Bluetooth permissions and configurations are set correctly for Android and iOS.

---

## Contributing Guidelines

We welcome contributions to enhance the plugin's functionality!  
To contribute, please fork the repository, make changes, and submit a pull request.  
For bug reports or feature requests, feel free to open an issue.
 

---

## Contributors

![Contributors](https://contrib.rocks/image?repo=SunilDevX/flutter_thermal_printer)


Feel free to contribute to this project and help make it better for everyone!

---
