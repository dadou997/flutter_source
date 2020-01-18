// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/task/strong/checker.dart';
import 'package:nnbd_migration/src/fix_aggregator.dart';
import 'package:nnbd_migration/src/fix_builder.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'migration_visitor_test_base.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FixBuilderTest);
  });
}

/// Information about the target of an assignment expression analyzed by
/// [FixBuilder].
class AssignmentTargetInfo {
  /// The type that the assignment target has when read.  This is only relevant
  /// for compound assignments (since they both read and write the assignment
  /// target)
  final DartType readType;

  /// The type that the assignment target has when written to.
  final DartType writeType;

  AssignmentTargetInfo(this.readType, this.writeType);
}

@reflectiveTest
class FixBuilderTest extends EdgeBuilderTestBase {
  static const isNullCheck = TypeMatcher<NullCheck>();

  static const isAddRequiredKeyword = TypeMatcher<AddRequiredKeyword>();

  static const isMakeNullable = TypeMatcher<MakeNullable>();

  DartType get dynamicType => postMigrationTypeProvider.dynamicType;

  DartType get objectType => postMigrationTypeProvider.objectType;

  TypeProvider get postMigrationTypeProvider =>
      (typeProvider as TypeProviderImpl).asNonNullableByDefault;

  @override
  Future<CompilationUnit> analyze(String code) async {
    var unit = await super.analyze(code);
    graph.propagate();
    return unit;
  }

  Map<AstNode, NodeChange> scopedChanges(
          FixBuilder fixBuilder, AstNode scope) =>
      {
        for (var entry in fixBuilder.changes.entries)
          if (_isInScope(entry.key, scope)) entry.key: entry.value
      };

  Map<AstNode, Set<Problem>> scopedProblems(
          FixBuilder fixBuilder, AstNode scope) =>
      {
        for (var entry in fixBuilder.problems.entries)
          if (_isInScope(entry.key, scope)) entry.key: entry.value
      };

  Future<void>
      test_assignmentExpression_compound_combined_nullable_noProblem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*?*/ value);
  f(int/*!*/ y) => x += y;
}
''');
    visitSubexpression(findNode.assignment('+='), '_D?');
  }

  Future<void>
      test_assignmentExpression_compound_combined_nullable_noProblem_dynamic() async {
    await analyze('''
abstract class _E {
  dynamic get x;
  void set x(Object/*!*/ value);
  f(int/*!*/ y) => x += y;
}
''');
    var assignment = findNode.assignment('+=');
    visitSubexpression(assignment, 'dynamic');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void>
      test_assignmentExpression_compound_combined_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*!*/ value);
  f(int/*!*/ y) => x += y;
}
''');
    var assignment = findNode.assignment('+=');
    visitSubexpression(assignment, '_D', problems: {
      assignment: {const CompoundAssignmentCombinedNullable()}
    });
  }

  Future<void> test_assignmentExpression_compound_dynamic() async {
    // To confirm that the RHS is visited, we check that a null check was
    // properly inserted into a subexpression of the RHS.
    await analyze('''
_f(dynamic x, int/*?*/ y) => x += y + 1;
''');
    visitSubexpression(findNode.assignment('+='), 'dynamic',
        changes: {findNode.simple('y +'): isNullCheck});
  }

  Future<void> test_assignmentExpression_compound_intRules() async {
    await analyze('''
_f(int x, int y) => x += y;
''');
    visitSubexpression(findNode.assignment('+='), 'int');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_assignmentExpression_compound_lhs_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*?*/ get x;
  void set x(_C/*?*/ value);
  f(int/*!*/ y) => x += y;
}
''');
    var assignment = findNode.assignment('+=');
    visitSubexpression(assignment, '_D', problems: {
      assignment: {const CompoundAssignmentReadNullable()}
    });
  }

  @FailingTest(issue: 'https://github.com/dart-lang/sdk/issues/39641')
  Future<void> test_assignmentExpression_compound_promoted() async {
    await analyze('''
f(bool/*?*/ x, bool/*?*/ y) => x != null && (x = y);
''');
    // It is ok to assign a nullable value to `x` even though it is promoted to
    // non-nullable, so `y` should not be null-checked.  However, the whole
    // assignment `x = y` should be null checked because the RHS of `&&` cannot
    // be nullable.
    visitSubexpression(findNode.binary('&&'), 'bool',
        changes: {findNode.parenthesized('x = y'): isNullCheck});
  }

  Future<void> test_assignmentExpression_compound_rhs_nonNullable() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
_f(_C/*!*/ x, int/*!*/ y) => x += y;
''');
    visitSubexpression(findNode.assignment('+='), '_D');
  }

  @FailingTest(issue: 'https://github.com/dart-lang/sdk/issues/39642')
  Future<void> test_assignmentExpression_compound_rhs_nullable_check() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
