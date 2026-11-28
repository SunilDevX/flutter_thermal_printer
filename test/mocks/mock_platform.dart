import 'dart:typed_data';

import 'package:flutter_thermal_printer/flutter_thermal_printer_platform_interface.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterThermalPrinterPlatform extends FlutterThermalPrinterPlatform
    with MockPlatformInterfaceMixin {
  String? platformVersionToReturn = 'Mock Platform 1.0';
  List<Map<String, dynamic>>? usbDevicesToReturn;
  bool connectResult = true;
  bool isConnectedResult = false;
  bool disconnectResult = true;
  bool printTextResult = true;
  Duration printTextDelay = Duration.zero;
  dynamic convertImageResult;

  /// `start <first byte>` / `end <first byte>` per printText call, in order.
  final List<String> printLog = [];

  final List<String> methodCalls = [];
  final List<dynamic> methodArguments = [];

  void reset() {
    methodCalls.clear();
    methodArguments.clear();
    platformVersionToReturn = 'Mock Platform 1.0';
    usbDevicesToReturn = null;
    connectResult = true;
    isConnectedResult = false;
    disconnectResult = true;
    printTextResult = true;
    printTextDelay = Duration.zero;
    printLog.clear();
    convertImageResult = null;
  }

  @override
  Future<String?> getPlatformVersion() async {
    methodCalls.add('getPlatformVersion');
    return platformVersionToReturn;
  }

  @override
  Future<dynamic> startUsbScan() async {
    methodCalls.add('startUsbScan');
    return usbDevicesToReturn ?? [];
  }

  @override
  Future<bool> connect(Printer device) async {
    methodCalls.add('connect');
    methodArguments.add(device);
    return connectResult;
  }

  @override
  Future<bool> isConnected(Printer device) async {
    methodCalls.add('isConnected');
    methodArguments.add(device);
    return isConnectedResult;
  }

  @override
  Future<bool> disconnect(Printer device) async {
    methodCalls.add('disconnect');
    methodArguments.add(device);
    return disconnectResult;
  }

  @override
  Future<bool> printText(Printer device, Uint8List data, {String? path}) async {
    methodCalls.add('printText');
    methodArguments.add({'device': device, 'data': data, 'path': path});
    printLog.add('start ${data.first}');
    await Future<void>.delayed(printTextDelay);
    printLog.add('end ${data.first}');
    return printTextResult;
  }

  @override
  Future<dynamic> convertImageToGrayscale(Uint8List? value) async {
    methodCalls.add('convertImageToGrayscale');
    methodArguments.add(value);
    return convertImageResult ?? value;
  }

  @override
  Future<void> stopScan() async {
    methodCalls.add('stopScan');
  }

  @override
  Future<void> getPrinters() async {
    methodCalls.add('getPrinters');
  }
}
