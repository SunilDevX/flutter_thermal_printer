// ignore_for_file: prefer_foreach

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';
import 'Windows/windows_platform.dart'
    if (dart.library.html) 'Windows/windows_stub.dart';

import 'flutter_thermal_printer_platform_interface.dart';
import 'utils/printer.dart';

/// Universal printer manager for all platforms
/// Handles BLE and USB printer discovery and operations using universal_ble for all platforms
/// Removes dependency on win_ble and creates a single manager for all platforms
class PrinterManager {
  PrinterManager._privateConstructor();

  static PrinterManager? _instance;

  // ignore: prefer_constructors_over_static_methods
  static PrinterManager get instance {
    _instance ??= PrinterManager._privateConstructor();
    return _instance!;
  }

  final StreamController<List<Printer>> _devicesStream =
      StreamController<List<Printer>>.broadcast();

  Stream<List<Printer>> get devicesStream => _devicesStream.stream;

  StreamSubscription? _bleSubscription;
  StreamSubscription? _usbSubscription;
  StreamSubscription? _bleAvailabilitySubscription;

  static const String _channelName = 'flutter_thermal_printer/events';
  final EventChannel _eventChannel = const EventChannel(_channelName);

  final List<Printer> _devices = [];

  /// Initialize the manager and check BLE availability
  Future<void> initialize() async {
    try {
      // Check BLE availability
      final isAvailable = await UniversalBle.getBluetoothAvailabilityState();
      log('Bluetooth availability: $isAvailable');

      // Note: Universal BLE may not have real-time availability change streams
      // Users should check availability before scanning
    } catch (e) {
      log('Failed to initialize printer manager: $e');
    }
  }

