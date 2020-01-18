// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_TESTING_ASSERTIONS_SKIA_H_
#define FLUTTER_TESTING_ASSERTIONS_SKIA_H_

#include <ostream>

#include "third_party/skia/include/core/SkClipOp.h"
#include "third_party/skia/include/core/SkMatrix.h"
#include "third_party/skia/include/core/SkMatrix44.h"
#include "third_party/skia/include/core/SkPaint.h"
#include "third_party/skia/include/core/SkPath.h"
#include "third_party/skia/include/core/SkPoint3.h"
#include "third_party/skia/include/core/SkRRect.h"

namespace flutter {
namespace testing {

extern std::ostream& operator<<(std::ostream& os, const SkClipOp& o);
extern std::ostream& operator<<(std::ostream& os, const SkMatrix& m);
extern std::ostream& operator<<(std::ostream& os, const SkMatrix44& m);
extern std::ostream& operator<<(std::ostream& os, const SkVector3& v);
extern std::ostream& operator<<(std::ostream& os, const SkVector4& v);
extern std::ostream& operator<<(std::ostream& os, const SkRect& r);
extern std::ostream& operator<<(std::ostream& os, const SkRRect& r);
extern std::ostream& operator<<(std::ostream& os, const SkPath& r);
extern std::ostream& operator<<(std::ostream& os, const SkPoint& r);
extern std::ostream& operator<<(std::ostream& os, const SkISize& size);
extern std::ostream& operator<<(std::ostream& os, const SkColor4f& r);
extern std::ostream& operator<<(std::ostream& os, const SkPaint& r);

}  // namespace testing
}  // namespace flutter

#endif  // FLUTTER_TESTING_ASSERTIONS_SKIA_H_