_f(_C/*!*/ x, int/*?*/ y) => x += y;
''');
    visitSubexpression(findNode.assignment('+='), '_D',
        changes: {findNode.simple('y;'): isNullCheck});
  }

  Future<void> test_assignmentExpression_compound_rhs_nullable_noCheck() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*?*/ value);
}
abstract class _D extends _C {}
_f(_C/*!*/ x, int/*?*/ y) => x += y;
''');
    visitSubexpression(findNode.assignment('+='), '_D');
  }

  Future<void>
      test_assignmentExpression_null_aware_rhs_does_not_promote() async {
    await analyze('''
_f(bool/*?*/ b, int/*?*/ i) {
  b ??= i.isEven; // 1
  b = i.isEven; // 2
  b = i.isEven; // 3
}
''');
    // The null check inserted at 1 fails to promote i because it's inside the
    // `??=`, so a null check is inserted at 2.  This does promote i, so no null
    // check is inserted at 3.
    visitStatement(findNode.block('{'), changes: {
      findNode.simple('i.isEven; // 1'): isNullCheck,
      findNode.simple('i.isEven; // 2'): isNullCheck
    });
  }

  Future<void> test_assignmentExpression_null_aware_rhs_nonNullable() async {
    await analyze('''
abstract class _B {}
abstract class _C extends _B {}
abstract class _D extends _C {}
abstract class _E extends _C {}
abstract class _F {
  _D/*?*/ get x;
  void set x(_B/*?*/ value);
  f(_E/*!*/ y) => x ??= y;
}
''');
    visitSubexpression(findNode.assignment('??='), '_C');
  }

  Future<void> test_assignmentExpression_null_aware_rhs_nullable() async {
    await analyze('''
abstract class _B {}
abstract class _C extends _B {}
abstract class _D extends _C {}
abstract class _E extends _C {}
abstract class _F {
  _D/*?*/ get x;
  void set x(_B/*?*/ value);
  f(_E/*?*/ y) => x ??= y;
}
''');
    visitSubexpression(findNode.assignment('??='), '_C?');
  }

  Future<void>
      test_assignmentExpression_simple_nonNullable_to_nonNullable() async {
    await analyze('''
_f(int/*!*/ x, int/*!*/ y) => x = y;
''');
    visitSubexpression(findNode.assignment('= '), 'int');
  }

  Future<void>
      test_assignmentExpression_simple_nonNullable_to_nullable() async {
    await analyze('''
_f(int/*?*/ x, int/*!*/ y) => x = y;
''');
    visitSubexpression(findNode.assignment('= '), 'int');
  }

  Future<void>
      test_assignmentExpression_simple_nullable_to_nonNullable() async {
    await analyze('''
_f(int/*!*/ x, int/*?*/ y) => x = y;
''');
    visitSubexpression(findNode.assignment('= '), 'int',
        changes: {findNode.simple('y;'): isNullCheck});
  }

  Future<void> test_assignmentExpression_simple_nullable_to_nullable() async {
    await analyze('''
_f(int/*?*/ x, int/*?*/ y) => x = y;
''');
    visitSubexpression(findNode.assignment('= '), 'int?');
  }

  @FailingTest(issue: 'https://github.com/dart-lang/sdk/issues/39641')
  Future<void> test_assignmentExpression_simple_promoted() async {
    await analyze('''
_f(bool/*?*/ x, bool/*?*/ y) => x != null && (x = y) != null;
''');
    // On the RHS of the `&&`, `x` is promoted to non-nullable, but it is still
    // considered to be a nullable assignment target, so no null check is
    // generated for `y`.
    visitSubexpression(findNode.binary('&&'), 'bool');
  }

  Future<void> test_assignmentTarget_indexExpression_compound_dynamic() async {
    await analyze('''
_f(dynamic d, int/*?*/ i) => d[i] += 0;
''');
    visitAssignmentTarget(findNode.index('d[i]'), 'dynamic', 'dynamic');
  }

  Future<void> test_assignmentTarget_indexExpression_compound_simple() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
  void operator[]=(String s, num n) {}
}
_f(_C c) => c['foo'] += 0;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'num');
  }

  Future<void>
      test_assignmentTarget_indexExpression_compound_simple_check_lhs() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
  void operator[]=(String s, num n) {}
}
_f(_C/*?*/ c) => c['foo'] += 0;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'num',
        changes: {findNode.simple('c['): isNullCheck});
  }

  @FailingTest(reason: 'TODO(paulberry): decide if this is worth caring about')
  Future<void>
      test_assignmentTarget_indexExpression_compound_simple_check_rhs() async {
    await analyze('''
class _C {
  int operator[](String/*!*/ s) => 1;
  void operator[]=(String/*?*/ s, num n) {}
}
_f(_C c, String/*?*/ s) => c[s] += 0;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'num',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void>
      test_assignmentTarget_indexExpression_compound_substituted() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U u, T t) {}
}
_f(_C<int, String> c) => c['foo'] += 1;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'int');
  }

  @FailingTest(reason: 'TODO(paulberry): decide if this is worth caring about')
  Future<void>
      test_assignmentTarget_indexExpression_compound_substituted_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U/*?*/ u, T t) {}
}
_f(_C<int, String/*!*/> c, String/*?*/ s) => c[s] += 1;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'int',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void>
      test_assignmentTarget_indexExpression_compound_substituted_no_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U u, T t) {}
}
_f(_C<int, String/*?*/> c, String/*?*/ s) => c[s] += 0;
''');
    visitAssignmentTarget(findNode.index('c['), 'int', 'int');
  }

  Future<void> test_assignmentTarget_indexExpression_dynamic() async {
    await analyze('''
_f(dynamic d, int/*?*/ i) => d[i] = 0;
''');
    visitAssignmentTarget(findNode.index('d[i]'), null, 'dynamic');
  }

  Future<void> test_assignmentTarget_indexExpression_simple() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
  void operator[]=(String s, num n) {}
}
_f(_C c) => c['foo'] = 0;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'num');
  }

  Future<void> test_assignmentTarget_indexExpression_simple_check_lhs() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
  void operator[]=(String s, num n) {}
}
_f(_C/*?*/ c) => c['foo'] = 0;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'num',
        changes: {findNode.simple('c['): isNullCheck});
  }

  Future<void> test_assignmentTarget_indexExpression_simple_check_rhs() async {
    await analyze('''
class _C {
  int operator[](String/*?*/ s) => 1;
  void operator[]=(String/*!*/ s, num n) {}
}
_f(_C c, String/*?*/ s) => c[s] = 0;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'num',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void> test_assignmentTarget_indexExpression_substituted() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U u, T t) {}
}
_f(_C<int, String> c) => c['foo'] = 1;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'int');
  }

  Future<void>
      test_assignmentTarget_indexExpression_substituted_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U/*!*/ u, T t) {}
}
_f(_C<int, String/*!*/> c, String/*?*/ s) => c[s] = 1;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'int',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void>
      test_assignmentTarget_indexExpression_substituted_no_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
  void operator[]=(U u, T t) {}
}
_f(_C<int, String/*?*/> c, String/*?*/ s) => c[s] = 0;
''');
    visitAssignmentTarget(findNode.index('c['), null, 'int');
  }

  Future<void> test_assignmentTarget_prefixedIdentifier_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d) => d.x += 1;
''');
    visitAssignmentTarget(findNode.prefixed('d.x'), 'dynamic', 'dynamic');
  }

  Future<void> test_assignmentTarget_propertyAccess_dynamic() async {
    await analyze('''
_f(dynamic d) => (d).x += 1;
''');
    visitAssignmentTarget(
        findNode.propertyAccess('(d).x'), 'dynamic', 'dynamic');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_dynamic_notCompound() async {
    await analyze('''
