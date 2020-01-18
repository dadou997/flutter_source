// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/testing/assertions_skia.h"

namespace flutter {
namespace testing {

std::ostream& operator<<(std::ostream& os, const SkClipOp& o) {
  switch (o) {
    case SkClipOp::kDifference:
      os << "ClipOpDifference";
      break;
    case SkClipOp::kIntersect:
      os << "ClipOpIntersect";
      break;
#ifdef SK_SUPPORT_DEPRECATED_CLIPOPS
    case SkClipOp::kUnion_deprecated:
      os << "ClipOpUnion_deprecated";
      break;
    case SkClipOp::kXOR_deprecated:
      os << "ClipOpXOR_deprecated";
      break;
    case SkClipOp::kReverseDifference_deprecated:
      os << "ClipOpReverseDifference_deprecated";
      break;
    case SkClipOp::kReplace_deprecated:
      os << "ClipOpReplace_deprectaed";
      break;
#else
    case SkClipOp::kExtraEnumNeedInternallyPleaseIgnoreWillGoAway2:
      os << "ClipOpReserved2";
      break;
    case SkClipOp::kExtraEnumNeedInternallyPleaseIgnoreWillGoAway3:
      os << "ClipOpReserved3";
      break;
    case SkClipOp::kExtraEnumNeedInternallyPleaseIgnoreWillGoAway4:
      os << "ClipOpReserved4";
      break;
    case SkClipOp::kExtraEnumNeedInternallyPleaseIgnoreWillGoAway5:
      os << "ClipOpReserved5";
      break;
#endif
  }
  return os;
}

std::ostream& operator<<(std::ostream& os, const SkMatrix& m) {
  os << std::endl;
  os << "Scale X: " << m[SkMatrix::kMScaleX] << ", ";
  os << "Skew  X: " << m[SkMatrix::kMSkewX] << ", ";
  os << "Trans X: " << m[SkMatrix::kMTransX] << std::endl;
  os << "Skew  Y: " << m[SkMatrix::kMSkewY] << ", ";
  os << "Scale Y: " << m[SkMatrix::kMScaleY] << ", ";
  os << "Trans Y: " << m[SkMatrix::kMTransY] << std::endl;
  os << "Persp X: " << m[SkMatrix::kMPersp0] << ", ";
  os << "Persp Y: " << m[SkMatrix::kMPersp1] << ", ";
  os << "Persp Z: " << m[SkMatrix::kMPersp2];
  os << std::endl;
  return os;
}

std::ostream& operator<<(std::ostream& os, const SkMatrix44& m) {
  os << m.get(0, 0) << ", " << m.get(0, 1) << ", " << m.get(0, 2) << ", "
     << m.get(0, 3) << std::endl;
  os << m.get(1, 0) << ", " << m.get(1, 1) << ", " << m.get(1, 2) << ", "
     << m.get(1, 3) << std::endl;
  os << m.get(2, 0) << ", " << m.get(2, 1) << ", " << m.get(2, 2) << ", "
     << m.get(2, 3) << std::endl;
  os << m.get(3, 0) << ", " << m.get(3, 1) << ", " << m.get(3, 2) << ", "
     << m.get(3, 3);
  return os;
}

std::ostream& operator<<(std::ostream& os, const SkVector3& v) {
  return os << v.x() << ", " << v.y() << ", " << v.z();
}

std::ostream& operator<<(std::ostream& os, const SkVector4& v) {
  return os << v.fData[0] << ", " << v.fData[1] << ", " << v.fData[2] << ", "
            << v.fData[3];
}

std::ostream& operator<<(std::ostream& os, const SkRect& r) {
  return os << "LTRB: " << r.fLeft << ", " << r.fTop << ", " << r.fRight << ", "
            << r.fBottom;
}

std::ostream& operator<<(std::ostream& os, const SkRRect& r) {
  return os << "LTRB: " << r.rect().fLeft << ", " << r.rect().fTop << ", "
            << r.rect().fRight << ", " << r.rect().fBottom;
}

std::ostream& operator<<(std::ostream& os, const SkPath& r) {
  return os << "Valid: " << r.isValid()
            << ", FillType: " << static_cast<int>(r.getFillType())
            << ", Bounds: " << r.getBounds();
}

std::ostream& operator<<(std::ostream& os, const SkPoint& r) {
  return os << "XY: " << r.fX << ", " << r.fY;
}

std::ostream& operator<<(std::ostream& os, const SkISize& size) {
  return os << size.width() << ", " << size.height();
}

std::ostream& operator<<(std::ostream& os, const SkColor4f& r) {
  return os << r.fR << ", " << r.fG << ", " << r.fB << ", " << r.fA;
}

std::ostream& operator<<(std::ostream& os, const SkPaint& r) {
  return os << "Color: " << r.getColor4f() << ", Style: " << r.getStyle()
            << ", AA: " << r.isAntiAlias() << ", Shader: " << r.getShader();
}

}  // namespace testing
}  // namespace flutter
