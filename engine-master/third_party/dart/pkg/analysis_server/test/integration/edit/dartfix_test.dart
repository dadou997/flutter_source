// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/integration_tests.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DartfixTest);
  });
}

@reflectiveTest
class DartfixTest extends AbstractAnalysisServerIntegrationTest {
  void setupTarget() {
    writeFile(sourcePath('test.dart'), '''
class A {}
class B extends A {}
class C with B {}
    ''');
    standardAnalysisSetup();
  }

  test_dartfix() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)]);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, greaterThanOrEqualTo(1));
    expect(result.edits.length, greaterThanOrEqualTo(1));
  }

  test_dartfix_exclude() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)],
        excludedFixes: ['use-mixin']);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, 0);
    expect(result.edits.length, 0);
  }

  test_dartfix_exclude_other() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)],
        excludedFixes: ['double-to-int']);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, greaterThanOrEqualTo(1));
    expect(result.edits.length, greaterThanOrEqualTo(1));
  }

  test_dartfix_include() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)],
        includedFixes: ['use-mixin']);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, greaterThanOrEqualTo(1));
    expect(result.edits.length, greaterThanOrEqualTo(1));
  }

  test_dartfix_include_other() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)],
        includedFixes: ['double-to-int']);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, 0);
    expect(result.edits.length, 0);
  }

  test_dartfix_required() async {
    setupTarget();
    EditDartfixResult result = await sendEditDartfix([(sourceDirectory.path)],
        includeRequiredFixes: true);
    expect(result.hasErrors, isFalse);
    expect(result.suggestions.length, greaterThanOrEqualTo(1));
    expect(result.edits.length, greaterThanOrEqualTo(1));
  }
}
