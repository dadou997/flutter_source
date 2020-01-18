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
    defineReflectiveTests(ReplaceWithIsEmptyTest);
  });
}

@reflectiveTest
class ReplaceWithIsEmptyTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REPLACE_WITH_IS_EMPTY;

  @override
  String get lintCode => LintNames.prefer_is_empty;

  test_constantOnLeft_equal() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/0 == c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }

  test_constantOnLeft_greaterThan() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/1 > c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }

  test_constantOnLeft_greaterThanOrEqual() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/0 >= c.length) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }

  test_constantOnRight_equal() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/c.length == 0) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }

  test_constantOnRight_lessThan() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/c.length < 1) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }

  test_constantOnRight_lessThanOrEqual() async {
    await resolveTestUnit('''
f(List c) {
  if (/*LINT*/c.length <= 0) {}
}
''');
    await assertHasFix('''
f(List c) {
  if (/*LINT*/c.isEmpty) {}
}
''');
  }
}
