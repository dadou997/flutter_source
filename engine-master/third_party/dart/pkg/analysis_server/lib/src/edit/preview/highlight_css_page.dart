// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/src/edit/nnbd_migration/highlight_css.dart';
import 'package:analysis_server/src/edit/preview/preview_page.dart';
import 'package:analysis_server/src/edit/preview/preview_site.dart';

/// The page that contains the CSS used to style the semantic highlighting
/// within a Dart file.
class HighlightCssPage extends PreviewPage {
  /// The decoded content of the page. Use [pageContent] to access this field so
  /// that it is initialized on first read.
  static String _pageContent;

  /// Initialize a newly created CSS page within the given [site].
  HighlightCssPage(PreviewSite site)
      : super(site, PreviewSite.highlightCssPagePath.substring(1));

  @override
  void generateBody(Map<String, String> params) {
    throw UnimplementedError();
  }

  @override
  Future<void> generatePage(Map<String, String> params) async {
    buf.write(pageContent());
  }

  /// Return the content of the page, decoding it if it hasn't been decoded
  /// before.
  String pageContent() {
    return _pageContent ??= decodeHighlightCss();
  }
}
