import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';

import 'printer_manager.dart';
import 'utils/ble_config.dart';
import 'utils/printer.dart';

export 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
export 'package:flutter_thermal_printer/network/network_printer.dart';
export 'package:flutter_thermal_printer/utils/ble_config.dart';
export 'package:flutter_thermal_printer/utils/printer.dart';
export 'package:universal_ble/universal_ble.dart';

/// Main class for thermal printer operations across all platforms
///
/// This class provides a unified interface for printing operations
/// on Windows (USB/BLE) and other platforms (Android/iOS/macOS).
class FlutterThermalPrinter {
  FlutterThermalPrinter._({BleConfig bleConfig = const BleConfig()})
    : _bleConfig = bleConfig;

  // ==========================================================================
  // STATIC VARIABLES AND INSTANCE
  // ==========================================================================

  static FlutterThermalPrinter? _instance;

  // ignore: prefer_constructors_over_static_methods
  static FlutterThermalPrinter get instance {
    _instance ??= FlutterThermalPrinter._();
    return _instance!;
  }

  // ==========================================================================
  // BLE CONFIGURATION
  // ==========================================================================

  BleConfig _bleConfig;

  BleConfig get bleConfig => _bleConfig;

  set bleConfig(BleConfig config) {
    _bleConfig = config;
    PrinterManager.instance.bleConfig = config;
  }

  // ==========================================================================
  // STREAMS AND GETTERS
  // ==========================================================================

  /// Stream of available printers
  Stream<List<Printer>> get devicesStream =>
      PrinterManager.instance.devicesStream;

  /// Stream to monitor Bluetooth state
  Stream<bool> get isBleTurnedOnStream =>
      PrinterManager.instance.isBleTurnedOnStream;

