// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_ENGINE_H_
#define FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_ENGINE_H_

#include <memory>
#include <unordered_map>

#include "flutter/fml/macros.h"
#include "flutter/shell/common/shell.h"
#include "flutter/shell/common/thread_host.h"
#include "flutter/shell/platform/embedder/embedder.h"
#include "flutter/shell/platform/embedder/embedder_engine.h"
#include "flutter/shell/platform/embedder/embedder_external_texture_gl.h"
#include "flutter/shell/platform/embedder/embedder_thread_host.h"

namespace flutter {

struct ShellArgs;

// The object that is returned to the embedder as an opaque pointer to the
// instance of the Flutter engine.
class EmbedderEngine {
 public:
  EmbedderEngine(std::unique_ptr<EmbedderThreadHost> thread_host,
                 TaskRunners task_runners,
                 Settings settings,
                 RunConfiguration run_configuration,
                 Shell::CreateCallback<PlatformView> on_create_platform_view,
                 Shell::CreateCallback<Rasterizer> on_create_rasterizer,
                 EmbedderExternalTextureGL::ExternalTextureCallback
                     external_texture_callback);

  ~EmbedderEngine();

  bool LaunchShell();

  bool CollectShell();

  const TaskRunners& GetTaskRunners() const;

  bool NotifyCreated();

  bool NotifyDestroyed();

  bool RunRootIsolate();

  bool IsValid() const;

  bool SetViewportMetrics(flutter::ViewportMetrics metrics);

  bool DispatchPointerDataPacket(
      std::unique_ptr<flutter::PointerDataPacket> packet);

  bool SendPlatformMessage(fml::RefPtr<flutter::PlatformMessage> message);

  bool RegisterTexture(int64_t texture);

  bool UnregisterTexture(int64_t texture);

  bool MarkTextureFrameAvailable(int64_t texture);

  bool SetSemanticsEnabled(bool enabled);

  bool SetAccessibilityFeatures(int32_t flags);

  bool DispatchSemanticsAction(int id,
                               flutter::SemanticsAction action,
                               std::vector<uint8_t> args);

  bool OnVsyncEvent(intptr_t baton,
                    fml::TimePoint frame_start_time,
                    fml::TimePoint frame_target_time);

  bool ReloadSystemFonts();

  bool PostRenderThreadTask(const fml::closure& task);

  bool RunTask(const FlutterTask* task);

  const Shell& GetShell() const;

 private:
  const std::unique_ptr<EmbedderThreadHost> thread_host_;
  TaskRunners task_runners_;
  RunConfiguration run_configuration_;
  std::unique_ptr<ShellArgs> shell_args_;
  std::unique_ptr<Shell> shell_;
  const EmbedderExternalTextureGL::ExternalTextureCallback
      external_texture_callback_;

  FML_DISALLOW_COPY_AND_ASSIGN(EmbedderEngine);
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_PLATFORM_EMBEDDER_EMBEDDER_ENGINE_H_
