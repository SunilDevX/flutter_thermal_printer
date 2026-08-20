// ignore_for_file: prefer_foreach

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import 'Windows/windows_platform.dart'
    if (dart.library.html) 'Windows/windows_stub.dart';
import 'flutter_thermal_printer_platform_interface.dart';
import 'utils/ble_config.dart';
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

  BleConfig bleConfig = const BleConfig();

  final StreamController<List<Printer>> _devicesStream =
      StreamController<List<Printer>>.broadcast();

  Stream<List<Printer>> get devicesStream => _devicesStream.stream;

  StreamSubscription? _bleSubscription;
  StreamSubscription? _usbSubscription;
  StreamSubscription? _bleAvailabilitySubscription;
  final Map<String, StreamSubscription<bool>> _bleConnectionSubscriptions =
      <String, StreamSubscription<bool>>{};
  Timer? _bleStateSyncTimer;
  bool _isBleStateSyncInProgress = false;
  static const Duration _bleStateSyncInterval = Duration(seconds: 3);

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
        await _stopBleStateSync();
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
  ///
  /// [device] The printer device to connect to.
  /// [connectionStabilizationDelay] Optional delay to wait after connection is established
  /// before considering it stable. Defaults to [BleConfig.connectionStabilizationDelay].
  Future<bool> connect(
    Printer device, {
    Duration? connectionStabilizationDelay,
  }) async {
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
        final address = device.address!;
        _ensureBleConnectionListener(address, fallbackName: device.name);

        final isConnected = await _isBleDeviceConnected(address);
        if (isConnected) {
          _updateBleConnectionState(
            address,
            true,
            fallbackName: device.name,
          );
          log('Device ${device.name} is already connected');
          return true;
        }
        final connectionCompleter = Completer<bool>();
        log('Connecting to BLE device ${device.name} at ${device.address}');

        StreamSubscription? subscription;

        try {
          // Listen to global connection changes
          subscription = device.connectionStream.listen((state) {
            log('Connection state changed for device ${device.name}: $state');
            if (state) {
              if (!connectionCompleter.isCompleted) {
                connectionCompleter.complete(true);
              }
            }
          });

          await device.connect();
          final delay = connectionStabilizationDelay ??
              bleConfig.connectionStabilizationDelay;
          final connected = await connectionCompleter.future.timeout(
            delay,
            onTimeout: () {
              log('Connection to device ${device.name} timed out');
              return false;
            },
          );
          _updateBleConnectionState(
            address,
            connected,
            fallbackName: device.name,
          );
          return connected;
        } catch (e) {
          log('Error connecting to device: $e');
          return false;
        } finally {
          await subscription?.cancel();
        }
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
        return await _isBleDeviceConnected(device.address!);
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
          _updateBleConnectionState(
            device.address!,
            false,
            fallbackName: device.name,
          );
          log('Disconnected from device ${device.name}');
        }
      } catch (e) {
        log('Failed to disconnect device: $e');
      }
    }

    ///
    /// [printer] The printer device to print to.
    /// [bytes] The raw bytes to print.
    /// [longData] Whether the data is long and should be split into chunks.
    /// [chunkSize] The size of each chunk if [longData] is true.
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

          ///
          /// [refreshDuration] The duration between each scan refresh.
          /// [connectionTypes] List of connection types to scan for (BLE, USB).
          /// [androidUsesFineLocation] Whether to use fine location on Android for BLE scanning.
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

      await _syncBleDevicesAndConnectionState();
      _startBleStateSync();

      // Stop any ongoing scan
      await UniversalBle.stopScan();

      // Start scanning
      await UniversalBle.startScan(
        platformConfig: PlatformConfig(
          android: AndroidOptions(
            requestLocationPermission: androidUsesFineLocation,
          ),
        ),
      );
      log('Started BLE scan');

      sortDevices();

      // Listen to scan results using universal_ble
      _bleSubscription = UniversalBle.scanStream.listen(
        (scanResult) async {
          if (scanResult.name?.isNotEmpty ?? false) {
            final isConnected =
                await _isBleDeviceConnected(scanResult.deviceId);
            _updateOrAddPrinter(
              Printer(
                address: scanResult.deviceId,
                name: scanResult.name,
                connectionType: ConnectionType.BLE,
                isConnected: isConnected,
                services: scanResult.services,
                serviceData: scanResult.serviceData,
                manufacturerDataList: scanResult.manufacturerDataList,
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
    final index = _devices.indexWhere(
      (device) =>
          device.connectionType == printer.connectionType &&
          device.address == printer.address,
    );
    if (index == -1) {
      _devices.add(printer);
    } else {
      // System-device and connection-state records carry no advertisement
      // payload, so keep the one the scan already resolved for this device.
      _devices[index] = printer.mergeAdvertisementData(_devices[index]);
    }
    if (printer.connectionType == ConnectionType.BLE &&
        (printer.address?.isNotEmpty ?? false)) {
      _ensureBleConnectionListener(
        printer.address!,
        fallbackName: printer.name,
      );
    }
    sortDevices();
  }

  Future<bool> _isBleDeviceConnected(String deviceId) async {
    try {
      return await UniversalBle.getConnectionState(deviceId) ==
          BleConnectionState.connected;
    } catch (e) {
      log('Failed to fetch BLE state for $deviceId: $e');
      return false;
    }
  }

  Future<void> _syncBleDevicesAndConnectionState() async {
    if (_isBleStateSyncInProgress) {
      return;
    }
    _isBleStateSyncInProgress = true;
    try {
      await _syncSystemBleDevices();
      await _syncKnownBleConnectionStates();
    } finally {
      _isBleStateSyncInProgress = false;
    }
  }

  Future<void> _syncSystemBleDevices() async {
    try {
      final systemDevices = await UniversalBle.getSystemDevices();
      for (final device in systemDevices) {
        final deviceId = device.deviceId;
        if (deviceId.isEmpty) {
          continue;
        }
        final deviceName = _normalizeDeviceName(device.name);
        final isConnected = await _isBleDeviceConnected(deviceId);
        _updateOrAddPrinter(
          Printer(
            address: deviceId,
            name: deviceName,
            connectionType: ConnectionType.BLE,
            isConnected: isConnected,
            services: device.services,
            serviceData: device.serviceData,
            manufacturerDataList: device.manufacturerDataList,
          ),
        );
      }
    } catch (e) {
      log('Failed to synchronize system BLE devices: $e');
    }
  }

  Future<void> _syncKnownBleConnectionStates() async {
    final bleDevices = _devices
        .where(
          (device) =>
              device.connectionType == ConnectionType.BLE &&
              (device.address?.isNotEmpty ?? false),
        )
        .toList(growable: false);

    for (final device in bleDevices) {
      final isConnected = await _isBleDeviceConnected(device.address!);
      if (device.isConnected != isConnected) {
        _updateOrAddPrinter(device.copyWith(isConnected: isConnected));
      }
    }
  }

  void _startBleStateSync() {
    _bleStateSyncTimer?.cancel();
    _bleStateSyncTimer = Timer.periodic(_bleStateSyncInterval, (_) {
      unawaited(_syncBleDevicesAndConnectionState());
    });
  }

  Future<void> _stopBleStateSync() async {
    _bleStateSyncTimer?.cancel();
    _bleStateSyncTimer = null;

    final subscriptions = _bleConnectionSubscriptions.values.toList();
    _bleConnectionSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  void _ensureBleConnectionListener(
    String deviceId, {
    String? fallbackName,
  }) {
    if (_bleConnectionSubscriptions.containsKey(deviceId)) {
      return;
    }
    _bleConnectionSubscriptions[deviceId] = UniversalBle.connectionStream(
      deviceId,
    ).listen(
      (isConnected) {
        _updateBleConnectionState(
          deviceId,
          isConnected,
          fallbackName: fallbackName,
        );
      },
      onError: (error) {
        log('BLE connection stream error for $deviceId: $error');
      },
    );
  }

  void _updateBleConnectionState(
    String deviceId,
    bool isConnected, {
    String? fallbackName,
  }) {
    final index = _devices.indexWhere(
      (device) =>
          device.connectionType == ConnectionType.BLE &&
          device.address == deviceId,
    );

    if (index == -1) {
      _updateOrAddPrinter(
        Printer(
          address: deviceId,
          name: _normalizeDeviceName(fallbackName),
          connectionType: ConnectionType.BLE,
          isConnected: isConnected,
        ),
      );
      return;
    }

    final current = _devices[index];
    final normalizedFallbackName = _normalizeDeviceName(fallbackName);
    final resolvedName = _normalizeDeviceName(current.name) ??
        normalizedFallbackName ??
        current.name;

    if (current.isConnected == isConnected && current.name == resolvedName) {
      return;
    }

    _devices[index] = current.copyWith(
      isConnected: isConnected,
      name: resolvedName,
    );
    sortDevices();
  }

  String? _normalizeDeviceName(String? name) {
    final normalized = name?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
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
