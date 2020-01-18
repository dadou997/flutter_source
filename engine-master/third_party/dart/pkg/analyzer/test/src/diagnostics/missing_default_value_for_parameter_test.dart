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
    defineReflectiveTests(MissingDefaultValueForParameterTest);
  });
}

@reflectiveTest
class MissingDefaultValueForParameterTest extends DriverResolutionTest {
  @override
  AnalysisOptionsImpl get analysisOptions => AnalysisOptionsImpl()
    ..contextFeatures = FeatureSet.forTesting(
        sdkVersion: '2.3.0', additionalFeatures: [Feature.non_nullable]);

  test_constructor_nonNullable_named_optional_noDefault() async {
    await assertErrorsInCode('''
class C {
  C({int a});
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 19, 1),
    ]);
  }

  test_constructor_nonNullable_positional_optional_noDefault() async {
    await assertErrorsInCode('''
class C {
  C([int a]);
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 19, 1),
    ]);
  }

  test_constructor_nullable_named_optional_noDefault() async {
    await assertNoErrorsInCode('''
class C {
  C({int? a});
}
''');
  }

  test_constructor_nullable_named_optional_noDefault_fieldFormal() async {
    await assertNoErrorsInCode('''
class C {
  int? f;
  C({this.f});
}
''');
  }

  test_fieldFormalParameter_functionTyped_named_optional() async {
    await assertNoErrorsInCode('''
class A {
  dynamic f;
  A(void this.f({int a, int? b}));
}
''');
  }

  test_fieldFormalParameter_functionTyped_positional_optional() async {
    await assertNoErrorsInCode('''
class A {
  dynamic f;
  A(void this.f([int a, int? b]));
}
''');
  }

  test_function_nonNullable_named_optional_default() async {
    await assertNoErrorsInCode('''
void f({int a = 0}) {}
''');
  }

  test_function_nonNullable_named_optional_noDefault() async {
    await assertErrorsInCode('''
void f({int a}) {}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 12, 1),
    ]);
  }

  test_function_nonNullable_named_required() async {
    await assertNoErrorsInCode('''
void f({required int a}) {}
''');
  }

  test_function_nonNullable_positional_optional_default() async {
    await assertNoErrorsInCode('''
void f([int a = 0]) {}
''');
  }

  test_function_nonNullable_positional_optional_noDefault() async {
    await assertErrorsInCode('''
void f([int a]) {}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 12, 1),
    ]);
  }

  test_function_nonNullable_positional_required() async {
    await assertNoErrorsInCode('''
void f(int a) {}
''');
  }

  test_function_nullable_named_optional_default() async {
    await assertNoErrorsInCode('''
void f({int? a = 0}) {}
''');
  }

  test_function_nullable_named_optional_noDefault() async {
    await assertNoErrorsInCode('''
void f({int? a}) {}
''');
  }

  test_function_nullable_named_required() async {
    await assertNoErrorsInCode('''
void f({required int? a}) {}
''');
  }

  test_function_nullable_positional_optional_default() async {
    await assertNoErrorsInCode('''
void f([int? a = 0]) {}
''');
  }

  test_function_nullable_positional_optional_noDefault() async {
    await assertNoErrorsInCode('''
void f([int? a]) {}
''');
  }

  test_function_nullable_positional_required() async {
    await assertNoErrorsInCode('''
void f(int? a) {}
''');
  }

  test_functionTypeAlias_named_optional() async {
    await assertNoErrorsInCode('''
typedef void F({int a, int? b});
''');
  }

  test_functionTypeAlias_positional_optional() async {
    await assertNoErrorsInCode('''
typedef void F([int a, int? b]);
''');
  }

  test_functionTypedFormalParameter_named_optional() async {
    await assertNoErrorsInCode('''
void f(void p({int a, int? b})) {}
''');
  }

  test_functionTypedFormalParameter_positional_optional() async {
    await assertNoErrorsInCode('''
void f(void p([int a, int? b])) {}
''');
  }

  test_genericFunctionType_named_optional() async {
    await assertNoErrorsInCode('''
void f(void Function({int a, int? b}) p) {}
''');
  }

  test_genericFunctionType_positional_optional() async {
    await assertNoErrorsInCode('''
void f(void Function([int a, int? b]) p) {}
''');
  }

  test_genericFunctionType_positional_optional2() async {
    await assertNoErrorsInCode('''
void f(void Function([int, int?]) p) {}
''');
  }

  test_method_nonNullable_named_optional_noDefault() async {
    await assertErrorsInCode('''
class C {
  void foo({int a}) {}
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 26, 1),
    ]);
  }

  test_method_nonNullable_positional_optional_noDefault() async {
    await assertErrorsInCode('''
class C {
  void foo([int a]) {}
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 26, 1),
    ]);
  }

  test_method_nullable_named_optional_noDefault() async {
    await assertNoErrorsInCode('''
class C {
  void foo({int? a}) {}
}
''');
  }

  test_method_potentiallyNonNullable_named_optional() async {
    await assertErrorsInCode('''
class A<T extends Object?> {
  void foo({T a}) {}
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 43, 1),
    ]);
  }

  test_method_potentiallyNonNullable_positional_optional() async {
    await assertErrorsInCode('''
class A<T extends Object?> {
  void foo([T a]) {}
}
''', [
      error(CompileTimeErrorCode.MISSING_DEFAULT_VALUE_FOR_PARAMETER, 43, 1),
    ]);
  }
}
