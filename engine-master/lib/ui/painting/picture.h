// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_LIB_UI_PAINTING_PICTURE_H_
#define FLUTTER_LIB_UI_PAINTING_PICTURE_H_

#include "flutter/flow/skia_gpu_object.h"
#include "flutter/lib/ui/dart_wrapper.h"
#include "flutter/lib/ui/painting/image.h"
#include "third_party/skia/include/core/SkPicture.h"

namespace tonic {
class DartLibraryNatives;
}  // namespace tonic

namespace flutter {
class Canvas;

class Picture : public RefCountedDartWrappable<Picture> {
  DEFINE_WRAPPERTYPEINFO();
  FML_FRIEND_MAKE_REF_COUNTED(Picture);

 public:
  ~Picture() override;
  static fml::RefPtr<Picture> Create(flutter::SkiaGPUObject<SkPicture> picture);

  sk_sp<SkPicture> picture() const { return picture_.get(); }

  Dart_Handle toImage(uint32_t width,
                      uint32_t height,
                      Dart_Handle raw_image_callback);

  void dispose();

  size_t GetAllocationSize() override;

  static void RegisterNatives(tonic::DartLibraryNatives* natives);

  static Dart_Handle RasterizeToImage(sk_sp<SkPicture> picture,
                                      uint32_t width,
                                      uint32_t height,
                                      Dart_Handle raw_image_callback);

 private:
  explicit Picture(flutter::SkiaGPUObject<SkPicture> picture);

  flutter::SkiaGPUObject<SkPicture> picture_;
};

}  // namespace flutter

#endif  // FLUTTER_LIB_UI_PAINTING_PICTURE_H_
