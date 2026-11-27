import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_thermal_printer/utils/ble_config.dart';

void main() {
  group('BleConfig', () {
    group('constructor', () {
      test('uses default connectionTimeout of 10 seconds', () {
        const config = BleConfig();
        expect(config.connectionTimeout, const Duration(seconds: 10));
      });

      test('accepts custom connectionTimeout', () {
        const config = BleConfig(connectionTimeout: Duration(seconds: 5));
        expect(config.connectionTimeout, const Duration(seconds: 5));
      });

      test('accepts zero duration', () {
        const config = BleConfig(connectionTimeout: Duration.zero);
        expect(config.connectionTimeout, Duration.zero);
      });

      test('accepts milliseconds precision', () {
        const config = BleConfig(
          connectionTimeout: Duration(milliseconds: 500),
        );
        expect(config.connectionTimeout, const Duration(milliseconds: 500));
      });

      test('is const constructible', () {
        const config1 = BleConfig();
        const config2 = BleConfig();
        expect(identical(config1, config2), isTrue);
      });
    });

    group('copyWith', () {
      test('returns new instance with updated connectionTimeout', () {
        const original = BleConfig(
          // ignore: avoid_redundant_argument_values
          connectionTimeout: Duration(seconds: 10),
        );
        final copied = original.copyWith(
          connectionTimeout: const Duration(seconds: 3),
        );

        expect(copied.connectionTimeout, const Duration(seconds: 3));
        expect(original.connectionTimeout, const Duration(seconds: 10));
      });

      test('preserves value when null passed', () {
        const original = BleConfig(connectionTimeout: Duration(seconds: 7));
        final copied = original.copyWith();

        expect(copied.connectionTimeout, const Duration(seconds: 7));
      });

      test('returns different instance', () {
        const original = BleConfig();
        final copied = original.copyWith();

        expect(identical(original, copied), isFalse);
      });
    });

    group('toString', () {
      test('includes connectionTimeout', () {
        const config = BleConfig(connectionTimeout: Duration(seconds: 5));
        final result = config.toString();

        expect(result, contains('BleConfig'));
        expect(result, contains('connectionTimeout'));
        expect(result, contains('0:00:05'));
      });

      test('formats default duration correctly', () {
        const config = BleConfig();
        final result = config.toString();

        expect(result, contains('0:00:10'));
      });
    });

    group('equality', () {
      test('const instances with same values are identical', () {
        const config1 = BleConfig(connectionTimeout: Duration(seconds: 5));
        const config2 = BleConfig(connectionTimeout: Duration(seconds: 5));

        expect(identical(config1, config2), isTrue);
      });

      test('default const instances are identical', () {
        const config1 = BleConfig();
        const config2 = BleConfig();

        expect(identical(config1, config2), isTrue);
      });
    });

    group('edge cases', () {
      test('handles very long duration', () {
        const config = BleConfig(connectionTimeout: Duration(hours: 1));
        expect(config.connectionTimeout, const Duration(hours: 1));
      });

      test('still accepts the deprecated connectionStabilizationDelay', () {
        // ignore: deprecated_member_use_from_same_package
        const config = BleConfig(
          connectionStabilizationDelay: Duration(seconds: 4),
        );
        expect(config.connectionTimeout, const Duration(seconds: 4));
        // ignore: deprecated_member_use_from_same_package
        expect(config.connectionStabilizationDelay, const Duration(seconds: 4));
        expect(
          // ignore: deprecated_member_use_from_same_package
          config
              .copyWith(connectionStabilizationDelay: Duration.zero)
              .connectionTimeout,
          Duration.zero,
        );
      });

      test('handles microseconds', () {
        const config = BleConfig(
          connectionTimeout: Duration(microseconds: 100),
        );
        expect(config.connectionTimeout, const Duration(microseconds: 100));
      });
    });
  });
}