  // ==========================================================================
  // PUBLIC METHODS - CORE PRINTER OPERATIONS
  // ==========================================================================

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
  }) async => PrinterManager.instance.connect(
    device,
    connectionTimeout: connectionTimeout ?? connectionStabilizationDelay,
  );

  /// Disconnect from a printer device
  Future<void> disconnect(Printer device) async {
    await PrinterManager.instance.disconnect(device);
  }

  /// Print raw data to printer. Returns whether all bytes reached the printer.
  ///
  /// [device] The printer device to print to.
  /// [bytes] The raw bytes to print.
  /// [longData] Adds a 10 ms pause between BLE writes.
  /// [chunkSize] Bytes per BLE write. Defaults to the negotiated MTU minus 3.
  Future<bool> printData(
    Printer device,
    List<int> bytes, {
    bool longData = false,
    int? chunkSize,
  }) async => PrinterManager.instance.printData(
    device,
    bytes,
    longData: longData,
    chunkSize: chunkSize,
  );

  /// Get available printers. NETWORK includes installed macOS print queues;
  /// it does not scan the LAN for uninstalled printers or imply ESC/POS support.
  Future<void> getPrinters({
    Duration refreshDuration = const Duration(seconds: 2),
    List<ConnectionType> connectionTypes = const [
      ConnectionType.USB,
      ConnectionType.BLE,
      ConnectionType.NETWORK,
    ],
    bool androidUsesFineLocation = false,
  }) async {
    await PrinterManager.instance.getPrinters(
      refreshDuration: refreshDuration,
      connectionTypes: connectionTypes,
      androidUsesFineLocation: androidUsesFineLocation,
    );
  }

  /// Stop scanning for printers
  Future<void> stopScan() async {
    await PrinterManager.instance.stopScan();
  }

  /// Turn on Bluetooth
  Future<void> turnOnBluetooth() async {
    await PrinterManager.instance.turnOnBluetooth();
  }

  /// Check if Bluetooth is turned on
  Future<bool> isBleTurnedOn() async => PrinterManager.instance.isBleTurnedOn();

  // ==========================================================================
  // ADVANCED PRINTING METHODS
  // ==========================================================================

  /// Optimized screen capture and conversion to printer-ready bytes
  Future<Uint8List> screenShotWidget(
    BuildContext context, {
    required Widget widget,
    Duration delay = const Duration(milliseconds: 100),
    int? customWidth,
    PaperSize paperSize = PaperSize.mm80,
    Generator? generator,
  }) async {
    final controller = ScreenshotController();

    try {
      final image = await controller.captureFromLongWidget(
        widget,
        pixelRatio: View.of(context).devicePixelRatio,
        delay: delay,
      );

      final profile = await CapabilityProfile.load();
      final generator0 = generator ?? Generator(paperSize, profile);

      var imagebytes = img.decodeImage(image);
      if (imagebytes == null) {
        throw Exception('Failed to decode captured image');
      }

      // Apply custom width if specified
      if (customWidth != null) {
        final width = _makeDivisibleBy8(customWidth);
        imagebytes = img.copyResize(imagebytes, width: width);
      }

      // Ensure image width is compatible with thermal printers
      imagebytes = _buildImageRasterAvailable(imagebytes);
      imagebytes = img.grayscale(imagebytes);

      // Process image in optimized chunks
      return _processImageInChunks(imagebytes, generator0);
    } catch (e) {
      throw Exception('Failed to capture widget screenshot: $e');
    }
  }

  /// Captures [widget] as an image and prints it. Returns whether the image
  /// (and the cut, if requested) reached the printer. Throws if the widget
  /// cannot be captured.
  Future<bool> printWidget(
    BuildContext context, {
    required Printer printer,
    required Widget widget,
    Duration delay = const Duration(milliseconds: 10),
    PaperSize paperSize = PaperSize.mm80,
    CapabilityProfile? profile,
    bool cutAfterPrinted = true,
    int? chunkSize,
  }) async {
    final controller = ScreenshotController();

    try {
      final image = await controller.captureFromLongWidget(
        widget,
        pixelRatio: View.of(context).devicePixelRatio,
        delay: delay,
      );

      return await _printChunkedWidget(
        image,
        printer,
        paperSize,
        profile,
        cutAfterPrinted,
        chunkSize: chunkSize,
      );
    } catch (e) {
      throw Exception('Failed to print widget: $e');
    }
  }

  // ==========================================================================
  // PRIVATE HELPER METHODS
  // ==========================================================================

  /// Process image in optimized chunks for better memory management
  /// Skip chunking for macOS platform
  Uint8List _processImageInChunks(img.Image image, Generator generator) {
    // For other platforms, use chunked approach
    const chunkHeight = 30;
    final totalHeight = image.height;
    final totalWidth = image.width;
    final chunksCount = (totalHeight / chunkHeight).ceil();

    final bytes = <int>[];

    for (var i = 0; i < chunksCount; i++) {
      final startY = i * chunkHeight;
      final endY = (startY + chunkHeight > totalHeight)
          ? totalHeight
          : startY + chunkHeight;
      final actualHeight = endY - startY;

      final croppedImage = img.copyCrop(
        image,
        x: 0,
        y: startY,
        width: totalWidth,
        height: actualHeight,
      );

      final raster = generator.imageRaster(croppedImage);
      bytes.addAll(raster);
    }

    return Uint8List.fromList(bytes);
  }

  /// Ensure image width is compatible with thermal printers (divisible by 8)
  img.Image _buildImageRasterAvailable(img.Image image) {
    if (image.width % 8 == 0) {
      return image;
    }
    final newWidth = _makeDivisibleBy8(image.width);
    return img.copyResize(image, width: newWidth);
  }

  /// Make number divisible by 8 for printer compatibility
  int _makeDivisibleBy8(int number) {
    if (number % 8 == 0) {
      return number;
    }
    return number + (8 - (number % 8));
  }

  /// Print widget using chunked approach for better memory management
  /// Skip chunking for macOS platform
  Future<bool> _printChunkedWidget(
    Uint8List image,
    Printer printer,
    PaperSize paperSize,
    CapabilityProfile? profile,
    bool cutAfterPrinted, {
    int? chunkSize,
  }) async {
    final profile0 = profile ?? await CapabilityProfile.load();
    final ticket = Generator(paperSize, profile0);

    var imagebytes = img.decodeImage(image);
    if (imagebytes == null) {
      throw Exception('Failed to decode image for chunked printing');
    }

    imagebytes = _buildImageRasterAvailable(imagebytes);

    if ((Platform.isMacOS && printer.isSystemPrinter) ||
        ((Platform.isMacOS || Platform.isWindows) &&
            printer.connectionType == ConnectionType.USB)) {
      List<int> raster;
      raster = ticket.imageRaster(imagebytes);
      if (cutAfterPrinted) {
        raster += ticket.cut();
      }
      return printData(printer, raster, longData: true, chunkSize: chunkSize);
    } else {
      // For other platforms, use chunked approach
      const chunkHeight = 30;
      final totalHeight = imagebytes.height;
      final totalWidth = imagebytes.width;
      final chunksCount = (totalHeight / chunkHeight).ceil();
      var raster = <int>[];
      // Print image in chunks
      for (var i = 0; i < chunksCount; i++) {
        final startY = i * chunkHeight;
        final endY = (startY + chunkHeight > totalHeight)
            ? totalHeight
            : startY + chunkHeight;
        final actualHeight = endY - startY;

        final croppedImage = img.copyCrop(
          imagebytes,
          x: 0,
          y: startY,
          width: totalWidth,
          height: actualHeight,
        );

        raster += ticket.imageRaster(croppedImage);
      }
      // One job, so another print cannot land between the image and its cut.
      if (cutAfterPrinted) {
        raster += ticket.cut();
      }
      return printData(printer, raster, longData: true, chunkSize: chunkSize);
    }
  }
}
