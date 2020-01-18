// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_RUNTIME_RUNTIME_CONTROLLER_H_
#define FLUTTER_RUNTIME_RUNTIME_CONTROLLER_H_

#include <memory>
#include <vector>

#include "flutter/common/task_runners.h"
#include "flutter/flow/layers/layer_tree.h"
#include "flutter/fml/macros.h"
#include "flutter/lib/ui/io_manager.h"
#include "flutter/lib/ui/text/font_collection.h"
#include "flutter/lib/ui/ui_dart_state.h"
#include "flutter/lib/ui/window/pointer_data_packet.h"
#include "flutter/lib/ui/window/window.h"
#include "flutter/runtime/dart_vm.h"
#include "rapidjson/document.h"
#include "rapidjson/stringbuffer.h"

namespace flutter {
class Scene;
class RuntimeDelegate;
class View;
class Window;

class RuntimeController final : public WindowClient {
 public:
  RuntimeController(
      RuntimeDelegate& client,
      DartVM* vm,
      fml::RefPtr<const DartSnapshot> isolate_snapshot,
      TaskRunners task_runners,
      fml::WeakPtr<SnapshotDelegate> snapshot_delegate,
      fml::WeakPtr<IOManager> io_manager,
      fml::RefPtr<SkiaUnrefQueue> unref_queue,
      fml::WeakPtr<ImageDecoder> image_decoder,
      std::string advisory_script_uri,
      std::string advisory_script_entrypoint,
      const std::function<void(int64_t)>& idle_notification_callback,
      const fml::closure& isolate_create_callback,
      const fml::closure& isolate_shutdown_callback,
      std::shared_ptr<const fml::Mapping> persistent_isolate_data);

  ~RuntimeController() override;

  std::unique_ptr<RuntimeController> Clone() const;

  bool SetViewportMetrics(const ViewportMetrics& metrics);

  bool SetLocales(const std::vector<std::string>& locale_data);

  bool SetUserSettingsData(const std::string& data);

  bool SetLifecycleState(const std::string& data);

  bool SetSemanticsEnabled(bool enabled);

  bool SetAccessibilityFeatures(int32_t flags);

  bool BeginFrame(fml::TimePoint frame_time);

  bool ReportTimings(std::vector<int64_t> timings);

  bool NotifyIdle(int64_t deadline);

  bool IsRootIsolateRunning() const;

  bool DispatchPlatformMessage(fml::RefPtr<PlatformMessage> message);

  bool DispatchPointerDataPacket(const PointerDataPacket& packet);

  bool DispatchSemanticsAction(int32_t id,
                               SemanticsAction action,
                               std::vector<uint8_t> args);

  Dart_Port GetMainPort();

  std::string GetIsolateName();

  bool HasLivePorts();

  tonic::DartErrorHandleType GetLastError();

  std::weak_ptr<DartIsolate> GetRootIsolate();

  std::pair<bool, uint32_t> GetRootIsolateReturnCode();

 private:
  struct Locale {
    Locale(std::string language_code_,
           std::string country_code_,
           std::string script_code_,
           std::string variant_code_);

    ~Locale();

    std::string language_code;
    std::string country_code;
    std::string script_code;
    std::string variant_code;
  };

  // Stores data about the window to be used at startup
  // as well as on hot restarts. Data kept here will persist
  // after hot restart.
  struct WindowData {
    WindowData();

    WindowData(const WindowData& other);

    ~WindowData();

    ViewportMetrics viewport_metrics;
    std::string language_code;
    std::string country_code;
    std::string script_code;
    std::string variant_code;
    std::vector<std::string> locale_data;
    std::string user_settings_data = "{}";
    std::string lifecycle_state = "AppLifecycleState.detached";
    bool semantics_enabled = false;
    bool assistive_technology_enabled = false;
    int32_t accessibility_feature_flags_ = 0;
  };

  RuntimeDelegate& client_;
  DartVM* const vm_;
  fml::RefPtr<const DartSnapshot> isolate_snapshot_;
  TaskRunners task_runners_;
  fml::WeakPtr<SnapshotDelegate> snapshot_delegate_;
  fml::WeakPtr<IOManager> io_manager_;
  fml::RefPtr<SkiaUnrefQueue> unref_queue_;
  fml::WeakPtr<ImageDecoder> image_decoder_;
  std::string advisory_script_uri_;
  std::string advisory_script_entrypoint_;
  std::function<void(int64_t)> idle_notification_callback_;
  WindowData window_data_;
  std::weak_ptr<DartIsolate> root_isolate_;
  std::pair<bool, uint32_t> root_isolate_return_code_ = {false, 0};
  const fml::closure isolate_create_callback_;
  const fml::closure isolate_shutdown_callback_;
  std::shared_ptr<const fml::Mapping> persistent_isolate_data_;

  RuntimeController(
      RuntimeDelegate& client,
      DartVM* vm,
      fml::RefPtr<const DartSnapshot> isolate_snapshot,
      TaskRunners task_runners,
      fml::WeakPtr<SnapshotDelegate> snapshot_delegate,
      fml::WeakPtr<IOManager> io_manager,
      fml::RefPtr<SkiaUnrefQueue> unref_queue,
      fml::WeakPtr<ImageDecoder> image_decoder,
      std::string advisory_script_uri,
      std::string advisory_script_entrypoint,
      const std::function<void(int64_t)>& idle_notification_callback,
      WindowData data,
      const fml::closure& isolate_create_callback,
      const fml::closure& isolate_shutdown_callback,
      std::shared_ptr<const fml::Mapping> persistent_isolate_data);

  Window* GetWindowIfAvailable();

  bool FlushRuntimeStateToIsolate();

  // |WindowClient|
  std::string DefaultRouteName() override;

  // |WindowClient|
  void ScheduleFrame() override;

  // |WindowClient|
  void Render(Scene* scene) override;

  // |WindowClient|
  void UpdateSemantics(SemanticsUpdate* update) override;

  // |WindowClient|
  void HandlePlatformMessage(fml::RefPtr<PlatformMessage> message) override;

  // |WindowClient|
  FontCollection& GetFontCollection() override;

  // |WindowClient|
  void UpdateIsolateDescription(const std::string isolate_name,
                                int64_t isolate_port) override;

  // |WindowClient|
  void SetNeedsReportTimings(bool value) override;

  // |WindowClient|
  std::shared_ptr<const fml::Mapping> GetPersistentIsolateData() override;

  FML_DISALLOW_COPY_AND_ASSIGN(RuntimeController);
};

}  // namespace flutter

#endif  // FLUTTER_RUNTIME_RUNTIME_CONTROLLER_H_
