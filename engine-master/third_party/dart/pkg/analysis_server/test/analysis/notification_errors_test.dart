// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_constants.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/domain_analysis.dart';
import 'package:analyzer/src/lint/linter.dart';
import 'package:analyzer/src/services/lint.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:linter/src/rules.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../analysis_abstract.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(NotificationErrorsTest);
  });
}

@reflectiveTest
class NotificationErrorsTest extends AbstractAnalysisTest {
  Map<String, List<AnalysisError>> filesErrors = {};

  void processNotification(Notification notification) {
    if (notification.event == ANALYSIS_NOTIFICATION_ERRORS) {
      var decoded = AnalysisErrorsParams.fromNotification(notification);
      filesErrors[decoded.file] = decoded.errors;
    } else if (notification.event == ANALYSIS_NOTIFICATION_FLUSH_RESULTS) {
      var decoded = AnalysisFlushResultsParams.fromNotification(notification);
      for (var file in decoded.files) {
        filesErrors[file] = null;
      }
    }
  }

  @override
  void setUp() {
    generateSummaryFiles = true;
    registerLintRules();
    super.setUp();
    server.handlers = [
      AnalysisDomainHandler(server),
    ];
  }

  test_analysisOptionsFile() async {
    String filePath = join(projectPath, 'analysis_options.yaml');
    String analysisOptionsFile = newFile(filePath, content: '''
linter:
  rules:
    - invalid_lint_rule_name
''').path;

    Request request =
        AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(request);
    await waitForTasksFinished();
    await pumpEventQueue();
    //
    // Verify the error result.
    //
    List<AnalysisError> errors = filesErrors[analysisOptionsFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.location.file, filePath);
    expect(error.severity, AnalysisErrorSeverity.WARNING);
    expect(error.type, AnalysisErrorType.STATIC_WARNING);
  }

  test_androidManifestFile() async {
    String filePath = join(projectPath, 'android', 'AndroidManifest.xml');
    String manifestFile = newFile(filePath, content: '''
<manifest
    xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
    <uses-feature android:name="android.software.home_screen" />
</manifest>
''').path;
    newFile(join(projectPath, 'analysis_options.yaml'), content: '''
analyzer:
  optional-checks:
    chrome-os-manifest-checks: true
''');

    Request request =
        AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(request);
    await waitForTasksFinished();
    await pumpEventQueue();
    //
    // Verify the error result.
    //
    List<AnalysisError> errors = filesErrors[manifestFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.location.file, filePath);
    expect(error.severity, AnalysisErrorSeverity.WARNING);
    expect(error.type, AnalysisErrorType.STATIC_WARNING);
  }

  test_androidManifestFile_dotDirectoryIgnored() async {
    String filePath =
        join(projectPath, 'ios', '.symlinks', 'AndroidManifest.xml');
    String manifestFile = newFile(filePath, content: '''
<manifest
    xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
    <uses-feature android:name="android.software.home_screen" />
</manifest>
''').path;
    newFile(join(projectPath, 'analysis_options.yaml'), content: '''
analyzer:
  optional-checks:
    chrome-os-manifest-checks: true
''');

    Request request =
        AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(request);
    await waitForTasksFinished();
    await pumpEventQueue();
    //
    // Verify that the file wasn't analyzed.
    //
    List<AnalysisError> errors = filesErrors[manifestFile];
    expect(errors, isNull);
  }

  test_dotFolder_priority() async {
    // Files inside dotFolders should not generate error notifications even
    // if they are added to priority (priority affects only priority, not what
    // is analyzed).
    createProject();
    addTestFile('');
    String brokenFile =
        newFile(join(projectPath, '.dart_tool/broken.dart'), content: 'err')
            .path;

    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    expect(filesErrors[brokenFile], isNull);

    // Add to priority files and give chance for the file to be analyzed (if
    // it would).
    await setPriorityFiles([brokenFile]);
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // There should still be no errors.
    expect(filesErrors[brokenFile], isNull);
  }

  test_dotFolder_unopenedFile() async {
    // Files inside dotFolders are not analyzed. Sending requests that cause
    // them to be opened (such as hovers) should not result in error notifications
    // because there is no event that would flush them and they'd remain in the
    // editor forever.
    createProject();
    addTestFile('');
    String brokenFile =
        newFile(join(projectPath, '.dart_tool/broken.dart'), content: 'err')
            .path;

    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    expect(filesErrors[brokenFile], isNull);

    // Send a getHover request for the file that will cause it to be read from disk.
    await waitResponse(AnalysisGetHoverParams(brokenFile, 0).toRequest('0'));
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // There should be no errors because the file is not being analyzed.
    expect(filesErrors[brokenFile], isNull);
  }

