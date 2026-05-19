// Copyright (c) 2020, Dart | Windows.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Enumerates locally-connected printers.

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

class PrinterNames {
  PrinterNames(this._flags);
  final int _flags;

  Iterable<String> all() sync* {
    try {
      _getBufferSize();

      try {
        _readRawBuff();
        yield* parse();
      } finally {
        free(_rawBuffer);
      }
    } finally {
      free(_pBuffSize);
      free(_bPrinterLen);
    }
  }

  late Pointer<DWORD> _pBuffSize;
  late Pointer<DWORD> _bPrinterLen;

  void _getBufferSize() {
    _pBuffSize = calloc<DWORD>();
    _bPrinterLen = calloc<DWORD>();

    EnumPrinters(_flags, null, 2, null, 0, _pBuffSize, _bPrinterLen);

    if (_pBuffSize.value == 0) {
      throw Exception('Read printer buffer size fail');
    }
  }

  late Pointer<BYTE> _rawBuffer;

  void _readRawBuff() {
    _rawBuffer = malloc.allocate<BYTE>(_pBuffSize.value);

    final isRawBuffFail = EnumPrinters(
          _flags,
          null,
          2,
          _rawBuffer,
          _pBuffSize.value,
          _pBuffSize,
          _bPrinterLen,
        ).value ==
        false;

    if (isRawBuffFail) {
      throw Exception('Read printer raw buffer fail');
    }
  }

  Iterable<String> parse() sync* {
    for (var i = 0; i < _bPrinterLen.value; i++) {
      final printer = _rawBuffer.cast<PRINTER_INFO_2>() + i;
      yield printer.ref.pPrinterName.toDartString();
    }
  }
}
