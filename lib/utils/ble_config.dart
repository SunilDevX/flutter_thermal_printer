class BleConfig {
  const BleConfig({
    Duration? connectionTimeout,
    @Deprecated('Use connectionTimeout instead.')
    Duration? connectionStabilizationDelay,
  }) : connectionTimeout =
           connectionTimeout ??
           connectionStabilizationDelay ??
           const Duration(seconds: 10);

  /// How long `connect()` waits for a BLE printer before reporting failure.
  final Duration connectionTimeout;

  @Deprecated('Use connectionTimeout instead.')
  Duration get connectionStabilizationDelay => connectionTimeout;

  BleConfig copyWith({
    Duration? connectionTimeout,
    @Deprecated('Use connectionTimeout instead.')
    Duration? connectionStabilizationDelay,
  }) => BleConfig(
    connectionTimeout:
        connectionTimeout ??
        connectionStabilizationDelay ??
        this.connectionTimeout,
  );

  @override
  String toString() => 'BleConfig(connectionTimeout: $connectionTimeout)';
}
