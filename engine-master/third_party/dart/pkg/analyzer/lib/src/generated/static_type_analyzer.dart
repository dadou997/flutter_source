// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart' show ConstructorMember;
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/element/type_algebra.dart';
import 'package:analyzer/src/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/resolver/flow_analysis_visitor.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/element_type_provider.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/migration.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/variable_type_provider.dart';
import 'package:analyzer/src/task/strong/checker.dart'
    show getExpressionType, getReadType;
import 'package:meta/meta.dart';

/**
 * Instances of the class `StaticTypeAnalyzer` perform two type-related tasks. First, they
 * compute the static type of every expression. Second, they look for any static type errors or
 * warnings that might need to be generated. The requirements for the type analyzer are:
 * <ol>
 * * Every element that refers to types should be fully populated.
 * * Every node representing an expression should be resolved to the Type of the expression.
 * </ol>
 */
class StaticTypeAnalyzer extends SimpleAstVisitor<void> {
  /**
   * The resolver driving the resolution and type analysis.
   */
  final ResolverVisitor _resolver;

  /**
   * The feature set that should be used to resolve types.
   */
  final FeatureSet _featureSet;

  /**
   * The object providing access to the types defined by the language.
   */
  TypeProviderImpl _typeProvider;

  /**
   * The type system in use for static type analysis.
   */
  TypeSystemImpl _typeSystem;

  /**
   * The type representing the type 'dynamic'.
   */
  DartType _dynamicType;

  /**
   * True if inference failures should be reported, otherwise false.
   */
  bool _strictInference;

  /**
   * The type representing the class containing the nodes being analyzed,
   * or `null` if the nodes are not within a class.
   */
  DartType thisType;

  /**
   * The object providing promoted or declared types of variables.
   */
  LocalVariableTypeProvider _localVariableTypeProvider;

  final FlowAnalysisHelper _flowAnalysis;

  final ElementTypeProvider _elementTypeProvider;

  /**
   * Initialize a newly created static type analyzer to analyze types for the
   * [_resolver] based on the
   *
   * @param resolver the resolver driving this participant
   */
  StaticTypeAnalyzer(this._resolver, this._featureSet, this._flowAnalysis,
      {ElementTypeProvider elementTypeProvider = const ElementTypeProvider()})
      : _elementTypeProvider = elementTypeProvider {
    _typeProvider = _resolver.typeProvider;
    _typeSystem = _resolver.typeSystem;
    _dynamicType = _typeProvider.dynamicType;
    _localVariableTypeProvider = _resolver.localVariableTypeProvider;
    AnalysisOptionsImpl analysisOptions =
        _resolver.definingLibrary.context.analysisOptions;
    _strictInference = analysisOptions.strictInference;
  }

  /// Is `true` if the library being analyzed is non-nullable by default.
  bool get _isNonNullableByDefault =>
      _featureSet.isEnabled(Feature.non_nullable);

  /**
   * Given an iterable expression from a foreach loop, attempt to infer
   * a type for the elements being iterated over.  Inference is based
   * on the type of the iterator or stream over which the foreach loop
   * is defined.
   */
  DartType computeForEachElementType(Expression iterable, bool isAsync) {
    DartType iterableType = iterable.staticType;
    if (iterableType == null) return null;
    iterableType = iterableType.resolveToBound(_typeProvider.objectType);

    ClassElement iteratedElement =
        isAsync ? _typeProvider.streamElement : _typeProvider.iterableElement;

    InterfaceType iteratedType = iterableType is InterfaceTypeImpl
        ? iterableType.asInstanceOf(iteratedElement)
        : null;

    if (iteratedType != null) {
      return iteratedType.typeArguments.single;
    } else {
      return null;
    }
  }

  /**
   * Given a constructor for a generic type, returns the equivalent generic
   * function type that we could use to forward to the constructor, or for a
   * non-generic type simply returns the constructor type.
   *
   * For example given the type `class C<T> { C(T arg); }`, the generic function
   * type is `<T>(T) -> C<T>`.
   */
  FunctionType constructorToGenericFunctionType(
      ConstructorElement constructor) {
    var classElement = constructor.enclosingElement;
    var typeParameters = classElement.typeParameters;
    if (typeParameters.isEmpty) {
      return _elementTypeProvider.getExecutableType(constructor);
    }

    return FunctionTypeImpl(
      typeFormals: typeParameters,
      parameters: _elementTypeProvider.getExecutableParameters(constructor),
      returnType: _elementTypeProvider.getExecutableReturnType(constructor),
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  /**
   * Given a formal parameter list and a function type use the function type
   * to infer types for any of the parameters which have implicit (missing)
   * types.  Returns true if inference has occurred.
   */
  bool inferFormalParameterList(
      FormalParameterList node, DartType functionType) {
    bool inferred = false;
    if (node != null && functionType is FunctionType) {
      void inferType(ParameterElementImpl p, DartType inferredType) {
        // Check that there is no declared type, and that we have not already
        // inferred a type in some fashion.
        if (p.hasImplicitType &&
            (_elementTypeProvider.getVariableType(p) == null ||
                _elementTypeProvider.getVariableType(p).isDynamic)) {
          inferredType = _typeSystem.upperBoundForType(inferredType);
          if (inferredType.isDartCoreNull) {
            inferredType = _typeProvider.objectType;
          }
          if (!inferredType.isDynamic) {
            p.type = inferredType;
            inferred = true;
          }
        }
      }

      List<ParameterElement> parameters = node.parameterElements;
      {
        Iterator<ParameterElement> positional =
            parameters.where((p) => p.isPositional).iterator;
        Iterator<ParameterElement> fnPositional =
            functionType.parameters.where((p) => p.isPositional).iterator;
        while (positional.moveNext() && fnPositional.moveNext()) {
          inferType(positional.current,
              _elementTypeProvider.getVariableType(fnPositional.current));
        }
      }

      {
        Map<String, DartType> namedParameterTypes =
            functionType.namedParameterTypes;
        Iterable<ParameterElement> named = parameters.where((p) => p.isNamed);
        for (ParameterElementImpl p in named) {
          if (!namedParameterTypes.containsKey(p.name)) {
            continue;
          }
          inferType(p, namedParameterTypes[p.name]);
        }
      }
    }
    return inferred;
  }

  /**
   * The Dart Language Specification, 12.5: <blockquote>The static type of a string literal is
   * `String`.</blockquote>
   */
  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    _recordStaticType(node, _nonNullable(_typeProvider.stringType));
  }

  /**
   * The Dart Language Specification, 12.32: <blockquote>... the cast expression <i>e as T</i> ...
   *
   * It is a static warning if <i>T</i> does not denote a type available in the current lexical
   * scope.
   *
   * The static type of a cast expression <i>e as T</i> is <i>T</i>.</blockquote>
   */
  @override
  void visitAsExpression(AsExpression node) {
    _recordStaticType(node, _getType(node.type));
  }

  /**
   * The Dart Language Specification, 12.18: <blockquote>... an assignment <i>a</i> of the form <i>v
   * = e</i> ...
   *
   * It is a static type warning if the static type of <i>e</i> may not be assigned to the static
   * type of <i>v</i>.
   *
   * The static type of the expression <i>v = e</i> is the static type of <i>e</i>.
   *
   * ... an assignment of the form <i>C.v = e</i> ...
   *
   * It is a static type warning if the static type of <i>e</i> may not be assigned to the static
   * type of <i>C.v</i>.
   *
   * The static type of the expression <i>C.v = e</i> is the static type of <i>e</i>.
   *
   * ... an assignment of the form <i>e<sub>1</sub>.v = e<sub>2</sub></i> ...
   *
   * Let <i>T</i> be the static type of <i>e<sub>1</sub></i>. It is a static type warning if
   * <i>T</i> does not have an accessible instance setter named <i>v=</i>. It is a static type
   * warning if the static type of <i>e<sub>2</sub></i> may not be assigned to <i>T</i>.
   *
   * The static type of the expression <i>e<sub>1</sub>.v = e<sub>2</sub></i> is the static type of
   * <i>e<sub>2</sub></i>.
   *
   * ... an assignment of the form <i>e<sub>1</sub>[e<sub>2</sub>] = e<sub>3</sub></i> ...
   *
   * The static type of the expression <i>e<sub>1</sub>[e<sub>2</sub>] = e<sub>3</sub></i> is the
   * static type of <i>e<sub>3</sub></i>.
   *
   * A compound assignment of the form <i>v op= e</i> is equivalent to <i>v = v op e</i>. A compound
   * assignment of the form <i>C.v op= e</i> is equivalent to <i>C.v = C.v op e</i>. A compound
   * assignment of the form <i>e<sub>1</sub>.v op= e<sub>2</sub></i> is equivalent to <i>((x) => x.v
   * = x.v op e<sub>2</sub>)(e<sub>1</sub>)</i> where <i>x</i> is a variable that is not used in
   * <i>e<sub>2</sub></i>. A compound assignment of the form <i>e<sub>1</sub>[e<sub>2</sub>] op=
   * e<sub>3</sub></i> is equivalent to <i>((a, i) => a[i] = a[i] op e<sub>3</sub>)(e<sub>1</sub>,
   * e<sub>2</sub>)</i> where <i>a</i> and <i>i</i> are a variables that are not used in
   * <i>e<sub>3</sub></i>.</blockquote>
   */
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    TokenType operator = node.operator.type;
    if (operator == TokenType.EQ) {
      Expression rightHandSide = node.rightHandSide;
      DartType staticType = _getStaticType(rightHandSide);
      _recordStaticType(node, staticType);
    } else if (operator == TokenType.QUESTION_QUESTION_EQ) {
      if (_isNonNullableByDefault) {
        // The static type of a compound assignment using ??= with NNBD is the
        // least upper bound of the static types of the LHS and RHS after
        // promoting the LHS/ to non-null (as we know its value will not be used
        // if null)
        _analyzeLeastUpperBoundTypes(
            node,
            _typeSystem.promoteToNonNull(
                _getExpressionType(node.leftHandSide, read: true)),
            _getExpressionType(node.rightHandSide, read: true));
      } else {
        // The static type of a compound assignment using ??= before NNBD is the
        // least upper bound of the static types of the LHS and RHS.
        _analyzeLeastUpperBound(node, node.leftHandSide, node.rightHandSide,
            read: true);
      }
    } else if (operator == TokenType.AMPERSAND_AMPERSAND_EQ ||
        operator == TokenType.BAR_BAR_EQ) {
      _recordStaticType(node, _nonNullable(_typeProvider.boolType));
    } else {
      var operatorElement = node.staticElement;
      var type =
          _elementTypeProvider.safeExecutableReturnType(operatorElement) ??
              _dynamicType;
      type = _typeSystem.refineBinaryExpressionType(
        _getStaticType(node.leftHandSide, read: true),
        operator,
        node.rightHandSide.staticType,
        type,
      );
      _recordStaticType(node, type);

      var leftWriteType = _getStaticType(node.leftHandSide);
      if (!_typeSystem.isAssignableTo(type, leftWriteType)) {
        _resolver.errorReporter.reportErrorForNode(
          StaticTypeWarningCode.INVALID_ASSIGNMENT,
          node.rightHandSide,
          [type, leftWriteType],
        );
      }
    }
    _nullShortingTermination(node);
  }

