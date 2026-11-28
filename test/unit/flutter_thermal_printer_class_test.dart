import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';

import '../mocks/mock_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterThermalPrinter', () {
    late MockFlutterThermalPrinterPlatform mockPlatform;
    late FlutterThermalPrinterPlatform originalPlatform;

    setUp(() {
      originalPlatform = FlutterThermalPrinterPlatform.instance;
      mockPlatform = MockFlutterThermalPrinterPlatform();
      FlutterThermalPrinterPlatform.instance = mockPlatform;
    });

    tearDown(() {
      FlutterThermalPrinterPlatform.instance = originalPlatform;
      mockPlatform.reset();
    });

    group('singleton', () {
      test('instance returns same object every time', () {
        final instance1 = FlutterThermalPrinter.instance;
        final instance2 = FlutterThermalPrinter.instance;
        final instance3 = FlutterThermalPrinter.instance;

        expect(identical(instance1, instance2), true);
        expect(identical(instance2, instance3), true);
      });

      test('instance is FlutterThermalPrinter type', () {
        expect(FlutterThermalPrinter.instance, isA<FlutterThermalPrinter>());
      });
    });

    group('streams', () {
      test('devicesStream is a broadcast stream', () {
        final stream = FlutterThermalPrinter.instance.devicesStream;
        expect(stream.isBroadcast, true);
      });

      test('devicesStream emits List<Printer>', () async {
        final stream = FlutterThermalPrinter.instance.devicesStream;
        expect(stream, isA<Stream<List<Printer>>>());
      });

      test('isBleTurnedOnStream is available', () {
        final stream = FlutterThermalPrinter.instance.isBleTurnedOnStream;
        expect(stream, isA<Stream<bool>>());
      });
    });

    group('connect', () {
      test('returns false for printer with null connection type', () async {
        final printer = Printer(name: 'Test');
        final result = await FlutterThermalPrinter.instance.connect(printer);
        expect(result, false);
      });

      test('returns false for BLE printer without address', () async {
        final printer = Printer(
          name: 'Test',
          connectionType: ConnectionType.BLE,
        );
        final result = await FlutterThermalPrinter.instance.connect(printer);
        expect(result, false);
      });
    });

    group('disconnect', () {
      test('handles null connection type gracefully', () async {
        final printer = Printer(name: 'Test');
        await FlutterThermalPrinter.instance.disconnect(printer);
      });

      test('handles USB printer', () async {
        final printer = Printer(
          name: 'Test',
          connectionType: ConnectionType.USB,
          vendorId: '123',
          productId: '456',
        );
        await FlutterThermalPrinter.instance.disconnect(printer);
      });
    });

    group('stopScan', () {
      test('can be called without error', () async {
        await FlutterThermalPrinter.instance.stopScan();
      });
    });

    group('getPrinters', () {
      test('throws when empty connectionTypes provided', () async {
        expect(
          () => FlutterThermalPrinter.instance.getPrinters(connectionTypes: []),
          throwsException,
        );
      });
    });

    group('bleConfig', () {
      test('has default config with 10 second delay', () {
        final config = FlutterThermalPrinter.instance.bleConfig;
        expect(config.connectionTimeout, const Duration(seconds: 10));
      });

      test('bleConfig setter updates the configuration', () {
        final originalConfig = FlutterThermalPrinter.instance.bleConfig;

        FlutterThermalPrinter.instance.bleConfig = const BleConfig(
          connectionTimeout: Duration(seconds: 5),
        );

        final newConfig = FlutterThermalPrinter.instance.bleConfig;
        expect(newConfig.connectionTimeout, const Duration(seconds: 5));

        FlutterThermalPrinter.instance.bleConfig = originalConfig;
      });

      test('bleConfig getter returns current config', () {
        final config1 = FlutterThermalPrinter.instance.bleConfig;
        final config2 = FlutterThermalPrinter.instance.bleConfig;
        expect(config1.connectionTimeout, config2.connectionTimeout);
      });
    });
  });

  group('Exports verification', () {
    test('Generator is exported from esc_pos_utils_plus', () {
      expect(Generator, isNotNull);
    });

    test('PaperSize is exported', () {
      expect(PaperSize.mm58, isNotNull);
      expect(PaperSize.mm80, isNotNull);
    });

    test('CapabilityProfile is exported', () async {
      final profile = await CapabilityProfile.load();
      expect(profile, isNotNull);
    });

    test('PosStyles is exported', () {
      const styles = PosStyles();
      expect(styles, isNotNull);
    });

    test('PosAlign is exported', () {
      expect(PosAlign.left, isNotNull);
      expect(PosAlign.center, isNotNull);
      expect(PosAlign.right, isNotNull);
    });

    test('PosTextSize is exported', () {
      expect(PosTextSize.size1, isNotNull);
      expect(PosTextSize.size2, isNotNull);
    });

    test('PosColumn is exported', () {
      final column = PosColumn(text: 'Test', width: 6);
      expect(column, isNotNull);
    });

    test('FlutterThermalPrinterNetwork is exported', () {
      final network = FlutterThermalPrinterNetwork('127.0.0.1');
      expect(network, isNotNull);
    });

    test('BleConfig is exported', () {
      const config = BleConfig();
      expect(config, isNotNull);
      expect(config.connectionTimeout, const Duration(seconds: 10));
    });
  });
}
