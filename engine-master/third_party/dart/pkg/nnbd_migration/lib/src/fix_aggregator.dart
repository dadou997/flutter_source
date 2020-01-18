// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/precedence.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:nnbd_migration/src/edit_plan.dart';

/// Implementation of [NodeChange] representing the addition of the keyword
/// `required` to a named parameter.
///
/// TODO(paulberry): store additional information necessary to include in the
/// preview.
class AddRequiredKeyword extends _NestableChange {
  const AddRequiredKeyword([NodeChange inner = const NoChange()])
      : super(inner);

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    var innerPlan = _inner.apply(node, gather);
    return EditPlan.surround(innerPlan,
        prefix: [const InsertText('required ')]);
  }
}

/// Visitor that combines together the changes produced by [FixBuilder] into a
/// concrete set of source code edits using the infrastructure of [EditPlan].
class FixAggregator extends UnifyingAstVisitor<void> {
  /// Map from the [AstNode]s that need to have changes made, to the changes
  /// that need to be applied to them.
  final Map<AstNode, NodeChange> _changes;

  /// The set of [EditPlan]s being accumulated.
  List<EditPlan> _plans = [];

  FixAggregator._(this._changes);

  @override
  void visitNode(AstNode node) {
    var change = _changes[node];
    if (change != null) {
      var innerPlan = change.apply(node, _gather);
      if (innerPlan != null) {
        _plans.add(innerPlan);
      }
    } else {
      node.visitChildren(this);
    }
  }

  /// Gathers all the changes to nodes descended from [node] into a single
  /// [EditPlan].
  EditPlan _gather(AstNode node) {
    var previousPlans = _plans;
    try {
      _plans = [];
      node.visitChildren(this);
      return EditPlan.passThrough(node, innerPlans: _plans);
    } finally {
      _plans = previousPlans;
    }
  }

  /// Runs the [FixAggregator] on a [unit] and returns the resulting edits.
  static Map<int, List<AtomicEdit>> run(
      CompilationUnit unit, Map<AstNode, NodeChange> changes) {
    var aggregator = FixAggregator._(changes);
    unit.accept(aggregator);
    if (aggregator._plans.isEmpty) return {};
    EditPlan plan;
    if (aggregator._plans.length == 1) {
      plan = aggregator._plans[0];
    } else {
      plan = EditPlan.passThrough(unit, innerPlans: aggregator._plans);
    }
    return plan.finalize();
  }
}

/// Implementation of [NodeChange] representing introduction of an explicit
/// downcast.
///
/// TODO(paulberry): store additional information necessary to include in the
/// preview.
class IntroduceAs extends _NestableChange {
  /// TODO(paulberry): shouldn't be a String
  final String type;

  const IntroduceAs(this.type, [NodeChange inner = const NoChange()])
      : super(inner);

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    var innerPlan = _inner.apply(node, gather);
    return EditPlan.surround(innerPlan,
        suffix: [InsertText(' as $type')],
        outerPrecedence: Precedence.relational,
        innerPrecedence: Precedence.relational);
  }
}

/// Implementation of [NodeChange] representing the addition of a trailing `?`
/// to a type.
///
/// TODO(paulberry): store additional information necessary to include in the
/// preview.
class MakeNullable extends _NestableChange {
  const MakeNullable([NodeChange inner = const NoChange()]) : super(inner);

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    var innerPlan = _inner.apply(node, gather);
    return EditPlan.surround(innerPlan, suffix: [const InsertText('?')]);
  }
}

/// Implementation of [NodeChange] representing no change at all.  This class
/// is intended to be used as a base class for changes that wrap around other
/// changes.
class NoChange extends NodeChange {
  const NoChange();

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    return gather(node);
  }
}

/// Base class representing a kind of change that [FixAggregator] might make to a
/// particular AST node.
abstract class NodeChange {
  const NodeChange();

  /// Applies this change to the given [node], producing an [EditPlan].  The
  /// [gather] callback is used to gather up any edits to the node's descendants
  /// into their own [EditPlan].
  ///
  /// Note: the reason the caller can't just gather up the edits and pass them
  /// in is that some changes don't preserve all of the structure of the nodes
  /// below them (e.g. dropping an unnecessary cast), so those changes need to
  /// be able to call [gather] just on the nodes they need.
  /// TODO(paulberry): can we just do the gather prior to the call?
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather);
}

/// Implementation of [NodeChange] representing the addition of a null check to
/// an expression.
///
/// TODO(paulberry): store additional information necessary to include in the
/// preview.
class NullCheck extends _NestableChange {
  const NullCheck([NodeChange inner = const NoChange()]) : super(inner);

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    var innerPlan = _inner.apply(node, gather);
    return EditPlan.surround(innerPlan,
        suffix: [const InsertText('!')],
        outerPrecedence: Precedence.postfix,
        innerPrecedence: Precedence.postfix,
        associative: true);
  }
}

/// Implementation of [NodeChange] representing the removal of an unnecessary
/// cast.
///
/// TODO(paulberry): store additional information necessary to include in the
/// preview.
class RemoveAs extends _NestableChange {
  const RemoveAs([NodeChange inner = const NoChange()]) : super(inner);

  @override
  EditPlan apply(AstNode node, EditPlan Function(AstNode) gather) {
    return EditPlan.extract(
        node, _inner.apply((node as AsExpression).expression, gather));
  }
}

/// Shared base class for [NodeChange]s that are based on an [_inner] change.
abstract class _NestableChange extends NodeChange {
  final NodeChange _inner;

  const _NestableChange(this._inner);
}
