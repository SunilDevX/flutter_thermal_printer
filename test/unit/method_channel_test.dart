import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer_method_channel.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelFlutterThermalPrinter', () {
    late MethodChannelFlutterThermalPrinter platform;
    const channel = MethodChannel('flutter_thermal_printer');

    final log = <MethodCall>[];

    setUp(() {
      platform = MethodChannelFlutterThermalPrinter();
      log.clear();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (methodCall) async {
            log.add(methodCall);

            switch (methodCall.method) {
              case 'getPlatformVersion':
                return 'Test Platform 1.0';
              case 'getUsbDevicesList':
                return [
                  {'name': 'Printer1', 'vendorId': '123', 'productId': '456'},
                  {'name': 'Printer2', 'vendorId': '789', 'productId': '012'},
                ];
              case 'connect':
                return true;
              case 'printText':
                return true;
              case 'isConnected':
                return true;
              case 'convertimage':
                return [1, 2, 3, 4];
              case 'disconnect':
                return true;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    group('getPlatformVersion', () {
      test('invokes correct method', () async {
        await platform.getPlatformVersion();

        expect(log.length, 1);
        expect(log.first.method, 'getPlatformVersion');
      });

      test('returns platform string', () async {
        final version = await platform.getPlatformVersion();
        expect(version, 'Test Platform 1.0');
      });
    });

    group('startUsbScan', () {
      test('invokes getUsbDevicesList', () async {
        await platform.startUsbScan();

        expect(log.length, 1);
        expect(log.first.method, 'getUsbDevicesList');
      });

      test('returns device list', () async {
        final devices = await platform.startUsbScan();

        expect(devices, isA<List>());
        expect(devices.length, 2);
        expect(devices[0]['name'], 'Printer1');
        expect(devices[1]['name'], 'Printer2');
      });
    });

    group('connect', () {
      test('invokes connect with printer JSON', () async {
        final printer = Printer(
          vendorId: '1234',
          productId: '5678',
          name: 'Test Printer',
          address: 'addr',
          connectionType: ConnectionType.USB,
        );

        await platform.connect(printer);

        expect(log.length, 1);
        expect(log.first.method, 'connect');
        expect(log.first.arguments, printer.toJson());
      });

      test('returns connection result', () async {
        final printer = Printer();
        final result = await platform.connect(printer);
        expect(result, true);
      });
    });

    group('printText', () {
      test('invokes printText with correct parameters', () async {
        final printer = Printer(
          vendorId: '1234',
          productId: '5678',
          name: 'Test Printer',
        );
        final data = Uint8List.fromList([27, 64, 10]);

        await platform.printText(printer, data, path: '/dev/usb0');

        expect(log.length, 1);
        expect(log.first.method, 'printText');
      });

      test('includes vendorId, productId, name, data, path', () async {
        final printer = Printer(
          vendorId: '1234',
          productId: '5678',
          name: 'Test Printer',
        );
        final data = Uint8List.fromList([27, 64, 10]);

        await platform.printText(printer, data, path: '/dev/usb0');

        final args = log.first.arguments as Map;
        expect(args['vendorId'], '1234');
        expect(args['productId'], '5678');
        expect(args['name'], 'Test Printer');
        expect(args['data'], [27, 64, 10]);
        expect(args['path'], '/dev/usb0');
      });

      test('uses empty string for null path', () async {
        final printer = Printer(
          vendorId: '1234',
          productId: '5678',
          name: 'Test Printer',
        );
        final data = Uint8List.fromList([1, 2, 3]);

        await platform.printText(printer, data);

        final args = log.first.arguments as Map;
        expect(args['path'], '');
      });

      test('treats a null native reply as a failed print', () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (methodCall) async => null);

        expect(
          await platform.printText(Printer(), Uint8List.fromList([1])),
          isFalse,
        );
      });

      test('converts Uint8List to List<int>', () async {
        final printer = Printer();
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        await platform.printText(printer, data);

        final args = log.first.arguments as Map;
        expect(args['data'], [1, 2, 3, 4, 5]);
        expect(args['data'], isList);
      });
    });

    group('isConnected', () {
      test('invokes isConnected with printer JSON', () async {
        final printer = Printer(vendorId: '1234', productId: '5678');

        await platform.isConnected(printer);

        expect(log.length, 1);
        expect(log.first.method, 'isConnected');
        expect(log.first.arguments, printer.toJson());
      });

      test('returns connection state', () async {
        final printer = Printer();
        final result = await platform.isConnected(printer);
        expect(result, true);
      });
    });

    group('convertImageToGrayscale', () {
      test('invokes convertimage with path data', () async {
        final data = Uint8List.fromList([255, 128, 64, 32]);

        await platform.convertImageToGrayscale(data);

        expect(log.length, 1);
        expect(log.first.method, 'convertimage');

        final args = log.first.arguments as Map;
        expect(args['path'], [255, 128, 64, 32]);
      });

      test('returns converted data', () async {
        final data = Uint8List.fromList([255, 128, 64, 32]);
        final result = await platform.convertImageToGrayscale(data);

        expect(result, [1, 2, 3, 4]);
      });
    });

    group('disconnect', () {
      test('invokes disconnect with vendorId and productId', () async {
        final printer = Printer(vendorId: '1234', productId: '5678');

        await platform.disconnect(printer);

        expect(log.length, 1);
        expect(log.first.method, 'disconnect');

        final args = log.first.arguments as Map;
        expect(args['vendorId'], '1234');
        expect(args['productId'], '5678');
      });

      test('returns disconnect result', () async {
        final printer = Printer();
        final result = await platform.disconnect(printer);
        expect(result, true);
      });
    });

    group('methodChannel', () {
      test('uses correct channel name', () {
        expect(platform.methodChannel.name, 'flutter_thermal_printer');
      });
    });
  });
}
