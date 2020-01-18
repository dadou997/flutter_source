// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Requirements=nnbd-strong

import 'dart:async';

import 'runtime_utils.dart';
import 'runtime_utils_nnbd.dart';

class A {}

class B extends A {}

class C extends B {}

class D<T extends B> {}

class E<T, S> {}

class F extends E<B, B> {}

void main() {
  // Top type symmetry.
  // Object? <: dynamic
  checkSubtype(nullable(Object), dynamic);
  // dynamic <: Object?
  checkSubtype(dynamic, nullable(Object));
  // Object? <: void
  checkSubtype(nullable(Object), voidType);
  // void <: Object?
  checkSubtype(voidType, nullable(Object));
  // void <: dynamic
  checkSubtype(voidType, dynamic);
  // dynamic <: void
  checkSubtype(dynamic, voidType);

  // Bottom is subtype of top.
  // never <: dynamic
  checkProperSubtype(neverType, dynamic);
  // never <: void
  checkProperSubtype(neverType, voidType);
  // never <: Object?
  checkProperSubtype(neverType, nullable(Object));

  // Object is between top and bottom.
  // Object <: Object?
  checkProperSubtype(Object, nullable(Object));
  // never <: Object
  checkProperSubtype(neverType, Object);

  // Null is between top and bottom.
  // Null <: Object?
  checkProperSubtype(Null, nullable(Object));
  // never <: Null
  checkProperSubtype(neverType, Null);

  // Class is between Object and bottom.
  // A <: Object
  checkProperSubtype(A, dynamic);
  // never <: A
  checkProperSubtype(neverType, A);

  // Nullable types are a union of T and Null.
  // A <: A?
  checkProperSubtype(A, nullable(A));
  // Null <: A?
  checkProperSubtype(Null, nullable(A));
  // A? <: Object?
  checkProperSubtype(nullable(A), nullable(Object));

  // Legacy types will eventually be migrated to T or T? but until then are
  // symmetric with both.
  // Object* <: Object
  checkSubtype(legacy(Object), Object);
  // Object <: Object*
  checkSubtype(Object, legacy(Object));
  // Object* <: Object?
  checkSubtype(legacy(Object), nullable(Object));
  // Object? <: Object*
  checkSubtype(nullable(Object), legacy(Object));
  // Null <: Object*
  checkSubtype(Null, legacy(Object));
  // never <: Object*
  checkSubtype(neverType, legacy(Object));
  // A* <: A
  checkSubtype(legacy(A), A);
  // A <: A*
  checkSubtype(A, legacy(A));
  // A* <: A?
  checkSubtype(legacy(A), nullable(A));
  // A? <: A*
  checkSubtype(nullable(A), legacy(A));
  // A* <: Object
  checkProperSubtype(legacy(A), Object);
  // A* <: Object?
  checkProperSubtype(legacy(A), nullable(Object));
  // Null <: A*
  checkProperSubtype(Null, legacy(A));
  // never <: A*
  checkProperSubtype(neverType, legacy(A));

  // Futures.
  // Null <: FutureOr<Object?>
  checkProperSubtype(Null, generic1(FutureOr, nullable(Object)));
  // Object <: FutureOr<Object?>
  checkProperSubtype(Object, generic1(FutureOr, nullable(Object)));
  // Object? <: FutureOr<Object?>
  checkSubtype(nullable(Object), generic1(FutureOr, nullable(Object)));
  // Object <: FutureOr<Object>
  checkSubtype(Object, generic1(FutureOr, Object));
  // FutureOr<Object> <: Object
  checkSubtype(generic1(FutureOr, Object), Object);
  // Object <: FutureOr<dynamic>
  checkProperSubtype(Object, generic1(FutureOr, dynamic));
  // Object <: FutureOr<void>
  checkProperSubtype(Object, generic1(FutureOr, voidType));
  // Future<Object> <: FutureOr<Object?>
  checkProperSubtype(
      generic1(Future, Object), generic1(FutureOr, nullable(Object)));
  // Future<Object?> <: FutureOr<Object?>
  checkProperSubtype(
      generic1(Future, nullable(Object)), generic1(FutureOr, nullable(Object)));
  // FutureOr<Never> <: Future<Never>
  checkSubtype(generic1(FutureOr, neverType), generic1(Future, neverType));
  // Future<B> <: FutureOr<A>
  checkProperSubtype(generic1(Future, B), generic1(FutureOr, A));
  // B <: <: FutureOr<A>
  checkProperSubtype(B, generic1(FutureOr, A));
  // Future<B> <: Future<A>
  checkProperSubtype(generic1(Future, B), generic1(Future, A));

  // Interface subtypes.
  // A <: A
  checkSubtype(A, A);
  // B <: A
  checkProperSubtype(B, A);
  // C <: B
  checkProperSubtype(C, B);
  // C <: A
  checkProperSubtype(C, A);

  // Functions.
  // A -> B <: Function
  checkProperSubtype(function1(B, A), Function);

  // A -> B <: A -> B
  checkSubtype(function1(B, A), function1(B, A));

  // A -> B <: B -> B
  checkProperSubtype(function1(B, A), function1(B, B));
  // TODO(nshahan) Subtype check with covariant keyword?

  // A -> B <: A -> A
  checkSubtype(function1(B, A), function1(A, A));

  // Generic Function Subtypes.
  // Bound is a built in type.
  // <T extends int> void -> void <: <T extends int> void -> void
  checkSubtype(genericFunction(int), genericFunction(int));

  // <T extends String> A -> T <: <T extends String> B -> T
  checkProperSubtype(
      functionGenericReturn(String, A), functionGenericReturn(String, B));

  // <T extends double> T -> B <: <T extends double> T -> A
  checkProperSubtype(
      functionGenericArg(double, B), functionGenericArg(double, A));

  // Bound is a function type.
  // <T extends A -> B> void -> void <: <T extends A -> B> void -> void
  checkSubtype(
      genericFunction(function1(B, A)), genericFunction(function1(B, A)));

  // <T extends A -> B> A -> T <: <T extends A -> B> B -> T
  checkProperSubtype(functionGenericReturn(function1(B, A), A),
      functionGenericReturn(function1(B, A), B));

  // <T extends A -> B> T -> B <: <T extends A -> B> T -> A
  checkProperSubtype(functionGenericArg(function1(B, A), B),
      functionGenericArg(function1(B, A), A));

  // Bound is a user defined class.
  // <T extends B> void -> void <: <T extends B> void -> void
  checkSubtype(genericFunction(B), genericFunction(B));

  // <T extends B> A -> T <: <T extends B> B -> T
  checkProperSubtype(functionGenericReturn(B, A), functionGenericReturn(B, B));

  // <T extends B> T -> B <: <T extends B> T -> A
  checkProperSubtype(functionGenericArg(B, B), functionGenericArg(B, A));

  // Bound is a Future.
  // <T extends Future<B>> void -> void <: <T extends Future<B>> void -> void
  checkSubtype(genericFunction(generic1(Future, B)),
      genericFunction(generic1(Future, B)));

  // <T extends Future<B>> A -> T <: <T extends Future<B>> B -> T
  checkProperSubtype(functionGenericReturn(generic1(Future, B), A),
      functionGenericReturn(generic1(Future, B), B));

  // <T extends Future<B>> T -> B <: <T extends Future<B>> T -> A
  checkProperSubtype(functionGenericArg(generic1(Future, B), B),
      functionGenericArg(generic1(Future, B), A));

  // Bound is a FutureOr.
  // <T extends FutureOr<B>> void -> void <:
  //    <T extends FutureOr<B>> void -> void
  checkSubtype(genericFunction(generic1(FutureOr, B)),
      genericFunction(generic1(FutureOr, B)));

  // <T extends FutureOr<B>> A -> T <: <T extends FutureOr<B>> B -> T
  checkProperSubtype(functionGenericReturn(generic1(FutureOr, B), A),
      functionGenericReturn(generic1(FutureOr, B), B));

  // <T extends FutureOr<B>> T -> B <: <T extends FutureOr<B>> T -> A
  checkProperSubtype(functionGenericArg(generic1(FutureOr, B), B),
      functionGenericArg(generic1(FutureOr, B), A));

  // Generics.
  // D <: D<B>
  checkSubtype(D, generic1(D, B));
  // D<B> <: D
  checkSubtype(generic1(D, B), D);
  // D<C> <: D<B>
  checkProperSubtype(generic1(D, C), generic1(D, B));

  // F <: E
  checkProperSubtype(F, E);
  // F <: E<A, A>
  checkProperSubtype(F, generic2(E, A, A));
  // E<B, B> <: E<A, A>
  checkProperSubtype(generic2(E, B, B), E);
  // E<B, B> <: E<A, A>
  checkProperSubtype(generic2(E, B, B), generic2(E, A, A));

  // Nullable interface subtypes.
  // B <: A?
  checkProperSubtype(B, nullable(A));
  // C <: A?
  checkProperSubtype(C, nullable(A));
  // B? <: A?
  checkProperSubtype(nullable(B), nullable(A));
  // C? <: A?
  checkProperSubtype(nullable(C), nullable(A));

  // Mixed mode.
  // B* <: A
  checkProperSubtype(legacy(B), A);
  // B* <: A?
  checkProperSubtype(legacy(B), nullable(A));
  // A* <\: B
  checkSubtypeFailure(legacy(A), B);
  // B? <: A*
  checkProperSubtype(nullable(B), legacy(A));
  // B <: A*
  checkProperSubtype(B, legacy(A));
  // A <: B*
  checkSubtypeFailure(A, legacy(B));
  // A? <: B*
  checkSubtypeFailure(nullable(A), legacy(B));

  // Allowed in weak mode.
  // dynamic <\: Object
  checkSubtypeFailure(dynamic, Object);
  // void <\: Object
  checkSubtypeFailure(voidType, Object);
  // Object? <\: Object
  checkSubtypeFailure(nullable(Object), Object);
  // A? <\: Object
  checkSubtypeFailure(nullable(A), Object);
  // A? <\: A
  checkSubtypeFailure(nullable(A), A);
  // Null <\: never
  checkSubtypeFailure(Null, neverType);
  // Null <\: Object
  checkSubtypeFailure(Null, Object);
  // Null <\: A
  checkSubtypeFailure(Null, A);
  // Null <\: FutureOr<A>
  checkSubtypeFailure(Null, generic1(FutureOr, A));
  // Null <\: Future<A>
  checkSubtypeFailure(Null, generic1(Future, A));
  // FutureOr<Null> <\: Future<Null>
  checkSubtypeFailure(generic1(FutureOr, Null), generic1(Future, Null));
  // Null <\: Future<A?>
  checkSubtypeFailure(Null, generic1(Future, nullable(A)));
  // FutureOr<Object?> <\: Object
  checkSubtypeFailure(generic1(FutureOr, nullable(Object)), Object);
  // FutureOr<dynamic> <\: Object
  checkSubtypeFailure(generic1(FutureOr, dynamic), Object);
  // FutureOr<void> <\: Object
  checkSubtypeFailure(generic1(FutureOr, voidType), Object);
}
