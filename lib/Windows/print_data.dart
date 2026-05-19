// Sends RAW data (string or hex sequences) directly to the printer

// Example taken from:
// https://learn.microsoft.com/windows/win32/printdocs/sending-data-directly-to-a-printer

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class RawPrinter {
  RawPrinter(this.printerName, this.alloc);
  final String printerName;
  final Arena alloc;

  void printEscPosWin32(List<int> data) {
    final hPrinter = alloc<Pointer>();
    final docInfo = alloc<DOC_INFO_1>();

    final printerNamePtr = printerName.toNativeUtf16(allocator: alloc);
    final docNamePtr = 'ESC/POS Print Job'.toNativeUtf16(allocator: alloc);
    final rawDatatypePtr = 'RAW'.toNativeUtf16(allocator: alloc);

    docInfo.ref.pDocName = PWSTR(docNamePtr);
    docInfo.ref.pOutputFile = PWSTR(nullptr.cast());
    docInfo.ref.pDatatype = PWSTR(rawDatatypePtr);

    if (OpenPrinter(PCWSTR(printerNamePtr), hPrinter, null).value) {
      final printerHandle = PRINTER_HANDLE(hPrinter.value);

      if (StartDocPrinter(printerHandle, 1, docInfo.cast()) != 0) {
        StartPagePrinter(printerHandle);

        final buffer = alloc<Uint8>(data.length);
        buffer.asTypedList(data.length).setAll(0, data);
        final bytesWritten = alloc<Uint32>();

        WritePrinter(
          printerHandle,
          buffer,
          data.length,
          bytesWritten,
        );

        EndPagePrinter(printerHandle);
        EndDocPrinter(printerHandle);
      }

      ClosePrinter(printerHandle);
    }
  }
}
