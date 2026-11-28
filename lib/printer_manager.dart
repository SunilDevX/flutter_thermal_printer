// ignore_for_file: prefer_foreach

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

// dart.library.html is false under wasm, so key on ffi instead.
import 'Windows/windows_stub.dart'
    if (dart.library.ffi) 'Windows/windows_platform.dart';
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

  /// A disconnected BLE printer unseen for this many syncs (~30 s) is dropped.
  static const int _bleMaxMissedSyncs = 10;
  final Map<String, int> _bleMissedSyncs = {};

  /// Write characteristic and chunk size per connected BLE printer, so they
  /// are negotiated once per connection instead of on every print.
  final Map<String, ({BleCharacteristic characteristic, int chunkSize})>
  _bleWriteTargets = {};

  static const String _channelName = 'flutter_thermal_printer/events';
  final EventChannel _eventChannel = const EventChannel(_channelName);

  final List<Printer> _devices = [];
  Set<ConnectionType> _scanConnectionTypes = ConnectionType.values.toSet();
  int _queueScanGeneration = 0;

  bool _usesMacOSQueue(Printer printer) =>
      Platform.isMacOS && printer.isSystemPrinter;

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
  Future<void> stopScan({bool stopBle = true, bool stopUsb = true}) async {
    try {
      if (stopBle) {
        await _stopBleStateSync();
        await _bleSubscription?.cancel();
        _bleSubscription = null;
        await UniversalBle.stopScan();
      }
      if (stopUsb) {
        _queueScanGeneration++;
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
  /// [connectionTimeout] How long to wait for a BLE printer to connect.
  /// Defaults to [BleConfig.connectionTimeout].
  Future<bool> connect(
    Printer device, {
    Duration? connectionTimeout,
    @Deprecated('Use connectionTimeout instead.')
    Duration? connectionStabilizationDelay,
  }) async {
    if (_usesMacOSQueue(device) ||
        device.connectionType == ConnectionType.USB) {
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
          _updateBleConnectionState(address, true, fallbackName: device.name);
          log('Device ${device.name} is already connected');
          return true;
        }
        log('Connecting to BLE device ${device.name} at $address');
        // stopScan() cancels the listener that would have cleared this.
        _bleWriteTargets.remove(address);
        // Completes once connected; throws on failure or timeout.
        await device.connect(
          timeout:
              connectionTimeout ??
              connectionStabilizationDelay ??
              bleConfig.connectionTimeout,
        );
        _updateBleConnectionState(address, true, fallbackName: device.name);
        return true;
      } catch (e) {
        log('Failed to connect to BLE device: $e');
        return false;
      }
    }
    return false;
  }

  /// Check if a device is connected
  Future<bool> isConnected(Printer device) async {
    if (_usesMacOSQueue(device) ||
        device.connectionType == ConnectionType.USB) {
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
          _bleWriteTargets.remove(device.address);
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
    // USB devices don't need explicit disconnection
  }

  /// Sends [bytes] to [printer] and returns whether all of them were handed
  /// to the printer. Failures are logged, not thrown.
  ///
  /// Jobs for the same printer run one after another, so two calls made at
  /// once cannot interleave their bytes.
  ///
  /// [longData] adds a 10 ms pause between BLE writes.
  /// [chunkSize] is the number of bytes per BLE write; it defaults to the
  /// negotiated MTU minus 3. Values below 1 throw an [ArgumentError].
  Future<bool> printData(
    Printer printer,
    List<int> bytes, {
    bool longData = false,
    int? chunkSize,
  }) async {
    if (chunkSize != null && chunkSize < 1) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
    }
    final key = '${printer.connectionType?.name}|${printer.address}';
    final job = (_printQueues[key] ?? Future<void>.value()).then(
      (_) =>
          _sendData(printer, bytes, longData: longData, chunkSize: chunkSize),
    );
    // The tail never fails, so one broken job cannot stall the queue.
    final tail = job.then<void>((_) {}, onError: (_) {});
    _printQueues[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_printQueues[key], tail)) {
          _printQueues.remove(key);
        }
      }),
    );
    return job;
  }

  final Map<String, Future<void>> _printQueues = {};

  Future<bool> _sendData(
    Printer printer,
    List<int> bytes, {
    required bool longData,
    int? chunkSize,
  }) async {
    if (_usesMacOSQueue(printer) ||
        printer.connectionType == ConnectionType.USB) {
      if (Platform.isWindows) {
        // Windows USB printing using Win32 API
        return using(
          (alloc) => RawPrinter(printer.name!, alloc).printEscPosWin32(bytes),
        );
      }
      // Non-Windows USB printing
      try {
        return await FlutterThermalPrinterPlatform.instance.printText(
          printer,
          Uint8List.fromList(bytes),
          path: printer.address,
        );
      } catch (e) {
        log('FlutterThermalPrinter: Unable to Print Data $e');
        return false;
      }
    } else if (printer.connectionType == ConnectionType.BLE) {
      try {
        final target = await _bleWriteTarget(printer);
        if (target == null) {
          log('No write characteristic found');
          return false;
        }
        final maxChunkSize = chunkSize ?? target.chunkSize;

        for (var i = 0; i < bytes.length; i += maxChunkSize) {
          final chunk = bytes.sublist(
            i,
            i + maxChunkSize > bytes.length ? bytes.length : i + maxChunkSize,
          );

          await target.characteristic.write(Uint8List.fromList(chunk));

          // Small delay between chunks to avoid overwhelming the device
          if (longData) {
            await Future.delayed(const Duration(milliseconds: 10));
          }
        }
        return true;
      } catch (e) {
        // Negotiate again next time in case the connection changed under us.
        _bleWriteTargets.remove(printer.address);
        log('Failed to print data to device $e');
        return false;
      }
    }
    // Raw IP printers go through FlutterThermalPrinterNetwork instead.
    log('printData does not support ${printer.connectionTypeString} printers');
    return false;
  }

  Future<({BleCharacteristic characteristic, int chunkSize})?> _bleWriteTarget(
    Printer printer,
  ) async {
    final address = printer.address!;
    final cached = _bleWriteTargets[address];
    if (cached != null) {
      return cached;
    }
    final services = await printer.discoverServices();

    BleCharacteristic? writeCharacteristic;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.contains(CharacteristicProperty.write)) {
          writeCharacteristic = characteristic;
          break;
        }
      }
    }
    if (writeCharacteristic == null) {
      return null;
    }

    // An ATT write carries at most MTU - 3 bytes; 23 is the BLE minimum MTU.
    var mtu = 23;
    if (Platform.isWindows) {
      mtu = 53;
    } else {
      try {
        mtu = await printer.requestMtu(Platform.isMacOS ? 150 : 500);
      } catch (e) {
        log('MTU request failed, using 20-byte writes: $e');
      }
    }
    // The connection listener drops this entry when the printer disconnects.
    _ensureBleConnectionListener(address, fallbackName: printer.name);
    return _bleWriteTargets[address] = (
      characteristic: writeCharacteristic,
      chunkSize: mtu - 3,
    );
  }

  /// Discover BLE and USB printers, plus installed network queues on macOS.
  /// Network discovery on other platforms still requires an explicit IP address.
  Future<void> getPrinters({
    Duration refreshDuration = const Duration(seconds: 2),
    List<ConnectionType> connectionTypes = const [
      ConnectionType.BLE,
      ConnectionType.USB,
      ConnectionType.NETWORK,
    ],
    bool androidUsesFineLocation = false,
  }) async {
    if (connectionTypes.isEmpty) {
      throw Exception('No connection type provided');
    }
    _scanConnectionTypes = connectionTypes.toSet();
    _queueScanGeneration++;
    await _usbSubscription?.cancel();
    _usbSubscription = null;
    sortDevices();

    if (Platform.isMacOS &&
        (connectionTypes.contains(ConnectionType.USB) ||
            connectionTypes.contains(ConnectionType.NETWORK))) {
      await _getMacOSPrinters(refreshDuration);
    } else if (connectionTypes.contains(ConnectionType.USB)) {
      await _getUSBPrinters(refreshDuration);
    }

    if (connectionTypes.contains(ConnectionType.BLE)) {
      await _getBLEPrinters(androidUsesFineLocation);
    }
  }

  /// The native macOS API enumerates installed queues of every transport.
  Future<void> _getMacOSPrinters(Duration refreshDuration) async {
    final generation = _queueScanGeneration;
    Future<void> refresh() async {
      final records = await FlutterThermalPrinterPlatform.instance
          .startUsbScan();
      final printers = <Printer>[];
      for (final record in records) {
        final printer = Printer.fromJson(Map<String, dynamic>.from(record));
        final isConnected = await FlutterThermalPrinterPlatform.instance
            .isConnected(printer);
        printers.add(printer.copyWith(isConnected: isConnected));
      }
      // Replace the queue snapshot so removed queues and changed transports
      // cannot leave stale entries in the list.
      if (generation != _queueScanGeneration) {
        return;
      }
      _devices
        ..removeWhere((printer) => printer.isSystemPrinter)
        ..addAll(printers);
      sortDevices();
    }

    await refresh();
    if (generation != _queueScanGeneration) {
      return;
    }
    var refreshing = false;
    _usbSubscription = Stream.periodic(refreshDuration).listen((_) async {
      if (refreshing) {
        return;
      }
      refreshing = true;
      try {
        await refresh();
      } catch (e) {
        log('Failed to refresh macOS printer queues: $e');
      } finally {
        refreshing = false;
      }
    });
  }

  /// USB printer discovery for all platforms
  Future<void> _getUSBPrinters(Duration refreshDuration) async {
    try {
      if (Platform.isWindows) {
        // Windows USB printer discovery using Win32 API
        await _usbSubscription?.cancel();
        _usbSubscription = Stream.periodic(refreshDuration, (x) => x).listen((
          event,
        ) async {
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
        final devices = await FlutterThermalPrinterPlatform.instance
            .startUsbScan();

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
          final isConnected = await FlutterThermalPrinterPlatform.instance
              .isConnected(printer);
          usbPrinters.add(printer.copyWith(isConnected: isConnected));
        }

        for (final printer in usbPrinters) {
          _updateOrAddPrinter(printer);
        }
        if (Platform.isAndroid) {
          await _usbSubscription?.cancel();
          _usbSubscription = _eventChannel.receiveBroadcastStream().listen((
            event,
          ) {
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
          _usbSubscription = Stream.periodic(refreshDuration, (x) => x).listen((
            event,
          ) async {
            final devices = await FlutterThermalPrinterPlatform.instance
                .startUsbScan();

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
              final isConnected = await FlutterThermalPrinterPlatform.instance
                  .isConnected(printer);
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
      switch (availability) {
        case AvailabilityState.poweredOff:
          throw Exception('Bluetooth is turned off. Please enable Bluetooth.');
        case AvailabilityState.unauthorized:
          throw Exception('Bluetooth permission is not granted.');
        case AvailabilityState.unsupported:
          throw Exception('Bluetooth LE is not supported on this device.');
        case AvailabilityState.poweredOn:
          break;
        // Transient states: let the scan start, or fail with the real cause.
        case AvailabilityState.unknown:
        case AvailabilityState.resetting:
          log('Bluetooth state is $availability; scanning anyway');
      }

      // A new scan gives every listed printer a fresh ~30 s to be seen.
      _bleMissedSyncs.clear();
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
            _bleMissedSyncs.remove(scanResult.deviceId);
            // Printers already listed get their state from the connection
            // listener; only ask the platform about new ones.
            final isConnected =
                _findBlePrinter(scanResult.deviceId)?.isConnected ??
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
    var changed = true;
    if (index == -1) {
      _devices.add(printer);
    } else {
      final previous = _devices[index];
      changed =
          previous.name != printer.name ||
          previous.isConnected != printer.isConnected ||
          previous.vendorId != printer.vendorId ||
          previous.productId != printer.productId;
      // System-device and connection-state records carry no advertisement
      // payload, so keep the one the scan already resolved for this device.
      _devices[index] = Printer.mergeAdvertisementData(
        previous: previous,
        incoming: printer,
      );
    }
    if (printer.connectionType == ConnectionType.BLE &&
        (printer.address?.isNotEmpty ?? false)) {
      _ensureBleConnectionListener(
        printer.address!,
        fallbackName: printer.name,
      );
    }
    // Repeated advertisements would otherwise re-emit the list many times a
    // second per printer.
    if (changed) {
      sortDevices();
    }
  }

  Printer? _findBlePrinter(String deviceId) {
    for (final device in _devices) {
      if (device.connectionType == ConnectionType.BLE &&
          device.address == deviceId) {
        return device;
      }
    }
    return null;
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

  Future<void> _syncBleDevicesAndConnectionState({bool prune = false}) async {
    if (_isBleStateSyncInProgress) {
      return;
    }
    _isBleStateSyncInProgress = true;
    try {
      await _syncSystemBleDevices();
      await _syncKnownBleConnectionStates();
      if (prune) {
        _pruneUnseenBlePrinters();
      }
    } finally {
      _isBleStateSyncInProgress = false;
    }
  }

  /// Drops disconnected BLE printers that stopped advertising, such as ones
  /// that went out of range or were switched off.
  void _pruneUnseenBlePrinters() {
    final stale = <String>{};
    for (final device in _devices) {
      final address = device.address;
      if (device.connectionType != ConnectionType.BLE || address == null) {
        continue;
      }
      // A connected printer stops advertising, so it is never stale.
      final missed = device.isConnected == true
          ? 0
          : (_bleMissedSyncs[address] ?? 0) + 1;
      _bleMissedSyncs[address] = missed;
      if (missed > _bleMaxMissedSyncs) {
        stale.add(address);
      }
    }
    if (stale.isEmpty) {
      return;
    }
    _devices.removeWhere(
      (device) =>
          device.connectionType == ConnectionType.BLE &&
          stale.contains(device.address),
    );
    for (final address in stale) {
      _bleMissedSyncs.remove(address);
      unawaited(_bleConnectionSubscriptions.remove(address)?.cancel());
    }
    sortDevices();
  }

  Future<void> _syncSystemBleDevices() async {
    try {
      final systemDevices = await UniversalBle.getSystemDevices();
      for (final device in systemDevices) {
        final deviceId = device.deviceId;
        if (deviceId.isEmpty) {
          continue;
        }
        _bleMissedSyncs.remove(deviceId);
        final deviceName = _normalizeDeviceName(device.name);
        final isConnected = await _isBleDeviceConnected(deviceId);
        _updateOrAddPrinter(
          Printer(
            address: deviceId,
            name: deviceName,
            connectionType: ConnectionType.BLE,
            isConnected: isConnected,
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
      unawaited(_syncBleDevicesAndConnectionState(prune: true));
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

  void _ensureBleConnectionListener(String deviceId, {String? fallbackName}) {
    if (_bleConnectionSubscriptions.containsKey(deviceId)) {
      return;
    }
    _bleConnectionSubscriptions[deviceId] =
        UniversalBle.connectionStream(deviceId).listen(
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
    if (!isConnected) {
      // MTU and services must be negotiated again on the next connection.
      _bleWriteTargets.remove(deviceId);
    }
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
    final resolvedName =
        _normalizeDeviceName(current.name) ??
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
    _devices.removeWhere(
      (element) => element.name == null || element.name == '',
    );
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
    _devicesStream.add(
      _devices.where((printer) {
        final type = printer.connectionType;
        if (type != null) {
          return _scanConnectionTypes.contains(type);
        }
        // Unknown system queues appear only when both queue transports are
        // requested; a USB-only or network-only scan never guesses their type.
        return printer.isSystemPrinter &&
            _scanConnectionTypes.contains(ConnectionType.USB) &&
            _scanConnectionTypes.contains(ConnectionType.NETWORK);
      }).toList(),
    );
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

  /// Whether Bluetooth is on: the current state first, then every change.
  Stream<bool> get isBleTurnedOnStream => _bleTurnedOnStates().distinct();

  Stream<bool> _bleTurnedOnStates() async* {
    yield await isBleTurnedOn();
    yield* UniversalBle.availabilityStream
        .map((state) => state == AvailabilityState.poweredOn)
        .handleError((Object e) => log('Bluetooth state stream error: $e'));
  }

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
