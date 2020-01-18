// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Platform;

import 'package:front_end/src/api_prototype/compiler_options.dart';
import 'package:front_end/src/api_unstable/bazel_worker.dart';

import 'package:kernel/kernel.dart'
    show Component, Library, LibraryPart, Reference;

import 'incremental_load_from_dill_suite.dart' as helper;

import "incremental_utils.dart" as util;

main(List<String> args) async {
  bool fast = false;
  bool useExperimentalInvalidation = false;
  for (String arg in args) {
    if (arg == "--fast") {
      fast = true;
    } else if (arg == "--experimental") {
      useExperimentalInvalidation = true;
    } else {
      throw "Unsupported argument: $arg";
    }
  }

  Stopwatch stopwatch = new Stopwatch()..start();
  Uri input = Platform.script.resolve("../../compiler/bin/dart2js.dart");
  CompilerOptions options = helper.getOptions(targetName: "None");
  helper.TestIncrementalCompiler compiler =
      new helper.TestIncrementalCompiler(options, input);
  compiler.useExperimentalInvalidation = useExperimentalInvalidation;
  Component c = await compiler.computeDelta();
  print("Compiled dart2js to Component with ${c.libraries.length} libraries "
      "in ${stopwatch.elapsedMilliseconds} ms.");
  stopwatch.reset();
  List<int> firstCompileData;
  Map<Uri, List<int>> libToData;
  if (fast) {
    libToData = {};
    c.libraries.sort((l1, l2) {
      return "${l1.fileUri}".compareTo("${l2.fileUri}");
    });

    c.problemsAsJson?.sort();

    c.computeCanonicalNames();

    for (Library library in c.libraries) {
      library.additionalExports.sort((Reference r1, Reference r2) {
        return "${r1.canonicalName}".compareTo("${r2.canonicalName}");
      });
      library.problemsAsJson?.sort();

      List<int> libSerialized =
          serializeComponent(c, filter: (l) => l == library);
      libToData[library.importUri] = libSerialized;
    }
  } else {
    firstCompileData = util.postProcess(c);
  }
  print("Serialized in ${stopwatch.elapsedMilliseconds} ms");
  stopwatch.reset();

  List<Uri> uris = c.uriToSource.values
      .map((s) => s != null ? s.importUri : null)
      .where((u) => u != null && u.scheme != "dart")
      .toSet()
      .toList();

  c = null;

  List<Uri> diffs = new List<Uri>();

  Stopwatch localStopwatch = new Stopwatch()..start();
  for (int i = 0; i < uris.length; i++) {
    Uri uri = uris[i];
    print("Invalidating $uri ($i)");
    compiler.invalidate(uri);
    localStopwatch.reset();
    Component c2 = await compiler.computeDelta(fullComponent: true);
    print("Recompiled in ${localStopwatch.elapsedMilliseconds} ms");
    print("invalidatedImportUrisForTesting: "
        "${compiler.invalidatedImportUrisForTesting}");
    print("rebuildBodiesCount: ${compiler.rebuildBodiesCount}");
    localStopwatch.reset();

    if (fast) {
      c2.libraries.sort((l1, l2) {
        return "${l1.fileUri}".compareTo("${l2.fileUri}");
      });

      c2.problemsAsJson?.sort();

      c2.computeCanonicalNames();

      int foundCount = 0;
      for (Library library in c2.libraries) {
        Set<Uri> uris = new Set<Uri>();
        uris.add(library.importUri);
        for (LibraryPart part in library.parts) {
          Uri uri = library.importUri.resolve(part.partUri);
          uris.add(uri);
        }
        if (!uris.contains(uri)) continue;
        foundCount++;
        library.additionalExports.sort((Reference r1, Reference r2) {
          return "${r1.canonicalName}".compareTo("${r2.canonicalName}");
        });
        library.problemsAsJson?.sort();

        List<int> libSerialized =
            serializeComponent(c2, filter: (l) => l == library);
        if (!isEqual(libToData[library.importUri], libSerialized)) {
          print("=====");
          print("=====");
          print("=====");
          print("Notice diff on $uri ($i)!");
          libToData[library.importUri] = libSerialized;
          diffs.add(uri);
          print("=====");
          print("=====");
          print("=====");
        }
      }
      if (foundCount != 1) {
        throw "Expected to find $uri, but it $foundCount times.";
      }
      print("Serialized library in ${localStopwatch.elapsedMilliseconds} ms");
    } else {
      List<int> thisCompileData = util.postProcess(c2);
      print("Serialized in ${localStopwatch.elapsedMilliseconds} ms");
      if (!isEqual(firstCompileData, thisCompileData)) {
        print("=====");
        print("=====");
        print("=====");
        print("Notice diff on $uri ($i)!");
        firstCompileData = thisCompileData;
        diffs.add(uri);
        print("=====");
        print("=====");
        print("=====");
      }
    }
    print("-----");
  }

  print("A total of ${diffs.length} diffs:");
  for (Uri uri in diffs) {
    print(" - $uri");
  }

  print("Done after ${uris.length} recompiles in "
      "${stopwatch.elapsedMilliseconds} ms");
}

bool isEqual(List<int> a, List<int> b) {
  int length = a.length;
  if (b.length != length) {
    return false;
  }
  for (int i = 0; i < length; ++i) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
