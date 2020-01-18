// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_TESTING_TEST_METAL_SURFACE_H_
#define FLUTTER_TESTING_TEST_METAL_SURFACE_H_

#include "flutter/fml/macros.h"
#include "third_party/skia/include/core/SkSize.h"
#include "third_party/skia/include/core/SkSurface.h"
#include "third_party/skia/include/gpu/GrContext.h"

namespace flutter {

//------------------------------------------------------------------------------
/// @brief      Creates a MTLTexture backed SkSurface and context that can be
///             used to render to in unit-tests.
///
class TestMetalSurface {
 public:
  static bool PlatformSupportsMetal();

  static std::unique_ptr<TestMetalSurface> Create(
      SkISize surface_size = SkISize::MakeEmpty());

  virtual ~TestMetalSurface();

  virtual bool IsValid() const;

  virtual sk_sp<GrContext> GetGrContext() const;

  virtual sk_sp<SkSurface> GetSurface() const;

 protected:
  TestMetalSurface();

 private:
  std::unique_ptr<TestMetalSurface> impl_;

  TestMetalSurface(std::unique_ptr<TestMetalSurface> impl);

  FML_DISALLOW_COPY_AND_ASSIGN(TestMetalSurface);
};

}  // namespace flutter

#endif  // FLUTTER_TESTING_TEST_METAL_SURFACE_H_
