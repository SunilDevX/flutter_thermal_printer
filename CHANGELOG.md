## 2.2.1

* Added Swift Package Manager support for iOS and macOS, so Flutter apps can use the plugin through the newer Apple package flow.
* Kept CocoaPods support in place for projects that have not moved fully to Swift Package Manager yet.
* Moved the iOS and macOS Swift sources into the package layout expected by Swift Package Manager.
* Updated the iOS minimum version to 13.1 to match the current `universal_ble` requirement.
* Updated dependency versions, including `universal_ble`, `image`, and `win32`.
* Fixed the Windows raw-printing helpers so they compile cleanly with the latest `win32` API.

## 2.0.1

* Fixed BLE discovery to also include system-connected devices using `getSystemDevices()`.
* Fixed BLE reconnect behavior so connection state updates correctly when reconnecting from system Bluetooth settings.
* Added BLE connection-state synchronization and listener management to keep `devicesStream` in sync after disconnect/reconnect cycles.
* Updated BLE scan initialization to honor Android fine-location permission settings through platform scan config.

## 2.0.0

* **Major Refactoring & Code Quality Improvements**
  - Fixed all linting and static analysis issues across the project.
  - Improved null safety and type safety in `Printer` and `PrinterManager`.
  - Refactored `Printer` class to correctly handle name overrides and data sanitization.
  - Fixed Windows stub implementation for better cross-platform compatibility.

* **Documentation**
  - Added comprehensive DartDoc comments for all public methods in `FlutterThermalPrinter` and `PrinterManager`.
  - Documented all parameters including `chunkSize`, `connectionStabilizationDelay`, and others.

* **Testing**
  - Fixed and updated unit tests to ensure reliability Thanks to `@LosDanieloss`.
  - Verified behavior of `Printer` class serialization and initialization.

## 1.2.4
* For windows and macos no chunking is required

## 1.2.3+1
* Updated BLE MTU query or pass custom chunksize

## 1.2.3
* Added Full Support for USB on Macos
* Changed Flutter_blue_plus to universal_ble for better support of BLE and Classic Devices

## 1.2.2 - Optimized Version

* **Enhanced Memory Management**
  - Proper stream lifecycle management with automatic cleanup
  - Improved resource disposal in disconnect operations
  - Optimized singleton pattern for thread safety
  - Better garbage collection patterns

* **Image Processing Improvements**
  - Dynamic chunked image processing for better memory efficiency
  - Improved image validation with comprehensive error handling
  - Optimized image resizing algorithms
  - Better support for varying image dimensions

* **Network Printer Enhancements**
  - Automatic connection validation and reconnection
  - Improved socket error handling with specific exception types
  - Better connection state management
  - Enhanced timeout handling

* **Code Architecture Improvements**
  - Immutable Printer model with validation methods
  - Separated concerns into focused, testable methods
  - Enhanced error handling with meaningful messages
  - Comprehensive documentation and type safety

* **Platform-Specific Optimizations**
  - Windows: Enhanced BLE initialization with proper error handling
  - Android/iOS: Optimized BLE scanning with better subscription management
  - All Platforms: Improved USB printer detection and management

* **New Features**
  - `copyWith()` method for immutable Printer updates
  - `uniqueId` property for better printer identification
  - `hasValidConnectionData` validation method
  - Enhanced connection type validation
  - Comprehensive toString() and equality implementations

* **Breaking Changes**
  - Printer class fields are now final (immutable)
  - Use `copyWith()` for printer updates instead of direct field assignment
  - Some internal method signatures have changed for better error handling

* **Developer Experience**
  - Added OPTIMIZATION_GUIDE.md with detailed optimization explanations
  - Enhanced analysis_options.yaml with strict linting rules
  - Improved error messages for better debugging
  - Better type safety throughout the codebase

## 1.2.1
* Fixed the issue of Flutter Blue plus for windows as it not supported for windows
* Github repo for issues is now changed

## 1.2.0
* Fixed BLE turn on exception for ios and macos by `@eduardohr-muniz`
* Reduced time to print image on ble devices by `@eduardohr-muniz`

## 1.1.0
* Added Improvments for windows Printing Thanks to `@eduardohr-muniz`
* Updated Dependents Packages

## 1.0.1
* Updated ReadMe

## 1.0.0
* New Feature Network Printers added 
* Thanks to `@eduardohr-muniz`

## 0.0.20
* Bugs fixed for usb printers

## 0.0.19+2
* Bugs fixed for usb printers

## 0.0.19+1
* Bugs Fixes

## 0.0.19
* Refracted code and fixed bugs

## 0.0.18+1
* Update some bugs

## 0.0.18
* Added `turnOnBluetooth` function
* Added `isBleTurnedOnStream` Stream of bluetooth is turned on or off
* Added `isBleTurnedOn` function
* Added `printWidget` function for printing any flutter widget
* Updated USB Connection for Android
* Updated BLE for All Platforms

## 0.0.17
* Fixed get system devices in ble

## 0.0.16
* Bumped packages dependent on like flutter_blue_plus,win32,flutter_utils_plus

## 0.0.15
* Added new extension for Printer of connectionsState
* Now you can get system connected devices on macos

## 0.0.14
* Fixed flickering of bt devices
* Added some improvements

## 0.0.13
* Removed unused library flutterlib_serialport
* Updated some dependencies

## 0.0.12
* Some Bugs Fixed in MacOs

## 0.0.11
* Some Bugs Fixed in MacOs

## 0.0.10
* Some Bugs Fixed in MacOs

## 0.0.9
* Added Getting USB Devices for MacOs

## 0.0.8
* Updated Bluetooth Services Package

## 0.0.7
* Removed test printing from the example

## 0.0.6
* Added USB Printing for Windows Devices
* Read Take Care Of part at below in Readme for More.

## 0.0.5
* Added esc_pos_utils_plus for printing 

## 0.0.4
* Added getPrinter() to get the printers from both USB and Bluetooth

## 0.0.3
* Added USB Printer Support for Android 

## 0.0.2

* Added Support for Windows Bluetooth
* Added Start and Stop Scanning for BLE devices
* Added Connect and Disconnect Printer
* Added Printer Model Class
* Added `longdata` to print data for long text

## 0.0.1

* Initial release