_f(dynamic d) => (d).x = 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(d).x'), null, 'dynamic');
  }

  Future<void> test_assignmentTarget_propertyAccess_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C c) => (c).x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), 'int', 'int');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_field_nonNullable_notCompound() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C c) => (c).x = 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), null, 'int');
  }

  Future<void> test_assignmentTarget_propertyAccess_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x = 0;
}
_f(_C c) => (c).x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), 'int?', 'int?');
  }

  Future<void> test_assignmentTarget_propertyAccess_getter_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ get x;
  void set x(num/*?*/ value);
}
_f(_C c) => (c).x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), 'int?', 'num?');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_getter_setter_check_lhs() async {
    await analyze('''
abstract class _C {
  int get x;
  void set x(num value);
}
_f(_C/*?*/ c) => (c).x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), 'int', 'num',
        changes: {findNode.parenthesized('(c).x'): isNullCheck});
  }

  Future<void>
      test_assignmentTarget_propertyAccess_getter_setter_nonNullable() async {
    await analyze('''
abstract class _C {
  int/*!*/ get x;
  void set x(num/*!*/ value);
}
_f(_C c) => (c).x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('(c).x'), 'int', 'num');
  }

  Future<void> test_assignmentTarget_propertyAccess_nullAware_dynamic() async {
    await analyze('''
_f(dynamic d) => d?.x += 1;
''');
    visitAssignmentTarget(
        findNode.propertyAccess('d?.x'), 'dynamic', 'dynamic');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_nullAware_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C/*?*/ c) => c?.x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('c?.x'), 'int', 'int');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_nullAware_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x = 0;
}
_f(_C/*?*/ c) => c?.x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('c?.x'), 'int?', 'int?');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_nullAware_getter_setter_nonNullable() async {
    await analyze('''
abstract class _C {
  int/*!*/ get x;
  void set x(num/*!*/ value);
}
_f(_C/*?*/ c) => c?.x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('c?.x'), 'int', 'num');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_nullAware_getter_setter_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ get x;
  void set x(num/*?*/ value);
}
_f(_C/*?*/ c) => c?.x += 1;
''');
    visitAssignmentTarget(findNode.propertyAccess('c?.x'), 'int?', 'num?');
  }

  Future<void>
      test_assignmentTarget_propertyAccess_nullAware_substituted() async {
    await analyze('''
abstract class _C<T> {
  _E<T> get x;
  void set x(_D<T> value);
}
class _D<T> implements Iterable<T> {
  noSuchMethod(invocation) => super.noSuchMethod(invocation);
  _D<T> operator+(int i) => this;
}
class _E<T> extends _D<T> {}
_f(_C<int>/*?*/ c) => c?.x += 1;
''');
    visitAssignmentTarget(
        findNode.propertyAccess('c?.x'), '_E<int>', '_D<int>');
  }

  Future<void> test_assignmentTarget_propertyAccess_substituted() async {
    await analyze('''
abstract class _C<T> {
  _E<T> get x;
  void set x(_D<T> value);
}
class _D<T> implements Iterable<T> {
  noSuchMethod(invocation) => super.noSuchMethod(invocation);
  _D<T> operator+(int i) => this;
}
class _E<T> extends _D<T> {}
_f(_C<int> c) => (c).x += 1;
''');
    visitAssignmentTarget(
        findNode.propertyAccess('(c).x'), '_E<int>', '_D<int>');
  }

  Future<void> test_assignmentTarget_simpleIdentifier_field_generic() async {
    await analyze('''
abstract class _C<T> {
  _C<T> operator+(int i);
}
class _D<T> {
  _D(this.x);
  _C<T/*!*/>/*!*/ x;
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x +='), '_C<T>', '_C<T>');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x;
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x '), 'int', 'int');
  }

  Future<void> test_assignmentTarget_simpleIdentifier_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x;
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x '), 'int?', 'int?');
  }

  Future<void> test_assignmentTarget_simpleIdentifier_getset_generic() async {
    await analyze('''
abstract class _C<T> {
  _C<T> operator+(int i);
}
abstract class _D<T> extends _C<T> {}
abstract class _E<T> {
  _D<T/*!*/>/*!*/ get x;
  void set x(_C<T/*!*/>/*!*/ value);
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x +='), '_D<T>', '_C<T>');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_getset_getterNullable() async {
    await analyze('''
class _C {
  int/*?*/ get x => 1;
  void set x(int/*!*/ value) {}
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x +='), 'int?', 'int');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_getset_setterNullable() async {
    await analyze('''
class _C {
  int/*!*/ get x => 1;
  void set x(int/*?*/ value) {}
  _f() => x += 0;
}
''');
    visitAssignmentTarget(findNode.simple('x +='), 'int', 'int?');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_localVariable_nonNullable() async {
    await analyze('''
_f(int/*!*/ x) => x += 0;
''');
    visitAssignmentTarget(findNode.simple('x '), 'int', 'int');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_localVariable_nullable() async {
    await analyze('''
_f(int/*?*/ x) => x += 0;
''');
    visitAssignmentTarget(findNode.simple('x '), 'int?', 'int?');
  }

  Future<void>
      test_assignmentTarget_simpleIdentifier_setter_nonNullable() async {
    await analyze('''
class _C {
  void set x(int/*!*/ value) {}
  _f() => x = 0;
}
''');
    visitAssignmentTarget(findNode.simple('x '), null, 'int');
  }

  Future<void> test_assignmentTarget_simpleIdentifier_setter_nullable() async {
    await analyze('''
class _C {
  void set x(int/*?*/ value) {}
  _f() => x = 0;
}
''');
    visitAssignmentTarget(findNode.simple('x '), null, 'int?');
  }

  Future<void> test_binaryExpression_ampersand_ampersand() async {
    await analyze('''
_f(bool x, bool y) => x && y;
''');
    visitSubexpression(findNode.binary('&&'), 'bool');
  }

  Future<void> test_binaryExpression_ampersand_ampersand_flow() async {
    await analyze('''
_f(bool/*?*/ x) => x != null && x;
''');
    visitSubexpression(findNode.binary('&&'), 'bool');
  }

  Future<void> test_binaryExpression_ampersand_ampersand_nullChecked() async {
    await analyze('''
_f(bool/*?*/ x, bool/*?*/ y) => x && y;
''');
    var xRef = findNode.simple('x &&');
    var yRef = findNode.simple('y;');
    visitSubexpression(findNode.binary('&&'), 'bool',
        changes: {xRef: isNullCheck, yRef: isNullCheck});
  }

  Future<void> test_binaryExpression_bang_eq() async {
    await analyze('''
_f(Object/*?*/ x, Object/*?*/ y) => x != y;
''');
    visitSubexpression(findNode.binary('!='), 'bool');
  }

  Future<void> test_binaryExpression_bar_bar() async {
    await analyze('''
_f(bool x, bool y) {
  return x || y;
}
''');
    visitSubexpression(findNode.binary('||'), 'bool');
  }

  Future<void> test_binaryExpression_bar_bar_flow() async {
    await analyze('''
_f(bool/*?*/ x) {
  return x == null || x;
}
''');
    visitSubexpression(findNode.binary('||'), 'bool');
  }

  Future<void> test_binaryExpression_bar_bar_nullChecked() async {
    await analyze('''
_f(Object/*?*/ x, Object/*?*/ y) {
  return x || y;
}
''');
    var xRef = findNode.simple('x ||');
    var yRef = findNode.simple('y;');
    visitSubexpression(findNode.binary('||'), 'bool',
        changes: {xRef: isNullCheck, yRef: isNullCheck});
  }

  Future<void> test_binaryExpression_eq_eq() async {
    await analyze('''
_f(Object/*?*/ x, Object/*?*/ y) {
  return x == y;
}
''');
    visitSubexpression(findNode.binary('=='), 'bool');
  }

  Future<void> test_binaryExpression_question_question() async {
    await analyze('''
_f(int/*?*/ x, double/*?*/ y) {
  return x ?? y;
}
''');
    visitSubexpression(findNode.binary('??'), 'num?');
  }

  Future<void> test_binaryExpression_question_question_flow() async {
    await analyze('''
_f(int/*?*/ x, int/*?*/ y) =>
    <dynamic>[x ?? (y != null ? 1 : throw 'foo'), y + 1];
''');
    // The null check on the RHS of the `??` doesn't promote, because it is not
    // guaranteed to execute.
    visitSubexpression(findNode.listLiteral('['), 'List<dynamic>',
        changes: {findNode.simple('y +'): isNullCheck});
  }

  @FailingTest(issue: 'https://github.com/dart-lang/sdk/issues/39642')
  Future<void> test_binaryExpression_question_question_nullChecked() async {
    await analyze('''
Object/*!*/ _f(int/*?*/ x, double/*?*/ y) {
  return x ?? y;
}
''');
    var yRef = findNode.simple('y;');
    visitSubexpression(findNode.binary('??'), 'num',
        changes: {yRef: isNullCheck});
  }

  Future<void> test_binaryExpression_userDefinable_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d, int/*?*/ i) => d + i;
''');
    visitSubexpression(findNode.binary('+'), 'dynamic');
  }

  Future<void> test_binaryExpression_userDefinable_intRules() async {
    await analyze('''
_f(int i, int j) => i + j;
''');
    visitSubexpression(findNode.binary('+'), 'int');
  }

  Future<void> test_binaryExpression_userDefinable_simple() async {
    await analyze('''
class _C {
  int operator+(String s) => 1;
}
_f(_C c) => c + 'foo';
''');
    visitSubexpression(findNode.binary('c +'), 'int');
  }

  Future<void> test_binaryExpression_userDefinable_simple_check_lhs() async {
    await analyze('''
class _C {
  int operator+(String s) => 1;
}
_f(_C/*?*/ c) => c + 'foo';
''');
    visitSubexpression(findNode.binary('c +'), 'int',
        changes: {findNode.simple('c +'): isNullCheck});
  }

  Future<void> test_binaryExpression_userDefinable_simple_check_rhs() async {
    await analyze('''
class _C {
  int operator+(String/*!*/ s) => 1;
}
_f(_C c, String/*?*/ s) => c + s;
''');
    visitSubexpression(findNode.binary('c +'), 'int',
        changes: {findNode.simple('s;'): isNullCheck});
  }

  Future<void> test_binaryExpression_userDefinable_substituted() async {
    await analyze('''
class _C<T, U> {
  T operator+(U u) => throw 'foo';
}
_f(_C<int, String> c) => c + 'foo';
''');
    visitSubexpression(findNode.binary('c +'), 'int');
  }

  Future<void>
      test_binaryExpression_userDefinable_substituted_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator+(U/*!*/ u) => throw 'foo';
}
_f(_C<int, String/*!*/> c, String/*?*/ s) => c + s;
''');
    visitSubexpression(findNode.binary('c +'), 'int',
        changes: {findNode.simple('s;'): isNullCheck});
  }

  Future<void>
      test_binaryExpression_userDefinable_substituted_no_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator+(U u) => throw 'foo';
}
_f(_C<int, String/*?*/> c, String/*?*/ s) => c + s;
''');
    visitSubexpression(findNode.binary('c +'), 'int');
  }

  Future<void> test_block() async {
    await analyze('''
_f(int/*?*/ x, int/*?*/ y) {
  { // block
    x + 1;
    y + 1;
  }
}
''');
    visitStatement(findNode.statement('{ // block'), changes: {
      findNode.simple('x + 1'): isNullCheck,
      findNode.simple('y + 1'): isNullCheck
    });
  }

  Future<void> test_booleanLiteral() async {
    await analyze('''
f() => true;
''');
    visitSubexpression(findNode.booleanLiteral('true'), 'bool');
  }

  Future<void> test_conditionalExpression_flow_as_condition() async {
    await analyze('''
_f(bool x, int/*?*/ y) => (x ? y != null : y != null) ? y + 1 : 0;
''');
    // No explicit check needs to be added to `y + 1`, because both arms of the
    // conditional can only be true if `y != null`.
    visitSubexpression(findNode.conditionalExpression('y + 1'), 'int');
  }

  Future<void> test_conditionalExpression_flow_condition() async {
    await analyze('''
_f(bool/*?*/ x) => x ? (x && true) : (x && true);
''');
    // No explicit check needs to be added to either `x && true`, because there
    // is already an explicit null check inserted for the condition.
    visitSubexpression(findNode.conditionalExpression('x ?'), 'bool',
        changes: {findNode.simple('x ?'): isNullCheck});
  }

  Future<void> test_conditionalExpression_flow_then_else() async {
    await analyze('''
_f(bool x, bool/*?*/ y) => (x ? (y && true) : (y && true)) && y;
''');
    // No explicit check needs to be added to the final reference to `y`,
    // because null checks are added to the "then" and "else" branches promoting
    // y.
    visitSubexpression(findNode.binary('&& y'), 'bool', changes: {
      findNode.simple('y && true) '): isNullCheck,
      findNode.simple('y && true))'): isNullCheck
    });
  }

  Future<void> test_conditionalExpression_lub() async {
    await analyze('''
_f(bool b) => b ? 1 : 1.0;
''');
    visitSubexpression(findNode.conditionalExpression('1.0'), 'num');
  }

  Future<void> test_conditionalExpression_throw_promotes() async {
    await analyze('''
_f(int/*?*/ x) =>
    <dynamic>[(x != null ? 1 : throw 'foo'), x + 1];
''');
    // No null check needs to be added to `x + 1`, because there is already an
    // explicit null check.
    visitSubexpression(findNode.listLiteral('['), 'List<dynamic>');
  }

  Future<void>
      test_defaultFormalParameter_add_required_no_because_default() async {
    await analyze('''
int _f({int x = 0}) => x + 1;
''');
    visitAll();
  }

  Future<void>
      test_defaultFormalParameter_add_required_no_because_nullable() async {
    await analyze('''
int _f({int/*?*/ x}) => 1;
''');
    visitAll(changes: {findNode.typeName('int/*?*/ x'): isMakeNullable});
  }

  Future<void>
      test_defaultFormalParameter_add_required_no_because_positional() async {
    await analyze('''
int _f([int/*!*/ x]) => x + 1;
''');
    visitAll(problems: {
      findNode.defaultParameter('int/*!*/ x'): {
        const NonNullableUnnamedOptionalParameter()
      }
    });
  }

  Future<void> test_defaultFormalParameter_add_required_yes() async {
    await analyze('''
int _f({int x}) => x + 1;
''');
    visitAll(
        changes: {findNode.defaultParameter('int x'): isAddRequiredKeyword});
  }

  Future<void> test_doubleLiteral() async {
    await analyze('''
f() => 1.0;
''');
    visitSubexpression(findNode.doubleLiteral('1.0'), 'double');
  }

  Future<void> test_expressionStatement() async {
    await analyze('''
_f(int/*!*/ x, int/*?*/ y) {
  x = y;
}
''');
    visitStatement(findNode.statement('x = y'),
        changes: {findNode.simple('y;'): isNullCheck});
  }

  Future<void> test_functionExpressionInvocation_dynamic() async {
    await analyze('''
_f(dynamic d) => d();
''');
    visitSubexpression(findNode.functionExpressionInvocation('d('), 'dynamic');
  }

  Future<void> test_functionExpressionInvocation_function_checked() async {
    await analyze('''
_f(Function/*?*/ func) => func();
''');
    visitSubexpression(
        findNode.functionExpressionInvocation('func('), 'dynamic',
        changes: {findNode.simple('func()'): isNullCheck});
  }

  Future<void> test_functionExpressionInvocation_getter() async {
    await analyze('''
abstract class _C {
  int Function() get f;
}
_f(_C c) => (c.f)();
''');
    visitSubexpression(findNode.functionExpressionInvocation('c.f'), 'int');
  }

  Future<void>
      test_functionExpressionInvocation_getter_looksLikeMethodCall() async {
    await analyze('''
abstract class _C {
  int Function() get f;
}
_f(_C c) => c.f();
''');
    visitSubexpression(findNode.functionExpressionInvocation('c.f'), 'int');
  }

  Future<void> test_functionExpressionInvocation_getter_nullChecked() async {
    await analyze('''
abstract class _C {
  int Function()/*?*/ get f;
}
_f(_C c) => (c.f)();
''');
    visitSubexpression(findNode.functionExpressionInvocation('c.f'), 'int',
        changes: {findNode.parenthesized('c.f'): isNullCheck});
  }

  Future<void>
      test_functionExpressionInvocation_getter_nullChecked_looksLikeMethodCall() async {
    await analyze('''
abstract class _C {
  int Function()/*?*/ get f;
}
_f(_C c) => c.f();
''');
    visitSubexpression(findNode.functionExpressionInvocation('c.f'), 'int',
        changes: {findNode.propertyAccess('c.f'): isNullCheck});
  }

  Future<void> test_ifStatement_flow_promote_in_else() async {
    await analyze('''
_f(int/*?*/ x) {
  if (x == null) {
    x + 1;
  } else {
    x + 2;
  }
}
''');
    visitStatement(findNode.statement('if'),
        changes: {findNode.simple('x + 1'): isNullCheck});
  }

  Future<void> test_ifStatement_flow_promote_in_then() async {
    await analyze('''
_f(int/*?*/ x) {
  if (x != null) {
    x + 1;
  } else {
    x + 2;
  }
}
''');
    visitStatement(findNode.statement('if'),
        changes: {findNode.simple('x + 2'): isNullCheck});
  }

  Future<void> test_ifStatement_flow_promote_in_then_no_else() async {
    await analyze('''
_f(int/*?*/ x) {
  if (x != null) {
    x + 1;
  }
}
''');
    visitStatement(findNode.statement('if'));
  }

  Future<void> test_indexExpression_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d, int/*?*/ i) => d[i];
