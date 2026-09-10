import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:flutter_thermal_printer/printer_manager.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import '../mocks/mock_platform.dart';

Map<String, dynamic> queue(String name, String? uri) => {
  'name': name,
  'address': name,
  'queueName': name,
  'deviceUri': uri,
  'vendorId': '1234',
  'productId': '1000',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'classifies destination URIs without assuming unknown devices are BLE',
    () {
      expect(
        Printer.connectionTypeFromDeviceUri('usb://printer/model'),
        ConnectionType.USB,
      );
      for (final scheme in [
        'dnssd',
        'ipp',
        'ipps',
        'http',
        'https',
        'socket',
        'lpd',
        'smb',
        'IPPS',
      ]) {
        expect(
          Printer.connectionTypeFromDeviceUri('$scheme://printer/queue'),
          ConnectionType.NETWORK,
        );
      }
      for (final uri in [
        null,
        '',
        'invalid',
        'file:///tmp/print',
        'bluetooth://id',
      ]) {
        expect(Printer.connectionTypeFromDeviceUri(uri), isNull);
      }
    },
  );

  test(
    'system queue metadata survives serialization and connection updates',
    () {
      final printer = Printer.fromJson(
        queue('Brother', 'dnssd://Brother._ipps._tcp.local./'),
      );
      final restored = Printer.fromJson(
        printer.copyWith(isConnected: true).toJson(),
      );
      expect(restored.connectionType, ConnectionType.NETWORK);
      expect(restored.deviceUri, printer.deviceUri);
      expect(restored.queueName, 'Brother');
      expect(restored.address, 'Brother');
      expect(restored.isConnected, isTrue);
      expect(restored.isSystemPrinter, isTrue);
      expect(restored.hasValidConnectionData, isTrue);
      expect(
        Printer.fromJson(queue('Unknown', null)).connectionTypeString,
        'UNKNOWN',
      );
    },
  );

  group('macOS queue discovery and routing', () {
    final manager = PrinterManager.instance;
    late FlutterThermalPrinterPlatform originalPlatform;
    late MockFlutterThermalPrinterPlatform platform;
    late StreamSubscription<List<Printer>> subscription;
    late List<List<Printer>> snapshots;

    setUp(() {
      originalPlatform = FlutterThermalPrinterPlatform.instance;
      platform = MockFlutterThermalPrinterPlatform()
        ..usbDevicesToReturn = [
          queue('Brother', 'dnssd://Brother._ipps._tcp.local./'),
          queue('USB printer', 'usb://printer/model'),
          queue('Unknown', null),
        ];
      FlutterThermalPrinterPlatform.instance = platform;
      snapshots = [];
      subscription = manager.devicesStream.listen(snapshots.add);
    });

    tearDown(() async {
      await manager.stopScan(stopBle: false);
      await subscription.cancel();
      FlutterThermalPrinterPlatform.instance = originalPlatform;
    });

    test('filters network and USB queues when restarting discovery', () async {
      await manager.getPrinters(connectionTypes: [ConnectionType.NETWORK]);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((p) => p.name), ['Brother']);

      await manager.getPrinters(connectionTypes: [ConnectionType.USB]);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((p) => p.name), ['USB printer']);

      await manager.getPrinters(
        connectionTypes: [ConnectionType.USB, ConnectionType.NETWORK],
      );
      await Future<void>.delayed(Duration.zero);
      expect(snapshots.last.map((p) => p.connectionTypeString), [
        'NETWORK',
        'USB',
        'UNKNOWN',
      ]);
    });

    test(
      'refresh replaces removed queues and changed connection types',
      () async {
        await manager.getPrinters(
          connectionTypes: [ConnectionType.USB, ConnectionType.NETWORK],
          refreshDuration: const Duration(milliseconds: 20),
        );
        final refreshed = manager.devicesStream.firstWhere(
          (printers) =>
              printers.length == 1 &&
              printers.single.name == 'Brother' &&
              printers.single.connectionType == ConnectionType.USB,
        );
        platform.usbDevicesToReturn = [queue('Brother', 'usb://Brother/model')];
        final printers = await refreshed.timeout(const Duration(seconds: 2));
        expect(printers.single.deviceUri, 'usb://Brother/model');
      },
    );

    test(
      'network and unknown queues retain native connection and print routing',
      () async {
        for (final uri in ['ipps://brother/ipp/print', null]) {
          final printer = Printer.fromJson(queue('Brother', uri));
          platform.isConnectedResult = true;
          expect(await manager.connect(printer), isTrue);
          expect(await manager.isConnected(printer), isTrue);
          await manager.printData(printer, [27, 64]);
          expect(platform.methodCalls, ['connect', 'isConnected', 'printText']);
          final printArgs = platform.methodArguments.last as Map;
          expect(printArgs['device'], same(printer));
          expect(printArgs['data'], [27, 64]);
          platform.reset();
        }
        // A raw network endpoint is not a macOS queue.
        expect(
          await manager.connect(
            Printer(
              address: '192.0.2.1',
              connectionType: ConnectionType.NETWORK,
            ),
          ),
          isFalse,
        );
        expect(platform.methodCalls, isEmpty);
      },
    );
  }, skip: !Platform.isMacOS);
}
