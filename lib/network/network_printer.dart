import 'dart:io';
import 'network_print_result.dart';

/// Optimized network thermal printer with improved connection management
class FlutterThermalPrinterNetwork {
  FlutterThermalPrinterNetwork(
    String host, {
    int port = 9100,
    Duration timeout = const Duration(seconds: 5),
  }) : _host = host,
       _port = port,
       _timeout = timeout;
  final String _host;
  final int _port;
  final Duration _timeout;

  bool _isConnected = false;
  Socket? _socket;

  /// Connect to network printer with improved error handling
  Future<NetworkPrintResult> connect({Duration? timeout}) async {
    if (_isConnected && _socket != null) {
      return NetworkPrintResult.success;
    }

    try {
      _socket = await Socket.connect(
        _host,
        _port,
        timeout: timeout ?? _timeout,
      );
      _isConnected = true;
      return NetworkPrintResult.success;
    } on SocketException {
      _isConnected = false;
      return NetworkPrintResult.timeout;
    } catch (e) {
      _isConnected = false;
      return NetworkPrintResult.timeout;
    }
  }

  Future<void> _printQueue = Future<void>.value();

  /// Print data with automatic connection management. Tickets sent to one
  /// instance print one after another, never interleaved.
  Future<NetworkPrintResult> printTicket(
    List<int> data, {
    bool isDisconnect = true,
  }) {
    final job = _printQueue.then(
      (_) => _printTicket(data, isDisconnect: isDisconnect),
    );
    _printQueue = job.then<void>((_) {}, onError: (_) {});
    return job;
  }

  Future<NetworkPrintResult> _printTicket(
    List<int> data, {
    required bool isDisconnect,
  }) async {
    try {
      if (!_isConnected || _socket == null) {
        final connectResult = await connect();
        if (connectResult != NetworkPrintResult.success) {
          return connectResult;
        }
      }

      _socket!.add(data);
      await _socket!.flush();

      if (isDisconnect) {
        await disconnect();
      }

      return NetworkPrintResult.success;
    } on SocketException {
      _isConnected = false;
      return NetworkPrintResult.timeout;
    } catch (e) {
      return NetworkPrintResult.timeout;
    }
  }

  /// Disconnect with proper resource cleanup
  Future<NetworkPrintResult> disconnect({Duration? timeout}) async {
    try {
      if (_socket != null) {
        await _socket!.flush();
        await _socket!.close();
        _socket = null;
      }
      _isConnected = false;

      if (timeout != null) {
        await Future.delayed(timeout);
      }

      return NetworkPrintResult.success;
    } catch (e) {
      _isConnected = false;
      _socket = null;
      return NetworkPrintResult.success; // Still consider it successful cleanup
    }
  }

  /// Check if currently connected
  bool get isConnected => _isConnected && _socket != null;

  /// Get connection info
  String get connectionInfo => '$_host:$_port';
}