''');
    visitSubexpression(findNode.index('d[i]'), 'dynamic');
  }

  Future<void> test_indexExpression_simple() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
}
_f(_C c) => c['foo'];
''');
    visitSubexpression(findNode.index('c['), 'int');
  }

  Future<void> test_indexExpression_simple_check_lhs() async {
    await analyze('''
class _C {
  int operator[](String s) => 1;
}
_f(_C/*?*/ c) => c['foo'];
''');
    visitSubexpression(findNode.index('c['), 'int',
        changes: {findNode.simple('c['): isNullCheck});
  }

  Future<void> test_indexExpression_simple_check_rhs() async {
    await analyze('''
class _C {
  int operator[](String/*!*/ s) => 1;
}
_f(_C c, String/*?*/ s) => c[s];
''');
    visitSubexpression(findNode.index('c['), 'int',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void> test_indexExpression_substituted() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
}
_f(_C<int, String> c) => c['foo'];
''');
    visitSubexpression(findNode.index('c['), 'int');
  }

  Future<void> test_indexExpression_substituted_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U/*!*/ u) => throw 'foo';
}
_f(_C<int, String/*!*/> c, String/*?*/ s) => c[s];
''');
    visitSubexpression(findNode.index('c['), 'int',
        changes: {findNode.simple('s]'): isNullCheck});
  }

  Future<void> test_indexExpression_substituted_no_check_rhs() async {
    await analyze('''
class _C<T, U> {
  T operator[](U u) => throw 'foo';
}
_f(_C<int, String/*?*/> c, String/*?*/ s) => c[s];
''');
    visitSubexpression(findNode.index('c['), 'int');
  }

  Future<void> test_integerLiteral() async {
    await analyze('''
f() => 1;
''');
    visitSubexpression(findNode.integerLiteral('1'), 'int');
  }

  Future<void> test_listLiteral_typed() async {
    await analyze('''
_f() => <int>[];
''');
    visitSubexpression(findNode.listLiteral('['), 'List<int>');
  }

  Future<void> test_listLiteral_typed_visit_contents() async {
    await analyze('''
_f(int/*?*/ x) => <int/*!*/>[x];
''');
    visitSubexpression(findNode.listLiteral('['), 'List<int>',
        changes: {findNode.simple('x]'): isNullCheck});
  }

  Future<void> test_methodInvocation_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d) => d.f();
