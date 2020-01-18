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
    defineReflectiveTests(AddDiagnosticPropertyReferenceTest);
  });
}

@reflectiveTest
class AddDiagnosticPropertyReferenceTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.ADD_DIAGNOSTIC_PROPERTY_REFERENCE;

  @override
  String get lintCode => LintNames.diagnostic_describe_all_properties;

  test_boolField_debugFillProperties() async {
    await resolveTestUnit('''
class Absorber extends Widget {
  bool get absorbing => _absorbing;
  bool _absorbing;
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('absorbing', absorbing));
  }
}
''');
    await assertHasFix('''
class Absorber extends Widget {
  bool get absorbing => _absorbing;
  bool _absorbing;
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('absorbing', absorbing));
    properties.add(DiagnosticsProperty<bool>('ignoringSemantics', ignoringSemantics));
  }
}
''');
  }

  test_boolField_debugFillProperties_empty() async {
    await resolveTestUnit('''
class Absorber extends Widget {
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  }
}
''');
    await assertHasFix('''
class Absorber extends Widget {
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties.add(DiagnosticsProperty<bool>('ignoringSemantics', ignoringSemantics));
  }
}
''');
  }

  test_boolField_debugFillProperties_empty_customParamName() async {
    await resolveTestUnit('''
class Absorber extends Widget {
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder props) {
  }
}
''');
    await assertHasFix('''
class Absorber extends Widget {
  bool /*LINT*/ignoringSemantics;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder props) {
    props.add(DiagnosticsProperty<bool>('ignoringSemantics', ignoringSemantics));
  }
}
''');
  }

  test_boolGetter_debugFillProperties() async {
    await resolveTestUnit('''
class Absorber extends Widget {
  bool get /*LINT*/absorbing => _absorbing;
  bool _absorbing;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class Absorber extends Widget {
  bool get /*LINT*/absorbing => _absorbing;
  bool _absorbing;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('absorbing', absorbing));
  }
}
''');
  }

  test_colorField_debugFillProperties() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';
class A extends Widget {
  Color /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
import 'package:flutter/material.dart';
class A extends Widget {
  Color /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('field', field));
  }
}
''');
  }

  test_doubleField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  double /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  double /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('field', field));
  }
}
''');
  }

  test_dynamicField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  dynamic /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  dynamic /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty('field', field));
  }
}
''');
  }

  test_enumField_debugFillProperties() async {
    await resolveTestUnit('''
enum Foo {bar}
class A extends Widget {
  Foo /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
enum Foo {bar}
class A extends Widget {
  Foo /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Foo>('field', field));
  }
}
''');
  }

  test_functionField_debugFillProperties() async {
    addFlutterPackage();
    await resolveTestUnit('''
import 'package:flutter/material.dart';

typedef ValueChanged<T> = void Function(T value);

class A extends Widget {
  ValueChanged<double> /*LINT*/onChanged;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
import 'package:flutter/material.dart';

typedef ValueChanged<T> = void Function(T value);

class A extends Widget {
  ValueChanged<double> /*LINT*/onChanged;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<ValueChanged<double>>.has('onChanged', onChanged));
  }
}
''');
  }

  test_intField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  int /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  int /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('field', field));
  }
}
''');
  }

  test_iterableField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  Iterable<String> /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  Iterable<String> /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<String>('field', field));
  }
}
''');
  }

  test_listField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  List<List<String>> /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  List<List<String>> /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<List<String>>('field', field));
  }
}
''');
  }

  test_matrix4Field_debugFillProperties() async {
    addVectorMathPackage();
    await resolveTestUnit('''
import 'package:vector_math/vector_math_64.dart';
class A extends Widget {
  Matrix4 /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
import 'package:vector_math/vector_math_64.dart';
class A extends Widget {
  Matrix4 /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(TransformProperty('field', field));
  }
}
''');
  }

  test_objectField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  Object /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  Object /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Object>('field', field));
  }
}
''');
  }

  test_stringField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  String /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  String /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('field', field));
  }
}
''');
  }

  test_stringField_noDebugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  String /*LINT*/field;
}
''');
    await assertHasFix('''
class A extends Widget {
  String /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('field', field));
  }
}
''');
  }

  test_typeOutOfScopeField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  ClassNotInScope<bool> /*LINT*/onChanged;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  ClassNotInScope<bool> /*LINT*/onChanged;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ClassNotInScope<bool>>('onChanged', onChanged));
  }
}
''');
  }

  test_typeOutOfScopeGetter_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  ClassNotInScope<bool> get /*LINT*/onChanged => null;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  ClassNotInScope<bool> get /*LINT*/onChanged => null;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ClassNotInScope<bool>>('onChanged', onChanged));
  }
}
''');
  }

  test_varField_debugFillProperties() async {
    await resolveTestUnit('''
class A extends Widget {
  var /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
  }
}
''');
    await assertHasFix('''
class A extends Widget {
  var /*LINT*/field;
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty('field', field));
  }
}
''');
  }

  // todo (pq): consider a test for a body w/ no CR
}
