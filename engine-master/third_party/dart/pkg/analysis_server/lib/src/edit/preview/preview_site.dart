// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:analysis_server/src/edit/nnbd_migration/migration_info.dart';
import 'package:analysis_server/src/edit/nnbd_migration/path_mapper.dart';
import 'package:analysis_server/src/edit/preview/dart_file_page.dart';
import 'package:analysis_server/src/edit/preview/exception_page.dart';
import 'package:analysis_server/src/edit/preview/highlight_css_page.dart';
import 'package:analysis_server/src/edit/preview/highlight_js_page.dart';
import 'package:analysis_server/src/edit/preview/http_preview_server.dart';
import 'package:analysis_server/src/edit/preview/index_file_page.dart';
import 'package:analysis_server/src/edit/preview/not_found_page.dart';
import 'package:analysis_server/src/status/pages.dart';
import 'package:analyzer/file_system/file_system.dart';

/// The site used to serve pages for the preview tool.
class PreviewSite extends Site implements AbstractGetHandler {
  /// The path of the CSS page used to style the semantic highlighting within a
  /// Dart file.
  static const highlightCssPagePath = '/css/androidstudio.css';

  /// The path of the JS page used to associate highlighting within a Dart file.
  static const highlightJSPagePath = '/js/highlight.pack.js';

  /// The information about the migration that will be used to serve up pages.
  final MigrationInfo migrationInfo;

  /// The path mapper used to map paths from the unit infos to the paths being
  /// served.
  final PathMapper pathMapper;

  /// A table mapping the paths of files to the information about the
  /// compilation units at those paths.
  final Map<String, UnitInfo> unitInfoMap = {};

  /// Initialize a newly created site to serve a preview of the results of an
  /// NNBD migration.
  PreviewSite(this.migrationInfo, this.pathMapper)
      : super('NNBD Migration Preview') {
    Set<UnitInfo> unitInfos = migrationInfo.units;
    ResourceProvider provider = pathMapper.provider;
    for (UnitInfo unit in unitInfos) {
      unitInfoMap[unit.path] = unit;
    }
    for (UnitInfo unit in migrationInfo.unitMap.values) {
      if (!unitInfos.contains(unit)) {
        if (unit.content == null) {
          try {
            unit.content = provider.getFile(unit.path).readAsStringSync();
          } catch (_) {
            // If we can't read the content of the file, then skip it.
            continue;
          }
        }
        unitInfoMap[unit.path] = unit;
      }
    }
  }

  @override
  Page createExceptionPage(String message, StackTrace trace) {
    // Use createExceptionPageWithPath instead.
    throw UnimplementedError();
  }

  /// Return a page used to display an exception that occurred while attempting
  /// to render another page. The [path] is the path to the page that was being
  /// rendered when the exception was thrown. The [message] and [stackTrace] are
  /// those from the exception.
  Page createExceptionPageWithPath(
      String path, String message, StackTrace stackTrace) {
    return ExceptionPage(this, path, message, stackTrace);
  }

  @override
  Page createUnknownPage(String unknownPath) {
    return NotFoundPage(this, unknownPath.substring(1));
  }

  @override
  Future<void> handleGetRequest(HttpRequest request) async {
    Uri uri = request.uri;
    if (uri.query.contains('replacement')) {
      performEdit(uri);
      performMigration();
    }
    String path = uri.path;
    try {
      if (path == highlightCssPagePath) {
        return respond(request, HighlightCssPage(this));
      } else if (path == highlightJSPagePath) {
        return respond(request, HighlightJSPage(this));
      } else if (path == '/' || path == migrationInfo.includedRoot) {
        return respond(request, IndexFilePage(this));
      }
      UnitInfo unitInfo = unitInfoMap[path];
      if (unitInfo != null) {
        if (uri.queryParameters.containsKey('inline')) {
          return respond(request, DartFilePage(this, unitInfo));
        } else {
          return respond(request, IndexFilePage(this));
        }
      }
      return respond(request, createUnknownPage(path), HttpStatus.notFound);
    } catch (exception, stackTrace) {
      try {
        await respond(
            request,
            createExceptionPageWithPath(path, '$exception', stackTrace),
            HttpStatus.internalServerError);
      } catch (exception, stackTrace) {
        HttpResponse response = request.response;
        response.statusCode = HttpStatus.internalServerError;
        response.headers.contentType = ContentType.text;
        response.write('$exception\n\n$stackTrace');
        response.close();
      }
    }
  }

  /// Perform the edit indicated by the [uri].
  void performEdit(Uri uri) {
    // We might want to allow edits to files other than the file to be displayed
    // after the edit is performed, in which case we'll need to encode the file
    // path as a query parameter.
    Map<String, String> params = uri.queryParameters;
    String path = uri.path;
    int offset = int.parse(params['offset']);
    int end = int.parse(params['end']);
    String replacement = params['replacement'];
    File file = pathMapper.provider.getFile(path);
    String oldContent = file.readAsStringSync();
    String newContent = oldContent.replaceRange(offset, end, replacement);
    file.writeAsStringSync(newContent);
  }

  /// Perform the migration again and update this site to serve up the results
  /// of the new migration.
  void performMigration() {
    // TODO(brianwilkerson) Implement this.
  }

  @override
  Future<void> respond(HttpRequest request, Page page,
      [int code = HttpStatus.ok]) async {
    HttpResponse response = request.response;
    response.statusCode = code;
    if (page is HighlightCssPage) {
      response.headers.contentType =
          ContentType('text', 'css', charset: 'utf-8');
    } else if (page is HighlightJSPage) {
      response.headers.contentType =
          ContentType('application', 'javascript', charset: 'utf-8');
    } else {
      response.headers.contentType = ContentType.html;
    }
    response.write(await page.generate(request.uri.queryParameters));
    response.close();
  }
}
