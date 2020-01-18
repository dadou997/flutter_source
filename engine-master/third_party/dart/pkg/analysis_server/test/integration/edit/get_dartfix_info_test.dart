// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/integration_tests.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(GetDartfixInfoTest);
  });
}

@reflectiveTest
class GetDartfixInfoTest extends AbstractAnalysisServerIntegrationTest {
  test_getDartfixInfo() async {
    standardAnalysisSetup();
    EditGetDartfixInfoResult info = await sendEditGetDartfixInfo();
    expect(info.fixes.length, greaterThanOrEqualTo(3));
    var fix = info.fixes.firstWhere((f) => f.name == 'use-mixin');
    expect(fix.isRequired, isTrue);
  }
}
