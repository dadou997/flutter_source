// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library vm.elf.reader;

import 'dart:typed_data';
import 'dart:math';

String paddedHex(int value, [int bytes = 0]) {
  return value.toRadixString(16).padLeft(2 * bytes, '0');
}

class Reader {
  final ByteData bdata;
  final Endian endian;
  final int wordSize;

  int _offset = 0;

  Reader.fromTypedData(TypedData data, {int this.wordSize, Endian this.endian})
      : bdata =
            ByteData.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

  Reader copy() =>
      Reader.fromTypedData(bdata, wordSize: wordSize, endian: endian);

  Reader shrink(int offset, [int size = -1]) {
    if (size < 0) size = bdata.lengthInBytes - offset;
    assert(offset >= 0 && offset < bdata.lengthInBytes);
    assert(size >= 0 && (offset + size) <= bdata.lengthInBytes);
    return Reader.fromTypedData(
        ByteData.view(bdata.buffer, bdata.offsetInBytes + offset, size),
        wordSize: wordSize,
        endian: endian);
  }

  Reader refocus(int pos, [int size = -1]) {
    if (size < 0) size = bdata.lengthInBytes - pos;
    assert(pos >= 0 && pos < bdata.buffer.lengthInBytes);
    assert(size >= 0 && (pos + size) <= bdata.buffer.lengthInBytes);
    return Reader.fromTypedData(ByteData.view(bdata.buffer, pos, size),
        wordSize: wordSize, endian: endian);
  }

  int get start => bdata.offsetInBytes;
  int get offset => _offset;
  int get length => bdata.lengthInBytes;
  bool get done => _offset >= length;

  void seek(int offset, {bool absolute = false}) {
    final newOffset = (absolute ? 0 : _offset) + offset;
    assert(newOffset >= 0 && newOffset < bdata.lengthInBytes);
    _offset = newOffset;
  }

  void reset() {
    seek(0, absolute: true);
  }

  int readBytes(int size, {bool signed = false}) {
    assert(_offset + size < length);
    int ret;
    switch (size) {
      case 1:
        ret = signed ? bdata.getInt8(_offset) : bdata.getUint8(_offset);
        break;
      case 2:
        ret = signed
            ? bdata.getInt16(_offset, endian)
            : bdata.getUint16(_offset, endian);
        break;
      case 4:
        ret = signed
            ? bdata.getInt32(_offset, endian)
            : bdata.getUint32(_offset, endian);
        break;
      case 8:
        ret = signed
            ? bdata.getInt64(_offset, endian)
            : bdata.getUint64(_offset, endian);
        break;
      default:
        throw ArgumentError("invalid request to read $size bytes");
    }
    _offset += size;
    return ret;
  }

  int readByte({bool signed = false}) => readBytes(1, signed: signed);
  int readWord() => readBytes(wordSize);
  String readNullTerminatedString() {
    final start = bdata.offsetInBytes + _offset;
    for (int i = 0; _offset + i < bdata.lengthInBytes; i++) {
      if (bdata.getUint8(_offset + i) == 0) {
        _offset += i + 1;
        return String.fromCharCodes(bdata.buffer.asUint8List(start, i));
      }
    }
    return String.fromCharCodes(
        bdata.buffer.asUint8List(start, bdata.lengthInBytes - _offset));
  }

  int readLEB128EncodedInteger({bool signed = false}) {
    var ret = 0;
    var shift = 0;
    for (var byte = readByte(); !done; byte = readByte()) {
      ret |= (byte & 0x7f) << shift;
      shift += 7;
      if (byte & 0x80 == 0) {
        if (signed && byte & 0x40 != 0) {
          ret |= -(1 << shift);
        }
        break;
      }
    }
    return ret;
  }

  String dumpCurrentReaderPosition({int maxSize = 0, int bytesPerLine = 16}) {
    var baseData = ByteData.view(bdata.buffer, 0, bdata.buffer.lengthInBytes);
    var startOffset = 0;
    var endOffset = baseData.lengthInBytes;
    final currentOffset = start + _offset;
    if (maxSize != 0 && maxSize < baseData.lengthInBytes) {
      var lowerWindow = currentOffset - (maxSize >> 1);
      // Adjust so that we always start at the beginning of a line.
      lowerWindow -= lowerWindow % bytesPerLine;
      final upperWindow = lowerWindow + maxSize;
      startOffset = max(startOffset, lowerWindow);
      endOffset = min(endOffset, upperWindow);
    }
    var ret = "";
    for (int i = startOffset; i < endOffset; i += bytesPerLine) {
      ret += "0x" + paddedHex(i, 8) + " ";
      for (int j = 0; j < bytesPerLine && i + j < endOffset; j++) {
        var byte = baseData.getUint8(i + j);
        ret += (i + j == currentOffset) ? "|" : " ";
        ret += paddedHex(byte, 1);
      }
      ret += "\n";
    }
    return ret;
  }

  String toString() => dumpCurrentReaderPosition();
}
