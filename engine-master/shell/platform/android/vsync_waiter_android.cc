// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/shell/platform/android/vsync_waiter_android.h"

#include <cmath>
#include <utility>

#include "flutter/common/task_runners.h"
#include "flutter/fml/logging.h"
#include "flutter/fml/platform/android/jni_util.h"
#include "flutter/fml/platform/android/scoped_java_ref.h"
#include "flutter/fml/size.h"
#include "flutter/fml/trace_event.h"

namespace flutter {

static fml::jni::ScopedJavaGlobalRef<jclass>* g_vsync_waiter_class = nullptr;
static jmethodID g_async_wait_for_vsync_method_ = nullptr;

VsyncWaiterAndroid::VsyncWaiterAndroid(flutter::TaskRunners task_runners)
    : VsyncWaiter(std::move(task_runners)) {}

VsyncWaiterAndroid::~VsyncWaiterAndroid() = default;

// |VsyncWaiter|
void VsyncWaiterAndroid::AwaitVSync() {
  auto* weak_this = new std::weak_ptr<VsyncWaiter>(shared_from_this());
  jlong java_baton = reinterpret_cast<jlong>(weak_this);

  task_runners_.GetPlatformTaskRunner()->PostTask([java_baton]() {
    JNIEnv* env = fml::jni::AttachCurrentThread();
    env->CallStaticVoidMethod(g_vsync_waiter_class->obj(),     //
                              g_async_wait_for_vsync_method_,  //
                              java_baton                       //
    );
  });
}

float VsyncWaiterAndroid::GetDisplayRefreshRate() const {
  JNIEnv* env = fml::jni::AttachCurrentThread();
  if (g_vsync_waiter_class == nullptr) {
    return kUnknownRefreshRateFPS;
  }
  jclass clazz = g_vsync_waiter_class->obj();
  if (clazz == nullptr) {
    return kUnknownRefreshRateFPS;
  }
  jfieldID fid = env->GetStaticFieldID(clazz, "refreshRateFPS", "F");
  return env->GetStaticFloatField(clazz, fid);
}

// static
void VsyncWaiterAndroid::OnNativeVsync(JNIEnv* env,
                                       jclass jcaller,
                                       jlong frameTimeNanos,
                                       jlong frameTargetTimeNanos,
                                       jlong java_baton) {
  auto frame_time = fml::TimePoint::FromEpochDelta(
      fml::TimeDelta::FromNanoseconds(frameTimeNanos));
  auto target_time = fml::TimePoint::FromEpochDelta(
      fml::TimeDelta::FromNanoseconds(frameTargetTimeNanos));

  ConsumePendingCallback(java_baton, frame_time, target_time);
}

// static
void VsyncWaiterAndroid::ConsumePendingCallback(
    jlong java_baton,
    fml::TimePoint frame_start_time,
    fml::TimePoint frame_target_time) {
  auto* weak_this = reinterpret_cast<std::weak_ptr<VsyncWaiter>*>(java_baton);
  auto shared_this = weak_this->lock();
  delete weak_this;

  if (shared_this) {
    shared_this->FireCallback(frame_start_time, frame_target_time);
  }
}

// static
bool VsyncWaiterAndroid::Register(JNIEnv* env) {
  static const JNINativeMethod methods[] = {{
      .name = "nativeOnVsync",
      .signature = "(JJJ)V",
      .fnPtr = reinterpret_cast<void*>(&OnNativeVsync),
  }};

  jclass clazz = env->FindClass("io/flutter/embedding/engine/FlutterJNI");

  if (clazz == nullptr) {
    return false;
  }

  g_vsync_waiter_class = new fml::jni::ScopedJavaGlobalRef<jclass>(env, clazz);

  FML_CHECK(!g_vsync_waiter_class->is_null());

  g_async_wait_for_vsync_method_ = env->GetStaticMethodID(
      g_vsync_waiter_class->obj(), "asyncWaitForVsync", "(J)V");

  FML_CHECK(g_async_wait_for_vsync_method_ != nullptr);

  return env->RegisterNatives(clazz, methods, fml::size(methods)) == 0;
}

}  // namespace flutter
