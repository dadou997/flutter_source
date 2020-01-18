// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef SHELL_GPU_GPU_SURFACE_VULKAN_H_
#define SHELL_GPU_GPU_SURFACE_VULKAN_H_

#include <memory>

#include "flutter/fml/macros.h"
#include "flutter/fml/memory/weak_ptr.h"
#include "flutter/shell/common/surface.h"
#include "flutter/vulkan/vulkan_native_surface.h"
#include "flutter/vulkan/vulkan_window.h"

namespace flutter {

class GPUSurfaceVulkan : public Surface {
 public:
  GPUSurfaceVulkan(fml::RefPtr<vulkan::VulkanProcTable> proc_table,
                   std::unique_ptr<vulkan::VulkanNativeSurface> native_surface);

  ~GPUSurfaceVulkan() override;

  // |Surface|
  bool IsValid() override;

  // |Surface|
  std::unique_ptr<SurfaceFrame> AcquireFrame(const SkISize& size) override;

  // |Surface|
  SkMatrix GetRootTransformation() const override;

  // |Surface|
  GrContext* GetContext() override;

 private:
  vulkan::VulkanWindow window_;
  fml::WeakPtrFactory<GPUSurfaceVulkan> weak_factory_;

  FML_DISALLOW_COPY_AND_ASSIGN(GPUSurfaceVulkan);
};

}  // namespace flutter

#endif  // SHELL_GPU_GPU_SURFACE_VULKAN_H_
