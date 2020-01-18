// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
//
// Dart test program for testing the --enable-ffi=false flag.
//
// Note: In AoT and Android the flag is passed to Dart when executing the
// precompiled executable, so the error shows up as a runtime error rather than
// a compile time error.
//
// VMOptions=--enable-ffi=false

import 'dart:ffi'; //# 01: compile-time error, runtime error
import 'package:ffi/ffi.dart'; //# 01: compile-time error, runtime error

void main() {
  Pointer<Int8> p = //# 01: compile-time error, runtime error
      allocate(); //# 01: compile-time error, runtime error
  print(p.address); //# 01: compile-time error, runtime error
  free(p); //# 01: compile-time error, runtime error
}
