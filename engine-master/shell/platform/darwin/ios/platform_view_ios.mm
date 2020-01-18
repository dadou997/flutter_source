// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/shell/platform/darwin/ios/platform_view_ios.h"

#import <QuartzCore/CAEAGLLayer.h>

#include <utility>

#include "flutter/common/task_runners.h"
#include "flutter/fml/synchronization/waitable_event.h"
#include "flutter/fml/trace_event.h"
#include "flutter/shell/common/shell_io_manager.h"
#include "flutter/shell/gpu/gpu_surface_gl_delegate.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/FlutterViewController_Internal.h"
#include "flutter/shell/platform/darwin/ios/framework/Source/vsync_waiter_ios.h"
#include "flutter/shell/platform/darwin/ios/ios_external_texture_gl.h"

namespace flutter {

PlatformViewIOS::PlatformViewIOS(PlatformView::Delegate& delegate,
                                 flutter::TaskRunners task_runners)
    : PlatformView(delegate, std::move(task_runners)) {
#if !TARGET_IPHONE_SIMULATOR
  gl_context_ = std::make_shared<IOSGLContext>();
#endif  // !TARGET_IPHONE_SIMULATOR
}

PlatformViewIOS::~PlatformViewIOS() = default;

PlatformMessageRouter& PlatformViewIOS::GetPlatformMessageRouter() {
  return platform_message_router_;
}

// |PlatformView|
void PlatformViewIOS::HandlePlatformMessage(fml::RefPtr<flutter::PlatformMessage> message) {
  platform_message_router_.HandlePlatformMessage(std::move(message));
}

fml::WeakPtr<FlutterViewController> PlatformViewIOS::GetOwnerViewController() const {
  return owner_controller_;
}

void PlatformViewIOS::SetOwnerViewController(fml::WeakPtr<FlutterViewController> owner_controller) {
  FML_DCHECK(task_runners_.GetPlatformTaskRunner()->RunsTasksOnCurrentThread());
  std::lock_guard<std::mutex> guard(ios_surface_mutex_);
  if (ios_surface_ || !owner_controller) {
    NotifyDestroyed();
    ios_surface_.reset();
    accessibility_bridge_.reset();
  }
  owner_controller_ = owner_controller;

  // Add an observer that will clear out the owner_controller_ ivar and
  // the accessibility_bridge_ in case the view controller is deleted.
  dealloc_view_controller_observer_.reset(
      [[[NSNotificationCenter defaultCenter] addObserverForName:FlutterViewControllerWillDealloc
                                                         object:owner_controller_.get()
                                                          queue:[NSOperationQueue mainQueue]
                                                     usingBlock:^(NSNotification* note) {
                                                       // Implicit copy of 'this' is fine.
                                                       accessibility_bridge_.reset();
                                                       owner_controller_.reset();
                                                     }] retain]);

  if (owner_controller_) {
    ios_surface_ =
        [static_cast<FlutterView*>(owner_controller.get().view) createSurface:gl_context_];
    FML_DCHECK(ios_surface_ != nullptr);

    if (accessibility_bridge_) {
      accessibility_bridge_.reset(
          new AccessibilityBridge(static_cast<FlutterView*>(owner_controller_.get().view), this,
                                  [owner_controller.get() platformViewsController]));
    }
    // Do not call `NotifyCreated()` here - let FlutterViewController take care
    // of that when its Viewport is sized.  If `NotifyCreated()` is called here,
    // it can occasionally get invoked before the viewport is sized resulting in
    // a framebuffer that will not be able to completely attach.
  }
}

PointerDataDispatcherMaker PlatformViewIOS::GetDispatcherMaker() {
  return [](DefaultPointerDataDispatcher::Delegate& delegate) {
    return std::make_unique<SmoothPointerDataDispatcher>(delegate);
  };
}

void PlatformViewIOS::RegisterExternalTexture(int64_t texture_id,
                                              NSObject<FlutterTexture>* texture) {
  RegisterTexture(std::make_shared<IOSExternalTextureGL>(texture_id, texture));
}

// |PlatformView|
std::unique_ptr<Surface> PlatformViewIOS::CreateRenderingSurface() {
  FML_DCHECK(task_runners_.GetGPUTaskRunner()->RunsTasksOnCurrentThread());
  std::lock_guard<std::mutex> guard(ios_surface_mutex_);
  if (!ios_surface_) {
    FML_DLOG(INFO) << "Could not CreateRenderingSurface, this PlatformViewIOS "
                      "has no ViewController.";
    return nullptr;
  }
  return ios_surface_->CreateGPUSurface();
}

// |PlatformView|
sk_sp<GrContext> PlatformViewIOS::CreateResourceContext() const {
  FML_DCHECK(task_runners_.GetIOTaskRunner()->RunsTasksOnCurrentThread());
  if (!gl_context_ || !gl_context_->ResourceMakeCurrent()) {
    FML_DLOG(INFO) << "Could not make resource context current on IO thread. "
                      "Async texture uploads will be disabled. On Simulators, "
                      "this is expected.";
    return nullptr;
  }

  return ShellIOManager::CreateCompatibleResourceLoadingContext(
      GrBackend::kOpenGL_GrBackend, GPUSurfaceGLDelegate::GetDefaultPlatformGLInterface());
}

// |PlatformView|
void PlatformViewIOS::SetSemanticsEnabled(bool enabled) {
  if (!owner_controller_) {
    FML_LOG(WARNING) << "Could not set semantics to enabled, this "
                        "PlatformViewIOS has no ViewController.";
    return;
  }
  if (enabled && !accessibility_bridge_) {
    accessibility_bridge_ = std::make_unique<AccessibilityBridge>(
        static_cast<FlutterView*>(owner_controller_.get().view), this,
        [owner_controller_.get() platformViewsController]);
  } else if (!enabled && accessibility_bridge_) {
    accessibility_bridge_.reset();
  }
  PlatformView::SetSemanticsEnabled(enabled);
}

// |shell:PlatformView|
void PlatformViewIOS::SetAccessibilityFeatures(int32_t flags) {
  PlatformView::SetAccessibilityFeatures(flags);
}

// |PlatformView|
void PlatformViewIOS::UpdateSemantics(flutter::SemanticsNodeUpdates update,
                                      flutter::CustomAccessibilityActionUpdates actions) {
  FML_DCHECK(owner_controller_);
  if (accessibility_bridge_) {
    accessibility_bridge_->UpdateSemantics(std::move(update), std::move(actions));
    [[NSNotificationCenter defaultCenter] postNotificationName:FlutterSemanticsUpdateNotification
                                                        object:owner_controller_.get()];
  }
}

// |PlatformView|
std::unique_ptr<VsyncWaiter> PlatformViewIOS::CreateVSyncWaiter() {
  return std::make_unique<VsyncWaiterIOS>(task_runners_);
}

void PlatformViewIOS::OnPreEngineRestart() const {
  if (accessibility_bridge_) {
    accessibility_bridge_->clearState();
  }
  if (!owner_controller_) {
    return;
  }
  [owner_controller_.get() platformViewsController] -> Reset();
}

fml::scoped_nsprotocol<FlutterTextInputPlugin*> PlatformViewIOS::GetTextInputPlugin() const {
  return text_input_plugin_;
}

void PlatformViewIOS::SetTextInputPlugin(fml::scoped_nsprotocol<FlutterTextInputPlugin*> plugin) {
  text_input_plugin_ = plugin;
}

PlatformViewIOS::ScopedObserver::ScopedObserver() : observer_(nil) {}

PlatformViewIOS::ScopedObserver::~ScopedObserver() {
  if (observer_) {
    [[NSNotificationCenter defaultCenter] removeObserver:observer_];
    [observer_ release];
  }
}

void PlatformViewIOS::ScopedObserver::reset(id<NSObject> observer) {
  if (observer != observer_) {
    if (observer_) {
      [[NSNotificationCenter defaultCenter] removeObserver:observer_];
      [observer_ release];
    }
    observer_ = observer;
  }
}

}  // namespace flutter
