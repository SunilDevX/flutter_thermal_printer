# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests
flutter test

# Run a single test file
flutter test test/unit/printer_test.dart

# Run tests with coverage
flutter test --coverage

# Analyze code (strict linting)
flutter analyze

# Run the example app
cd example && flutter run

# Run integration tests
cd example && flutter test integration_test/plugin_integration_test.dart
```

## Architecture

This is a Flutter **plugin** (not an app), published to pub.dev as `flutter_thermal_printer`. It supports printing via BLE, USB, and WiFi/Network across Android, iOS, macOS, and Windows.

### Layer structure

```
FlutterThermalPrinter (singleton facade)       lib/flutter_thermal_printer.dart
    └── PrinterManager (singleton, all logic)  lib/printer_manager.dart
            ├── UniversalBle (BLE on all platforms)
            ├── FlutterThermalPrinterPlatform  lib/flutter_thermal_printer_platform_interface.dart
            │       └── MethodChannelFlutterThermalPrinter  lib/flutter_thermal_printer_method_channel.dart
            │               └── native plugins (Android/iOS/macOS: USB only)
            └── Windows-specific USB (Win32 API)  lib/Windows/
```

**`FlutterThermalPrinter`** is the public API — consumers only touch this class. It delegates everything to `PrinterManager`.

**`PrinterManager`** owns all state: the `_devices` list, subscriptions, and connection tracking. It has three code paths per operation:
1. **Windows USB** — uses `win32` FFI directly (`PrinterNames`, `RawPrinter`)
2. **Non-Windows USB** — delegates to `FlutterThermalPrinterPlatform` (method channel to native code)
3. **BLE** — uses `universal_ble` package on all platforms

**`FlutterThermalPrinterPlatform`** / `MethodChannelFlutterThermalPrinter` bridge to native Android/iOS/macOS for USB operations only.

### Key types

- **`Printer`** (`lib/utils/printer.dart`) — extends `BleDevice` from `universal_ble`; carries `address`, `name`, `connectionType`, `isConnected`, `vendorId`, `productId`
- **`ConnectionType`** enum — `BLE`, `USB`, `NETWORK`
- **`BleConfig`** (`lib/utils/ble_config.dart`) — controls `connectionStabilizationDelay` (default 10s); configurable globally or per-connect call
- **`FlutterThermalPrinterNetwork`** (`lib/network/network_printer.dart`) — standalone TCP socket client for WiFi printing on port 9100; used independently of `PrinterManager`

### Platform-conditional imports

`lib/Windows/windows_platform.dart` is imported conditionally:
```dart
import 'Windows/windows_platform.dart'
    if (dart.library.html) 'Windows/windows_stub.dart';
```
The stub avoids `win32`/`ffi` symbols on non-Windows. Any Win32-specific code must stay inside the `Windows/` directory.

### Image printing pipeline

`FlutterThermalPrinter.printWidget` / `screenShotWidget`:
1. Capture widget via `screenshot` package
2. Resize width to multiple of 8 (thermal printer constraint)
3. Convert to grayscale
4. Slice into 30-pixel-tall strips (chunked rasterization for memory)
5. Generate ESC/POS raster bytes via `esc_pos_utils_plus`
6. For macOS/Windows USB: send full raster at once; for BLE/other: send each chunk via `printData`

BLE data is sent in MTU-sized chunks: Windows uses fixed 50 bytes, macOS requests 150, others request 500 (actual chunk = MTU − 3).

### BLE connection flow

`PrinterManager` maintains per-device `StreamSubscription<bool>` in `_bleConnectionSubscriptions`. On `getPrinters()`:
- Syncs already-connected system devices (`UniversalBle.getSystemDevices()`)
- Starts scan via `UniversalBle.startScan()`
- Runs a 3-second periodic timer (`_bleStateSyncTimer`) to poll connection state

### `devicesStream` behavior

`_devices` is a mutable `List<Printer>` deduplicated by `vendorId_address`. Every mutation calls `sortDevices()` which removes nameless devices, deduplicates, and pushes to the broadcast `StreamController`.

## Linting

The project uses a very strict `analysis_options.yaml` (based on `flutter_lints`). Notable enforced rules:
- `prefer_single_quotes`
- `require_trailing_commas`
- `always_declare_return_types`
- `avoid_print` — use `dart:developer`'s `log()` instead
- `unawaited_futures` — must wrap fire-and-forget calls with `unawaited()`
- `implicit-casts: false` and `implicit-dynamic: false`

## Testing

Tests live in `test/unit/`. Mock the platform interface via `MockPlatformInterfaceMixin` (see `test/flutter_thermal_printer_test.dart`). `PrinterManager` is a singleton — reset state between tests if needed. The `test/mocks/` directory contains reusable mock implementations.
