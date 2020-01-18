// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/variance.dart';
import 'package:analyzer/src/generated/utilities_dart.dart';
import 'package:meta/meta.dart';

mixin ElementsTypesMixin {
  InterfaceType get doubleNone {
    var element = typeProvider.doubleType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get doubleQuestion {
    var element = typeProvider.doubleType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get doubleStar {
    var element = typeProvider.doubleType.element;
    return interfaceTypeStar(element);
  }

  DartType get dynamicNone => DynamicTypeImpl.instance;

  DynamicTypeImpl get dynamicType => DynamicTypeImpl.instance;

  InterfaceType get functionNone {
    var element = typeProvider.functionType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get functionQuestion {
    var element = typeProvider.functionType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get functionStar {
    var element = typeProvider.functionType.element;
    return interfaceTypeStar(element);
  }

  InterfaceType get intNone {
    var element = typeProvider.intType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get intQuestion {
    var element = typeProvider.intType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get intStar {
    var element = typeProvider.intType.element;
    return interfaceTypeStar(element);
  }

  NeverTypeImpl get neverNone => NeverTypeImpl.instance;

  NeverTypeImpl get neverQuestion => NeverTypeImpl.instanceNullable;

  NeverTypeImpl get neverStar => NeverTypeImpl.instanceLegacy;

  InterfaceTypeImpl get nullNone {
    var element = typeProvider.nullType.element;
    return interfaceTypeNone(element);
  }

  InterfaceTypeImpl get nullQuestion {
    var element = typeProvider.nullType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceTypeImpl get nullStar {
    var element = typeProvider.nullType.element;
    return interfaceTypeStar(element);
  }

  InterfaceType get numNone {
    var element = typeProvider.numType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get numQuestion {
    var element = typeProvider.numType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get numStar {
    var element = typeProvider.numType.element;
    return interfaceTypeStar(element);
  }

  InterfaceType get objectNone {
    var element = typeProvider.objectType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get objectQuestion {
    var element = typeProvider.objectType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get objectStar {
    var element = typeProvider.objectType.element;
    return interfaceTypeStar(element);
  }

  InterfaceType get stringNone {
    var element = typeProvider.stringType.element;
    return interfaceTypeNone(element);
  }

  InterfaceType get stringQuestion {
    var element = typeProvider.stringType.element;
    return interfaceTypeQuestion(element);
  }

  InterfaceType get stringStar {
    var element = typeProvider.stringType.element;
    return interfaceTypeStar(element);
  }

  TypeProvider get typeProvider;

  VoidTypeImpl get voidNone => VoidTypeImpl.instance;

  ClassElementImpl class_({
    @required String name,
    bool isAbstract = false,
    InterfaceType superType,
    List<TypeParameterElement> typeParameters = const [],
    List<InterfaceType> interfaces = const [],
    List<InterfaceType> mixins = const [],
    List<MethodElement> methods = const [],
  }) {
    var element = ClassElementImpl(name, 0);
    element.typeParameters = typeParameters;
    element.supertype = superType ?? typeProvider.objectType;
    element.interfaces = interfaces;
    element.mixins = mixins;
    element.methods = methods;
    return element;
  }

  InterfaceType comparableNone(DartType type) {
    var coreLibrary = typeProvider.intElement.library;
    var element = coreLibrary.getType('Comparable');
    return element.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceType comparableQuestion(DartType type) {
    var coreLibrary = typeProvider.intElement.library;
    var element = coreLibrary.getType('Comparable');
    return element.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceType comparableStar(DartType type) {
    var coreLibrary = typeProvider.intElement.library;
    var element = coreLibrary.getType('Comparable');
    return element.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  FunctionTypeImpl functionType({
    @required List<TypeParameterElement> typeFormals,
    @required List<ParameterElement> parameters,
    @required DartType returnType,
    @required NullabilitySuffix nullabilitySuffix,
  }) {
    return FunctionTypeImpl(
      typeFormals: typeFormals,
      parameters: parameters,
      returnType: returnType,
      nullabilitySuffix: nullabilitySuffix,
    );
  }

  FunctionType functionTypeAliasType(
    FunctionTypeAliasElement element, {
    List<DartType> typeArguments = const [],
    NullabilitySuffix nullabilitySuffix = NullabilitySuffix.star,
  }) {
    return element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: nullabilitySuffix,
    );
  }

  FunctionTypeImpl functionTypeNone({
    List<TypeParameterElement> typeFormals = const [],
    List<ParameterElement> parameters = const [],
    @required DartType returnType,
  }) {
    return functionType(
      typeFormals: typeFormals,
      parameters: parameters,
      returnType: returnType,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  FunctionTypeImpl functionTypeQuestion({
    List<TypeParameterElement> typeFormals = const [],
    List<ParameterElement> parameters = const [],
    @required DartType returnType,
  }) {
    return functionType(
      typeFormals: typeFormals,
      parameters: parameters,
      returnType: returnType,
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  FunctionTypeImpl functionTypeStar({
    List<TypeParameterElement> typeFormals = const [],
    List<ParameterElement> parameters = const [],
    @required DartType returnType,
  }) {
    return functionType(
      typeFormals: typeFormals,
      parameters: parameters,
      returnType: returnType,
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  InterfaceTypeImpl futureNone(DartType type) {
    return typeProvider.futureElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceTypeImpl futureOrNone(DartType type) {
    return typeProvider.futureOrElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceTypeImpl futureOrQuestion(DartType type) {
    return typeProvider.futureOrElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceTypeImpl futureOrStar(DartType type) {
    return typeProvider.futureOrElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  InterfaceTypeImpl futureQuestion(DartType type) {
    return typeProvider.futureElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceTypeImpl futureStar(DartType type) {
    return typeProvider.futureElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  DartType futureType(DartType T) {
    var futureElement = typeProvider.futureElement;
    return interfaceTypeStar(futureElement, typeArguments: [T]);
  }

  GenericFunctionTypeElementImpl genericFunctionType({
    List<TypeParameterElement> typeParameters,
    List<ParameterElement> parameters,
    DartType returnType,
  }) {
    var result = GenericFunctionTypeElementImpl.forOffset(0);
    result.typeParameters = typeParameters;
    result.parameters = parameters;
    result.returnType = returnType ?? typeProvider.voidType;
    return result;
  }

  GenericTypeAliasElementImpl genericTypeAlias({
    @required String name,
    List<TypeParameterElement> typeParameters = const [],
    @required GenericFunctionTypeElement function,
  }) {
    return GenericTypeAliasElementImpl(name, 0)
      ..typeParameters = typeParameters
      ..function = function;
  }

  InterfaceType interfaceType(
    ClassElement element, {
    List<DartType> typeArguments = const [],
    @required NullabilitySuffix nullabilitySuffix,
  }) {
    return element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: nullabilitySuffix,
    );
  }

  InterfaceType interfaceTypeNone(
    ClassElement element, {
    List<DartType> typeArguments = const [],
  }) {
    return element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceType interfaceTypeQuestion(
    ClassElement element, {
    List<DartType> typeArguments = const [],
  }) {
    return element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceType interfaceTypeStar(
    ClassElement element, {
    List<DartType> typeArguments = const [],
  }) {
    return element.instantiate(
      typeArguments: typeArguments,
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  InterfaceType iterableNone(DartType type) {
    return typeProvider.iterableElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceType iterableQuestion(DartType type) {
    return typeProvider.iterableElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceType iterableStar(DartType type) {
    return typeProvider.iterableElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  InterfaceType listNone(DartType type) {
    return typeProvider.listElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.none,
    );
  }

  InterfaceType listQuestion(DartType type) {
    return typeProvider.listElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.question,
    );
  }

  InterfaceType listStar(DartType type) {
    return typeProvider.listElement.instantiate(
      typeArguments: [type],
      nullabilitySuffix: NullabilitySuffix.star,
    );
  }

  MethodElement method(
    String name,
    DartType returnType, {
    bool isStatic = false,
    List<TypeParameterElement> typeFormals = const [],
    List<ParameterElement> parameters = const [],
  }) {
    return MethodElementImpl(name, 0)
      ..isStatic = isStatic
      ..parameters = parameters
      ..returnType = returnType
      ..typeParameters = typeFormals;
  }

  MixinElementImpl mixin_({
    @required String name,
    List<TypeParameterElement> typeParameters = const [],
    List<InterfaceType> constraints,
    List<InterfaceType> interfaces = const [],
  }) {
    var element = MixinElementImpl(name, 0);
    element.typeParameters = typeParameters;
    element.superclassConstraints = constraints ?? [typeProvider.objectType];
    element.interfaces = interfaces;
    element.constructors = const <ConstructorElement>[];
    return element;
  }

  ParameterElement namedParameter({
    @required String name,
    @required DartType type,
  }) {
    var parameter = ParameterElementImpl(name, 0);
    parameter.parameterKind = ParameterKind.NAMED;
    parameter.type = type;
    return parameter;
  }

  ParameterElement namedRequiredParameter({
    @required String name,
    @required DartType type,
  }) {
    var parameter = ParameterElementImpl(name, 0);
    parameter.parameterKind = ParameterKind.NAMED_REQUIRED;
    parameter.type = type;
    return parameter;
  }

  ParameterElement positionalParameter({String name, @required DartType type}) {
    var parameter = ParameterElementImpl(name ?? '', 0);
    parameter.parameterKind = ParameterKind.POSITIONAL;
    parameter.type = type;
    return parameter;
  }

  TypeParameterMember promoteTypeParameter(
    TypeParameterElement element,
    DartType bound,
  ) {
    assert(element is! TypeParameterMember);
    return TypeParameterMember(element, null, bound);
  }

  ParameterElement requiredParameter({String name, @required DartType type}) {
    var parameter = ParameterElementImpl(name ?? '', 0);
    parameter.parameterKind = ParameterKind.REQUIRED;
    parameter.type = type;
    return parameter;
  }

  TypeParameterElementImpl typeParameter(String name,
      {DartType bound, Variance variance}) {
    var element = TypeParameterElementImpl.synthetic(name);
    element.bound = bound;
    element.variance = variance;
    return element;
  }

  TypeParameterTypeImpl typeParameterType(
    TypeParameterElement element, {
    NullabilitySuffix nullabilitySuffix = NullabilitySuffix.star,
  }) {
    return TypeParameterTypeImpl(
      element,
      nullabilitySuffix: nullabilitySuffix,
    );
  }

  TypeParameterTypeImpl typeParameterTypeNone(TypeParameterElement element) {
    return element.instantiate(nullabilitySuffix: NullabilitySuffix.none);
  }

  TypeParameterTypeImpl typeParameterTypeQuestion(
      TypeParameterElement element) {
    return element.instantiate(nullabilitySuffix: NullabilitySuffix.question);
  }

  TypeParameterTypeImpl typeParameterTypeStar(TypeParameterElement element) {
    return element.instantiate(nullabilitySuffix: NullabilitySuffix.star);
  }
}
