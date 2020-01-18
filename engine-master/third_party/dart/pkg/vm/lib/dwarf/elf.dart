// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';
import 'dart:io';

import 'reader.dart';

int _readElfBytes(Reader reader, int bytes, int alignment) {
  final alignOffset = reader.offset % alignment;
  if (alignOffset != 0) {
    // Move the reader to the next aligned position.
    reader.seek(reader.offset - alignOffset + alignment);
  }
  return reader.readBytes(bytes);
}

// Reads an Elf{32,64}_Addr.
int _readElfAddress(Reader reader) {
  return _readElfBytes(reader, reader.wordSize, reader.wordSize);
}

// Reads an Elf{32,64}_Off.
int _readElfOffset(Reader reader) {
  return _readElfBytes(reader, reader.wordSize, reader.wordSize);
}

// Reads an Elf{32,64}_Half.
int _readElfHalf(Reader reader) {
  return _readElfBytes(reader, 2, 2);
}

// Reads an Elf{32,64}_Word.
int _readElfWord(Reader reader) {
  return _readElfBytes(reader, 4, 4);
}

// Reads an Elf64_Xword.
int _readElfXword(Reader reader) {
  switch (reader.wordSize) {
    case 4:
      throw "Internal reader error: reading Elf64_Xword in 32-bit ELF file";
    case 8:
      return _readElfBytes(reader, 8, 8);
    default:
      throw "Unsupported word size ${reader.wordSize}";
  }
}

// Used in cases where the value read for a given field is Elf32_Word on 32-bit
// and Elf64_Xword on 64-bit.
int _readElfNative(Reader reader) {
  switch (reader.wordSize) {
    case 4:
      return _readElfWord(reader);
    case 8:
      return _readElfXword(reader);
    default:
      throw "Unsupported word size ${reader.wordSize}";
  }
}

class ElfHeader {
  final Reader startingReader;

  int wordSize;
  Endian endian;
  int entry;
  int flags;
  int headerSize;
  int programHeaderOffset;
  int sectionHeaderOffset;
  int programHeaderCount;
  int sectionHeaderCount;
  int programHeaderEntrySize;
  int sectionHeaderEntrySize;
  int sectionHeaderStringsIndex;

  int get programHeaderSize => programHeaderCount * programHeaderEntrySize;
  int get sectionHeaderSize => sectionHeaderCount * sectionHeaderEntrySize;

  // Constants used within the ELF specification.
  static const _ELFMAG = "\x7fELF";
  static const _ELFCLASS32 = 0x01;
  static const _ELFCLASS64 = 0x02;
  static const _ELFDATA2LSB = 0x01;
  static const _ELFDATA2MSB = 0x02;

  ElfHeader.fromReader(Reader this.startingReader) {
    _read();
  }

  static bool startsWithMagicNumber(Reader reader) {
    reader.reset();
    for (final sigByte in _ELFMAG.codeUnits) {
      if (reader.readByte() != sigByte) {
        return false;
      }
    }
    return true;
  }

  int _readWordSize(Reader reader) {
    switch (reader.readByte()) {
      case _ELFCLASS32:
        return 4;
      case _ELFCLASS64:
        return 8;
      default:
        throw FormatException("Unexpected e_ident[EI_CLASS] value");
    }
  }

  int get calculatedHeaderSize => 0x18 + 3 * wordSize + 0x10;

  Endian _readEndian(Reader reader) {
    switch (reader.readByte()) {
      case _ELFDATA2LSB:
        return Endian.little;
      case _ELFDATA2MSB:
        return Endian.big;
      default:
        throw FormatException("Unexpected e_indent[EI_DATA] value");
    }
  }

