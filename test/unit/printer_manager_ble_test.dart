import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/printer_manager.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:universal_ble/universal_ble.dart';

import '../mocks/fake_ble_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = PrinterManager.instance;
  late FakeBlePlatform ble;
  // The manager is a singleton that keeps its list, so each test gets its
  // own device ID.
  var testIndex = 0;
  late String id;

  Printer printerFor(String address) => Printer(
    address: address,
    name: 'BLE Printer',
    connectionType: ConnectionType.BLE,
  );

  setUp(() {
    ble = FakeBlePlatform();
    UniversalBle.setInstance(ble);
    // A command queued under fake time would block the real-time ones.
    UniversalBle.queueType = QueueType.none;
    id = 'aa:bb:cc:dd:ee:${(testIndex++).toRadixString(16).padLeft(2, '0')}';
  });

  tearDown(manager.stopScan);

  group('connect', () {
    test('returns true once the printer connects', () async {
      expect(await manager.connect(printerFor(id)), isTrue);
      expect(await manager.isConnected(printerFor(id)), isTrue);
    });

    test('returns false when the printer does not connect in time', () async {
      ble.connectSucceeds = false;
      expect(
        await manager.connect(
          printerFor(id),
          connectionTimeout: const Duration(milliseconds: 50),
        ),
        isFalse,
      );
    });
  });

  group('getPrinters', () {
    for (final state in [
      AvailabilityState.poweredOff,
      AvailabilityState.unauthorized,
      AvailabilityState.unsupported,
    ]) {
      test('throws when Bluetooth is ${state.name}', () {
        ble.availability = state;
        expect(
          manager.getPrinters(connectionTypes: [ConnectionType.BLE]),
          throwsException,
        );
      });
    }

    test('repeated advertisements emit the list once', () async {
      await manager.getPrinters(connectionTypes: [ConnectionType.BLE]);
      final stateCallsBefore = ble.getConnectionStateCalls;
      final lists = <List<Printer>>[];
      final subscription = manager.devicesStream.listen(lists.add);

      ble.advertise(id, 'Printer A');
      await pumpEventQueue();
      ble
        ..advertise(id, 'Printer A')
        ..advertise(id, 'Printer A');
      await pumpEventQueue();
      await subscription.cancel();

      expect(lists, hasLength(1));
      expect(lists.single.where((p) => p.address == id), hasLength(1));
      expect(ble.getConnectionStateCalls - stateCallsBefore, 1);
    });

    test('drops a disconnected printer that stops advertising', () {
      fakeAsync((async) {
        var latest = <Printer>[];
        final subscription = manager.devicesStream.listen(
          (list) => latest = list,
        );
        unawaited(manager.getPrinters(connectionTypes: [ConnectionType.BLE]));
        async.flushMicrotasks();
        ble.advertise(id, 'Printer B');
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 20));
        expect(latest.any((p) => p.address == id), isTrue);

        async.elapse(const Duration(seconds: 20));
        expect(latest.any((p) => p.address == id), isFalse);
        unawaited(subscription.cancel());
        unawaited(manager.stopScan());
        // Let the scan stop fully under fake time, or tearDown waits on it.
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('keeps a connected printer that stops advertising', () {
      fakeAsync((async) {
        var latest = <Printer>[];
        final subscription = manager.devicesStream.listen(
          (list) => latest = list,
        );
        unawaited(manager.getPrinters(connectionTypes: [ConnectionType.BLE]));
        async.flushMicrotasks();
        ble.advertise(id, 'Printer C');
        async.flushMicrotasks();
        ble
          ..connected.add(id)
          ..updateConnection(id, true);
        async.elapse(const Duration(seconds: 40));
        expect(latest.any((p) => p.address == id), isTrue);
        unawaited(subscription.cancel());
        unawaited(manager.stopScan());
        // Let the scan stop fully under fake time, or tearDown waits on it.
        async.elapse(const Duration(seconds: 1));
      });
    });
  });

  group('printData over BLE', () {
    test('negotiates services and MTU once per connection', () async {
      ble.mtu = 30;
      final printer = printerFor(id);
      await manager.connect(printer);

      expect(await manager.printData(printer, List.filled(60, 1)), isTrue);
      expect(await manager.printData(printer, List.filled(60, 2)), isTrue);

      expect(ble.discoverServicesCalls, 1);
      expect(ble.requestMtuCalls, 1);
      expect(ble.writes.map((w) => w.length), [27, 27, 6, 27, 27, 6]);
    }, skip: Platform.isWindows);

    test('negotiates again after a reconnect', () async {
      final printer = printerFor(id);
      await manager.connect(printer);
      await manager.printData(printer, [1]);
      await manager.disconnect(printer);
      await manager.connect(printer);
      await manager.printData(printer, [2]);

      expect(ble.discoverServicesCalls, 2);
    });

    test('falls back to 20-byte writes when the MTU request fails', () async {
      ble.mtuFails = true;
      final printer = printerFor(id);
      await manager.connect(printer);

      expect(await manager.printData(printer, List.filled(45, 1)), isTrue);
      expect(ble.writes.map((w) => w.length), [20, 20, 5]);
    }, skip: Platform.isWindows);
  });

  group('isBleTurnedOnStream', () {
    test('emits the current state, then each change', () async {
      final states = <bool>[];
      final subscription = manager.isBleTurnedOnStream.listen(states.add);
      await pumpEventQueue();
      ble.setAvailability(AvailabilityState.poweredOff);
      await pumpEventQueue();
      await subscription.cancel();

      expect(states, [true, false]);
    });
  });
}
