// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart test program for testing dart:ffi function pointers with callbacks.
//
// VMOptions=--enable-testing-pragmas
// VMOptions=--enable-testing-pragmas --stacktrace-every=100
// VMOptions=--enable-testing-pragmas --write-protect-code --no-dual-map-code
// VMOptions=--enable-testing-pragmas --write-protect-code --no-dual-map-code --stacktrace-every=100
// VMOptions=--use-slow-path --enable-testing-pragmas
// VMOptions=--use-slow-path --enable-testing-pragmas --stacktrace-every=100
// VMOptions=--use-slow-path --enable-testing-pragmas --write-protect-code --no-dual-map-code
// VMOptions=--use-slow-path --enable-testing-pragmas --write-protect-code --no-dual-map-code --stacktrace-every=100
// SharedObjects=ffi_test_functions

import 'dart:ffi';

import "package:expect/expect.dart";

import 'dylib_utils.dart';

typedef NativeCallbackTest = Int32 Function(Pointer);
typedef NativeCallbackTestFn = int Function(Pointer);

final DynamicLibrary testLibrary = dlopenPlatformSpecific("ffi_test_functions");

class Test {
  final String name;
  final Pointer callback;
  final bool skip;

  Test(this.name, this.callback, {bool skipIf: false}) : skip = skipIf {}

  void run() {
    if (skip) return;

    final NativeCallbackTestFn tester = testLibrary
        .lookupFunction<NativeCallbackTest, NativeCallbackTestFn>("Test$name");
    final int testCode = tester(callback);
    if (testCode != 0) {
      Expect.fail("Test $name failed.");
    }
  }
}

typedef SimpleAdditionType = Int32 Function(Int32, Int32);
int simpleAddition(int x, int y) => x + y;

typedef IntComputationType = Int64 Function(Int8, Int16, Int32, Int64);
int intComputation(int a, int b, int c, int d) => d - c + b - a;

typedef UintComputationType = Uint64 Function(Uint8, Uint16, Uint32, Uint64);
int uintComputation(int a, int b, int c, int d) => d - c + b - a;

typedef SimpleMultiplyType = Double Function(Double);
double simpleMultiply(double x) => x * 1.337;

typedef SimpleMultiplyFloatType = Float Function(Float);
double simpleMultiplyFloat(double x) => x * 1.337;

typedef ManyIntsType = IntPtr Function(IntPtr, IntPtr, IntPtr, IntPtr, IntPtr,
    IntPtr, IntPtr, IntPtr, IntPtr, IntPtr);
int manyInts(
    int a, int b, int c, int d, int e, int f, int g, int h, int i, int j) {
  return a + b + c + d + e + f + g + h + i + j;
}

typedef ManyDoublesType = Double Function(Double, Double, Double, Double,
    Double, Double, Double, Double, Double, Double);
double manyDoubles(double a, double b, double c, double d, double e, double f,
    double g, double h, double i, double j) {
  return a + b + c + d + e + f + g + h + i + j;
}

typedef ManyArgsType = Double Function(
    IntPtr,
    Float,
    IntPtr,
    Double,
    IntPtr,
    Float,
    IntPtr,
    Double,
    IntPtr,
    Float,
    IntPtr,
    Double,
    IntPtr,
    Float,
    IntPtr,
    Double,
    IntPtr,
    Float,
    IntPtr,
    Double);
double manyArgs(
    int _1,
    double _2,
    int _3,
    double _4,
    int _5,
    double _6,
    int _7,
    double _8,
    int _9,
    double _10,
    int _11,
    double _12,
    int _13,
    double _14,
    int _15,
    double _16,
    int _17,
    double _18,
    int _19,
    double _20) {
  return _1 +
      _2 +
      _3 +
      _4 +
      _5 +
      _6 +
      _7 +
      _8 +
      _9 +
      _10 +
      _11 +
      _12 +
      _13 +
      _14 +
      _15 +
      _16 +
      _17 +
      _18 +
      _19 +
      _20;
}

typedef StoreType = Pointer<Int64> Function(Pointer<Int64>);
Pointer<Int64> store(Pointer<Int64> ptr) => ptr.elementAt(1)..value = 1337;

typedef NullPointersType = Pointer<Int64> Function(Pointer<Int64>);
Pointer<Int64> nullPointers(Pointer<Int64> ptr) => ptr.elementAt(1);

typedef ReturnNullType = Int32 Function();
int returnNull() {
  return null;
}

typedef ReturnVoid = Void Function();
void returnVoid() {}

void throwException() {
  throw "Exception.";
}

typedef ThrowExceptionInt = IntPtr Function();
int throwExceptionInt() {
  throw "Exception.";
}

typedef ThrowExceptionDouble = Double Function();
double throwExceptionDouble() {
  throw "Exception.";
}

typedef ThrowExceptionPointer = Pointer<Void> Function();
Pointer<Void> throwExceptionPointer() {
  throw "Exception.";
}

final List<Test> testcases = [
  Test("SimpleAddition",
      Pointer.fromFunction<SimpleAdditionType>(simpleAddition, 0)),
  Test("IntComputation",
      Pointer.fromFunction<IntComputationType>(intComputation, 0)),
  Test("UintComputation",
      Pointer.fromFunction<UintComputationType>(uintComputation, 0)),
  Test("SimpleMultiply",
      Pointer.fromFunction<SimpleMultiplyType>(simpleMultiply, 0.0)),
  Test("SimpleMultiplyFloat",
      Pointer.fromFunction<SimpleMultiplyFloatType>(simpleMultiplyFloat, 0.0)),
  Test("ManyInts", Pointer.fromFunction<ManyIntsType>(manyInts, 0)),
  Test("ManyDoubles", Pointer.fromFunction<ManyDoublesType>(manyDoubles, 0.0)),
  Test("ManyArgs", Pointer.fromFunction<ManyArgsType>(manyArgs, 0.0)),
  Test("Store", Pointer.fromFunction<StoreType>(store)),
  Test("NullPointers", Pointer.fromFunction<NullPointersType>(nullPointers)),
  Test("ReturnNull", Pointer.fromFunction<ReturnNullType>(returnNull, 42)),
  Test("ReturnVoid", Pointer.fromFunction<ReturnVoid>(returnVoid)),
  Test("ThrowExceptionDouble",
      Pointer.fromFunction<ThrowExceptionDouble>(throwExceptionDouble, 42.0)),
  Test("ThrowExceptionPointer",
      Pointer.fromFunction<ThrowExceptionPointer>(throwExceptionPointer)),
  Test("ThrowException",
      Pointer.fromFunction<ThrowExceptionInt>(throwExceptionInt, 42)),
];

void main() {
  testcases.forEach((t) => t.run());
}