  void _read() {
    startingReader.reset();
    for (final sigByte in _ELFMAG.codeUnits) {
      if (startingReader.readByte() != sigByte) {
        throw FormatException("Not an ELF file");
      }
    }
    wordSize = _readWordSize(startingReader);
    final fileSize = startingReader.bdata.buffer.lengthInBytes;
    if (fileSize < calculatedHeaderSize) {
      throw FormatException("ELF file too small for header: "
          "file size ${fileSize} < "
          "calculated header size $calculatedHeaderSize");
    }
    endian = _readEndian(startingReader);
    if (startingReader.readByte() != 0x01) {
      throw FormatException("Unexpected e_ident[EI_VERSION] value");
    }

    // After this point, we need the reader to be correctly set up re: word
    // size and endianness, since we start reading more than single bytes.
    final reader = Reader.fromTypedData(startingReader.bdata,
        wordSize: wordSize, endian: endian);
    reader.seek(startingReader.offset);

    // Skip rest of e_ident/e_type/e_machine, i.e. move to e_version.
    reader.seek(0x14, absolute: true);
    if (_readElfWord(reader) != 0x01) {
      throw FormatException("Unexpected e_version value");
    }

    entry = _readElfAddress(reader);
    programHeaderOffset = _readElfOffset(reader);
    sectionHeaderOffset = _readElfOffset(reader);
    flags = _readElfWord(reader);
    headerSize = _readElfHalf(reader);
    programHeaderEntrySize = _readElfHalf(reader);
    programHeaderCount = _readElfHalf(reader);
    sectionHeaderEntrySize = _readElfHalf(reader);
    sectionHeaderCount = _readElfHalf(reader);
    sectionHeaderStringsIndex = _readElfHalf(reader);

    if (headerSize != calculatedHeaderSize) {
      throw FormatException("Stored ELF header size ${headerSize} != "
          "calculated ELF header size $calculatedHeaderSize");
    }
    if (fileSize < programHeaderOffset) {
      throw FormatException("File is truncated before program header");
    }
    if (fileSize < programHeaderOffset + programHeaderSize) {
      throw FormatException("File is truncated within the program header");
    }
    if (fileSize < sectionHeaderOffset) {
      throw FormatException("File is truncated before section header");
    }
    if (fileSize < sectionHeaderOffset + sectionHeaderSize) {
      throw FormatException("File is truncated within the section header");
    }
  }

  String toString() {
    var ret = "Format is ${wordSize * 8} bits\n";
    switch (endian) {
      case Endian.little:
        ret += "Little-endian format\n";
        break;
      case Endian.big:
        ret += "Big-endian format\n";
        break;
    }
    ret += "Entry point: 0x${paddedHex(entry, wordSize)}\n"
        "Flags: 0x${paddedHex(flags, 4)}\n"
        "Header size: ${headerSize}\n"
        "Program header offset: "
        "0x${paddedHex(programHeaderOffset, wordSize)}\n"
        "Program header entry size: ${programHeaderEntrySize}\n"
        "Program header entry count: ${programHeaderCount}\n"
        "Section header offset: "
        "0x${paddedHex(sectionHeaderOffset, wordSize)}\n"
        "Section header entry size: ${sectionHeaderEntrySize}\n"
        "Section header entry count: ${sectionHeaderCount}\n"
        "Section header strings index: ${sectionHeaderStringsIndex}\n";
    return ret;
  }
}

class ProgramHeaderEntry {
  Reader reader;

  int type;
  int flags;
  int offset;
  int vaddr;
  int paddr;
  int filesz;
  int memsz;
  int align;

  // p_type constants from ELF specification.
  static const _PT_NULL = 0;
  static const _PT_LOAD = 1;
  static const _PT_DYNAMIC = 2;
  static const _PT_PHDR = 6;

  ProgramHeaderEntry.fromReader(Reader this.reader) {
    assert(reader.wordSize == 4 || reader.wordSize == 8);
    _read();
  }

  void _read() {
    reader.reset();
    type = _readElfWord(reader);
    if (reader.wordSize == 8) {
      flags = _readElfWord(reader);
    }
    offset = _readElfOffset(reader);
    vaddr = _readElfAddress(reader);
    paddr = _readElfAddress(reader);
    filesz = _readElfNative(reader);
    memsz = _readElfNative(reader);
    if (reader.wordSize == 4) {
      flags = _readElfWord(reader);
    }
    align = _readElfNative(reader);
  }

  static const _typeStrings = <int, String>{
    _PT_NULL: "PT_NULL",
    _PT_LOAD: "PT_LOAD",
    _PT_DYNAMIC: "PT_DYNAMIC",
    _PT_PHDR: "PT_PHDR",
  };

  static String _typeToString(int type) {
    if (_typeStrings.containsKey(type)) {
      return _typeStrings[type];
    }
    return "unknown (${paddedHex(type, 4)})";
  }

  String toString() => "Type: ${_typeToString(type)}\n"
      "Flags: 0x${paddedHex(flags, 4)}\n"
      "Offset: $offset (0x${paddedHex(offset, reader.wordSize)})\n"
      "Virtual address: 0x${paddedHex(vaddr, reader.wordSize)}\n"
      "Physical address: 0x${paddedHex(paddr, reader.wordSize)}\n"
      "Size in file: $filesz\n"
      "Size in memory: $memsz\n"
      "Alignment: 0x${paddedHex(align, reader.wordSize)}\n";
}

