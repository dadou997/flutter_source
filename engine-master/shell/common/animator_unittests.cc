// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#define FML_USED_ON_EMBEDDER

#include <functional>
#include <future>
#include <memory>

#include "flutter/shell/common/animator.h"
#include "flutter/shell/common/shell_test.h"
#include "flutter/testing/testing.h"
#include "gtest/gtest.h"

namespace flutter {
namespace testing {

TEST_F(ShellTest, VSyncTargetTime) {
  // Add native callbacks to listen for window.onBeginFrame
  int64_t target_time;
  fml::AutoResetWaitableEvent on_target_time_latch;
  auto nativeOnBeginFrame = [&on_target_time_latch,
                             &target_time](Dart_NativeArguments args) {
    Dart_Handle exception = nullptr;
    target_time =
        tonic::DartConverter<int64_t>::FromArguments(args, 0, exception);
    on_target_time_latch.Signal();
  };
  AddNativeCallback("NativeOnBeginFrame",
                    CREATE_NATIVE_ENTRY(nativeOnBeginFrame));

  // Create all te prerequisites for a shell.
  ASSERT_FALSE(DartVMRef::IsInstanceRunning());
  auto settings = CreateSettingsForFixture();

  std::unique_ptr<Shell> shell;

  TaskRunners task_runners = GetTaskRunnersForFixture();
  // this is not used as we are not using simulated events.
  const auto vsync_clock = std::make_shared<ShellTestVsyncClock>();
  CreateVsyncWaiter create_vsync_waiter = [&]() {
    return static_cast<std::unique_ptr<VsyncWaiter>>(
        std::make_unique<ConstantFiringVsyncWaiter>(task_runners));
  };

  // create a shell with a constant firing vsync waiter.
  fml::AutoResetWaitableEvent shell_creation;

  auto platform_task = std::async(std::launch::async, [&]() {
    shell = Shell::Create(
        task_runners, settings,
        [vsync_clock, &create_vsync_waiter](Shell& shell) {
          return std::make_unique<ShellTestPlatformView>(
              shell, shell.GetTaskRunners(), vsync_clock,
              std::move(create_vsync_waiter));
        },
        [](Shell& shell) {
          return std::make_unique<Rasterizer>(shell, shell.GetTaskRunners());
        });
    ASSERT_TRUE(DartVMRef::IsInstanceRunning());

    auto configuration = RunConfiguration::InferFromSettings(settings);
    ASSERT_TRUE(configuration.IsValid());
    configuration.SetEntrypoint("onBeginFrameMain");

    RunEngine(shell.get(), std::move(configuration));
    shell_creation.Signal();
  });

  shell_creation.Wait();

  // schedule a frame to trigger window.onBeginFrame
  fml::TaskRunner::RunNowOrPostTask(shell->GetTaskRunners().GetUITaskRunner(),
                                    [engine = shell->GetEngine()]() {
                                      if (engine) {
                                        // this implies we can re-use the last
                                        // frame to trigger begin frame rather
                                        // than re-generating the layer tree.
                                        engine->ScheduleFrame(true);
                                      }
                                    });

  on_target_time_latch.Wait();
  ASSERT_EQ(ConstantFiringVsyncWaiter::frame_target_time.ToEpochDelta()
                .ToMicroseconds(),
            target_time);

  // teardown.
  DestroyShell(std::move(shell), std::move(task_runners));
  ASSERT_FALSE(DartVMRef::IsInstanceRunning());
}

}  // namespace testing
}  // namespace flutter
