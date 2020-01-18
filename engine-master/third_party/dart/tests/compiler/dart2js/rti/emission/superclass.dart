// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*class: B:checkedInstance,checks=[],indirectInstance,typeLiteral*/
class B {}

/*class: C:checks=[],instance*/
class C extends B {}

@pragma('dart2js:noInline')
test(o) => o is B;

main() {
  test(new C());
  test(null);
}