''');
    visitSubexpression(findNode.methodInvocation('d.f'), 'dynamic');
  }

  Future<void> test_methodInvocation_namedParameter() async {
    await analyze('''
abstract class _C {
  int f({int/*!*/ x});
}
_f(_C c, int/*?*/ y) => c.f(x: y);
''');
    visitSubexpression(findNode.methodInvocation('c.f'), 'int',
        changes: {findNode.simple('y);'): isNullCheck});
  }

  Future<void> test_methodInvocation_ordinaryParameter() async {
    await analyze('''
abstract class _C {
  int f(int/*!*/ x);
}
_f(_C c, int/*?*/ y) => c.f(y);
''');
    visitSubexpression(findNode.methodInvocation('c.f'), 'int',
        changes: {findNode.simple('y);'): isNullCheck});
  }

  Future<void> test_methodInvocation_return_nonNullable() async {
    await analyze('''
abstract class _C {
  int f();
}
_f(_C c) => c.f();
''');
    visitSubexpression(findNode.methodInvocation('c.f'), 'int');
  }

  Future<void> test_methodInvocation_return_nonNullable_check_target() async {
    await analyze('''
abstract class _C {
  int f();
}
_f(_C/*?*/ c) => c.f();
''');
    visitSubexpression(findNode.methodInvocation('c.f'), 'int',
        changes: {findNode.simple('c.f'): isNullCheck});
  }

  Future<void> test_methodInvocation_return_nonNullable_nullAware() async {
    await analyze('''
abstract class _C {
  int f();
}
_f(_C/*?*/ c) => c?.f();
''');
    visitSubexpression(findNode.methodInvocation('c?.f'), 'int?');
  }

  Future<void> test_methodInvocation_return_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ f();
}
_f(_C c) => c.f();
''');
    visitSubexpression(findNode.methodInvocation('c.f'), 'int?');
  }

  Future<void> test_methodInvocation_static() async {
    await analyze('''
_f() => _C.g();
class _C {
  static int g() => 1;
}
''');
    visitSubexpression(findNode.methodInvocation('_C.g();'), 'int');
  }

  Future<void> test_methodInvocation_topLevel() async {
    await analyze('''
_f() => _g();
int _g() => 1;
''');
    visitSubexpression(findNode.methodInvocation('_g();'), 'int');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_methodInvocation_toString() async {
    await analyze('''
abstract class _C {}
_f(_C/*?*/ c) => c.toString();
''');
    visitSubexpression(findNode.methodInvocation('c.toString'), 'String');
  }

  Future<void> test_nullAssertion_promotes() async {
    await analyze('''
_f(bool/*?*/ x) => x && x;
''');
    // Only the first `x` is null-checked because thereafter, the type of `x` is
    // promoted to `bool`.
    visitSubexpression(findNode.binary('&&'), 'bool',
        changes: {findNode.simple('x &&'): isNullCheck});
  }

  Future<void> test_nullLiteral() async {
    await analyze('''
f() => null;
''');
    visitSubexpression(findNode.nullLiteral('null'), 'Null');
  }

  Future<void> test_parenthesizedExpression() async {
    await analyze('''
f() => (1);
''');
    visitSubexpression(findNode.integerLiteral('1'), 'int');
  }

  Future<void> test_parenthesizedExpression_flow() async {
    await analyze('''
_f(bool/*?*/ x) => ((x) != (null)) && x;
''');
    visitSubexpression(findNode.binary('&&'), 'bool');
  }

  Future<void> test_postfixExpression_combined_nullable_noProblem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*?*/ value);
  f() => x++;
}
''');
    visitSubexpression(findNode.postfix('++'), '_C');
  }

  @FailingTest(issue: 'https://github.com/dart-lang/sdk/issues/38833')
  Future<void>
      test_postfixExpression_combined_nullable_noProblem_dynamic() async {
    await analyze('''
