import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:universal_ble/universal_ble.dart';

void main() {
  group('Printer', () {
    group('constructor', () {
      test('creates instance with all parameters', () {
        final printer = Printer(
          address: '00:11:22:33:44:55',
          name: 'Test Printer',
          connectionType: ConnectionType.BLE,
          isConnected: true,
          vendorId: '1234',
          productId: '5678',
        );

        expect(printer.address, '00:11:22:33:44:55');
        expect(printer.name, 'Test Printer');
        expect(printer.connectionType, ConnectionType.BLE);
        expect(printer.isConnected, true);
        expect(printer.vendorId, '1234');
        expect(printer.productId, '5678');
      });

      test('creates instance with minimal parameters', () {
        final printer = Printer();

        expect(printer.address, isNull);
        expect(printer.name, isNull);
        expect(printer.connectionType, isNull);
        expect(printer.isConnected, isNull);
        expect(printer.vendorId, isNull);
        expect(printer.productId, isNull);
      });

      test('sets deviceId from address for BleDevice', () {
        final printer = Printer(address: 'test-address');
        expect(printer.deviceId, 'test-address');
      });

      test('uses empty string for null address in deviceId', () {
        final printer = Printer();
        expect(printer.deviceId, '');
      });
    });

    group('fromJson', () {
      test('parses complete JSON correctly', () {
        final json = {
          'address': '00:11:22:33:44:55',
          'name': 'Test Printer',
          'connectionType': 'BLE',
          'isConnected': true,
          'vendorId': '1234',
          'productId': '5678',
        };

        final printer = Printer.fromJson(json);

        expect(printer.address, '00:11:22:33:44:55');
        expect(printer.name, 'Test Printer');
        expect(printer.connectionType, ConnectionType.BLE);
        expect(printer.isConnected, true);
        expect(printer.vendorId, '1234');
        expect(printer.productId, '5678');
      });

      test('parses JSON with null fields', () {
        final json = <String, dynamic>{
          'address': null,
          'name': null,
          'connectionType': null,
          'isConnected': null,
          'vendorId': null,
          'productId': null,
        };

        final printer = Printer.fromJson(json);

        expect(printer.address, isNull);
        expect(printer.name, isNull);
        expect(printer.connectionType, isNull);
        expect(printer.isConnected, isNull);
        expect(printer.vendorId, isNull);
        expect(printer.productId, isNull);
      });

      test('parses USB connectionType', () {
        final json = {'connectionType': 'USB'};
        final printer = Printer.fromJson(json);
        expect(printer.connectionType, ConnectionType.USB);
      });

      test('parses NETWORK connectionType', () {
        final json = {'connectionType': 'NETWORK'};
        final printer = Printer.fromJson(json);
        expect(printer.connectionType, ConnectionType.NETWORK);
      });

      test('parses connectionType case-insensitive', () {
        expect(
          Printer.fromJson({'connectionType': 'ble'}).connectionType,
          ConnectionType.BLE,
        );
        expect(
          Printer.fromJson({'connectionType': 'Usb'}).connectionType,
          ConnectionType.USB,
        );
        expect(
          Printer.fromJson({'connectionType': 'network'}).connectionType,
          ConnectionType.NETWORK,
        );
      });

      test('handles vendorId as int', () {
        final json = {'vendorId': 1234};
        final printer = Printer.fromJson(json);
        expect(printer.vendorId, '1234');
      });

      test('handles productId as int', () {
        final json = {'productId': 5678};
        final printer = Printer.fromJson(json);
        expect(printer.productId, '5678');
      });

      test('returns null for unknown connectionType', () {
        final json = {'connectionType': 'INVALID'};
        final printer = Printer.fromJson(json);
        expect(printer.connectionType, isNull);
      });
    });

    group('toJson', () {
      test('serializes all fields correctly', () {
        final printer = Printer(
          address: '00:11:22:33:44:55',
          name: 'Test Printer',
          connectionType: ConnectionType.BLE,
          isConnected: true,
          vendorId: '1234',
          productId: '5678',
        );

        final json = printer.toJson();

        expect(json['address'], '00:11:22:33:44:55');
        expect(json['name'], 'Test Printer');
        expect(json['connectionType'], 'BLE');
        expect(json['isConnected'], true);
        expect(json['vendorId'], '1234');
        expect(json['productId'], '5678');
      });

      test('serializes null fields as null', () {
        final printer = Printer();
        final json = printer.toJson();

        expect(json['address'], isNull);
        expect(json['name'], isNull);
        expect(json['connectionType'], isNull);
        expect(json['isConnected'], isNull);
        expect(json['vendorId'], isNull);
        expect(json['productId'], isNull);
      });

      test('serializes USB connectionType', () {
        final printer = Printer(connectionType: ConnectionType.USB);
        expect(printer.toJson()['connectionType'], 'USB');
      });

      test('serializes NETWORK connectionType', () {
        final printer = Printer(connectionType: ConnectionType.NETWORK);
        expect(printer.toJson()['connectionType'], 'NETWORK');
      });
    });

    group('copyWith', () {
      test('creates copy with no changes', () {
        final original = Printer(
          address: 'addr',
          name: 'name',
          connectionType: ConnectionType.BLE,
          isConnected: true,
          vendorId: 'v1',
          productId: 'p1',
        );

        final copy = original.copyWith();

        expect(copy.address, original.address);
        expect(copy.name, original.name);
        expect(copy.connectionType, original.connectionType);
        expect(copy.isConnected, original.isConnected);
        expect(copy.vendorId, original.vendorId);
        expect(copy.productId, original.productId);
      });

      test('updates single field', () {
        final original = Printer(name: 'Original');
        final copy = original.copyWith(name: 'Updated');

        expect(copy.name, 'Updated');
        expect(original.name, 'Original');
      });

      test('updates multiple fields', () {
        final original = Printer(
          name: 'Original',
          isConnected: false,
        );

        final copy = original.copyWith(
          name: 'Updated',
          isConnected: true,
          connectionType: ConnectionType.USB,
        );

        expect(copy.name, 'Updated');
        expect(copy.isConnected, true);
        expect(copy.connectionType, ConnectionType.USB);
      });

      test('preserves unspecified fields', () {
        final original = Printer(
          address: 'addr',
          name: 'name',
          vendorId: 'vendor',
        );

        final copy = original.copyWith(name: 'new name');

        expect(copy.address, 'addr');
        expect(copy.vendorId, 'vendor');
      });
    });

    group('connectionTypeString', () {
      test('returns BLE for ConnectionType.BLE', () {
        final printer = Printer(connectionType: ConnectionType.BLE);
        expect(printer.connectionTypeString, 'BLE');
      });

      test('returns USB for ConnectionType.USB', () {
        final printer = Printer(connectionType: ConnectionType.USB);
        expect(printer.connectionTypeString, 'USB');
      });

      test('returns NETWORK for ConnectionType.NETWORK', () {
        final printer = Printer(connectionType: ConnectionType.NETWORK);
        expect(printer.connectionTypeString, 'NETWORK');
      });

      test('returns UNKNOWN for null connectionType', () {
        final printer = Printer();
        expect(printer.connectionTypeString, 'UNKNOWN');
      });
    });

    group('uniqueId', () {
      test('combines vendorId and address', () {
        final printer = Printer(vendorId: 'V123', address: 'A456');
        expect(printer.uniqueId, 'V123_A456');
      });

      test('handles null vendorId', () {
        final printer = Printer(address: 'A456');
        expect(printer.uniqueId, '_A456');
      });

      test('handles null address', () {
        final printer = Printer(vendorId: 'V123');
        expect(printer.uniqueId, 'V123_');
      });

      test('handles both null', () {
        final printer = Printer();
        expect(printer.uniqueId, '_');
      });
    });

    group('hasValidConnectionData', () {
      test('USB requires vendorId and productId', () {
        expect(
          Printer(
            connectionType: ConnectionType.USB,
            vendorId: 'v',
            productId: 'p',
          ).hasValidConnectionData,
          true,
        );

        expect(
          Printer(
            connectionType: ConnectionType.USB,
            vendorId: 'v',
          ).hasValidConnectionData,
          false,
        );

        expect(
          Printer(
            connectionType: ConnectionType.USB,
            productId: 'p',
          ).hasValidConnectionData,
          false,
        );
      });

      test('BLE requires address', () {
        expect(
          Printer(
            connectionType: ConnectionType.BLE,
            address: 'addr',
          ).hasValidConnectionData,
          true,
        );

        expect(
          Printer(connectionType: ConnectionType.BLE).hasValidConnectionData,
          false,
        );
      });

      test('NETWORK requires address', () {
        expect(
          Printer(
            connectionType: ConnectionType.NETWORK,
            address: '192.168.1.1',
          ).hasValidConnectionData,
          true,
        );

        expect(
          Printer(connectionType: ConnectionType.NETWORK)
              .hasValidConnectionData,
          false,
        );
      });

      test('returns false for null connectionType', () {
        final printer = Printer(address: 'addr', vendorId: 'v', productId: 'p');
        expect(printer.hasValidConnectionData, false);
      });
    });

    group('toString', () {
      test('includes all relevant fields', () {
        final printer = Printer(
          name: 'Test',
          connectionType: ConnectionType.BLE,
          address: 'addr',
          isConnected: true,
        );

        final str = printer.toString();

        expect(str, contains('name: Test'));
        expect(str, contains('connectionType: BLE'));
        expect(str, contains('address: addr'));
        expect(str, contains('isConnected: true'));
      });
    });
  });

  group('ConnectionType', () {
    test('has three values', () {
      expect(ConnectionType.values.length, 3);
    });

    test('contains BLE, USB, NETWORK', () {
      expect(ConnectionType.values, contains(ConnectionType.BLE));
      expect(ConnectionType.values, contains(ConnectionType.USB));
      expect(ConnectionType.values, contains(ConnectionType.NETWORK));
    });

    test('name property returns correct strings', () {
      expect(ConnectionType.BLE.name, 'BLE');
      expect(ConnectionType.USB.name, 'USB');
      expect(ConnectionType.NETWORK.name, 'NETWORK');
    });

    test('index values are sequential', () {
      expect(ConnectionType.BLE.index, 0);
      expect(ConnectionType.USB.index, 1);
      expect(ConnectionType.NETWORK.index, 2);
    });
  });

  group('Printer JSON round-trip', () {
    test('complete printer survives JSON round-trip', () {
      final original = Printer(
        address: '00:11:22:33:44:55',
        name: 'Test Printer',
        connectionType: ConnectionType.BLE,
        isConnected: true,
        vendorId: '1234',
        productId: '5678',
      );

      final json = original.toJson();
      final restored = Printer.fromJson(json);

      expect(restored.address, original.address);
      expect(restored.name, original.name);
      expect(restored.connectionType, original.connectionType);
      expect(restored.isConnected, original.isConnected);
      expect(restored.vendorId, original.vendorId);
      expect(restored.productId, original.productId);
    });

    test('USB printer survives JSON round-trip', () {
      final original = Printer(
        name: 'USB Printer',
        connectionType: ConnectionType.USB,
        vendorId: 'VENDOR',
        productId: 'PRODUCT',
        isConnected: false,
      );

      final json = original.toJson();
      final restored = Printer.fromJson(json);

      expect(restored.connectionType, ConnectionType.USB);
      expect(restored.vendorId, 'VENDOR');
      expect(restored.productId, 'PRODUCT');
    });

    test('NETWORK printer survives JSON round-trip', () {
      final original = Printer(
        name: 'Network Printer',
        connectionType: ConnectionType.NETWORK,
        address: '192.168.1.100',
        isConnected: true,
      );

      final json = original.toJson();
      final restored = Printer.fromJson(json);

      expect(restored.connectionType, ConnectionType.NETWORK);
      expect(restored.address, '192.168.1.100');
    });

    test('empty printer survives JSON round-trip', () {
      final original = Printer();

      final json = original.toJson();
      final restored = Printer.fromJson(json);

      expect(restored.address, isNull);
      expect(restored.name, isNull);
      expect(restored.connectionType, isNull);
    });
  });

  group('Printer edge cases', () {
    test('handles special characters in name', () {
      final printer = Printer(name: 'Printer™ 日本語 émoji 🖨️');
      expect(printer.name, 'Printer™ 日本語 émoji 🖨️');

      final json = printer.toJson();
      final restored = Printer.fromJson(json);
      expect(restored.name, printer.name);
    });

    test('handles empty string name', () {
      final printer = Printer(name: '');
      expect(printer.name, '');
    });

    test('handles very long address', () {
      final longAddress = 'A' * 1000;
      final printer = Printer(address: longAddress);
      expect(printer.address, longAddress);
    });

    test('handles numeric strings', () {
      final printer = Printer(
        vendorId: '12345',
        productId: '67890',
      );

      final json = printer.toJson();
      expect(json['vendorId'], '12345');
      expect(json['productId'], '67890');
    });
  });

  group('BleDevice compatibility', () {
    test('deviceId matches address', () {
      final printer = Printer(address: 'test-device-id');
      expect(printer.deviceId, 'test-device-id');
    });

    test('name override works', () {
      final printer = Printer(name: 'Custom Name', address: 'addr');
      expect(printer.name, 'Custom Name');
    });
  });

  group('advertisement data', () {
    final serviceData = <String, Uint8List>{
      '000018f0-0000-1000-8000-00805f9b34fb': Uint8List.fromList([1, 2, 3]),
    };
    final manufacturerDataList = [
      ManufacturerData(0x004c, Uint8List.fromList([9, 8])),
    ];

    test('constructor forwards advertisement data to BleDevice', () {
      final printer = Printer(
        address: 'addr',
        name: 'name',
        connectionType: ConnectionType.BLE,
        services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
        serviceData: serviceData,
        manufacturerDataList: manufacturerDataList,
      );

      expect(printer.services, ['000018f0-0000-1000-8000-00805f9b34fb']);
      expect(printer.serviceData, serviceData);
      expect(printer.manufacturerDataList, manufacturerDataList);
    });

    test('defaults to empty advertisement data', () {
      final printer = Printer(address: 'addr');

      expect(printer.services, isEmpty);
      expect(printer.serviceData, isEmpty);
      expect(printer.manufacturerDataList, isEmpty);
    });

    test('copyWith preserves advertisement data', () {
      final original = Printer(
        address: 'addr',
        name: 'name',
        connectionType: ConnectionType.BLE,
        services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
        serviceData: serviceData,
        manufacturerDataList: manufacturerDataList,
      );

      final copy = original.copyWith(isConnected: true);

      expect(copy.isConnected, true);
      expect(copy.services, original.services);
      expect(copy.serviceData, original.serviceData);
      expect(copy.manufacturerDataList, original.manufacturerDataList);
    });

    test('copyWith can override advertisement data', () {
      final original = Printer(
        address: 'addr',
        services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
      );

      final copy = original.copyWith(
        services: const ['0000180d-0000-1000-8000-00805f9b34fb'],
      );

      expect(copy.services, ['0000180d-0000-1000-8000-00805f9b34fb']);
    });

    group('mergeAdvertisementData', () {
      test('carries previous data over when incoming has none', () {
        final scanned = Printer(
          address: 'addr',
          name: 'name',
          connectionType: ConnectionType.BLE,
          services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
          serviceData: serviceData,
          manufacturerDataList: manufacturerDataList,
        );
        final systemRecord = Printer(
          address: 'addr',
          name: 'name',
          connectionType: ConnectionType.BLE,
          isConnected: true,
        );

        final merged = Printer.mergeAdvertisementData(
          previous: scanned,
          incoming: systemRecord,
        );

        expect(merged.isConnected, true);
        expect(merged.services, scanned.services);
        expect(merged.serviceData, scanned.serviceData);
        expect(merged.manufacturerDataList, scanned.manufacturerDataList);
      });

      test('keeps incoming data when incoming carries some', () {
        final previous = Printer(
          address: 'addr',
          services: const ['0000180d-0000-1000-8000-00805f9b34fb'],
        );
        final incoming = Printer(
          address: 'addr',
          services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
        );

        final merged = Printer.mergeAdvertisementData(
          previous: previous,
          incoming: incoming,
        );

        expect(merged.services, ['000018f0-0000-1000-8000-00805f9b34fb']);
      });

      test('does not keep stale serviceData alongside fresh services', () {
        final previous = Printer(
          address: 'addr',
          services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
          serviceData: serviceData,
        );
        final incoming = Printer(
          address: 'addr',
          services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
        );

        final merged = Printer.mergeAdvertisementData(
          previous: previous,
          incoming: incoming,
        );

        expect(merged.serviceData, isEmpty);
      });

      test('returns incoming unchanged when there is nothing to inherit', () {
        final incoming = Printer(address: 'addr');
        final previous = Printer(address: 'addr');

        expect(
          identical(
            Printer.mergeAdvertisementData(
              previous: previous,
              incoming: incoming,
            ),
            incoming,
          ),
          true,
        );
      });

      test('inheriting keeps the incoming connection state, not previous', () {
        // With the arguments swapped, every fresh isConnected/name update
        // would be silently discarded; this pins the direction.
        final previous = Printer(
          address: 'addr',
          name: 'old name',
          isConnected: false,
          services: const ['000018f0-0000-1000-8000-00805f9b34fb'],
        );
        final incoming = Printer(
          address: 'addr',
          name: 'new name',
          isConnected: true,
        );

        final merged = Printer.mergeAdvertisementData(
          previous: previous,
          incoming: incoming,
        );

        expect(merged.name, 'new name');
        expect(merged.isConnected, true);
        expect(merged.services, previous.services);
      });
    });
  });
}
