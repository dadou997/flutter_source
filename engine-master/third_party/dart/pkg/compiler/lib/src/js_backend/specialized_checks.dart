// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../common_elements.dart' show ElementEnvironment, JCommonElements;
import '../deferred_load.dart';
import '../elements/entities.dart';
import '../elements/types.dart';
import '../js_backend/interceptor_data.dart' show InterceptorData;
import '../ssa/nodes.dart' show HGraph;
import '../universe/class_hierarchy.dart' show ClassHierarchy;
import '../world.dart' show JClosedWorld;

enum IsTestSpecialization {
  null_,
  string,
  bool,
  num,
  int,
  arrayTop,
  instanceof,
}

class SpecializedChecks {
  static IsTestSpecialization findIsTestSpecialization(
      DartType dartType, HGraph graph, JClosedWorld closedWorld) {
    if (dartType is InterfaceType) {
      ClassEntity element = dartType.element;
      JCommonElements commonElements = closedWorld.commonElements;

      if (element == commonElements.nullClass ||
          element == commonElements.jsNullClass) {
        return IsTestSpecialization.null_;
      }

      if (element == commonElements.jsStringClass ||
          element == commonElements.stringClass) {
        return IsTestSpecialization.string;
      }

      if (element == commonElements.jsBoolClass ||
          element == commonElements.boolClass) {
        return IsTestSpecialization.bool;
      }

      if (element == commonElements.jsDoubleClass ||
          element == commonElements.doubleClass ||
          element == commonElements.jsNumberClass ||
          element == commonElements.numClass) {
        return IsTestSpecialization.num;
      }

      if (element == commonElements.jsIntClass ||
          element == commonElements.intClass ||
          element == commonElements.jsUInt32Class ||
          element == commonElements.jsUInt31Class ||
          element == commonElements.jsPositiveIntClass) {
        return IsTestSpecialization.int;
      }

      DartTypes dartTypes = closedWorld.dartTypes;
      ElementEnvironment elementEnvironment = closedWorld.elementEnvironment;
      if (!dartTypes.isSubtype(
          elementEnvironment.getClassInstantiationToBounds(element),
          dartType)) {
        return null;
      }

      if (element == commonElements.jsArrayClass) {
        return IsTestSpecialization.arrayTop;
      }

      ClassHierarchy classHierarchy = closedWorld.classHierarchy;
      InterceptorData interceptorData = closedWorld.interceptorData;
      OutputUnitData outputUnitData = closedWorld.outputUnitData;

      if (classHierarchy.hasOnlySubclasses(element) &&
          !interceptorData.isInterceptedClass(element) &&
          outputUnitData.hasOnlyNonDeferredImportPathsToClass(
              graph.element, element)) {
        return IsTestSpecialization.instanceof;
      }
    }
    return null;
  }

  static MemberEntity findAsCheck(
      DartType dartType, bool isTypeError, JCommonElements commonElements) {
    if (dartType is InterfaceType) {
      if (dartType.typeArguments.isNotEmpty) return null;
      return _findAsCheck(dartType.element, commonElements,
          isTypeError: isTypeError, isNullable: true);
    }
    return null;
  }

  static MemberEntity _findAsCheck(
      ClassEntity element, JCommonElements commonElements,
      {bool isTypeError, bool isNullable}) {
    if (element == commonElements.jsStringClass ||
        element == commonElements.stringClass) {
      if (isNullable) {
        return isTypeError
            ? commonElements.specializedCheckStringNullable
            : commonElements.specializedAsStringNullable;
      }
      return null;
    }

    if (element == commonElements.jsBoolClass ||
        element == commonElements.boolClass) {
      if (isNullable) {
        return isTypeError
            ? commonElements.specializedCheckBoolNullable
            : commonElements.specializedAsBoolNullable;
      }
      return null;
    }

    if (element == commonElements.jsDoubleClass ||
        element == commonElements.doubleClass) {
      if (isNullable) {
        return isTypeError
            ? commonElements.specializedCheckDoubleNullable
            : commonElements.specializedAsDoubleNullable;
      }
      return null;
    }

    if (element == commonElements.jsNumberClass ||
        element == commonElements.numClass) {
      if (isNullable) {
        return isTypeError
            ? commonElements.specializedCheckNumNullable
            : commonElements.specializedAsNumNullable;
      }
      return null;
    }

    if (element == commonElements.jsIntClass ||
        element == commonElements.intClass ||
        element == commonElements.jsUInt32Class ||
        element == commonElements.jsUInt31Class ||
        element == commonElements.jsPositiveIntClass) {
      if (isNullable) {
        return isTypeError
            ? commonElements.specializedCheckIntNullable
            : commonElements.specializedAsIntNullable;
      }
      return null;
    }

    return null;
  }
}