abstract class _E {
  dynamic get x;
  void set x(Object/*!*/ value);
  f() => x++;
}
''');
    visitSubexpression(findNode.postfix('++'), 'dynamic');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_postfixExpression_combined_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*!*/ value);
  f() => x++;
}
''');
    var postfix = findNode.postfix('++');
    visitSubexpression(postfix, '_C', problems: {
      postfix: {const CompoundAssignmentCombinedNullable()}
    });
  }

  Future<void> test_postfixExpression_decrement_undoes_promotion() async {
    await analyze('''
abstract class _C {
  _C/*?*/ operator-(int value);
}
_f(_C/*?*/ c) { // method
  if (c != null) {
    c--;
    _g(c);
  }
}
_g(_C/*!*/ c) {}
''');
    visitStatement(findNode.block('{ // method'),
        changes: {findNode.simple('c);'): isNullCheck});
  }

  Future<void> test_postfixExpression_dynamic() async {
    await analyze('''
_f(dynamic x) => x++;
''');
    visitSubexpression(findNode.postfix('++'), 'dynamic');
  }

  Future<void> test_postfixExpression_increment_undoes_promotion() async {
    await analyze('''
abstract class _C {
  _C/*?*/ operator+(int value);
}
_f(_C/*?*/ c) { // method
  if (c != null) {
    c++;
    _g(c);
  }
}
_g(_C/*!*/ c) {}
''');
    visitStatement(findNode.block('{ // method'),
        changes: {findNode.simple('c);'): isNullCheck});
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_postfixExpression_lhs_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*?*/ get x;
  void set x(_C/*?*/ value);
  f() => x++;
}
''');
    var postfix = findNode.postfix('++');
    visitSubexpression(postfix, '_C?', problems: {
      postfix: {const CompoundAssignmentReadNullable()}
    });
  }

  Future<void> test_postfixExpression_rhs_nonNullable() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
_f(_C/*!*/ x) => x++;
''');
    visitSubexpression(findNode.postfix('++'), '_C');
  }

  Future<void> test_prefixedIdentifier_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d) => d.x;
''');
    visitSubexpression(findNode.prefixed('d.x'), 'dynamic');
  }

  Future<void> test_prefixedIdentifier_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'int');
  }

  Future<void> test_prefixedIdentifier_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x = 0;
}
_f(_C c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'int?');
  }

  Future<void> test_prefixedIdentifier_getter_check_lhs() async {
    await analyze('''
abstract class _C {
  int get x;
}
_f(_C/*?*/ c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'int',
        changes: {findNode.simple('c.x'): isNullCheck});
  }

  Future<void> test_prefixedIdentifier_getter_nonNullable() async {
    await analyze('''
abstract class _C {
  int/*!*/ get x;
}
_f(_C c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'int');
  }

  Future<void> test_prefixedIdentifier_getter_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ get x;
}
_f(_C c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'int?');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_prefixedIdentifier_object_getter() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => c.hashCode;
''');
    visitSubexpression(findNode.prefixed('c.hashCode'), 'int');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_prefixedIdentifier_object_tearoff() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => c.toString;
''');
    visitSubexpression(findNode.prefixed('c.toString'), 'String Function()');
  }

  Future<void> test_prefixedIdentifier_substituted() async {
    await analyze('''
abstract class _C<T> {
  List<T> get x;
}
_f(_C<int> c) => c.x;
''');
    visitSubexpression(findNode.prefixed('c.x'), 'List<int>');
  }

  Future<void> test_prefixExpression_bang_flow() async {
    await analyze('''
_f(int/*?*/ x) {
  if (!(x == null)) {
    x + 1;
  }
}
''');
    // No null check should be needed on `x + 1` because `!(x == null)` promotes
    // x's type to `int`.
    visitStatement(findNode.statement('if'));
  }

  Future<void> test_prefixExpression_bang_nonNullable() async {
    await analyze('''
_f(bool/*!*/ x) => !x;
''');
    visitSubexpression(findNode.prefix('!x'), 'bool');
  }

  Future<void> test_prefixExpression_bang_nullable() async {
    await analyze('''
_f(bool/*?*/ x) => !x;
''');
    visitSubexpression(findNode.prefix('!x'), 'bool',
        changes: {findNode.simple('x;'): isNullCheck});
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_prefixExpression_combined_nullable_noProblem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*?*/ value);
  f() => ++x;
}
''');
    visitSubexpression(findNode.prefix('++'), '_D?');
  }

  Future<void>
      test_prefixExpression_combined_nullable_noProblem_dynamic() async {
    await analyze('''
abstract class _E {
  dynamic get x;
  void set x(Object/*!*/ value);
  f() => ++x;
}
''');
    var prefix = findNode.prefix('++');
    visitSubexpression(prefix, 'dynamic');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_prefixExpression_combined_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*?*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*!*/ get x;
  void set x(_C/*!*/ value);
  f() => ++x;
}
''');
    var prefix = findNode.prefix('++');
    visitSubexpression(prefix, '_D', problems: {
      prefix: {const CompoundAssignmentCombinedNullable()}
    });
  }

  Future<void> test_prefixExpression_decrement_undoes_promotion() async {
    await analyze('''
abstract class _C {
  _C/*?*/ operator-(int value);
}
_f(_C/*?*/ c) { // method
  if (c != null) {
    --c;
    _g(c);
  }
}
_g(_C/*!*/ c) {}
''');
    visitStatement(findNode.block('{ // method'),
        changes: {findNode.simple('c);'): isNullCheck});
  }

  Future<void> test_prefixExpression_increment_undoes_promotion() async {
    await analyze('''
abstract class _C {
  _C/*?*/ operator+(int value);
}
_f(_C/*?*/ c) { // method
  if (c != null) {
    ++c;
    _g(c);
  }
}
_g(_C/*!*/ c) {}
''');
    visitStatement(findNode.block('{ // method'),
        changes: {findNode.simple('c);'): isNullCheck});
  }

  Future<void> test_prefixExpression_intRules() async {
    await analyze('''
_f(int x) => ++x;
''');
    visitSubexpression(findNode.prefix('++'), 'int');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_prefixExpression_lhs_nullable_problem() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
abstract class _E {
  _C/*?*/ get x;
  void set x(_C/*?*/ value);
  f() => ++x;
}
''');
    var prefix = findNode.prefix('++');
    visitSubexpression(prefix, '_D', problems: {
      prefix: {const CompoundAssignmentReadNullable()}
    });
  }

  Future<void> test_prefixExpression_minus_dynamic() async {
    await analyze('''
_f(dynamic x) => -x;
''');
    visitSubexpression(findNode.prefix('-x'), 'dynamic');
  }

  Future<void> test_prefixExpression_minus_nonNullable() async {
    await analyze('''
_f(int/*!*/ x) => -x;
''');
    visitSubexpression(findNode.prefix('-x'), 'int');
  }

  Future<void> test_prefixExpression_minus_nullable() async {
    await analyze('''
_f(int/*?*/ x) => -x;
''');
    visitSubexpression(findNode.prefix('-x'), 'int',
        changes: {findNode.simple('x;'): isNullCheck});
  }

  Future<void> test_prefixExpression_minus_substitution() async {
    await analyze('''
abstract class _C<T> {
  List<T> operator-();
}
_f(_C<int> x) => -x;
''');
    visitSubexpression(findNode.prefix('-x'), 'List<int>');
  }

  Future<void> test_prefixExpression_rhs_nonNullable() async {
    await analyze('''
abstract class _C {
  _D/*!*/ operator+(int/*!*/ value);
}
abstract class _D extends _C {}
_f(_C/*!*/ x) => ++x;
''');
    visitSubexpression(findNode.prefix('++'), '_D');
  }

  Future<void> test_prefixExpression_tilde_dynamic() async {
    await analyze('''
_f(dynamic x) => ~x;
''');
    visitSubexpression(findNode.prefix('~x'), 'dynamic');
  }

  Future<void> test_prefixExpression_tilde_nonNullable() async {
    await analyze('''
_f(int/*!*/ x) => ~x;
''');
    visitSubexpression(findNode.prefix('~x'), 'int');
  }

  Future<void> test_prefixExpression_tilde_nullable() async {
    await analyze('''
_f(int/*?*/ x) => ~x;
''');
    visitSubexpression(findNode.prefix('~x'), 'int',
        changes: {findNode.simple('x;'): isNullCheck});
  }

  Future<void> test_prefixExpression_tilde_substitution() async {
    await analyze('''
abstract class _C<T> {
  List<T> operator~();
}
_f(_C<int> x) => ~x;
''');
    visitSubexpression(findNode.prefix('~x'), 'List<int>');
  }

  Future<void> test_propertyAccess_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d) => (d).x;
