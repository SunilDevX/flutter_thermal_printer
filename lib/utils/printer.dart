// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'package:universal_ble/universal_ble.dart';

/// Optimized printer model with better data validation and serialization
class Printer extends BleDevice {
  Printer({
    this.address,
    this.name,
    this.connectionType,
    this.isConnected,
    this.vendorId,
    this.productId,
    super.services,
    super.serviceData,
    super.manufacturerDataList,
  }) : super(deviceId: address ?? '', name: name ?? '');

  /// Create Printer from JSON with validation
  factory Printer.fromJson(Map<String, dynamic> json) {
    try {
      return Printer(
        address: json['address'] as String?,
        name: json['name'] as String?,
        connectionType:
            _getConnectionTypeFromString(json['connectionType'] as String?),
        isConnected: json['isConnected'] as bool?,
        vendorId: json['vendorId']?.toString(),
        productId: json['productId']?.toString(),
      );
    } catch (e) {
      throw FormatException('Invalid Printer JSON format: $e');
    }
  }

  @override
  // ignore: overridden_fields
  final String? name;
  final String? address;
  final ConnectionType? connectionType;
  final bool? isConnected;
  final String? vendorId;
  final String? productId;

  /// Convert to JSON with proper formatting
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};

    data['address'] = address;
    data['name'] = name;
    data['connectionType'] = connectionType?.name;
    data['isConnected'] = isConnected;
    data['vendorId'] = vendorId;
    data['productId'] = productId;

    return data;
  }

  /// Get human-readable connection type string
  String get connectionTypeString {
    switch (connectionType) {
      case ConnectionType.BLE:
        return 'BLE';
      case ConnectionType.USB:
        return 'USB';
      case ConnectionType.NETWORK:
        return 'NETWORK';
      default:
        return 'UNKNOWN';
    }
  }

  /// Create a copy with updated fields
  ///
  /// Advertisement data ([services], [serviceData], [manufacturerDataList]) is
  /// carried over unless explicitly overridden, so connection-state updates do
  /// not discard what the scan reported.
  Printer copyWith({
    String? address,
    String? name,
    ConnectionType? connectionType,
    bool? isConnected,
    String? vendorId,
    String? productId,
    List<String>? services,
    Map<String, Uint8List>? serviceData,
    List<ManufacturerData>? manufacturerDataList,
  }) =>
      Printer(
        address: address ?? this.address,
        name: name ?? this.name,
        connectionType: connectionType ?? this.connectionType,
        isConnected: isConnected ?? this.isConnected,
        vendorId: vendorId ?? this.vendorId,
        productId: productId ?? this.productId,
        services: services ?? this.services,
        serviceData: serviceData ?? this.serviceData,
        manufacturerDataList: manufacturerDataList ?? this.manufacturerDataList,
      );

  /// Carry [previous]'s advertisement data over to [incoming] when [incoming]
  /// has none of its own.
  ///
  /// Records from `getSystemDevices()` or from a connection-state change carry
  /// no advertisement payload, so replacing a scanned record with one of them
  /// would drop the service UUIDs the scan already resolved.
  ///
  /// The decision is all-or-nothing on purpose. A record that carries any
  /// advertisement data is treated as authoritative for all three fields, so a
  /// scan result whose `serviceData` is legitimately empty this time does not
  /// keep reporting bytes the peripheral has stopped advertising.
  ///
  /// Named parameters rather than a receiver and an argument: the two are
  /// interchangeable at the call site and getting the order backwards would
  /// silently discard every fresh `isConnected` or `name` update.
  static Printer mergeAdvertisementData({
    required Printer previous,
    required Printer incoming,
  }) {
    final hasOwnData = incoming.services.isNotEmpty ||
        incoming.serviceData.isNotEmpty ||
        incoming.manufacturerDataList.isNotEmpty;
    if (hasOwnData) {
      return incoming;
    }

    final hasInheritable = previous.services.isNotEmpty ||
        previous.serviceData.isNotEmpty ||
        previous.manufacturerDataList.isNotEmpty;
    if (!hasInheritable) {
      return incoming;
    }

    return incoming.copyWith(
      services: previous.services,
      serviceData: previous.serviceData,
      manufacturerDataList: previous.manufacturerDataList,
    );
  }

  /// Generate unique identifier for the printer
  String get uniqueId {
    final buffer = StringBuffer();
    if (vendorId != null) {
      buffer.write(vendorId);
    }
    buffer.write('_');
    if (address != null) {
      buffer.write(address);
    }
    return buffer.toString();
  }

  /// Check if printer has valid connection data
  bool get hasValidConnectionData {
    switch (connectionType) {
      case ConnectionType.USB:
        return vendorId != null && productId != null;
      case ConnectionType.BLE:
        return address != null;
      case ConnectionType.NETWORK:
        return address != null;
      default:
        return false;
    }
  }

  @override
  String toString() =>
      'Printer(name: $name, connectionType: ${connectionType?.name}, '
      'address: $address, isConnected: $isConnected)';

  /// Convert string to ConnectionType enum
  static ConnectionType? _getConnectionTypeFromString(String? type) {
    if (type == null) {
      return null;
    }

    switch (type.toUpperCase()) {
      case 'BLE':
        return ConnectionType.BLE;
      case 'USB':
        return ConnectionType.USB;
      case 'NETWORK':
        return ConnectionType.NETWORK;
      default:
        return null;
    }
  }
}

/// Enhanced connection type enum
enum ConnectionType {
  BLE,
  USB,
  NETWORK,
}
