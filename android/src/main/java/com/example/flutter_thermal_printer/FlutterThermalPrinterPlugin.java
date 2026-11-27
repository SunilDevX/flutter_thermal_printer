package com.example.flutter_thermal_printer;

import android.content.Context;

import androidx.annotation.NonNull;

import java.util.List;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.EventChannel;

/** FlutterThermalPrinterPlugin */
public class FlutterThermalPrinterPlugin implements FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private MethodChannel channel;
  private EventChannel eventChannel;
  private Context context;
  private UsbPrinter usbPrinter;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_thermal_printer");
    eventChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "flutter_thermal_printer/events");
    channel.setMethodCallHandler(this);
    context = flutterPluginBinding.getApplicationContext();
    usbPrinter = new UsbPrinter(context); 
    eventChannel.setStreamHandler(usbPrinter);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
      switch (call.method) {
          case "getPlatformVersion":
              result.success("Android " + android.os.Build.VERSION.RELEASE);
              break;
          case "getUsbDevicesList":
              result.success(usbPrinter.getUsbDevicesList());
              break;
          case "connect": {
              String vendorId = call.argument("vendorId");
              String productId = call.argument("productId");
              result.success(usbPrinter.connect(vendorId, productId));
              break;
          }
          case "disconnect": {
              String vendorId = call.argument("vendorId");
              String productId = call.argument("productId");
              result.success(usbPrinter.disconnect(vendorId, productId));
              break;
          }
          case "printText": {
              String vendorId = call.argument("vendorId");
              String productId = call.argument("productId");
              List<Integer> data = call.argument("data");
              usbPrinter.printText(vendorId, productId, data);
              result.success(true);
              break;
          }
          case "isConnected": {
              String vendorId = call.argument("vendorId");
              String productId = call.argument("productId");
              result.success(usbPrinter.isConnected(vendorId, productId));
              break;
          }
          default:
              result.notImplemented();
              break;
      }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
  }
}