class ProgramHeader {
  final Reader reader;
  final int entrySize;
  final int entryCount;

  List<ProgramHeaderEntry> _entries;

  ProgramHeader.fromReader(Reader this.reader,
      {int this.entrySize, int this.entryCount}) {
    _read();
  }

  int get length => _entries.length;
  ProgramHeaderEntry operator [](int index) => _entries[index];

  void _read() {
    reader.reset();
    _entries = <ProgramHeaderEntry>[];
    for (var i = 0; i < entryCount; i++) {
      final entry = ProgramHeaderEntry.fromReader(
          reader.shrink(i * entrySize, entrySize));
      _entries.add(entry);
    }
  }

  String toString() {
    var ret = "";
    for (var i = 0; i < length; i++) {
      ret += "Entry $i:\n${this[i]}\n";
    }
    return ret;
  }
}

class SectionHeaderEntry {
  final Reader reader;

  int nameIndex;
  String name;
  int type;
  int flags;
  int addr;
  int offset;
  int size;
  int link;
  int info;
  int addrAlign;
  int entrySize;

  SectionHeaderEntry.fromReader(this.reader) {
    _read();
  }

  // sh_type constants from ELF specification.
  static const _SHT_NULL = 0;
  static const _SHT_PROGBITS = 1;
  static const _SHT_SYMTAB = 2;
  static const _SHT_STRTAB = 3;
  static const _SHT_HASH = 5;
  static const _SHT_DYNAMIC = 6;
  static const _SHT_NOBITS = 8;
  static const _SHT_DYNSYM = 11;

  void _read() {
    reader.reset();
    nameIndex = _readElfWord(reader);
    type = _readElfWord(reader);
    flags = _readElfNative(reader);
    addr = _readElfAddress(reader);
    offset = _readElfOffset(reader);
    size = _readElfNative(reader);
    link = _readElfWord(reader);
    info = _readElfWord(reader);
    addrAlign = _readElfNative(reader);
    entrySize = _readElfNative(reader);
  }

  void setName(StringTable nameTable) {
    name = nameTable[nameIndex];
  }

  static const _typeStrings = <int, String>{
    _SHT_NULL: "SHT_NULL",
    _SHT_PROGBITS: "SHT_PROGBITS",
    _SHT_SYMTAB: "SHT_SYMTAB",
    _SHT_STRTAB: "SHT_STRTAB",
    _SHT_HASH: "SHT_HASH",
    _SHT_DYNAMIC: "SHT_DYNAMIC",
    _SHT_NOBITS: "SHT_NOBITS",
    _SHT_DYNSYM: "SHT_DYNSYM",
  };

  static String _typeToString(int type) {
    if (_typeStrings.containsKey(type)) {
      return _typeStrings[type];
    }
    return "unknown (${paddedHex(type, 4)})";
  }

  String toString() => "Name: ${name} (@ ${nameIndex})\n"
      "Type: ${_typeToString(type)}\n"
      "Flags: 0x${paddedHex(flags, reader.wordSize)}\n"
      "Address: 0x${paddedHex(addr, reader.wordSize)}\n"
      "Offset: $offset (0x${paddedHex(offset, reader.wordSize)})\n"
      "Size: $size\n"
      "Link: $link\n"
      "Info: 0x${paddedHex(info, 4)}\n"
      "Address alignment: 0x${paddedHex(addrAlign, reader.wordSize)}\n"
      "Entry size: ${entrySize}\n";
}

class SectionHeader {
  final Reader reader;
  final int entrySize;
  final int entryCount;
  final int stringsIndex;

  List<SectionHeaderEntry> _entries;
  StringTable nameTable = null;

  SectionHeader.fromReader(this.reader,
      {this.entrySize, this.entryCount, this.stringsIndex}) {
    _read();
  }

  SectionHeaderEntry _readSectionHeaderEntry(int index) {
    final ret = SectionHeaderEntry.fromReader(
        reader.shrink(index * entrySize, entrySize));
    if (nameTable != null) {
      ret.setName(nameTable);
    }
    return ret;
  }

