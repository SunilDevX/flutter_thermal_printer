import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/network/network_print_result.dart';
import 'package:flutter_thermal_printer/network/network_printer.dart';

void main() {
  group('FlutterThermalPrinterNetwork', () {
    group('constructor', () {
      test('sets host correctly', () {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');
        expect(printer.connectionInfo, startsWith('192.168.1.100'));
      });

      test('uses default port 9100', () {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');
        expect(printer.connectionInfo, '192.168.1.100:9100');
      });

      test('uses custom port', () {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.1.100',
          port: 8080,
        );
        expect(printer.connectionInfo, '192.168.1.100:8080');
      });

      test('accepts all parameters', () {
        final printer = FlutterThermalPrinterNetwork(
          '10.0.0.1',
          port: 9200,
          timeout: const Duration(seconds: 3),
        );
        expect(printer.connectionInfo, '10.0.0.1:9200');
      });
    });

    group('connectionInfo', () {
      test('returns host:port format', () {
        final printer = FlutterThermalPrinterNetwork(
          '10.0.0.1',
          port: 1234,
        );
        expect(printer.connectionInfo, '10.0.0.1:1234');
      });

      test('handles various hosts', () {
        expect(
          FlutterThermalPrinterNetwork('localhost').connectionInfo,
          'localhost:9100',
        );
        expect(
          FlutterThermalPrinterNetwork('0.0.0.0').connectionInfo,
          '0.0.0.0:9100',
        );
        expect(
          FlutterThermalPrinterNetwork('printer.local', port: 80)
              .connectionInfo,
          'printer.local:80',
        );
      });
    });

    group('isConnected', () {
      test('returns false initially', () {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');
        expect(printer.isConnected, false);
      });

      test('returns false after failed connection', () async {
        final printer = FlutterThermalPrinterNetwork(
          '999.999.999.999',
          timeout: const Duration(milliseconds: 50),
        );
        await printer.connect();
        expect(printer.isConnected, false);
      });

      test('returns false after disconnect', () async {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');
        await printer.disconnect();
        expect(printer.isConnected, false);
      });
    });

    group('connect', () {
      test('returns timeout on invalid host', () async {
        final printer = FlutterThermalPrinterNetwork(
          '999.999.999.999',
          timeout: const Duration(milliseconds: 100),
        );

        final result = await printer.connect();
        expect(result, NetworkPrintResult.timeout);
      });

      test('returns timeout with short timeout on unreachable host', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        final result = await printer.connect(
          timeout: const Duration(milliseconds: 50),
        );
        expect(result, NetworkPrintResult.timeout);
        expect(printer.isConnected, false);
      });

      test('uses default timeout when none provided', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        final result = await printer.connect();
        expect(result, NetworkPrintResult.timeout);
      });

      test('can override timeout in connect call', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(seconds: 30),
        );

        final result = await printer.connect(
          timeout: const Duration(milliseconds: 10),
        );
        expect(result, NetworkPrintResult.timeout);
      });
    });

    group('disconnect', () {
      test('returns success when not connected', () async {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');

        final result = await printer.disconnect();
        expect(result, NetworkPrintResult.success);
        expect(printer.isConnected, false);
      });

      test('returns success with timeout parameter', () async {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');

        final result = await printer.disconnect(
          timeout: const Duration(milliseconds: 10),
        );
        expect(result, NetworkPrintResult.success);
      });

      test('can be called multiple times safely', () async {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');

        final result1 = await printer.disconnect();
        final result2 = await printer.disconnect();
        final result3 = await printer.disconnect();

        expect(result1, NetworkPrintResult.success);
        expect(result2, NetworkPrintResult.success);
        expect(result3, NetworkPrintResult.success);
      });

      test('sets isConnected to false', () async {
        final printer = FlutterThermalPrinterNetwork('192.168.1.100');

        await printer.disconnect();
        expect(printer.isConnected, false);
      });
    });

    group('printTicket', () {
      test('attempts to connect if not connected', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        final result = await printer.printTicket([1, 2, 3]);

        expect(result, NetworkPrintResult.timeout);
      });

      test('respects isDisconnect parameter default true', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        await printer.printTicket([1, 2, 3]);
        expect(printer.isConnected, false);
      });

      test('respects isDisconnect false', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        await printer.printTicket([1, 2, 3], isDisconnect: false);
        expect(printer.isConnected, false);
      });

      test('handles large data array', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        final largeData = List.generate(10000, (i) => i % 256);
        final result = await printer.printTicket(largeData);
        expect(result, NetworkPrintResult.timeout);
      });

      test('tickets sent at once arrive whole and in order', () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);
        final received = <Future<List<int>>>[];
        server.listen(
          (client) => received.add(
            client.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
          ),
        );
        final printer = FlutterThermalPrinterNetwork(
          InternetAddress.loopbackIPv4.address,
          port: server.port,
        );

        final results = await Future.wait([
          printer.printTicket(List.filled(50000, 1)),
          printer.printTicket(List.filled(50000, 2)),
        ]);

        expect(results, [NetworkPrintResult.success, NetworkPrintResult.success]);
        final tickets = await Future.wait(received);
        expect(tickets, [List.filled(50000, 1), List.filled(50000, 2)]);
      });
    });

    group('edge cases', () {
      test('handles empty data', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 50),
        );

        final result = await printer.printTicket([]);
        expect(result, NetworkPrintResult.timeout);
      });

      test('handles localhost', () {
        final printer = FlutterThermalPrinterNetwork('127.0.0.1');
        expect(printer.connectionInfo, '127.0.0.1:9100');
      });

      test('handles hostname', () {
        final printer = FlutterThermalPrinterNetwork('printer.local');
        expect(printer.connectionInfo, 'printer.local:9100');
      });

      test('handles IPv6 address format', () {
        final printer = FlutterThermalPrinterNetwork('::1');
        expect(printer.connectionInfo, '::1:9100');
      });

      test('handles minimum port', () {
        final printer = FlutterThermalPrinterNetwork('host', port: 1);
        expect(printer.connectionInfo, 'host:1');
      });

      test('handles maximum port', () {
        final printer = FlutterThermalPrinterNetwork('host', port: 65535);
        expect(printer.connectionInfo, 'host:65535');
      });

      test('handles zero timeout', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: Duration.zero,
        );

        final result = await printer.connect();
        expect(result, NetworkPrintResult.timeout);
      });
    });

    group('multiple operations', () {
      test('can connect and disconnect multiple times', () async {
        final printer = FlutterThermalPrinterNetwork(
          '192.168.255.255',
          timeout: const Duration(milliseconds: 20),
        );

        await printer.connect();
        await printer.disconnect();
        await printer.connect();
        await printer.disconnect();

        expect(printer.isConnected, false);
      });

      test('disconnect after failed connect', () async {
        final printer = FlutterThermalPrinterNetwork(
          '999.999.999.999',
          timeout: const Duration(milliseconds: 20),
        );

        await printer.connect();
        expect(printer.isConnected, false);

        final result = await printer.disconnect();
        expect(result, NetworkPrintResult.success);
      });
    });
  });
}
