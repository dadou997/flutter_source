// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../dart/resolution/driver_resolution.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConflictingGenericInterfacesTest);
    defineReflectiveTests(ConflictingGenericInterfacesWithNnbdTest);
  });
}

@reflectiveTest
class ConflictingGenericInterfacesTest extends DriverResolutionTest {
  disabled_test_hierarchyLoop_infinite() async {
    // There is an interface conflict here due to a loop in the class
    // hierarchy leading to an infinite set of implemented types; this loop
    // shouldn't cause non-termination.

    // TODO(paulberry): this test is currently disabled due to non-termination
    // bugs elsewhere in the analyzer.
    await assertErrorsInCode('''
class A<T> implements B<List<T>> {}
class B<T> implements A<List<T>> {}
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 0, 0),
    ]);
  }

  test_class_extends_implements() async {
    await assertErrorsInCode('''
class I<T> {}
class A implements I<int> {}
class B implements I<String> {}
class C extends A implements B {}
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 75, 33),
    ]);
  }

  test_class_extends_with() async {
    await assertErrorsInCode('''
class I<T> {}
class A implements I<int> {}
class B implements I<String> {}
class C extends A with B {}
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 75, 27),
    ]);
  }

  test_classTypeAlias_extends_with() async {
    await assertErrorsInCode('''
class I<T> {}
class A implements I<int> {}
mixin M implements I<String> {}
class C = A with M;
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 75, 19),
    ]);
  }

  test_mixin_on_implements() async {
    await assertErrorsInCode('''
class I<T> {}
class A implements I<int> {}
class B implements I<String> {}
mixin M on A implements B {}
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 75, 28),
    ]);
  }
}

@reflectiveTest
class ConflictingGenericInterfacesWithNnbdTest
    extends ConflictingGenericInterfacesTest {
  @override
  AnalysisOptionsImpl get analysisOptions => AnalysisOptionsImpl()
    ..contextFeatures = FeatureSet.forTesting(
        sdkVersion: '2.6.0', additionalFeatures: [Feature.non_nullable]);

  test_class_extends_implements_nullability() async {
    await assertErrorsInCode('''
class I<T> {}
class A implements I<int> {}
class B implements I<int?> {}
class C extends A implements B {}
''', [
      error(CompileTimeErrorCode.CONFLICTING_GENERIC_INTERFACES, 73, 33),
    ]);
  }

  test_class_extends_implements_optOut() async {
    newFile('/test/lib/a.dart', content: r'''
class I<T> {}
class A implements I<int> {}
class B implements I<int?> {}
''');
    await assertNoErrorsInCode('''
// @dart = 2.5
import 'a.dart';

class C extends A implements B {}
''');
  }

  test_class_extends_optIn_implements_optOut() async {
    newFile('/test/lib/a.dart', content: r'''
class A<T> {}

class B extends A<int> {}
''');
    await assertNoErrorsInCode(r'''
// @dart = 2.5
import 'a.dart';

class C extends B implements A<int> {}
''');
  }
}
