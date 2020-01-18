// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/linter/lint_names.dart';
import 'package:analyzer/src/dart/analysis/experiments.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(InlineInvocationTest);
  });
}

@reflectiveTest
class InlineInvocationTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.INLINE_INVOCATION;

  void setUp() {
    createAnalysisOptionsFile(experiments: [EnableString.spread_collections]);
    super.setUp();
  }

  test_add_emptyTarget() async {
    await resolveTestUnit('''
var l = []..ad/*caret*/d('a')..add('b');
''');
    await assertHasAssist('''
var l = ['a']..add('b');
''');
  }

  test_add_emptyTarget_noAssistWithLint() async {
    createAnalysisOptionsFile(lints: [LintNames.prefer_inlined_adds]);
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
var l = []..ad/*caret*/d('a')..add('b');
''');
    await assertNoAssist();
  }

  test_add_nonEmptyTarget() async {
    await resolveTestUnit('''
var l = ['a']..ad/*caret*/d('b')..add('c');
''');
    await assertHasAssist('''
var l = ['a', 'b']..add('c');
''');
  }

  test_add_nonLiteralArgument() async {
    await resolveTestUnit('''
var e = 'b';
var l = ['a']..add/*caret*/(e);
''');
    await assertHasAssist('''
var e = 'b';
var l = ['a', e];
''');
  }

  test_add_nonLiteralTarget() async {
    await resolveTestUnit('''
var l1 = [];
var l2 = l1..ad/*caret*/d('b')..add('c');
''');
    await assertNoAssist();
  }

  test_add_notFirst() async {
    await resolveTestUnit('''
var l = ['a']..add('b')../*caret*/add('c');
''');
    await assertNoAssist();
  }

  test_addAll_emptyTarget() async {
    await resolveTestUnit('''
var l = []..add/*caret*/All(['a'])..addAll(['b']);
''');
    await assertHasAssist('''
var l = ['a']..addAll(['b']);
''');
  }

  test_addAll_emptyTarget_noAssistWithLint() async {
    createAnalysisOptionsFile(lints: [LintNames.prefer_inlined_adds]);
    verifyNoTestUnitErrors = false;
    await resolveTestUnit('''
var l = []..add/*caret*/All(['a'])..addAll(['b']);
''');
    await assertNoAssist();
  }

  test_addAll_nonEmptyTarget() async {
    await resolveTestUnit('''
var l = ['a']..add/*caret*/All(['b'])..addAll(['c']);
''');
    await assertHasAssist('''
var l = ['a', 'b']..addAll(['c']);
''');
  }

  test_addAll_nonLiteralArgument() async {
    await resolveTestUnit('''
var l1 = <String>[];
var l2 = ['a']..add/*caret*/All(l1);
''');
    await assertNoAssist();
  }

  test_addAll_nonLiteralTarget() async {
    await resolveTestUnit('''
var l1 = [];
var l2 = l1..addAl/*caret*/l(['b'])..addAll(['c']);
''');
    await assertNoAssist();
  }

  test_addAll_notFirst() async {
    await resolveTestUnit('''
var l = ['a']..addAll(['b'])../*caret*/addAll(['c']);
''');
    await assertNoAssist();
  }
}
