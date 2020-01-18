// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveUnusedLocalVariableTest);
  });
}

@reflectiveTest
class RemoveUnusedLocalVariableTest extends FixProcessorTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_UNUSED_LOCAL_VARIABLE;

  test_inArgumentList() async {
    await resolveTestUnit(r'''
main() {
  var v = 1;
  print(v = 2);
}
''');
    await assertHasFix(r'''
main() {
  print(2);
}
''');
  }

  test_inArgumentList2() async {
    await resolveTestUnit(r'''
main() {
  var v = 1;
  f(v = 1, 2);
}
void f(a, b) { }
''');
    await assertHasFix(r'''
main() {
  f(1, 2);
}
void f(a, b) { }
''');
  }

  test_inArgumentList3() async {
    await resolveTestUnit(r'''
main() {
  var v = 1;
  f(v = 1, v = 2);
}
void f(a, b) { }
''');
    await assertHasFix(r'''
main() {
  f(1, 2);
}
void f(a, b) { }
''');
  }

  test_inDeclarationList() async {
    await resolveTestUnit(r'''
main() {
  var v = 1, v2 = 3;
  v = 2;
  print(v2);
}
''');
    await assertHasFix(r'''
main() {
  var v2 = 3;
  print(v2);
}
''');
  }

  test_inDeclarationList2() async {
    await resolveTestUnit(r'''
main() {
  var v = 1, v2 = 3;
  print(v);
}
''');
    await assertHasFix(r'''
main() {
  var v = 1;
  print(v);
}
''');
  }

  test_withReferences() async {
    await resolveTestUnit(r'''
main() {
  var v = 1;
  v = 2;
}
''');
    await assertHasFix(r'''
main() {
}
''');
  }

  test_withReferences_beforeDeclaration() async {
    // CompileTimeErrorCode.REFERENCED_BEFORE_DECLARATION
    verifyNoTestUnitErrors = false;
    await resolveTestUnit(r'''
main() {
  v = 2;
  var v = 1;
}
''');
    await assertHasFix(r'''
main() {
}
''',
        errorFilter: (e) =>
            e.errorCode != CompileTimeErrorCode.REFERENCED_BEFORE_DECLARATION);
  }
}
