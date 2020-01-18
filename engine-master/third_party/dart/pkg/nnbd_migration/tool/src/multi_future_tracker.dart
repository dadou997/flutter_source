// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library helps run parallel thread-like closures asynchronously.
/// Borrowed from dartdoc:src/io_utils.dart.

// TODO(jcollins-g): like SubprocessLauncher, merge with io_utils in dartdoc
// before cut-and-paste gets out of hand.

class MultiFutureTracker {
  /// Maximum number of simultaneously incomplete [Future]s.
  final int parallel;

  final Set<Future<void>> _trackedFutures = Set();

  MultiFutureTracker(this.parallel);

  /// Wait until fewer or equal to this many Futures are outstanding.
  Future<void> _waitUntil(int max) async {
    assert(_trackedFutures.length <= parallel);
    while (_trackedFutures.length > max) {
      await Future.any(_trackedFutures);
    }
  }

  /// Generates a [Future] from the given closure and adds it to the queue,
  /// once the queue is sufficiently empty.  The returned future completes
  /// when the generated [Future] has been added to the queue.
  Future<void> addFutureFromClosure(Future<void> Function() closure) async {
    assert(_trackedFutures.length <= parallel);
    // Can't use _waitUntil because we might not return directly to this
    // invocation of addFutureFromClosure.
    while (_trackedFutures.length > parallel - 1) {
      await Future.any(_trackedFutures);
    }
    Future<void> future = closure();
    _trackedFutures.add(future);
    future.then((f) => _trackedFutures.remove(future));
  }

  /// Wait until all futures added so far have completed.
  Future<void> wait() => _waitUntil(0);
}
