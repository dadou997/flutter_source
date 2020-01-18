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
    defineReflectiveTests(AddConstTest);
  });
}

@reflectiveTest
class AddConstTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.ADD_CONST;

  @override
  String get lintCode => LintNames.prefer_const_constructors;

  test_basic() async {
    await resolveTestUnit('''
class C {
  const C();
}
main() {
  var c = C/*LINT*/();
}
''');
    await assertHasFix('''
class C {
  const C();
}
main() {
  var c = const C/*LINT*/();
}
''');
  }

  test_not_present() async {
    await resolveTestUnit('''
class C {
  const C();
}
main() {
  var c = new C/*LINT*/();
}
''');
    // handled by REPLACE_NEW_WITH_CONST
    await assertNoFix();
  }
}