  /// Optimized stop scanning with better resource cleanup
  Future<void> stopScan({
    bool stopBle = true,
    bool stopUsb = true,
  }) async {
    try {
      if (stopBle) {
        await _bleSubscription?.cancel();
        _bleSubscription = null;
        await UniversalBle.stopScan();
      }
      if (stopUsb) {
        await _usbSubscription?.cancel();
        _usbSubscription = null;
      }
    } catch (e) {
      log('Failed to stop scanning for devices: $e');
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await stopScan();
    await _bleAvailabilitySubscription?.cancel();
    await _devicesStream.close();
  }

  /// Connect to a printer device
  Future<bool> connect(Printer device) async {
    if (device.connectionType == ConnectionType.USB) {
      if (Platform.isWindows) {
        // Windows USB connection - device is already available, no connection needed
        return true;
      } else {
        return FlutterThermalPrinterPlatform.instance.connect(device);
      }
    } else if (device.connectionType == ConnectionType.BLE) {
      try {
        if (device.address == null) {
          log('Device address is null');
          return false;
        }
        final isConnected =
            (await UniversalBle.getConnectionState(device.address!) ==
                BleConnectionState.connected);
        if (isConnected) {
          log('Device ${device.name} is already connected');
          return true;
        }

        log('Connecting to BLE device ${device.name} at ${device.address}');

        // Connect using universal_ble for all platforms including Windows
        await device.connect();

        // Wait a moment to establish connection
        await Future.delayed(const Duration(seconds: 10));
        return (await UniversalBle.getConnectionState(device.address!) ==
            BleConnectionState.connected);
      } catch (e) {
        log('Failed to connect to BLE device: $e');
        return false;
      }
    }
    return false;
  }

  /// Check if a device is connected
  Future<bool> isConnected(Printer device) async {
    if (device.connectionType == ConnectionType.USB) {
      if (Platform.isWindows) {
        // For Windows USB printers, they're always "connected" if they're available
        return true;
      } else {
        return FlutterThermalPrinterPlatform.instance.isConnected(device);
      }
    } else if (device.connectionType == ConnectionType.BLE) {
      try {
        if (device.address == null) {
          return false;
        }
        return device.isConnected ?? false;
      } catch (e) {
        log('Failed to check connection status: $e');
        return false;
      }
    }
    return false;
  }

  /// Disconnect from a printer device
  Future<void> disconnect(Printer device) async {
    if (device.connectionType == ConnectionType.BLE) {
      try {
        if (device.address != null) {
          await device.disconnect();
          log('Disconnected from device ${device.name}');
        }
      } catch (e) {
        log('Failed to disconnect device: $e');
      }
    }
    // USB devices don't need explicit disconnection
  }

  /// Print data to printer device
  Future<void> printData(
    Printer printer,
    List<int> bytes, {
    bool longData = false,
    int? chunkSize,
  }) async {
    if (printer.connectionType == ConnectionType.USB) {
      if (Platform.isWindows) {
        // Windows USB printing using Win32 API
        using((alloc) {
          RawPrinter(printer.name!, alloc).printEscPosWin32(bytes);
        });
        return;
      } else {
        // Non-Windows USB printing
        try {
          await FlutterThermalPrinterPlatform.instance.printText(
            printer,
            Uint8List.fromList(bytes),
            path: printer.address,
          );
        } catch (e) {
          log('FlutterThermalPrinter: Unable to Print Data $e');
        }
      }
    } else if (printer.connectionType == ConnectionType.BLE) {
      try {
        final services = await printer.discoverServices();

        BleCharacteristic? writeCharacteristic;
        for (final service in services) {
          for (final characteristic in service.characteristics) {
            if (characteristic.properties.contains(
              CharacteristicProperty.write,
            )) {
              writeCharacteristic = characteristic;
              break;
            }
          }
        }

        if (writeCharacteristic == null) {
          log('No write characteristic found');
          return;
        }
        final mtu = chunkSize ??
            (Platform.isWindows
                ? 50
                : await printer.requestMtu(Platform.isMacOS ? 150 : 500));
        final maxChunkSize = mtu - 3;

        for (var i = 0; i < bytes.length; i += maxChunkSize) {
          final chunk = bytes.sublist(
            i,
            i + maxChunkSize > bytes.length ? bytes.length : i + maxChunkSize,
          );

          await writeCharacteristic.write(
            Uint8List.fromList(chunk),
          );

          // Small delay between chunks to avoid overwhelming the device
          if (longData) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
        return;
      } catch (e) {
        log('Failed to print data to device $e');
      }
    }
  }

  /// Get Printers from BT and USB
  Future<void> getPrinters({
    Duration refreshDuration = const Duration(seconds: 2),
    List<ConnectionType> connectionTypes = const [
      ConnectionType.BLE,
      ConnectionType.USB,
    ],
    bool androidUsesFineLocation = false,
  }) async {
    if (connectionTypes.isEmpty) {
      throw Exception('No connection type provided');
    }

    if (connectionTypes.contains(ConnectionType.USB)) {
      await _getUSBPrinters(refreshDuration);
    }

    if (connectionTypes.contains(ConnectionType.BLE)) {
      await _getBLEPrinters(androidUsesFineLocation);
    }
  }

  /// USB printer discovery for all platforms
  Future<void> _getUSBPrinters(Duration refreshDuration) async {
    try {
      if (Platform.isWindows) {
        // Windows USB printer discovery using Win32 API
        await _usbSubscription?.cancel();
        _usbSubscription =
            Stream.periodic(refreshDuration, (x) => x).listen((event) async {
          final devices = PrinterNames(PRINTER_ENUM_LOCAL);
          final tempList = <Printer>[];

          for (final printerName in devices.all()) {
            final device = Printer(
              vendorId: printerName,
              productId: 'N/A',
              name: printerName,
              connectionType: ConnectionType.USB,
              address: printerName,
              isConnected: true,
            );
            tempList.add(device);
          }

          // Update devices list and stream
          for (final printer in tempList) {
            _updateOrAddPrinter(printer);
          }
          sortDevices();
        });
      } else {
        // Non-Windows USB printer discovery
        final devices =
            await FlutterThermalPrinterPlatform.instance.startUsbScan();

        final usbPrinters = <Printer>[];
        for (final map in devices) {
          final printer = Printer(
            vendorId: map['vendorId'].toString(),
            productId: map['productId'].toString(),
            name: map['name'],
            connectionType: ConnectionType.USB,
            address: map['vendorId'].toString(),
            isConnected: false,
          );
          final isConnected =
              await FlutterThermalPrinterPlatform.instance.isConnected(
            printer,
          );
          usbPrinters.add(printer.copyWith(isConnected: isConnected));
        }

        for (final printer in usbPrinters) {
          _updateOrAddPrinter(printer);
        }
        if (Platform.isAndroid) {
          await _usbSubscription?.cancel();
          _usbSubscription =
              _eventChannel.receiveBroadcastStream().listen((event) {
            final map = Map<String, dynamic>.from(event);
            _updateOrAddPrinter(
              Printer(
                vendorId: map['vendorId'].toString(),
                productId: map['productId'].toString(),
                name: map['name'],
                connectionType: ConnectionType.USB,
                address: map['vendorId'].toString(),
                isConnected: map['connected'] ?? false,
              ),
            );
          });
        } else {
          await _usbSubscription?.cancel();
          _usbSubscription =
              Stream.periodic(refreshDuration, (x) => x).listen((event) async {
            final devices =
                await FlutterThermalPrinterPlatform.instance.startUsbScan();

            final usbPrinters = <Printer>[];
            for (final map in devices) {
              final printer = Printer(
                vendorId: map['vendorId'].toString(),
                productId: map['productId'].toString(),
                name: map['name'],
                connectionType: ConnectionType.USB,
                address: map['vendorId'].toString(),
                isConnected: false,
              );
              final isConnected =
                  await FlutterThermalPrinterPlatform.instance.isConnected(
                printer,
              );
              usbPrinters.add(printer.copyWith(isConnected: isConnected));
            }

            for (final printer in usbPrinters) {
              _updateOrAddPrinter(printer);
            }
            sortDevices();
          });
        }

        sortDevices();
      }
    } catch (e) {
      log('$e [USB Connection]');
    }
  }

  /// Universal BLE scanner implementation for all platforms
  Future<void> _getBLEPrinters(bool androidUsesFineLocation) async {
    try {
      await _bleSubscription?.cancel();
      _bleSubscription = null;

      // Check bluetooth availability
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      if (availability != AvailabilityState.poweredOn) {
        log('Bluetooth is not powered on. Current state: $availability');
        if (availability == AvailabilityState.poweredOff) {
          throw Exception('Bluetooth is turned off. Please enable Bluetooth.');
        }
        return;
      }

      // Stop any ongoing scan
      await UniversalBle.stopScan();

      // Start scanning
      await UniversalBle.startScan();
      log('Started BLE scan');

      sortDevices();

      // Listen to scan results using universal_ble
      _bleSubscription = UniversalBle.scanStream.listen(
        (scanResult) async {
          if (scanResult.name?.isNotEmpty ?? false) {
            _updateOrAddPrinter(
              Printer(
                address: scanResult.deviceId,
                name: scanResult.name,
                connectionType: ConnectionType.BLE,
                isConnected: await UniversalBle.getConnectionState(
                      scanResult.deviceId,
                    ) ==
                    BleConnectionState.connected,
              ),
            );
          }
        },
        onError: (error) {
          log('BLE scan error: $error');
        },
      );
    } catch (e) {
      log('Failed to start BLE scan: $e');
      rethrow;
    }
  }

  /// Update or add printer to the devices list
  void _updateOrAddPrinter(Printer printer) {
    final index =
        _devices.indexWhere((device) => device.address == printer.address);
    if (index == -1) {
      _devices.add(printer);
    } else {
      _devices[index] = printer;
    }
    sortDevices();
  }

  /// Sort and filter devices
  void sortDevices() {
    _devices
        .removeWhere((element) => element.name == null || element.name == '');
    // remove items having same vendorId
    final seen = <String>{};
    _devices.retainWhere((element) {
      final uniqueKey = '${element.vendorId}_${element.address}';
      if (seen.contains(uniqueKey)) {
        return false; // Remove duplicate
      } else {
        seen.add(uniqueKey); // Mark as seen
        return true; // Keep
      }
    });
    _devicesStream.add(_devices);
  }

  /// Turn on Bluetooth (universal approach)
  Future<void> turnOnBluetooth() async {
    try {
      // On some platforms, we might need to request user to enable Bluetooth
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      if (availability == AvailabilityState.poweredOff) {
        await UniversalBle.enableBluetooth();
      }
    } catch (e) {
      log('Failed to turn on Bluetooth: $e');
    }
  }

  /// Stream to monitor Bluetooth state
  Stream<bool> get isBleTurnedOnStream =>
      Stream.periodic(const Duration(seconds: 5), (_) async {
        final state = await UniversalBle.getBluetoothAvailabilityState();
        return state == AvailabilityState.poweredOn;
      }).asyncMap((event) => event).distinct();

  /// Check if Bluetooth is turned on
  Future<bool> isBleTurnedOn() async {
    try {
      final state = await UniversalBle.getBluetoothAvailabilityState();
      return state == AvailabilityState.poweredOn;
    } catch (e) {
      log('Failed to check Bluetooth state: $e');
      return false;
    }
  }
}
