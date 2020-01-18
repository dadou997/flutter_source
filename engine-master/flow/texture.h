// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_FLOW_TEXTURE_H_
#define FLUTTER_FLOW_TEXTURE_H_

#include <map>

#include "flutter/fml/macros.h"
#include "flutter/fml/synchronization/waitable_event.h"
#include "third_party/skia/include/core/SkCanvas.h"

namespace flutter {

class Texture {
 public:
  Texture(int64_t id);  // Called from UI or GPU thread.
  virtual ~Texture();   // Called from GPU thread.

  // Called from GPU thread.
  virtual void Paint(SkCanvas& canvas,
                     const SkRect& bounds,
                     bool freeze,
                     GrContext* context) = 0;

  // Called from GPU thread.
  virtual void OnGrContextCreated() = 0;

  // Called from GPU thread.
  virtual void OnGrContextDestroyed() = 0;

  // Called on GPU thread.
  virtual void MarkNewFrameAvailable() = 0;

  // Called on GPU thread.
  virtual void OnTextureUnregistered() = 0;

  int64_t Id() { return id_; }

 private:
  int64_t id_;

  FML_DISALLOW_COPY_AND_ASSIGN(Texture);
};

class TextureRegistry {
 public:
  TextureRegistry();

  // Called from GPU thread.
  void RegisterTexture(std::shared_ptr<Texture> texture);

  // Called from GPU thread.
  void UnregisterTexture(int64_t id);

  // Called from GPU thread.
  std::shared_ptr<Texture> GetTexture(int64_t id);

  // Called from GPU thread.
  void OnGrContextCreated();

  // Called from GPU thread.
  void OnGrContextDestroyed();

 private:
  std::map<int64_t, std::shared_ptr<Texture>> mapping_;

  FML_DISALLOW_COPY_AND_ASSIGN(TextureRegistry);
};

}  // namespace flutter

#endif  // FLUTTER_FLOW_TEXTURE_H_
