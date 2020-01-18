// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../support/integration_tests.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ListTokenDetailsTest);
  });
}

@reflectiveTest
class ListTokenDetailsTest extends AbstractAnalysisServerIntegrationTest {
  String testPackagePath;

  Future setUp() async {
    await super.setUp();
    testPackagePath = path.join(sourceDirectory.path, 'test_package');
  }

  @override
  Future standardAnalysisSetup({bool subscribeStatus = true}) {
    List<Future> futures = <Future>[];
    if (subscribeStatus) {
      futures.add(sendServerSetSubscriptions([ServerService.STATUS]));
    }
    futures.add(sendAnalysisSetAnalysisRoots([testPackagePath], []));
    return Future.wait(futures);
  }

  test_getSuggestions() async {
    String aPath = path.join(sourceDirectory.path, 'a');
    String aLibPath = path.join(aPath, 'lib');
    writeFile(path.join(aLibPath, 'a.dart'), '''
class A {}
''');
    writeFile(path.join(testPackagePath, '.packages'), '''
a:file://$aLibPath
test_package:lib/
''');
    String testFilePath = path.join(testPackagePath, 'lib', 'test.dart');
    writeFile(testFilePath, '''
import 'package:a/a.dart';
class B {}
String f(A a, B b) => a.toString() + b.toString();
''');
    await standardAnalysisSetup();
    await analysisFinished;

    CompletionListTokenDetailsResult result =
        await sendCompletionListTokenDetails(testFilePath);
    expect(result, isNotNull);
  }
}
