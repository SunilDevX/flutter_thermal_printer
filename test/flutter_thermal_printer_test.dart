import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_method_channel.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterThermalPrinterPlatform
    with MockPlatformInterfaceMixin
    implements FlutterThermalPrinterPlatform {
  @override
  Future<String?> getPlatformVersion() async => '42';

  @override
  Future<dynamic> startUsbScan() async => [];

  @override
  Future<bool> connect(Printer device) async => true;

  @override
  Future<bool> printText(
    Printer device,
    Uint8List data, {
    String? path,
  }) async => true;

  @override
  Future<bool> isConnected(Printer device) async => false;

  @override
  Future<dynamic> convertImageToGrayscale(Uint8List? value) async => value;

  @override
  Future<bool> disconnect(Printer device) async => true;

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> getPrinters() async {}
}

void main() {
  final initialPlatform = FlutterThermalPrinterPlatform.instance;

  group('FlutterThermalPrinterPlatform', () {
    test('MethodChannelFlutterThermalPrinter is the default instance', () {
      expect(
        initialPlatform,
        isInstanceOf<MethodChannelFlutterThermalPrinter>(),
      );
    });
  });

  group('FlutterThermalPrinter', () {
    test('instance returns singleton', () {
      final instance1 = FlutterThermalPrinter.instance;
      final instance2 = FlutterThermalPrinter.instance;

      expect(identical(instance1, instance2), true);
    });

    test('instance is FlutterThermalPrinter type', () {
      expect(FlutterThermalPrinter.instance, isA<FlutterThermalPrinter>());
    });

    test('devicesStream is available', () {
      expect(
        FlutterThermalPrinter.instance.devicesStream,
        isA<Stream<List<Printer>>>(),
      );
    });

    test('isBleTurnedOnStream is available', () {
      expect(
        FlutterThermalPrinter.instance.isBleTurnedOnStream,
        isA<Stream<bool>>(),
      );
    });
  });

  group('Exports', () {
    test('ConnectionType is exported', () {
      expect(ConnectionType.BLE, isNotNull);
      expect(ConnectionType.USB, isNotNull);
      expect(ConnectionType.NETWORK, isNotNull);
    });

    test('Printer is exported', () {
      final printer = Printer(name: 'Test');
      expect(printer, isA<Printer>());
    });

    test('FlutterThermalPrinterNetwork is exported', () {
      final network = FlutterThermalPrinterNetwork('192.168.1.1');
      expect(network, isA<FlutterThermalPrinterNetwork>());
    });
  });
}