  /**
   * The Dart Language Specification, 16.29 (Await Expressions):
   *
   *   The static type of [the expression "await e"] is flatten(T) where T is
   *   the static type of e.
   */
  @override
  void visitAwaitExpression(AwaitExpression node) {
    // Await the Future. This results in whatever type is (ultimately) returned.
    DartType awaitType(DartType awaitedType) {
      if (awaitedType == null) {
        return null;
      }
      if (awaitedType.isDartAsyncFutureOr) {
        return awaitType((awaitedType as InterfaceType).typeArguments[0]);
      }
      return _typeSystem.flatten(awaitedType);
    }

    _recordStaticType(node, awaitType(_getStaticType(node.expression)));
  }

  /**
   * The Dart Language Specification, 12.20: <blockquote>The static type of a logical boolean
   * expression is `bool`.</blockquote>
   *
   * The Dart Language Specification, 12.21:<blockquote>A bitwise expression of the form
   * <i>e<sub>1</sub> op e<sub>2</sub></i> is equivalent to the method invocation
   * <i>e<sub>1</sub>.op(e<sub>2</sub>)</i>. A bitwise expression of the form <i>super op
   * e<sub>2</sub></i> is equivalent to the method invocation
   * <i>super.op(e<sub>2</sub>)</i>.</blockquote>
   *
   * The Dart Language Specification, 12.22: <blockquote>The static type of an equality expression
   * is `bool`.</blockquote>
   *
   * The Dart Language Specification, 12.23: <blockquote>A relational expression of the form
   * <i>e<sub>1</sub> op e<sub>2</sub></i> is equivalent to the method invocation
   * <i>e<sub>1</sub>.op(e<sub>2</sub>)</i>. A relational expression of the form <i>super op
   * e<sub>2</sub></i> is equivalent to the method invocation
   * <i>super.op(e<sub>2</sub>)</i>.</blockquote>
   *
   * The Dart Language Specification, 12.24: <blockquote>A shift expression of the form
   * <i>e<sub>1</sub> op e<sub>2</sub></i> is equivalent to the method invocation
   * <i>e<sub>1</sub>.op(e<sub>2</sub>)</i>. A shift expression of the form <i>super op
   * e<sub>2</sub></i> is equivalent to the method invocation
   * <i>super.op(e<sub>2</sub>)</i>.</blockquote>
   *
   * The Dart Language Specification, 12.25: <blockquote>An additive expression of the form
   * <i>e<sub>1</sub> op e<sub>2</sub></i> is equivalent to the method invocation
   * <i>e<sub>1</sub>.op(e<sub>2</sub>)</i>. An additive expression of the form <i>super op
   * e<sub>2</sub></i> is equivalent to the method invocation
   * <i>super.op(e<sub>2</sub>)</i>.</blockquote>
   *
   * The Dart Language Specification, 12.26: <blockquote>A multiplicative expression of the form
   * <i>e<sub>1</sub> op e<sub>2</sub></i> is equivalent to the method invocation
   * <i>e<sub>1</sub>.op(e<sub>2</sub>)</i>. A multiplicative expression of the form <i>super op
   * e<sub>2</sub></i> is equivalent to the method invocation
   * <i>super.op(e<sub>2</sub>)</i>.</blockquote>
   */
  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.type == TokenType.QUESTION_QUESTION) {
      if (_isNonNullableByDefault) {
        // The static type of a compound assignment using ??= with NNBD is the
        // least upper bound of the static types of the LHS and RHS after
        // promoting the LHS/ to non-null (as we know its value will not be used
        // if null)
        _analyzeLeastUpperBoundTypes(
            node,
            _typeSystem.promoteToNonNull(
                _getExpressionType(node.leftOperand, read: true)),
            _getExpressionType(node.rightOperand, read: true));
      } else {
        // Without NNBD, evaluation of an if-null expression e of the form
        // e1 ?? e2 is equivalent to the evaluation of the expression
        // ((x) => x == null ? e2 : x)(e1).  The static type of e is the least
        // upper bound of the static type of e1 and the static type of e2.
        _analyzeLeastUpperBound(node, node.leftOperand, node.rightOperand);
      }
      return;
    }
    DartType staticType = node.staticInvokeType?.returnType ?? _dynamicType;
    if (node.leftOperand is! ExtensionOverride) {
      staticType = _typeSystem.refineBinaryExpressionType(
        node.leftOperand.staticType,
        node.operator.type,
        node.rightOperand.staticType,
        staticType,
      );
    }
    _recordStaticType(node, staticType);
  }

  /**
   * The Dart Language Specification, 12.4: <blockquote>The static type of a boolean literal is
   * bool.</blockquote>
   */
  @override
  void visitBooleanLiteral(BooleanLiteral node) {
    _recordStaticType(node, _nonNullable(_typeProvider.boolType));
  }

  /**
   * The Dart Language Specification, 12.15.2: <blockquote>A cascaded method invocation expression
   * of the form <i>e..suffix</i> is equivalent to the expression <i>(t) {t.suffix; return
   * t;}(e)</i>.</blockquote>
   */
  @override
  void visitCascadeExpression(CascadeExpression node) {
    _recordStaticType(node, _getStaticType(node.target));
  }

  /**
   * The Dart Language Specification, 12.19: <blockquote> ... a conditional expression <i>c</i> of
   * the form <i>e<sub>1</sub> ? e<sub>2</sub> : e<sub>3</sub></i> ...
   *
   * It is a static type warning if the type of e<sub>1</sub> may not be assigned to `bool`.
   *
   * The static type of <i>c</i> is the least upper bound of the static type of <i>e<sub>2</sub></i>
   * and the static type of <i>e<sub>3</sub></i>.</blockquote>
   */
  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _analyzeLeastUpperBound(node, node.thenExpression, node.elseExpression);
  }

  /**
   * The Dart Language Specification, 12.3: <blockquote>The static type of a literal double is
   * double.</blockquote>
   */
  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    _recordStaticType(node, _nonNullable(_typeProvider.doubleType));
  }

  @override
  void visitExtensionOverride(ExtensionOverride node) {
    _resolver.extensionResolver.resolveOverride(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    FunctionExpression function = node.functionExpression;
    ExecutableElementImpl functionElement =
        node.declaredElement as ExecutableElementImpl;
    if (node.parent is FunctionDeclarationStatement) {
      // TypeResolverVisitor sets the return type for top-level functions, so
      // we only need to handle local functions.
      if (node.returnType == null) {
        _inferLocalFunctionReturnType(node.functionExpression);
        return;
      }
      functionElement.returnType =
          _computeStaticReturnTypeOfFunctionDeclaration(node);
    }
    _recordStaticType(
        function, _elementTypeProvider.getExecutableType(functionElement));
  }

  /**
   * The Dart Language Specification, 12.9: <blockquote>The static type of a function literal of the
   * form <i>(T<sub>1</sub> a<sub>1</sub>, &hellip;, T<sub>n</sub> a<sub>n</sub>, [T<sub>n+1</sub>
   * x<sub>n+1</sub> = d1, &hellip;, T<sub>n+k</sub> x<sub>n+k</sub> = dk]) => e</i> is
   * <i>(T<sub>1</sub>, &hellip;, Tn, [T<sub>n+1</sub> x<sub>n+1</sub>, &hellip;, T<sub>n+k</sub>
   * x<sub>n+k</sub>]) &rarr; T<sub>0</sub></i>, where <i>T<sub>0</sub></i> is the static type of
   * <i>e</i>. In any case where <i>T<sub>i</sub>, 1 &lt;= i &lt;= n</i>, is not specified, it is
   * considered to have been specified as dynamic.
   *
   * The static type of a function literal of the form <i>(T<sub>1</sub> a<sub>1</sub>, &hellip;,
   * T<sub>n</sub> a<sub>n</sub>, {T<sub>n+1</sub> x<sub>n+1</sub> : d1, &hellip;, T<sub>n+k</sub>
   * x<sub>n+k</sub> : dk}) => e</i> is <i>(T<sub>1</sub>, &hellip;, T<sub>n</sub>, {T<sub>n+1</sub>
   * x<sub>n+1</sub>, &hellip;, T<sub>n+k</sub> x<sub>n+k</sub>}) &rarr; T<sub>0</sub></i>, where
   * <i>T<sub>0</sub></i> is the static type of <i>e</i>. In any case where <i>T<sub>i</sub>, 1
   * &lt;= i &lt;= n</i>, is not specified, it is considered to have been specified as dynamic.
   *
   * The static type of a function literal of the form <i>(T<sub>1</sub> a<sub>1</sub>, &hellip;,
   * T<sub>n</sub> a<sub>n</sub>, [T<sub>n+1</sub> x<sub>n+1</sub> = d1, &hellip;, T<sub>n+k</sub>
   * x<sub>n+k</sub> = dk]) {s}</i> is <i>(T<sub>1</sub>, &hellip;, T<sub>n</sub>, [T<sub>n+1</sub>
   * x<sub>n+1</sub>, &hellip;, T<sub>n+k</sub> x<sub>n+k</sub>]) &rarr; dynamic</i>. In any case
   * where <i>T<sub>i</sub>, 1 &lt;= i &lt;= n</i>, is not specified, it is considered to have been
   * specified as dynamic.
   *
   * The static type of a function literal of the form <i>(T<sub>1</sub> a<sub>1</sub>, &hellip;,
   * T<sub>n</sub> a<sub>n</sub>, {T<sub>n+1</sub> x<sub>n+1</sub> : d1, &hellip;, T<sub>n+k</sub>
   * x<sub>n+k</sub> : dk}) {s}</i> is <i>(T<sub>1</sub>, &hellip;, T<sub>n</sub>, {T<sub>n+1</sub>
   * x<sub>n+1</sub>, &hellip;, T<sub>n+k</sub> x<sub>n+k</sub>}) &rarr; dynamic</i>. In any case
   * where <i>T<sub>i</sub>, 1 &lt;= i &lt;= n</i>, is not specified, it is considered to have been
   * specified as dynamic.</blockquote>
   */
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (node.parent is FunctionDeclaration) {
      // The function type will be resolved and set when we visit the parent
      // node.
      return;
    }
    _inferLocalFunctionReturnType(node);
  }

  /**
   * The Dart Language Specification, 12.14.4: <blockquote>A function expression invocation <i>i</i>
   * has the form <i>e<sub>f</sub>(a<sub>1</sub>, &hellip;, a<sub>n</sub>, x<sub>n+1</sub>:
   * a<sub>n+1</sub>, &hellip;, x<sub>n+k</sub>: a<sub>n+k</sub>)</i>, where <i>e<sub>f</sub></i> is
   * an expression.
   *
   * It is a static type warning if the static type <i>F</i> of <i>e<sub>f</sub></i> may not be
   * assigned to a function type.
   *
   * If <i>F</i> is not a function type, the static type of <i>i</i> is dynamic. Otherwise the
   * static type of <i>i</i> is the declared return type of <i>F</i>.</blockquote>
   */
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    _inferGenericInvocationExpression(node);
    DartType staticType =
        _computeInvokeReturnType(node.staticInvokeType, isNullAware: false);
    _recordStaticType(node, staticType);
  }

  /**
   * The Dart Language Specification, 12.29: <blockquote>An assignable expression of the form
   * <i>e<sub>1</sub>[e<sub>2</sub>]</i> is evaluated as a method invocation of the operator method
   * <i>[]</i> on <i>e<sub>1</sub></i> with argument <i>e<sub>2</sub></i>.</blockquote>
   */
  @override
  void visitIndexExpression(IndexExpression node) {
    DartType type;
    if (node.inSetterContext()) {
      var parameters =
          _elementTypeProvider.safeExecutableParameters(node.staticElement);
      if (parameters?.length == 2) {
        type = _elementTypeProvider.getVariableType(parameters[1]);
      }
    } else {
      type = _elementTypeProvider.safeExecutableReturnType(node.staticElement);
    }

    type ??= _dynamicType;

    _recordStaticType(node, type);
    _nullShortingTermination(node);
  }

  /**
   * The Dart Language Specification, 12.11.1: <blockquote>The static type of a new expression of
   * either the form <i>new T.id(a<sub>1</sub>, &hellip;, a<sub>n</sub>)</i> or the form <i>new
   * T(a<sub>1</sub>, &hellip;, a<sub>n</sub>)</i> is <i>T</i>.</blockquote>
   *
   * The Dart Language Specification, 12.11.2: <blockquote>The static type of a constant object
   * expression of either the form <i>const T.id(a<sub>1</sub>, &hellip;, a<sub>n</sub>)</i> or the
   * form <i>const T(a<sub>1</sub>, &hellip;, a<sub>n</sub>)</i> is <i>T</i>. </blockquote>
   */
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _inferInstanceCreationExpression(node);
    _recordStaticType(node, node.constructorName.type.type);
  }

  /**
   * <blockquote>
   * An integer literal has static type \code{int}, unless the surrounding
   * static context type is a type which \code{int} is not assignable to, and
   * \code{double} is. In that case the static type of the integer literal is
   * \code{double}.
   * <blockquote>
   *
   * and
   *
   * <blockquote>
   * If $e$ is an expression of the form \code{-$l$} where $l$ is an integer
   * literal (\ref{numbers}) with numeric integer value $i$, then the static
   * type of $e$ is the same as the static type of an integer literal with the
   * same contexttype
   * </blockquote>
   */
  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    // Check the parent context for negated integer literals.
    var context = InferenceContext.getContext(
        (node as IntegerLiteralImpl).immediatelyNegated ? node.parent : node);
    if (context == null ||
        _typeSystem.isAssignableTo(_typeProvider.intType, context) ||
        !_typeSystem.isAssignableTo(_typeProvider.doubleType, context)) {
      _recordStaticType(node, _nonNullable(_typeProvider.intType));
    } else {
      _recordStaticType(node, _nonNullable(_typeProvider.doubleType));
    }
  }

  /**
   * The Dart Language Specification, 12.31: <blockquote>It is a static warning if <i>T</i> does not
   * denote a type available in the current lexical scope.
   *
   * The static type of an is-expression is `bool`.</blockquote>
   */
  @override
  void visitIsExpression(IsExpression node) {
    _recordStaticType(node, _nonNullable(_typeProvider.boolType));
  }

  /**
   * The Dart Language Specification, 12.15.1: <blockquote>An ordinary method invocation <i>i</i>
   * has the form <i>o.m(a<sub>1</sub>, &hellip;, a<sub>n</sub>, x<sub>n+1</sub>: a<sub>n+1</sub>,
   * &hellip;, x<sub>n+k</sub>: a<sub>n+k</sub>)</i>.
   *
   * Let <i>T</i> be the static type of <i>o</i>. It is a static type warning if <i>T</i> does not
   * have an accessible instance member named <i>m</i>. If <i>T.m</i> exists, it is a static warning
   * if the type <i>F</i> of <i>T.m</i> may not be assigned to a function type.
   *
   * If <i>T.m</i> does not exist, or if <i>F</i> is not a function type, the static type of
   * <i>i</i> is dynamic. Otherwise the static type of <i>i</i> is the declared return type of
   * <i>F</i>.</blockquote>
   *
   * The Dart Language Specification, 11.15.3: <blockquote>A static method invocation <i>i</i> has
   * the form <i>C.m(a<sub>1</sub>, &hellip;, a<sub>n</sub>, x<sub>n+1</sub>: a<sub>n+1</sub>,
   * &hellip;, x<sub>n+k</sub>: a<sub>n+k</sub>)</i>.
   *
   * It is a static type warning if the type <i>F</i> of <i>C.m</i> may not be assigned to a
   * function type.
   *
   * If <i>F</i> is not a function type, or if <i>C.m</i> does not exist, the static type of i is
   * dynamic. Otherwise the static type of <i>i</i> is the declared return type of
   * <i>F</i>.</blockquote>
   *
   * The Dart Language Specification, 11.15.4: <blockquote>A super method invocation <i>i</i> has
   * the form <i>super.m(a<sub>1</sub>, &hellip;, a<sub>n</sub>, x<sub>n+1</sub>: a<sub>n+1</sub>,
   * &hellip;, x<sub>n+k</sub>: a<sub>n+k</sub>)</i>.
   *
   * It is a static type warning if <i>S</i> does not have an accessible instance member named m. If
   * <i>S.m</i> exists, it is a static warning if the type <i>F</i> of <i>S.m</i> may not be
   * assigned to a function type.
   *
   * If <i>S.m</i> does not exist, or if <i>F</i> is not a function type, the static type of
   * <i>i</i> is dynamic. Otherwise the static type of <i>i</i> is the declared return type of
   * <i>F</i>.</blockquote>
   */
  @override
  void visitMethodInvocation(MethodInvocation node) {
    _inferGenericInvocationExpression(node);
    // Record static return type of the static element.
    bool inferredStaticType = _inferMethodInvocationObject(node);

    if (!inferredStaticType) {
      DartType staticStaticType = _computeInvokeReturnType(
          node.staticInvokeType,
          isNullAware: node.isNullAware);
      _recordStaticType(node, staticStaticType);
    }
  }

  @override
  void visitNamedExpression(NamedExpression node) {
    Expression expression = node.expression;
    _recordStaticType(node, _getStaticType(expression));
  }

  /**
   * The Dart Language Specification, 12.2: <blockquote>The static type of `null` is bottom.
   * </blockquote>
   */
  @override
  void visitNullLiteral(NullLiteral node) {
    _recordStaticType(node, _typeProvider.nullType);
  }

  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    Expression expression = node.expression;
    _recordStaticType(node, _getStaticType(expression));
  }

  /**
   * The Dart Language Specification, 12.28: <blockquote>A postfix expression of the form
   * <i>v++</i>, where <i>v</i> is an identifier, is equivalent to <i>(){var r = v; v = r + 1;
   * return r}()</i>.
   *
   * A postfix expression of the form <i>C.v++</i> is equivalent to <i>(){var r = C.v; C.v = r + 1;
   * return r}()</i>.
   *
   * A postfix expression of the form <i>e1.v++</i> is equivalent to <i>(x){var r = x.v; x.v = r +
   * 1; return r}(e1)</i>.
   *
   * A postfix expression of the form <i>e1[e2]++</i> is equivalent to <i>(a, i){var r = a[i]; a[i]
   * = r + 1; return r}(e1, e2)</i>
   *
   * A postfix expression of the form <i>v--</i>, where <i>v</i> is an identifier, is equivalent to
   * <i>(){var r = v; v = r - 1; return r}()</i>.
   *
   * A postfix expression of the form <i>C.v--</i> is equivalent to <i>(){var r = C.v; C.v = r - 1;
   * return r}()</i>.
   *
   * A postfix expression of the form <i>e1.v--</i> is equivalent to <i>(x){var r = x.v; x.v = r -
   * 1; return r}(e1)</i>.
   *
   * A postfix expression of the form <i>e1[e2]--</i> is equivalent to <i>(a, i){var r = a[i]; a[i]
   * = r - 1; return r}(e1, e2)</i></blockquote>
   */
  @override
  void visitPostfixExpression(PostfixExpression node) {
    Expression operand = node.operand;
    TypeImpl staticType = _getStaticType(operand, read: true);

    if (node.operator.type == TokenType.BANG) {
      staticType = _typeSystem.promoteToNonNull(staticType);
    } else {
      DartType operatorReturnType;
      if (staticType.isDartCoreInt) {
        // No need to check for `intVar++`, the result is `int`.
        operatorReturnType = staticType;
      } else {
        var operatorElement = node.staticElement;
        operatorReturnType = _computeStaticReturnType(operatorElement);
        _checkForInvalidAssignmentIncDec(node, operand, operatorReturnType);
      }
      if (operand is SimpleIdentifier) {
        var element = operand.staticElement;
        if (element is PromotableElement) {
          _flowAnalysis?.flow?.write(element, operatorReturnType);
        }
      }
    }

    _recordStaticType(node, staticType);
  }

  /**
   * See [visitSimpleIdentifier].
   */
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    SimpleIdentifier prefixedIdentifier = node.identifier;
    Element staticElement = prefixedIdentifier.staticElement;

    if (staticElement is ExtensionElement) {
      _setExtensionIdentifierType(node);
      return;
    }

    DartType staticType = _dynamicType;
    if (staticElement is ClassElement) {
      if (_isExpressionIdentifier(node)) {
        var type = _nonNullable(_typeProvider.typeType);
        node.staticType = type;
        node.identifier.staticType = type;
      }
      return;
    } else if (staticElement is FunctionTypeAliasElement) {
      if (node.parent is TypeName) {
        // no type
      } else {
        var type = _nonNullable(_typeProvider.typeType);
        node.staticType = type;
        node.identifier.staticType = type;
      }
      return;
    } else if (staticElement is MethodElement) {
      staticType = _elementTypeProvider.getExecutableType(staticElement);
    } else if (staticElement is PropertyAccessorElement) {
      staticType = _getTypeOfProperty(staticElement);
    } else if (staticElement is ExecutableElement) {
      staticType = _elementTypeProvider.getExecutableType(staticElement);
    } else if (staticElement is VariableElement) {
      staticType = _elementTypeProvider.getVariableType(staticElement);
    }

    staticType = _inferTearOff(node, node.identifier, staticType);
    if (!_inferObjectAccess(node, staticType, prefixedIdentifier)) {
      _recordStaticType(prefixedIdentifier, staticType);
      _recordStaticType(node, staticType);
    }
  }

  /**
   * The Dart Language Specification, 12.27: <blockquote>A unary expression <i>u</i> of the form
   * <i>op e</i> is equivalent to a method invocation <i>expression e.op()</i>. An expression of the
   * form <i>op super</i> is equivalent to the method invocation <i>super.op()<i>.</blockquote>
   */
  @override
  void visitPrefixExpression(PrefixExpression node) {
    TokenType operator = node.operator.type;
    if (operator == TokenType.BANG) {
      _recordStaticType(node, _nonNullable(_typeProvider.boolType));
    } else {
      // The other cases are equivalent to invoking a method.
      ExecutableElement staticMethodElement = node.staticElement;
      DartType staticType = _computeStaticReturnType(staticMethodElement);
      if (operator.isIncrementOperator) {
        Expression operand = node.operand;
        var operandReadType = _getStaticType(operand, read: true);
        if (operandReadType.isDartCoreInt) {
          staticType = _nonNullable(_typeProvider.intType);
        } else {
          _checkForInvalidAssignmentIncDec(node, operand, staticType);
        }
        if (operand is SimpleIdentifier) {
          var element = operand.staticElement;
          if (element is PromotableElement) {
            _flowAnalysis?.flow?.write(element, staticType);
          }
        }
      }
      _recordStaticType(node, staticType);
    }
  }

  /**
   * The Dart Language Specification, 12.13: <blockquote> Property extraction allows for a member of
   * an object to be concisely extracted from the object. If <i>o</i> is an object, and if <i>m</i>
   * is the name of a method member of <i>o</i>, then
   * * <i>o.m</i> is defined to be equivalent to: <i>(r<sub>1</sub>, &hellip;, r<sub>n</sub>,
   * {p<sub>1</sub> : d<sub>1</sub>, &hellip;, p<sub>k</sub> : d<sub>k</sub>}){return
   * o.m(r<sub>1</sub>, &hellip;, r<sub>n</sub>, p<sub>1</sub>: p<sub>1</sub>, &hellip;,
   * p<sub>k</sub>: p<sub>k</sub>);}</i> if <i>m</i> has required parameters <i>r<sub>1</sub>,
   * &hellip;, r<sub>n</sub></i>, and named parameters <i>p<sub>1</sub> &hellip; p<sub>k</sub></i>
   * with defaults <i>d<sub>1</sub>, &hellip;, d<sub>k</sub></i>.
   * * <i>(r<sub>1</sub>, &hellip;, r<sub>n</sub>, [p<sub>1</sub> = d<sub>1</sub>, &hellip;,
   * p<sub>k</sub> = d<sub>k</sub>]){return o.m(r<sub>1</sub>, &hellip;, r<sub>n</sub>,
   * p<sub>1</sub>, &hellip;, p<sub>k</sub>);}</i> if <i>m</i> has required parameters
   * <i>r<sub>1</sub>, &hellip;, r<sub>n</sub></i>, and optional positional parameters
   * <i>p<sub>1</sub> &hellip; p<sub>k</sub></i> with defaults <i>d<sub>1</sub>, &hellip;,
   * d<sub>k</sub></i>.
   * Otherwise, if <i>m</i> is the name of a getter member of <i>o</i> (declared implicitly or
   * explicitly) then <i>o.m</i> evaluates to the result of invoking the getter. </blockquote>
   *
   * The Dart Language Specification, 12.17: <blockquote> ... a getter invocation <i>i</i> of the
   * form <i>e.m</i> ...
   *
   * Let <i>T</i> be the static type of <i>e</i>. It is a static type warning if <i>T</i> does not
   * have a getter named <i>m</i>.
   *
   * The static type of <i>i</i> is the declared return type of <i>T.m</i>, if <i>T.m</i> exists;
   * otherwise the static type of <i>i</i> is dynamic.
   *
   * ... a getter invocation <i>i</i> of the form <i>C.m</i> ...
   *
   * It is a static warning if there is no class <i>C</i> in the enclosing lexical scope of
   * <i>i</i>, or if <i>C</i> does not declare, implicitly or explicitly, a getter named <i>m</i>.
   *
   * The static type of <i>i</i> is the declared return type of <i>C.m</i> if it exists or dynamic
   * otherwise.
   *
   * ... a top-level getter invocation <i>i</i> of the form <i>m</i>, where <i>m</i> is an
   * identifier ...
   *
   * The static type of <i>i</i> is the declared return type of <i>m</i>.</blockquote>
   */
  @override
  void visitPropertyAccess(PropertyAccess node) {
    SimpleIdentifier propertyName = node.propertyName;
    Element staticElement = propertyName.staticElement;
    DartType staticType = _dynamicType;
    if (staticElement is MethodElement) {
      staticType = _elementTypeProvider.getExecutableType(staticElement);
    } else if (staticElement is PropertyAccessorElement) {
      staticType = _getTypeOfProperty(staticElement);
    } else {
      // TODO(brianwilkerson) Report this internal error.
    }

    staticType = _inferTearOff(node, node.propertyName, staticType);

    if (!_inferObjectAccess(node, staticType, propertyName)) {
      _recordStaticType(propertyName, staticType);
      _recordStaticType(node, staticType);
      _nullShortingTermination(node);
    }
  }

  /**
   * The Dart Language Specification, 12.9: <blockquote>The static type of a rethrow expression is
   * bottom.</blockquote>
   */
  @override
  void visitRethrowExpression(RethrowExpression node) {
    _recordStaticType(node, _typeProvider.bottomType);
  }

  /**
   * The Dart Language Specification, 12.30: <blockquote>Evaluation of an identifier expression
   * <i>e</i> of the form <i>id</i> proceeds as follows:
   *
   * Let <i>d</i> be the innermost declaration in the enclosing lexical scope whose name is
   * <i>id</i>. If no such declaration exists in the lexical scope, let <i>d</i> be the declaration
   * of the inherited member named <i>id</i> if it exists.
   * * If <i>d</i> is a class or type alias <i>T</i>, the value of <i>e</i> is the unique instance
   * of class `Type` reifying <i>T</i>.
   * * If <i>d</i> is a type parameter <i>T</i>, then the value of <i>e</i> is the value of the
   * actual type argument corresponding to <i>T</i> that was passed to the generative constructor
   * that created the current binding of this. We are assured that this is well defined, because if
   * we were in a static member the reference to <i>T</i> would be a compile-time error.
   * * If <i>d</i> is a library variable then:
   * * If <i>d</i> is of one of the forms <i>var v = e<sub>i</sub>;</i>, <i>T v =
   * e<sub>i</sub>;</i>, <i>final v = e<sub>i</sub>;</i>, <i>final T v = e<sub>i</sub>;</i>, and no
   * value has yet been stored into <i>v</i> then the initializer expression <i>e<sub>i</sub></i> is
   * evaluated. If, during the evaluation of <i>e<sub>i</sub></i>, the getter for <i>v</i> is
   * referenced, a CyclicInitializationError is thrown. If the evaluation succeeded yielding an
   * object <i>o</i>, let <i>r = o</i>, otherwise let <i>r = null</i>. In any case, <i>r</i> is
   * stored into <i>v</i>. The value of <i>e</i> is <i>r</i>.
   * * If <i>d</i> is of one of the forms <i>const v = e;</i> or <i>const T v = e;</i> the result
   * of the getter is the value of the compile time constant <i>e</i>. Otherwise
   * * <i>e</i> evaluates to the current binding of <i>id</i>.
   * * If <i>d</i> is a local variable or formal parameter then <i>e</i> evaluates to the current
   * binding of <i>id</i>.
   * * If <i>d</i> is a static method, top level function or local function then <i>e</i>
   * evaluates to the function defined by <i>d</i>.
   * * If <i>d</i> is the declaration of a static variable or static getter declared in class
   * <i>C</i>, then <i>e</i> is equivalent to the getter invocation <i>C.id</i>.
   * * If <i>d</i> is the declaration of a top level getter, then <i>e</i> is equivalent to the
   * getter invocation <i>id</i>.
   * * Otherwise, if <i>e</i> occurs inside a top level or static function (be it function,
   * method, getter, or setter) or variable initializer, evaluation of e causes a NoSuchMethodError
   * to be thrown.
   * * Otherwise <i>e</i> is equivalent to the property extraction <i>this.id</i>.
   * </blockquote>
   */
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    Element element = node.staticElement;

    if (element is ExtensionElement) {
      _setExtensionIdentifierType(node);
      return;
    }

    DartType staticType = _dynamicType;
    if (element is ClassElement) {
      if (_isExpressionIdentifier(node)) {
        node.staticType = _nonNullable(_typeProvider.typeType);
      }
      return;
    } else if (element is FunctionTypeAliasElement) {
      if (node.inDeclarationContext() || node.parent is TypeName) {
        // no type
      } else {
        node.staticType = _nonNullable(_typeProvider.typeType);
      }
      return;
    } else if (element is MethodElement) {
      staticType = _elementTypeProvider.getExecutableType(element);
    } else if (element is PropertyAccessorElement) {
      staticType = _getTypeOfProperty(element);
    } else if (element is ExecutableElement) {
      staticType = _elementTypeProvider.getExecutableType(element);
    } else if (element is TypeParameterElement) {
      staticType = _nonNullable(_typeProvider.typeType);
    } else if (element is VariableElement) {
      staticType = _localVariableTypeProvider.getType(node);
    } else if (element is PrefixElement) {
      var parent = node.parent;
      if (parent is PrefixedIdentifier && parent.prefix == node ||
          parent is MethodInvocation && parent.target == node) {
        return;
      }
      staticType = _typeProvider.dynamicType;
    } else if (element is DynamicElementImpl) {
      staticType = _nonNullable(_typeProvider.typeType);
    } else {
      staticType = _dynamicType;
    }
    staticType = _inferTearOff(node, node, staticType);
    _recordStaticType(node, staticType);
  }

  /**
   * The Dart Language Specification, 12.5: <blockquote>The static type of a string literal is
   * `String`.</blockquote>
   */
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _recordStaticType(node, _nonNullable(_typeProvider.stringType));
  }

  /**
   * The Dart Language Specification, 12.5: <blockquote>The static type of a string literal is
   * `String`.</blockquote>
   */
  @override
  void visitStringInterpolation(StringInterpolation node) {
    _recordStaticType(node, _nonNullable(_typeProvider.stringType));
  }

  @override
  void visitSuperExpression(SuperExpression node) {
    if (thisType == null ||
        node.thisOrAncestorOfType<ExtensionDeclaration>() != null) {
      // TODO(brianwilkerson) Report this error if it hasn't already been
      // reported.
      _recordStaticType(node, _dynamicType);
    } else {
      _recordStaticType(node, thisType);
    }
  }

  @override
  void visitSymbolLiteral(SymbolLiteral node) {
    _recordStaticType(node, _nonNullable(_typeProvider.symbolType));
  }

  /**
   * The Dart Language Specification, 12.10: <blockquote>The static type of `this` is the
   * interface of the immediately enclosing class.</blockquote>
   */
  @override
  void visitThisExpression(ThisExpression node) {
    if (thisType == null) {
      // TODO(brianwilkerson) Report this error if it hasn't already been
      // reported.
      _recordStaticType(node, _dynamicType);
    } else {
      _recordStaticType(node, thisType);
    }
  }

  /**
   * The Dart Language Specification, 12.8: <blockquote>The static type of a throw expression is
   * bottom.</blockquote>
   */
  @override
  void visitThrowExpression(ThrowExpression node) {
    _recordStaticType(node, _typeProvider.bottomType);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _inferLocalVariableType(node, node.initializer);
  }

  /**
   * Set the static type of [node] to be the least upper bound of the static
   * types of subexpressions [expr1] and [expr2].
   */
  void _analyzeLeastUpperBound(
      Expression node, Expression expr1, Expression expr2,
      {bool read = false}) {
    DartType staticType1 = _getExpressionType(expr1, read: read);
    DartType staticType2 = _getExpressionType(expr2, read: read);

    _analyzeLeastUpperBoundTypes(node, staticType1, staticType2);
  }

  /**
   * Set the static type of [node] to be the least upper bound of the static
   * types [staticType1] and [staticType2].
   */
  void _analyzeLeastUpperBoundTypes(
      Expression node, DartType staticType1, DartType staticType2) {
    if (staticType1 == null) {
      // TODO(brianwilkerson) Determine whether this can still happen.
      staticType1 = _dynamicType;
    }

    if (staticType2 == null) {
      // TODO(brianwilkerson) Determine whether this can still happen.
      staticType2 = _dynamicType;
    }

    DartType staticType =
        _typeSystem.getLeastUpperBound(staticType1, staticType2) ??
            _dynamicType;

    staticType = _resolver.toLegacyTypeIfOptOut(staticType);

    _recordStaticType(node, staticType);
  }

  /// Check that the result [type] of a prefix or postfix `++` or `--`
  /// expression is assignable to the write type of the [operand].
  void _checkForInvalidAssignmentIncDec(
      AstNode node, Expression operand, DartType type) {
    var operandWriteType = _getStaticType(operand);
    if (!_typeSystem.isAssignableTo(type, operandWriteType)) {
      _resolver.errorReporter.reportErrorForNode(
        StaticTypeWarningCode.INVALID_ASSIGNMENT,
        node,
        [type, operandWriteType],
      );
    }
  }

  /**
   * Compute the return type of the method or function represented by the given
   * type that is being invoked.
   */
  DartType /*!*/ _computeInvokeReturnType(DartType type,
      {@required bool isNullAware}) {
    TypeImpl /*!*/ returnType;
    if (type is InterfaceType) {
      MethodElement callMethod = type.lookUpMethod2(
          FunctionElement.CALL_METHOD_NAME, _resolver.definingLibrary);
      returnType =
          _elementTypeProvider.safeExecutableType(callMethod)?.returnType ??
              _dynamicType;
    } else if (type is FunctionType) {
      returnType = type.returnType ?? _dynamicType;
    } else {
      returnType = _dynamicType;
    }

    if (isNullAware && _isNonNullableByDefault) {
      returnType = _typeSystem.makeNullable(returnType);
    }

    return returnType;
  }

  /**
   * Given a function body and its return type, compute the return type of
   * the entire function, taking into account whether the function body
   * is `sync*`, `async` or `async*`.
   *
   * See also [FunctionBody.isAsynchronous], [FunctionBody.isGenerator].
   */
  DartType _computeReturnTypeOfFunction(FunctionBody body, DartType type) {
    if (body.isGenerator) {
      InterfaceType generatedType = body.isAsynchronous
          ? _typeProvider.streamType2(type)
          : _typeProvider.iterableType2(type);
      return _nonNullable(generatedType);
    } else if (body.isAsynchronous) {
      if (type.isDartAsyncFutureOr) {
        type = (type as InterfaceType).typeArguments[0];
      }
      DartType futureType =
          _typeProvider.futureType2(_typeSystem.flatten(type));
      return _nonNullable(futureType);
    } else {
      return type;
    }
  }

  /**
   * Compute the static return type of the method or function represented by the given element.
   *
   * @param element the element representing the method or function invoked by the given node
   * @return the static return type that was computed
   */
  DartType _computeStaticReturnType(Element element) {
    if (element is PropertyAccessorElement) {
      //
      // This is a function invocation expression disguised as something else.
      // We are invoking a getter and then invoking the returned function.
      //
      FunctionType propertyType =
          _elementTypeProvider.getExecutableType(element);
      if (propertyType != null) {
        return _computeInvokeReturnType(propertyType.returnType,
            isNullAware: false);
      }
    } else if (element is ExecutableElement) {
      return _computeInvokeReturnType(
          _elementTypeProvider.getExecutableType(element),
          isNullAware: false);
    }
    return _dynamicType;
  }

  /**
   * Given a function declaration, compute the return static type of the function. The return type
   * of functions with a block body is `dynamicType`, with an expression body it is the type
   * of the expression.
   *
   * @param node the function expression whose static return type is to be computed
   * @return the static return type that was computed
   */
  DartType _computeStaticReturnTypeOfFunctionDeclaration(
      FunctionDeclaration node) {
    TypeAnnotation returnType = node.returnType;
    if (returnType == null) {
      return _dynamicType;
    }
    return returnType.type;
  }

  /**
   * Gets the definite type of expression, which can be used in cases where
   * the most precise type is desired, for example computing the least upper
   * bound.
   *
   * See [getExpressionType] for more information. Without strong mode, this is
   * equivalent to [_getStaticType].
   */
  DartType _getExpressionType(Expression expr, {bool read = false}) =>
      getExpressionType(expr, _typeSystem, _typeProvider,
          read: read, elementTypeProvider: _elementTypeProvider);

  /**
   * Return the static type of the given [expression].
   */
  DartType _getStaticType(Expression expression, {bool read = false}) {
    DartType type;
    if (read) {
      type = getReadType(expression, elementTypeProvider: _elementTypeProvider);
    } else {
      if (expression is SimpleIdentifier && expression.inSetterContext()) {
        var element = expression.staticElement;
        if (element is PromotableElement) {
          // We're writing to the element so ignore promotions.
          type = _elementTypeProvider.getVariableType(element);
        } else {
          type = expression.staticType;
        }
      } else {
        type = expression.staticType;
      }
    }
    if (type == null) {
      // TODO(brianwilkerson) Determine the conditions for which the static type
      // is null.
      return _dynamicType;
    }
    return type;
  }

  /**
   * Return the type represented by the given type [annotation].
   */
  DartType _getType(TypeAnnotation annotation) {
    DartType type = annotation.type;
    if (type == null) {
      //TODO(brianwilkerson) Determine the conditions for which the type is
      // null.
      return _dynamicType;
    }
    return type;
  }

  /**
   * Return the type that should be recorded for a node that resolved to the given accessor.
   *
   * @param accessor the accessor that the node resolved to
   * @return the type that should be recorded for a node that resolved to the given accessor
   */
  DartType _getTypeOfProperty(PropertyAccessorElement accessor) {
    FunctionType functionType =
        _elementTypeProvider.getExecutableType(accessor);
    if (functionType == null) {
      // TODO(brianwilkerson) Report this internal error. This happens when we
      // are analyzing a reference to a property before we have analyzed the
      // declaration of the property or when the property does not have a
      // defined type.
      return _dynamicType;
    }
    if (accessor.isSetter) {
      List<DartType> parameterTypes = functionType.normalParameterTypes;
      if (parameterTypes != null && parameterTypes.isNotEmpty) {
        return parameterTypes[0];
      }
      PropertyAccessorElement getter = accessor.variable.getter;
      if (getter != null) {
        functionType = _elementTypeProvider.getExecutableType(getter);
        if (functionType != null) {
          return functionType.returnType;
        }
      }
      return _dynamicType;
    }
    return functionType.returnType;
  }

  /**
   * Given a possibly generic invocation like `o.m(args)` or `(f)(args)` try to
   * infer the instantiated generic function type.
   *
   * This takes into account both the context type, as well as information from
   * the argument types.
   */
  void _inferGenericInvocationExpression(InvocationExpression node) {
    ArgumentList arguments = node.argumentList;
    var type = node.function.staticType;
    var freshType = _getFreshType(type);

    FunctionType inferred = _inferGenericInvoke(
        node, freshType, node.typeArguments, arguments, node.function);
    if (inferred != null && inferred != node.staticInvokeType) {
      // Fix up the parameter elements based on inferred method.
      arguments.correspondingStaticParameters =
          ResolverVisitor.resolveArgumentsToParameters(
              arguments, inferred.parameters, null);
      node.staticInvokeType = inferred;
    }
  }

  /**
   * Given a possibly generic invocation or instance creation, such as
   * `o.m(args)` or `(f)(args)` or `new T(args)` try to infer the instantiated
   * generic function type.
   *
   * This takes into account both the context type, as well as information from
   * the argument types.
   */
  FunctionType _inferGenericInvoke(
      Expression node,
      DartType fnType,
      TypeArgumentList typeArguments,
      ArgumentList argumentList,
      AstNode errorNode,
      {bool isConst = false}) {
    if (typeArguments == null &&
        fnType is FunctionType &&
        fnType.typeFormals.isNotEmpty) {
      // Get the parameters that correspond to the uninstantiated generic.
      List<ParameterElement> rawParameters =
          ResolverVisitor.resolveArgumentsToParameters(
              argumentList, fnType.parameters, null);

      List<ParameterElement> params = <ParameterElement>[];
      List<DartType> argTypes = <DartType>[];
      for (int i = 0, length = rawParameters.length; i < length; i++) {
        ParameterElement parameter = rawParameters[i];
        if (parameter != null) {
          params.add(parameter);
          argTypes.add(argumentList.arguments[i].staticType);
        }
      }
      var typeArgs = _typeSystem.inferGenericFunctionOrType(
        typeParameters: fnType.typeFormals,
        parameters: params,
        declaredReturnType: fnType.returnType,
        argumentTypes: argTypes,
        contextReturnType: InferenceContext.getContext(node),
        isConst: isConst,
        errorReporter: _resolver.errorReporter,
        errorNode: errorNode,
      );
      if (node is InvocationExpressionImpl) {
        node.typeArgumentTypes = typeArgs;
      }
      if (typeArgs != null) {
        return fnType.instantiate(typeArgs);
      }
      return fnType;
    }

    // There is currently no other place where we set type arguments
    // for FunctionExpressionInvocation(s), so set it here, if not inferred.
    if (node is FunctionExpressionInvocationImpl) {
      if (typeArguments != null) {
        var typeArgs = typeArguments.arguments.map((n) => n.type).toList();
        node.typeArgumentTypes = typeArgs;
      } else {
        node.typeArgumentTypes = const <DartType>[];
      }
    }

    return null;
  }

  /**
   * Given an instance creation of a possibly generic type, infer the type
   * arguments using the current context type as well as the argument types.
   */
  void _inferInstanceCreationExpression(InstanceCreationExpression node) {
    ConstructorName constructor = node.constructorName;
    ConstructorElement originalElement = constructor.staticElement;
    // If the constructor is generic, we'll have a ConstructorMember that
    // substitutes in type arguments (possibly `dynamic`) from earlier in
    // resolution.
    //
    // Otherwise we'll have a ConstructorElement, and we can skip inference
    // because there's nothing to infer in a non-generic type.
    if (originalElement is! ConstructorMember) {
      return;
    }

    // TODO(leafp): Currently, we may re-infer types here, since we
    // sometimes resolve multiple times.  We should really check that we
    // have not already inferred something.  However, the obvious ways to
    // check this don't work, since we may have been instantiated
    // to bounds in an earlier phase, and we *do* want to do inference
    // in that case.

    // Get back to the uninstantiated generic constructor.
    // TODO(jmesserly): should we store this earlier in resolution?
    // Or look it up, instead of jumping backwards through the Member?
    var rawElement = originalElement.declaration;

    FunctionType constructorType = constructorToGenericFunctionType(rawElement);

    ArgumentList arguments = node.argumentList;
    FunctionType inferred = _inferGenericInvoke(node, constructorType,
        constructor.type.typeArguments, arguments, node.constructorName,
        isConst: node.isConst);

    if (inferred != null &&
        inferred != _elementTypeProvider.getExecutableType(originalElement)) {
      // Fix up the parameter elements based on inferred method.
      arguments.correspondingStaticParameters =
          ResolverVisitor.resolveArgumentsToParameters(
              arguments, inferred.parameters, null);
      constructor.type.type = inferred.returnType;
      // Update the static element as well. This is used in some cases, such as
      // computing constant values. It is stored in two places.
      constructor.staticElement =
          ConstructorMember.from(rawElement, inferred.returnType);
      node.staticElement = constructor.staticElement;
    }
  }

  /**
   * Infers the return type of a local function, either a lambda or
   * (in strong mode) a local function declaration.
   */
  void _inferLocalFunctionReturnType(FunctionExpression node) {
    ExecutableElementImpl functionElement =
        node.declaredElement as ExecutableElementImpl;

    FunctionBody body = node.body;

    DartType computedType = InferenceContext.getContext(body) ?? _dynamicType;

    computedType = _computeReturnTypeOfFunction(body, computedType);
    functionElement.returnType = computedType;
    _recordStaticType(
        node, _elementTypeProvider.getExecutableType(functionElement));
  }

  /**
   * Given a local variable declaration and its initializer, attempt to infer
   * a type for the local variable declaration based on the initializer.
   * Inference is only done if an explicit type is not present, and if
   * inferring a type improves the type.
   */
  void _inferLocalVariableType(
      VariableDeclaration node, Expression initializer) {
    AstNode parent = node.parent;
    if (initializer != null) {
      if (parent is VariableDeclarationList && parent.type == null) {
        DartType type = initializer.staticType;
        if (type != null && !type.isBottom && !type.isDartCoreNull) {
          VariableElement element = node.declaredElement;
          if (element is LocalVariableElementImpl) {
            element.type = initializer.staticType;
          }
        }
      }
    } else if (_strictInference) {
      if (parent is VariableDeclarationList && parent.type == null) {
        _resolver.errorReporter.reportErrorForNode(
          HintCode.INFERENCE_FAILURE_ON_UNINITIALIZED_VARIABLE,
          node,
          [node.name.name],
        );
      }
    }
  }

  /**
   * Given a method invocation [node], attempt to infer a better
   * type for the result if the target is dynamic and the method
   * being called is one of the object methods.
   */
  // TODO(jmesserly): we should move this logic to ElementResolver.
  // If we do it here, we won't have correct parameter elements set on the
  // node's argumentList. (This likely affects only explicit calls to
  // `Object.noSuchMethod`.)
  bool _inferMethodInvocationObject(MethodInvocation node) {
    // If we have a call like `toString()` or `libraryPrefix.toString()`, don't
    // infer it.
    Expression target = node.realTarget;
    if (target == null ||
        target is SimpleIdentifier && target.staticElement is PrefixElement) {
      return false;
    }
    DartType nodeType = node.staticInvokeType;
    if (nodeType == null ||
        !nodeType.isDynamic ||
        node.argumentList.arguments.isNotEmpty) {
      return false;
    }
    // Object methods called on dynamic targets can have their types improved.
    String name = node.methodName.name;
    MethodElement inferredElement =
        _typeProvider.objectType.element.getMethod(name);
    if (inferredElement == null || inferredElement.isStatic) {
      return false;
    }
    DartType inferredType =
        _elementTypeProvider.getExecutableType(inferredElement);
    if (inferredType is FunctionType) {
      DartType returnType = inferredType.returnType;
      if (inferredType.parameters.isEmpty &&
          returnType is InterfaceType &&
          _typeProvider.nonSubtypableClasses.contains(returnType.element)) {
        node.staticInvokeType = inferredType;
        _recordStaticType(node, inferredType.returnType);
        return true;
      }
    }
    return false;
  }

  /**
   * Given a property access [node] with static type [nodeType],
   * and [id] is the property name being accessed, infer a type for the
   * access itself and its constituent components if the access is to one of the
   * methods or getters of the built in 'Object' type, and if the result type is
   * a sealed type. Returns true if inference succeeded.
   */
  bool _inferObjectAccess(
      Expression node, DartType nodeType, SimpleIdentifier id) {
    // If we have an access like `libraryPrefix.hashCode` don't infer it.
    if (node is PrefixedIdentifier &&
        node.prefix.staticElement is PrefixElement) {
      return false;
    }
    // Search for Object accesses.
    String name = id.name;
    PropertyAccessorElement inferredElement =
        _typeProvider.objectType.element.getGetter(name);
    if (inferredElement == null || inferredElement.isStatic) {
      return false;
    }
    DartType inferredType =
        _elementTypeProvider.getExecutableReturnType(inferredElement);
    if (nodeType != null &&
        nodeType.isDynamic &&
        inferredType is InterfaceType &&
        _typeProvider.nonSubtypableClasses.contains(inferredType.element)) {
      _recordStaticType(id, inferredType);
      _recordStaticType(node, inferredType);
      return true;
    }
    return false;
  }

  /**
   * Given an uninstantiated generic function type, referenced by the
   * [identifier] in the tear-off [expression], try to infer the instantiated
   * generic function type from the surrounding context.
   */
  DartType _inferTearOff(
    Expression expression,
    SimpleIdentifier identifier,
    DartType tearOffType,
  ) {
    var context = InferenceContext.getContext(expression);
    if (context is FunctionType && tearOffType is FunctionType) {
      var typeArguments = _typeSystem.inferFunctionTypeInstantiation(
        context,
        tearOffType,
        errorReporter: _resolver.errorReporter,
        errorNode: expression,
      );
      (identifier as SimpleIdentifierImpl).tearOffTypeArgumentTypes =
          typeArguments;
      if (typeArguments.isNotEmpty) {
        return tearOffType.instantiate(typeArguments);
      }
    }
    return tearOffType;
  }

  /**
   * Return `true` if the given [node] is not a type literal.
   */
  bool _isExpressionIdentifier(Identifier node) {
    var parent = node.parent;
    if (node is SimpleIdentifier && node.inDeclarationContext()) {
      return false;
    }
    if (parent is ConstructorDeclaration) {
      if (parent.name == node || parent.returnType == node) {
        return false;
      }
    }
    if (parent is ConstructorName ||
        parent is MethodInvocation ||
        parent is PrefixedIdentifier && parent.prefix == node ||
        parent is PropertyAccess ||
        parent is TypeName) {
      return false;
    }
    return true;
  }

  /**
   * Return the non-nullable variant of the [type] if NNBD is enabled, otherwise
   * return the type itself.
   */
  DartType _nonNullable(DartType type) {
    if (_isNonNullableByDefault) {
      return _typeSystem.promoteToNonNull(type);
    }
    return type;
  }

  /// If we reached a null-shorting termination, and the [node] has null
  /// shorting, make the type of the [node] nullable.
  void _nullShortingTermination(Expression node) {
    if (!_isNonNullableByDefault) return;

    if (identical(_resolver.unfinishedNullShorts.last, node)) {
      do {
        _resolver.unfinishedNullShorts.removeLast();
        _flowAnalysis.flow.nullAwareAccess_end();
      } while (identical(_resolver.unfinishedNullShorts.last, node));
      node.staticType = _typeSystem.makeNullable(node.staticType);
    }
  }

  /**
   * Record that the static type of the given node is the given type.
   *
   * @param expression the node whose type is to be recorded
   * @param type the static type of the node
   */
  void _recordStaticType(Expression expression, DartType type) {
    if (type == null) {
      expression.staticType = _dynamicType;
    } else {
      expression.staticType = type;
      if (identical(type, NeverTypeImpl.instance)) {
        _flowAnalysis?.flow?.handleExit();
      }
    }
  }

  void _setExtensionIdentifierType(Identifier node) {
    if (node is SimpleIdentifier && node.inDeclarationContext()) {
      return;
    }

    var parent = node.parent;

    if (parent is PrefixedIdentifier && parent.identifier == node) {
      node = parent;
      parent = node.parent;
    }

    if (parent is CommentReference ||
        parent is ExtensionOverride && parent.extensionName == node ||
        parent is MethodInvocation && parent.target == node ||
        parent is PrefixedIdentifier && parent.prefix == node ||
        parent is PropertyAccess && parent.target == node) {
      return;
    }

    _resolver.errorReporter.reportErrorForNode(
      CompileTimeErrorCode.EXTENSION_AS_EXPRESSION,
      node,
      [node.name],
    );

    if (node is PrefixedIdentifier) {
      node.identifier.staticType = _dynamicType;
      node.staticType = _dynamicType;
    } else if (node is SimpleIdentifier) {
      node.staticType = _dynamicType;
    }
  }

  static DartType _getFreshType(DartType type) {
    if (type is FunctionType) {
      var parameters = getFreshTypeParameters(type.typeFormals);
      return parameters.applyToFunctionType(type);
    } else {
      return type;
    }
  }
}

/// Override of [FlowAnalysisHelper] that invokes methods of
/// [MigrationResolutionHooks] when appropriate.
class StaticTypeAnalyzerForMigration extends StaticTypeAnalyzer {
  StaticTypeAnalyzerForMigration(
      ResolverVisitor resolver,
      FeatureSet featureSet,
      FlowAnalysisHelper flowAnalysis,
      MigrationResolutionHooks migrationResolutionHooks)
      : super(resolver, featureSet, flowAnalysis,
            elementTypeProvider: migrationResolutionHooks);

  @override
  void _recordStaticType(Expression expression, DartType type) {
    super._recordStaticType(
        expression,
        (_elementTypeProvider as MigrationResolutionHooks)
            .modifyExpressionType(expression, type ?? _dynamicType));
  }
}
