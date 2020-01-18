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
    defineReflectiveTests(ReplaceWithVarTest);
  });
}

@reflectiveTest
class ReplaceWithVarTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REPLACE_WITH_VAR;

  @override
  String get lintCode => LintNames.omit_local_variable_types;

  test_for() async {
    await resolveTestUnit('''
void f(List<int> list) {
  for (/*LINT*/int i = 0; i < list.length; i++) {
    print(i);
  }
}
''');
    await assertHasFix('''
void f(List<int> list) {
  for (/*LINT*/var i = 0; i < list.length; i++) {
    print(i);
  }
}
''');
  }

  test_forEach() async {
    await resolveTestUnit('''
void f(List<int> list) {
  for (/*LINT*/int i in list) {
    print(i);
  }
}
''');
    await assertHasFix('''
void f(List<int> list) {
  for (/*LINT*/var i in list) {
    print(i);
  }
}
''');
  }

  test_generic_instanceCreation_withArguments() async {
    await resolveTestUnit('''
C<int> f() {
  /*LINT*/C<int> c = C<int>();
  return c;
}
class C<T> {}
''');
    await assertHasFix('''
C<int> f() {
  /*LINT*/var c = C<int>();
  return c;
}
class C<T> {}
''');
  }

  test_generic_instanceCreation_withoutArguments() async {
    await resolveTestUnit('''
C<int> f() {
  /*LINT*/C<int> c = C();
  return c;
}
class C<T> {}
''');
    await assertHasFix('''
C<int> f() {
  /*LINT*/var c = C<int>();
  return c;
}
class C<T> {}
''');
  }

  test_generic_listLiteral() async {
    await resolveTestUnit('''
List f() {
  /*LINT*/List<int> l = [];
  return l;
}
''');
    await assertHasFix('''
List f() {
  /*LINT*/var l = <int>[];
  return l;
}
''');
  }

  test_generic_mapLiteral() async {
    await resolveTestUnit('''
Map f() {
  /*LINT*/Map<String, int> m = {};
  return m;
}
''');
    await assertHasFix('''
Map f() {
  /*LINT*/var m = <String, int>{};
  return m;
}
''');
  }

  test_generic_setLiteral() async {
    await resolveTestUnit('''
Set f() {
  /*LINT*/Set<int> s = {};
  return s;
}
''');
    await assertHasFix('''
Set f() {
  /*LINT*/var s = <int>{};
  return s;
}
''');
  }

  test_generic_setLiteral_ambiguous() async {
    await resolveTestUnit('''
Set f() {
  /*LINT*/Set s = {};
  return s;
}
''');
    await assertNoFix();
  }

  test_simple() async {
    await resolveTestUnit('''
String f() {
  /*LINT*/String s = '';
  return s;
}
''');
    await assertHasFix('''
String f() {
  /*LINT*/var s = '';
  return s;
}
''');
  }
}
