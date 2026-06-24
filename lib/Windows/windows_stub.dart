// Stub implementation for non-Windows platforms
// This file provides empty implementations for Windows-specific functionality
// ignore_for_file: avoid_annotating_with_dynamic

// Win32 constants stub
// ignore: constant_identifier_names
const int PRINTER_ENUM_LOCAL = 0x00000002;

class PrinterNames {
  PrinterNames(int _);

  Iterable<String> all() sync* {
    // No Windows printers available on non-Windows platforms
  }
}

class RawPrinter {
  RawPrinter(String _, __);

  void printEscPosWin32(List<int> data) {
    throw UnsupportedError(
      'Windows printing is not supported on this platform',
    );
  }
}

// Stub implementation for FFI's using function
R using<R>(R Function(dynamic) computation, [dynamic allocator]) {
  throw UnsupportedError('FFI using function is not supported on web platform');
}
