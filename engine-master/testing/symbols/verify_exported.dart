import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:collection/collection.dart' show MapEquality;

// This script verifies that the release binaries only export the expected
// symbols.
//
// Android binaries (libflutter.so) should only export one symbol "JNI_OnLoad"
// of type "T".
//
// iOS binaries (Flutter.framework/Flutter) should only export Objective-C
// Symbols from the Flutter namespace. These are either of type
// "(__DATA,__common)" or "(__DATA,__objc_data)".

/// Takes the path to the out directory as the first argument, and the path to
/// the buildtools directory as the second argument.
///
/// If the second argument is not specified, it is assumed that it is the parent
/// of the out directory (for backwards compatibility).
void main(List<String> arguments) {
  assert(arguments.length == 2 || arguments.length == 1);
  final String outPath = arguments.first;
  final String buildToolsPath = arguments.length == 1
      ? p.join(p.dirname(outPath), 'buildtools')
      : arguments[1];

  String platform;
  if (Platform.isLinux) {
    platform = 'linux-x64';
  } else if (Platform.isMacOS) {
    platform = 'mac-x64';
  } else {
    throw UnimplementedError('Script only support running on Linux or MacOS.');
  }
  final String nmPath = p.join(buildToolsPath, platform, 'clang', 'bin', 'llvm-nm');
  assert(new Directory(outPath).existsSync());

  final Iterable<String> releaseBuilds = Directory(outPath).listSync()
      .where((FileSystemEntity entity) => entity is Directory)
      .map<String>((FileSystemEntity dir) => p.basename(dir.path))
      .where((String s) => s.contains('_release'));

  final Iterable<String> iosReleaseBuilds = releaseBuilds
      .where((String s) => s.startsWith('ios_'));
  final Iterable<String> androidReleaseBuilds = releaseBuilds
      .where((String s) => s.startsWith('android_'));

  int failures = 0;
  failures += _checkIos(outPath, nmPath, iosReleaseBuilds);
  failures += _checkAndroid(outPath, nmPath, androidReleaseBuilds);
  print('Failing checks: $failures');
  exit(failures);
}

int _checkIos(String outPath, String nmPath, Iterable<String> builds) {
  int failures = 0;
  for (String build in builds) {
    final String libFlutter = p.join(outPath, build, 'Flutter.framework', 'Flutter');
    if (!new File(libFlutter).existsSync()) {
      print('SKIPPING: $libFlutter does not exist.');
      continue;
    }
    final ProcessResult nmResult = Process.runSync(nmPath, <String>['-gUm', libFlutter]);
    if (nmResult.exitCode != 0) {
      print('ERROR: failed to execute "nm -gUm $libFlutter":\n${nmResult.stderr}');
      failures++;
      continue;
    }
    final Iterable<NmEntry> unexpectedEntries = NmEntry.parse(nmResult.stdout).where((NmEntry entry) {
      return !(((entry.type == '(__DATA,__common)' || entry.type == '(__DATA,__const)') && entry.name.startsWith('_Flutter'))
          || (entry.type == '(__DATA,__objc_data)'
              && (entry.name.startsWith('_OBJC_METACLASS_\$_Flutter') || entry.name.startsWith('_OBJC_CLASS_\$_Flutter'))));
    });
    if (unexpectedEntries.isNotEmpty) {
      print('ERROR: $libFlutter exports unexpected symbols:');
      print(unexpectedEntries.fold<String>('', (String previous, NmEntry entry) {
        return '${previous == '' ? '' : '$previous\n'}     ${entry.type} ${entry.name}';
      }));
      failures++;
    } else {
      print('OK: $libFlutter');
    }
  }
  return failures;
}

int _checkAndroid(String outPath, String nmPath, Iterable<String> builds) {
  int failures = 0;
  for (String build in builds) {
    final String libFlutter = p.join(outPath, build, 'libflutter.so');
    if (!new File(libFlutter).existsSync()) {
      print('SKIPPING: $libFlutter does not exist.');
      continue;
    }
    final ProcessResult nmResult = Process.runSync(nmPath, <String>['-gU', libFlutter]);
    if (nmResult.exitCode != 0) {
      print('ERROR: failed to execute "nm -gU $libFlutter":\n${nmResult.stderr}');
      failures++;
      continue;
    }
    final Iterable<NmEntry> entries = NmEntry.parse(nmResult.stdout);
    final Map<String, String> entryMap = Map<String, String>.fromIterable(
        entries,
        key: (dynamic entry) => entry.name,
        value: (dynamic entry) => entry.type);
    final Map<String, String> expectedSymbols = <String, String>{
      'JNI_OnLoad': 'T',
      '_binary_icudtl_dat_size': 'A',
      '_binary_icudtl_dat_start': 'D',
    };
    if (!const MapEquality<String, String>().equals(entryMap, expectedSymbols)) {
      print('ERROR: $libFlutter exports the wrong symbols');
      print(' Expected $expectedSymbols');
      print(' Library has $entryMap.');
      failures++;
    } else {
      print('OK: $libFlutter');
    }
  }
  return failures;
}

class NmEntry {
  NmEntry._(this.address, this.type, this.name);

  final String address;
  final String type;
  final String name;

  static Iterable<NmEntry> parse(String stdout) {
    return LineSplitter.split(stdout).map((String line) {
      final List<String> parts = line.split(' ');
      return NmEntry._(parts[0], parts[1], parts.last);
    });
  }
}
