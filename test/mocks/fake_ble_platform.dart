import 'dart:async';
import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// In-memory BLE stack for [UniversalBle.setInstance]. Members a test does
/// not need fall through to [noSuchMethod].
class FakeBlePlatform extends UniversalBlePlatform {
  AvailabilityState availability = AvailabilityState.poweredOn;
  final Set<String> connected = {};

  /// When false, connect() never reports a connection.
  bool connectSucceeds = true;
  bool mtuFails = false;
  int mtu = 23;

  int getConnectionStateCalls = 0;
  int discoverServicesCalls = 0;
  int requestMtuCalls = 0;
  final List<List<int>> writes = [];

  static const serviceId = '0000ff00-0000-1000-8000-00805f9b34fb';
  static const characteristicId = '0000ff02-0000-1000-8000-00805f9b34fb';

  void advertise(String deviceId, String name) =>
      updateScanResult(BleDevice(deviceId: deviceId, name: name));

  void setAvailability(AvailabilityState state) {
    availability = state;
    updateAvailability(state);
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      availability;

  @override
  Future<void> startScan({
    ScanFilter? scanFilter,
    PlatformConfig? platformConfig,
  }) async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async =>
      [];

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async {
    getConnectionStateCalls++;
    return connected.contains(deviceId)
        ? BleConnectionState.connected
        : BleConnectionState.disconnected;
  }

  @override
  Future<void> connect(
    String deviceId, {
    Duration? connectionTimeout,
    bool autoConnect = false,
    ConnectionPlatformConfig? platformConfig,
  }) async {
    if (!connectSucceeds) {
      return;
    }
    connected.add(deviceId);
    scheduleMicrotask(() => updateConnection(deviceId, true));
  }

  @override
  Future<void> disconnect(String deviceId) async {
    connected.remove(deviceId);
    updateConnection(deviceId, false);
  }

  @override
  Future<List<BleService>> discoverServices(
    String deviceId,
    bool withDescriptors, {
    DiscoverServicesPlatformConfig? platformConfig,
  }) async {
    discoverServicesCalls++;
    return [
      BleService(serviceId, [
        BleCharacteristic.withMetaData(
          deviceId: deviceId,
          serviceId: serviceId,
          uuid: characteristicId,
          properties: [CharacteristicProperty.write],
          descriptors: [],
        ),
      ]),
    ];
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    requestMtuCalls++;
    if (mtuFails) {
      throw Exception('MTU request rejected');
    }
    return mtu;
  }

  @override
  Future<void> writeValue(
    String deviceId,
    String service,
    String characteristic,
    Uint8List value,
    BleOutputProperty bleOutputProperty,
  ) async {
    writes.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
