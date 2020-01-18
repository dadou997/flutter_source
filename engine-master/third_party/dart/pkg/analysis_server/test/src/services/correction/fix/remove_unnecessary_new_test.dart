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
    defineReflectiveTests(RemoveUnnecessaryNewTest);
  });
}

@reflectiveTest
class RemoveUnnecessaryNewTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_UNNECESSARY_NEW;

  @override
  String get lintCode => LintNames.unnecessary_new;

  test_constructor() async {
    await resolveTestUnit('''
class A { A(); }
m(){
  final a = /*LINT*/new A();
}
''');
    await assertHasFix('''
class A { A(); }
m(){
  final a = /*LINT*/A();
}
''');
  }
}
