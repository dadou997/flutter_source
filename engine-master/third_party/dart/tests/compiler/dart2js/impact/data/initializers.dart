// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/*member: main:
 static=[
  testDefaultValuesNamed(0),
  testDefaultValuesPositional(0),
  testFieldInitializer1(0),
  testFieldInitializer2(0),
  testFieldInitializer3(0),
  testGenericClass(0),
  testInstanceFieldTyped(0),
  testInstanceFieldWithInitializer(0),
  testSuperInitializer(0),
  testThisInitializer(0)]
*/
main() {
  testDefaultValuesPositional();
  testDefaultValuesNamed();
  testFieldInitializer1();
  testFieldInitializer2();
  testFieldInitializer3();
  testInstanceFieldWithInitializer();
  testInstanceFieldTyped();
  testThisInitializer();
  testSuperInitializer();
  testGenericClass();
}

/*strong.member: testDefaultValuesPositional:type=[inst:JSBool,param:bool]*/
testDefaultValuesPositional([bool value = false]) {}

/*strong.member: testDefaultValuesNamed:type=[inst:JSBool,param:bool]*/
testDefaultValuesNamed({bool value: false}) {}

class ClassFieldInitializer1 {
  /*member: ClassFieldInitializer1.field:type=[inst:JSNull]*/
  var field;

  /*member: ClassFieldInitializer1.:static=[Object.(0),init:ClassFieldInitializer1.field]*/
  ClassFieldInitializer1(this.field);
}

/*member: testFieldInitializer1:
 static=[ClassFieldInitializer1.(1)],
 type=[inst:JSDouble,inst:JSInt,inst:JSNumber,inst:JSPositiveInt,inst:JSUInt31,inst:JSUInt32]
*/
testFieldInitializer1() => new ClassFieldInitializer1(42);

class ClassFieldInitializer2 {
  /*member: ClassFieldInitializer2.field:type=[inst:JSNull]*/
  var field;

  /*member: ClassFieldInitializer2.:static=[Object.(0),init:ClassFieldInitializer2.field]*/
  ClassFieldInitializer2(value) : field = value;
}

/*member: testFieldInitializer2:
 static=[ClassFieldInitializer2.(1)],
 type=[inst:JSDouble,inst:JSInt,inst:JSNumber,inst:JSPositiveInt,inst:JSUInt31,inst:JSUInt32]
*/
testFieldInitializer2() => new ClassFieldInitializer2(42);

class ClassFieldInitializer3 {
  /*member: ClassFieldInitializer3.field:type=[inst:JSNull]*/
  var field;

  /*member: ClassFieldInitializer3.a:static=[Object.(0),init:ClassFieldInitializer3.field],type=[inst:JSNull]*/
  ClassFieldInitializer3.a();

  /*member: ClassFieldInitializer3.b:static=[Object.(0),init:ClassFieldInitializer3.field]*/
  ClassFieldInitializer3.b(value) : field = value;
}

/*member: testFieldInitializer3:
 static=[ClassFieldInitializer3.a(0),ClassFieldInitializer3.b(1)],
 type=[inst:JSDouble,inst:JSInt,inst:JSNumber,inst:JSPositiveInt,inst:JSUInt31,inst:JSUInt32]
*/
testFieldInitializer3() {
  new ClassFieldInitializer3.a();
  new ClassFieldInitializer3.b(42);
}

/*member: ClassInstanceFieldWithInitializer.:static=[Object.(0)]*/
class ClassInstanceFieldWithInitializer {
  /*member: ClassInstanceFieldWithInitializer.field:type=[inst:JSBool,param:bool]*/
  var field = false;
}

/*member: testInstanceFieldWithInitializer:static=[ClassInstanceFieldWithInitializer.(0)]*/
testInstanceFieldWithInitializer() => new ClassInstanceFieldWithInitializer();

/*member: ClassInstanceFieldTyped.:static=[Object.(0)]*/
class ClassInstanceFieldTyped {
  /*member: ClassInstanceFieldTyped.field:type=[inst:JSBool,inst:JSNull,param:int]*/
  int field;
}

/*member: testInstanceFieldTyped:static=[ClassInstanceFieldTyped.(0)]*/
testInstanceFieldTyped() => new ClassInstanceFieldTyped();

class ClassThisInitializer {
  /*member: ClassThisInitializer.:static=[ClassThisInitializer.internal(0)]*/
  ClassThisInitializer() : this.internal();

  /*member: ClassThisInitializer.internal:static=[Object.(0)]*/
  ClassThisInitializer.internal();
}

/*member: testThisInitializer:static=[ClassThisInitializer.(0)]*/
testThisInitializer() => new ClassThisInitializer();

class ClassSuperInitializer extends ClassThisInitializer {
  /*member: ClassSuperInitializer.:static=[ClassThisInitializer.internal(0)]*/
  ClassSuperInitializer() : super.internal();
}

/*member: testSuperInitializer:static=[ClassSuperInitializer.(0)]*/
testSuperInitializer() => new ClassSuperInitializer();

class ClassGeneric<T> {
  /*member: ClassGeneric.:
   static=[
    Object.(0),
    checkSubtype(4),
    checkSubtypeOfRuntimeType(2),
    getRuntimeTypeArgument(3),
    getRuntimeTypeArgumentIntercepted(4),
    getRuntimeTypeInfo(1),
    getTypeArgumentByIndex(2),
    setRuntimeTypeInfo(2)],
   type=[
    inst:JSArray<dynamic>,
    inst:JSBool,
    inst:JSExtendableArray<dynamic>,
    inst:JSFixedArray<dynamic>,
    inst:JSMutableArray<dynamic>,
    inst:JSUnmodifiableArray<dynamic>,
    param:ClassGeneric.T]
  */
  ClassGeneric(T arg);
}

/*member: testGenericClass:static=[ClassGeneric.(1),assertIsSubtype(5),throwTypeError(1)],type=[inst:JSDouble,inst:JSInt,inst:JSNumber,inst:JSPositiveInt,inst:JSUInt31,inst:JSUInt32]*/
testGenericClass() => new ClassGeneric<int>(0);