  void _read() {
    reader.reset();
    // Set up the section header string table first so we can use it
    // for the other section header entries.
    final nameTableEntry = _readSectionHeaderEntry(stringsIndex);
    assert(nameTableEntry.type == SectionHeaderEntry._SHT_STRTAB);
    nameTable = StringTable(nameTableEntry,
        reader.refocus(nameTableEntry.offset, nameTableEntry.size));
    nameTableEntry.setName(nameTable);

    _entries = <SectionHeaderEntry>[];
    for (var i = 0; i < entryCount; i++) {
      // We don't need to reparse the shstrtab entry.
      if (i == stringsIndex) {
        _entries.add(nameTableEntry);
      } else {
        _entries.add(_readSectionHeaderEntry(i));
      }
    }
  }

  int get length => _entries.length;
  SectionHeaderEntry operator [](int index) => _entries[index];

  String toString() {
    var ret = "";
    for (var i = 0; i < length; i++) {
      ret += "Entry $i:\n${this[i]}\n";
    }
    return ret;
  }
}

class Section {
  final Reader reader;
  final SectionHeaderEntry headerEntry;

  Section(this.headerEntry, this.reader);

  factory Section.fromEntryAndReader(SectionHeaderEntry entry, Reader reader) {
    switch (entry.type) {
      case SectionHeaderEntry._SHT_STRTAB:
        return StringTable(entry, reader);
      default:
        return Section(entry, reader);
    }
  }

  int get length => reader.bdata.lengthInBytes;
  String toString() => "an unparsed section of ${length} bytes\n";
}

class StringTable extends Section {
  final _entries = Map<int, String>();

  StringTable(SectionHeaderEntry entry, Reader reader) : super(entry, reader) {
    while (!reader.done) {
      _entries[reader.offset] = reader.readNullTerminatedString();
    }
  }

  String operator [](int index) => _entries[index];

  String toString() => _entries.keys.fold("a string table:\n",
      (String acc, int key) => acc + "  $key => ${_entries[key]}\n");
}

class Elf {
  final Reader startingReader;

  ElfHeader header;
  ProgramHeader programHeader;
  SectionHeader sectionHeader;

  Map<SectionHeaderEntry, Section> sections;

  Elf.fromReader(this.startingReader) {
    _read();
  }
  Elf.fromFile(String filename)
      : this.fromReader(Reader.fromTypedData(File(filename).readAsBytesSync(),
            // We provide null for the wordSize and endianness to ensure
            // we don't accidentally call any methods that use them until
            // we have gotten that information from the ELF header.
            wordSize: null,
            endian: null));

  static bool startsWithMagicNumber(String filename) {
    final file = File(filename).openSync();
    var ret = true;
    for (int code in ElfHeader._ELFMAG.codeUnits) {
      if (file.readByteSync() != code) {
        ret = false;
        break;
      }
    }
    file.closeSync();
    return ret;
  }

  Iterable<Section> namedSection(String name) {
    final ret = <Section>[];
    for (var entry in sections.keys) {
      if (entry.name == name) {
        ret.add(sections[entry]);
      }
    }
    if (ret.isEmpty) {
      throw FormatException("No section named $name found in ELF file");
    }
    return ret;
  }

  void _read() {
    startingReader.reset();
    header = ElfHeader.fromReader(startingReader.copy());
    // Now use the word size and endianness information from the header.
    final reader = Reader.fromTypedData(startingReader.bdata,
        wordSize: header.wordSize, endian: header.endian);
    programHeader = ProgramHeader.fromReader(
        reader.refocus(header.programHeaderOffset, header.programHeaderSize),
        entrySize: header.programHeaderEntrySize,
        entryCount: header.programHeaderCount);
    sectionHeader = SectionHeader.fromReader(
        reader.refocus(header.sectionHeaderOffset, header.sectionHeaderSize),
        entrySize: header.sectionHeaderEntrySize,
        entryCount: header.sectionHeaderCount,
        stringsIndex: header.sectionHeaderStringsIndex);
    sections = <SectionHeaderEntry, Section>{};
    for (var i = 0; i < sectionHeader.length; i++) {
      final entry = sectionHeader[i];
      if (i == header.sectionHeaderStringsIndex) {
        sections[entry] = sectionHeader.nameTable;
      } else {
        sections[entry] = Section.fromEntryAndReader(
            entry, reader.refocus(entry.offset, entry.size));
      }
    }
  }

  String toString() {
    String accumulateSection(String acc, SectionHeaderEntry entry) =>
        acc + "\nSection ${entry.name} is ${sections[entry]}";
    return "Header information:\n\n${header}"
        "\nProgram header information:\n\n${programHeader}"
        "\nSection header information:\n\n${sectionHeader}"
        "${sections.keys.fold("", accumulateSection)}";
  }
}