  test_importError() async {
    createProject();

    addTestFile('''
import 'does_not_exist.dart';
''');
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    List<AnalysisError> errors = filesErrors[testFile];
    // Verify that we are generating only 1 error for the bad URI.
    // https://github.com/dart-lang/sdk/issues/23754
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.severity, AnalysisErrorSeverity.ERROR);
    expect(error.type, AnalysisErrorType.COMPILE_TIME_ERROR);
    expect(error.message, startsWith("Target of URI doesn't exist"));
  }

  test_lintError() async {
    var camelCaseTypesLintName = 'camel_case_types';

    newFile(join(projectPath, '.analysis_options'), content: '''
linter:
  rules:
    - $camelCaseTypesLintName
''');

    addTestFile('class a { }');

    Request request =
        AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(request);

    await waitForTasksFinished();

    var testDriver = server.getAnalysisDriver(testFile);
    List<Linter> lints = testDriver.analysisOptions.lintRules;

    // Registry should only contain single lint rule.
    expect(lints, hasLength(1));
    LintRule lint = lints.first as LintRule;
    expect(lint.name, camelCaseTypesLintName);

    // Verify lint error result.
    List<AnalysisError> errors = filesErrors[testFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.location.file, join(projectPath, 'bin', 'test.dart'));
    expect(error.severity, AnalysisErrorSeverity.INFO);
    expect(error.type, AnalysisErrorType.LINT);
    expect(error.message, lint.description);
  }

  test_notInAnalysisRoot() async {
    createProject();
    String otherFile = newFile('/other.dart', content: 'UnknownType V;').path;
    addTestFile('''
import '/other.dart';
main() {
  print(V);
}
''');
    await waitForTasksFinished();
    expect(filesErrors[otherFile], isNull);
  }

  test_overlay_dotFolder() async {
    // Files inside dotFolders should not generate error notifications even
    // if they have overlays added.
    createProject();
    addTestFile('');
    String brokenFile =
        newFile(join(projectPath, '.dart_tool/broken.dart'), content: 'err')
            .path;

    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    expect(filesErrors[brokenFile], isNull);

    // Add and overlay and give chance for the file to be analyzed (if
    // it would).
    await waitResponse(
      AnalysisUpdateContentParams({
        brokenFile: AddContentOverlay('err'),
      }).toRequest('1'),
    );
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // There should still be no errors.
    expect(filesErrors[brokenFile], isNull);
  }

  test_overlay_newFile() async {
    // Overlays added for files that don't exist on disk should still generate
    // error notifications. Removing the overlay if the file is not on disk
    // should clear the errors.
    createProject();
    addTestFile('');
    String brokenFile = convertPath(join(projectPath, 'broken.dart'));

    // Add and overlay and give chance for the file to be analyzed.
    await waitResponse(
      AnalysisUpdateContentParams({
        brokenFile: AddContentOverlay('err'),
      }).toRequest('0'),
    );
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // There should now be errors.
    expect(filesErrors[brokenFile], hasLength(greaterThan(0)));

    // Remove the overlay (this file no longer exists anywhere).
    await waitResponse(
      AnalysisUpdateContentParams({
        brokenFile: RemoveContentOverlay(),
      }).toRequest('1'),
    );
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // Unlike other tests here, removing an overlay for a file that doesn't exist
    // on disk doesn't flush errors, but re-analyzes the missing file, which results
    // in an error notification of 0 errors rather than a flush.
    expect(filesErrors[brokenFile], isEmpty);
  }

  test_overlay_newFileSavedBeforeRemoving() async {
    // Overlays added for files that don't exist on disk should still generate
    // error notifications. If the file is subsequently saved to disk before the
    // overlay is removed, the errors should not be flushed when the overlay is
    // removed.
    createProject();
    addTestFile('');
    String brokenFile = convertPath(join(projectPath, 'broken.dart'));

    // Add and overlay and give chance for the file to be analyzed.
    await waitResponse(
      AnalysisUpdateContentParams({
        brokenFile: AddContentOverlay('err'),
      }).toRequest('0'),
    );
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // There should now be errors.
    expect(filesErrors[brokenFile], hasLength(greaterThan(0)));

    // Write the file to disk.
    newFile(brokenFile, content: 'err');
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // Remove the overlay.
    await waitResponse(
      AnalysisUpdateContentParams({
        brokenFile: RemoveContentOverlay(),
      }).toRequest('1'),
    );
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);

    // Errors should not have been flushed since the file still exists without
    // the overlay.
    expect(filesErrors[brokenFile], hasLength(greaterThan(0)));
  }

  test_ParserError() async {
    createProject();
    addTestFile('library lib');
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    List<AnalysisError> errors = filesErrors[testFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.location.file, join(projectPath, 'bin', 'test.dart'));
    expect(error.location.offset, isPositive);
    expect(error.location.length, isNonNegative);
    expect(error.severity, AnalysisErrorSeverity.ERROR);
    expect(error.type, AnalysisErrorType.SYNTACTIC_ERROR);
    expect(error.message, isNotNull);
  }

  test_pubspecFile() async {
    String filePath = join(projectPath, 'pubspec.yaml');
    String pubspecFile = newFile(filePath, content: '''
version: 1.3.2
''').path;

    Request setRootsRequest =
        AnalysisSetAnalysisRootsParams([projectPath], []).toRequest('0');
    handleSuccessfulRequest(setRootsRequest);
    await waitForTasksFinished();
    await pumpEventQueue();
    //
    // Verify the error result.
    //
    List<AnalysisError> errors = filesErrors[pubspecFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.location.file, filePath);
    expect(error.severity, AnalysisErrorSeverity.WARNING);
    expect(error.type, AnalysisErrorType.STATIC_WARNING);
    //
    // Fix the error and verify the new results.
    //
    modifyFile(pubspecFile, '''
name: sample
version: 1.3.2
''');
    await waitForTasksFinished();
    await pumpEventQueue();

    errors = filesErrors[pubspecFile];
    expect(errors, hasLength(0));
  }

  test_StaticWarning() async {
    createProject();
    addTestFile('''
main() {
  final int foo;
  print(foo);
}
''');
    await waitForTasksFinished();
    await pumpEventQueue(times: 5000);
    List<AnalysisError> errors = filesErrors[testFile];
    expect(errors, hasLength(1));
    AnalysisError error = errors[0];
    expect(error.severity, AnalysisErrorSeverity.ERROR);
    expect(error.type, AnalysisErrorType.STATIC_WARNING);
  }
}
