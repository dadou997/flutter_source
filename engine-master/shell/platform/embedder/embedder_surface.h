// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_SURFACE_H_
#define FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_SURFACE_H_

#include "flutter/flow/embedded_views.h"
#include "flutter/fml/macros.h"
#include "flutter/shell/common/surface.h"

namespace flutter {

class EmbedderSurface {
 public:
  EmbedderSurface();

  virtual ~EmbedderSurface();

  virtual bool IsValid() const = 0;

  virtual std::unique_ptr<Surface> CreateGPUSurface() = 0;

  virtual sk_sp<GrContext> CreateResourceContext() const = 0;

 private:
  FML_DISALLOW_COPY_AND_ASSIGN(EmbedderSurface);
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_SURFACE_H_
