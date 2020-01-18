// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server/src/services/linter/lint_names.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToRelativeImportTest);
  });
}

@reflectiveTest
class ConvertToRelativeImportTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.CONVERT_TO_RELATIVE_IMPORT;

  @override
  String get lintCode => LintNames.prefer_relative_imports;

  test_relativeImport() async {
    addSource('/home/test/lib/foo.dart', '');
    testFile = convertPath('/home/test/lib/src/test.dart');
    await resolveTestUnit('''
import /*LINT*/'package:test/foo.dart';
''');

    await assertHasFix('''
import /*LINT*/'../foo.dart';
''');
  }

  test_relativeImportSameDirectory() async {
    addSource('/home/test/lib/foo.dart', '');
    testFile = convertPath('/home/test/lib/bar.dart');
    await resolveTestUnit('''
import /*LINT*/'package:test/foo.dart';
''');

    await assertHasFix('''
import /*LINT*/'foo.dart';
''');
  }

  test_relativeImportSubDirectory() async {
    addSource('/home/test/lib/baz/foo.dart', '');
    testFile = convertPath('/home/test/lib/test.dart');
    await resolveTestUnit('''
import /*LINT*/'package:test/baz/foo.dart';
''');

    await assertHasFix('''
import /*LINT*/'baz/foo.dart';
''');
  }

  test_relativeImportRespectQuoteStyle() async {
    addSource('/home/test/lib/foo.dart', '');
    testFile = convertPath('/home/test/lib/bar.dart');
    await resolveTestUnit('''
import /*LINT*/"package:test/foo.dart";
''');

    await assertHasFix('''
import /*LINT*/"foo.dart";
''');
  }

  test_relativeImportGarbledUri() async {
    addSource('/home/test/lib/foo.dart', '');
    testFile = convertPath('/home/test/lib/bar.dart');
    await resolveTestUnit('''
import /*LINT*/'package:test/foo';
''');

    await assertHasFix('''
import /*LINT*/'foo';
''');
  }

  // Validate we don't get a fix with imports referencing different packages.
  test_relativeImportDifferentPackages() async {
    addSource('/home/test1/lib/foo.dart', '');
    testFile = convertPath('/home/test2/lib/bar.dart');
    await resolveTestUnit('''
import /*LINT*/'package:test1/foo.dart';
''');

    await assertNoFix();
  }
}