''');
    visitSubexpression(findNode.propertyAccess('(d).x'), 'dynamic');
  }

  Future<void> test_propertyAccess_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'int');
  }

  Future<void> test_propertyAccess_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x = 0;
}
_f(_C c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'int?');
  }

  Future<void> test_propertyAccess_getter_check_lhs() async {
    await analyze('''
abstract class _C {
  int get x;
}
_f(_C/*?*/ c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'int',
        changes: {findNode.parenthesized('(c).x'): isNullCheck});
  }

  Future<void> test_propertyAccess_getter_nonNullable() async {
    await analyze('''
abstract class _C {
  int/*!*/ get x;
}
_f(_C c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'int');
  }

  Future<void> test_propertyAccess_getter_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ get x;
}
_f(_C c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_dynamic() async {
    await analyze('''
Object/*!*/ _f(dynamic d) => d?.x;
''');
    visitSubexpression(findNode.propertyAccess('d?.x'), 'dynamic');
  }

  Future<void> test_propertyAccess_nullAware_field_nonNullable() async {
    await analyze('''
class _C {
  int/*!*/ x = 0;
}
_f(_C/*?*/ c) => c?.x;
''');
    visitSubexpression(findNode.propertyAccess('c?.x'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ x = 0;
}
_f(_C/*?*/ c) => c?.x;
''');
    visitSubexpression(findNode.propertyAccess('c?.x'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_getter_nonNullable() async {
    await analyze('''
abstract class _C {
  int/*!*/ get x;
}
_f(_C/*?*/ c) => c?.x;
''');
    visitSubexpression(findNode.propertyAccess('c?.x'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_getter_nullable() async {
    await analyze('''
abstract class _C {
  int/*?*/ get x;
}
_f(_C/*?*/ c) => c?.x;
''');
    visitSubexpression(findNode.propertyAccess('c?.x'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_object_getter() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => c?.hashCode;
''');
    visitSubexpression(findNode.propertyAccess('c?.hashCode'), 'int?');
  }

  Future<void> test_propertyAccess_nullAware_object_tearoff() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => c?.toString;
''');
    visitSubexpression(
        findNode.propertyAccess('c?.toString'), 'String Function()?');
  }

  Future<void> test_propertyAccess_nullAware_substituted() async {
    await analyze('''
abstract class _C<T> {
  List<T> get x;
}
_f(_C<int>/*?*/ c) => c?.x;
''');
    visitSubexpression(findNode.propertyAccess('c?.x'), 'List<int>?');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_propertyAccess_object_getter() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => (c).hashCode;
''');
    visitSubexpression(findNode.propertyAccess('(c).hashCode'), 'int');
  }

  @FailingTest(reason: 'TODO(paulberry)')
  Future<void> test_propertyAccess_object_tearoff() async {
    await analyze('''
class _C {}
_f(_C/*?*/ c) => (c).toString;
''');
    visitSubexpression(
        findNode.propertyAccess('(c).toString'), 'String Function()');
  }

  Future<void> test_propertyAccess_substituted() async {
    await analyze('''
abstract class _C<T> {
  List<T> get x;
}
_f(_C<int> c) => (c).x;
''');
    visitSubexpression(findNode.propertyAccess('(c).x'), 'List<int>');
  }

  Future<void> test_simpleIdentifier_className() async {
    await analyze('''
_f() => int;
''');
    visitSubexpression(findNode.simple('int'), 'Type');
  }

  Future<void> test_simpleIdentifier_field() async {
    await analyze('''
class _C {
  int i = 1;
  f() => i;
}
''');
    visitSubexpression(findNode.simple('i;'), 'int');
  }

  Future<void> test_simpleIdentifier_field_generic() async {
    await analyze('''
class _C<T> {
  List<T> x = null;
  f() => x;
}
''');
    visitSubexpression(findNode.simple('x;'), 'List<T>?');
  }

  Future<void> test_simpleIdentifier_field_nullable() async {
    await analyze('''
class _C {
  int/*?*/ i = 1;
  f() => i;
}
''');
    visitSubexpression(findNode.simple('i;'), 'int?');
  }

  Future<void> test_simpleIdentifier_getter() async {
    await analyze('''
class _C {
  int get i => 1;
  f() => i;
}
''');
    visitSubexpression(findNode.simple('i;'), 'int');
  }

  Future<void> test_simpleIdentifier_getter_nullable() async {
    await analyze('''
class _C {
  int/*?*/ get i => 1;
  f() => i;
}
''');
    visitSubexpression(findNode.simple('i;'), 'int?');
  }

  Future<void> test_simpleIdentifier_localVariable_nonNullable() async {
    await analyze('''
_f(int x) {
  return x;
}
''');
    visitSubexpression(findNode.simple('x;'), 'int');
  }

  Future<void> test_simpleIdentifier_localVariable_nullable() async {
    await analyze('''
_f(int/*?*/ x) {
  return x;
}
''');
    visitSubexpression(findNode.simple('x;'), 'int?');
  }

  Future<void> test_stringLiteral() async {
    await analyze('''
f() => 'foo';
''');
    visitSubexpression(findNode.stringLiteral("'foo'"), 'String');
  }

  Future<void> test_symbolLiteral() async {
    await analyze('''
f() => #foo;
''');
    visitSubexpression(findNode.symbolLiteral('#foo'), 'Symbol');
  }

  Future<void> test_throw_flow() async {
    await analyze('''
_f(int/*?*/ i) {
  if (i == null) throw 'foo';
  i + 1;
}
''');
    visitStatement(findNode.block('{'));
  }

  Future<void> test_throw_nullable() async {
    await analyze('''
_f(int/*?*/ i) => throw i;
''');
    visitSubexpression(findNode.throw_('throw'), 'Never',
        changes: {findNode.simple('i;'): isNullCheck});
  }

  Future<void> test_throw_simple() async {
    await analyze('''
_f() => throw 'foo';
''');
    visitSubexpression(findNode.throw_('throw'), 'Never');
  }

  Future<void> test_typeName_dynamic() async {
    await analyze('''
void _f() {
  dynamic d = null;
}
''');
    visitTypeAnnotation(findNode.typeAnnotation('dynamic'), 'dynamic');
  }

  Future<void> test_typeName_generic_nonNullable() async {
    await analyze('''
void _f() {
  List<int> i = [0];
}
''');
    visitTypeAnnotation(findNode.typeAnnotation('List<int>'), 'List<int>');
  }

  Future<void> test_typeName_generic_nullable() async {
    await analyze('''
void _f() {
  List<int> i = null;
}
''');
    var listIntAnnotation = findNode.typeAnnotation('List<int>');
    visitTypeAnnotation(listIntAnnotation, 'List<int>?',
        changes: {listIntAnnotation: isMakeNullable});
  }

  Future<void> test_typeName_generic_nullable_arg() async {
    await analyze('''
void _f() {
  List<int> i = [null];
}
''');
    visitTypeAnnotation(findNode.typeAnnotation('List<int>'), 'List<int?>',
        changes: {findNode.typeAnnotation('int'): isMakeNullable});
  }

  Future<void> test_typeName_simple_nonNullable() async {
    await analyze('''
void _f() {
  int i = 0;
}
''');
    visitTypeAnnotation(findNode.typeAnnotation('int'), 'int');
  }

  Future<void> test_typeName_simple_nullable() async {
    await analyze('''
void _f() {
  int i = null;
}
''');
    var intAnnotation = findNode.typeAnnotation('int');
    visitTypeAnnotation((intAnnotation), 'int?',
        changes: {intAnnotation: isMakeNullable});
  }

  Future<void> test_typeName_void() async {
    await analyze('''
void _f() {
  void v;
}
''');
    visitTypeAnnotation(findNode.typeAnnotation('void v'), 'void');
  }

  Future<void> test_use_of_dynamic() async {
    // Use of `dynamic` in a context requiring non-null is not explicitly null
    // checked.
    await analyze('''
bool _f(dynamic d, bool b) => d && b;
''');
    visitSubexpression(findNode.binary('&&'), 'bool');
  }

  Future<void> test_variableDeclaration_typed_initialized_nonNullable() async {
    await analyze('''
void _f() {
  int x = 0;
}
''');
    visitStatement(findNode.statement('int x'));
  }

  Future<void> test_variableDeclaration_typed_initialized_nullable() async {
    await analyze('''
void _f() {
  int x = null;
}
''');
    visitStatement(findNode.statement('int x'),
        changes: {findNode.typeAnnotation('int'): isMakeNullable});
  }

  Future<void> test_variableDeclaration_typed_uninitialized() async {
    await analyze('''
void _f() {
  int x;
}
''');
    visitStatement(findNode.statement('int x'));
  }

  Future<void> test_variableDeclaration_untyped_initialized() async {
    await analyze('''
void _f() {
  var x = 0;
}
''');
    visitStatement(findNode.statement('var x'));
  }

  Future<void> test_variableDeclaration_untyped_uninitialized() async {
    await analyze('''
void _f() {
  var x;
}
''');
    visitStatement(findNode.statement('var x'));
  }

  Future<void> test_variableDeclaration_visit_initializer() async {
    await analyze('''
void _f(bool/*?*/ x, bool/*?*/ y) {
  bool z = x && y;
}
''');
    visitStatement(findNode.statement('bool z'), changes: {
      findNode.simple('x &&'): isNullCheck,
      findNode.simple('y;'): isNullCheck
    });
  }

  void visitAll(
      {Map<AstNode, Matcher> changes = const <Expression, Matcher>{},
      Map<AstNode, Set<Problem>> problems = const <AstNode, Set<Problem>>{}}) {
    var fixBuilder = _createFixBuilder(testUnit);
    fixBuilder.visitAll(testUnit);
    expect(scopedChanges(fixBuilder, testUnit), changes);
    expect(scopedProblems(fixBuilder, testUnit), problems);
  }

  void visitAssignmentTarget(
      Expression node, String expectedReadType, String expectedWriteType,
      {Map<AstNode, Matcher> changes = const <Expression, Matcher>{},
      Map<AstNode, Set<Problem>> problems = const <AstNode, Set<Problem>>{}}) {
    var fixBuilder = _createFixBuilder(node);
    fixBuilder.visitAll(node.thisOrAncestorOfType<CompilationUnit>());
    var targetInfo = _computeAssignmentTargetInfo(node, fixBuilder);
    if (expectedReadType == null) {
      expect(targetInfo.readType, null);
    } else {
      expect((targetInfo.readType as TypeImpl).toString(withNullability: true),
          expectedReadType);
    }
    expect((targetInfo.writeType as TypeImpl).toString(withNullability: true),
        expectedWriteType);
    expect(scopedChanges(fixBuilder, node), changes);
    expect(scopedProblems(fixBuilder, node), problems);
  }

  void visitStatement(Statement node,
      {Map<AstNode, Matcher> changes = const <Expression, Matcher>{},
      Map<AstNode, Set<Problem>> problems = const <AstNode, Set<Problem>>{}}) {
    var fixBuilder = _createFixBuilder(node);
    fixBuilder.visitAll(node.thisOrAncestorOfType<CompilationUnit>());
    expect(scopedChanges(fixBuilder, node), changes);
    expect(scopedProblems(fixBuilder, node), problems);
  }

  void visitSubexpression(Expression node, String expectedType,
      {Map<AstNode, Matcher> changes = const <Expression, Matcher>{},
      Map<AstNode, Set<Problem>> problems = const <AstNode, Set<Problem>>{}}) {
    var fixBuilder = _createFixBuilder(node);
    fixBuilder.visitAll(node.thisOrAncestorOfType<CompilationUnit>());
    var type = node.staticType;
    expect((type as TypeImpl).toString(withNullability: true), expectedType);
    expect(scopedChanges(fixBuilder, node), changes);
    expect(scopedProblems(fixBuilder, node), problems);
  }

  void visitTypeAnnotation(TypeAnnotation node, String expectedType,
      {Map<AstNode, Matcher> changes = const <AstNode, Matcher>{},
      Map<AstNode, Set<Problem>> problems = const <AstNode, Set<Problem>>{}}) {
    var fixBuilder = _createFixBuilder(node);
    fixBuilder.visitAll(node.thisOrAncestorOfType<CompilationUnit>());
    var type = node.type;
    expect((type as TypeImpl).toString(withNullability: true), expectedType);
    expect(scopedChanges(fixBuilder, node), changes);
    expect(scopedProblems(fixBuilder, node), problems);
  }

  AssignmentTargetInfo _computeAssignmentTargetInfo(
      Expression node, FixBuilder fixBuilder) {
    var assignment = node.thisOrAncestorOfType<AssignmentExpression>();
    var isReadWrite = assignment.operator.type != TokenType.EQ;
    var readType = isReadWrite
        ? getReadType(node,
                elementTypeProvider:
                    MigrationResolutionHooksImpl(fixBuilder)) ??
            typeProvider.dynamicType
        : null;
    var writeType = node.staticType;
    return AssignmentTargetInfo(readType, writeType);
  }

  FixBuilder _createFixBuilder(AstNode scope) {
    var unit = scope.thisOrAncestorOfType<CompilationUnit>();
    var definingLibrary = unit.declaredElement.library;
    return FixBuilder(testSource, decoratedClassHierarchy, typeProvider,
        typeSystem, variables, definingLibrary);
  }

  bool _isInScope(AstNode node, AstNode scope) {
    return node
            .thisOrAncestorMatching((ancestor) => identical(ancestor, scope)) !=
        null;
  }
}
