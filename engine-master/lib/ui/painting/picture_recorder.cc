// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/lib/ui/painting/picture_recorder.h"

#include "flutter/lib/ui/painting/canvas.h"
#include "flutter/lib/ui/painting/picture.h"
#include "third_party/tonic/converter/dart_converter.h"
#include "third_party/tonic/dart_args.h"
#include "third_party/tonic/dart_binding_macros.h"
#include "third_party/tonic/dart_library_natives.h"

namespace flutter {

static void PictureRecorder_constructor(Dart_NativeArguments args) {
  DartCallConstructor(&PictureRecorder::Create, args);
}

IMPLEMENT_WRAPPERTYPEINFO(ui, PictureRecorder);

#define FOR_EACH_BINDING(V)       \
  V(PictureRecorder, isRecording) \
  V(PictureRecorder, endRecording)

FOR_EACH_BINDING(DART_NATIVE_CALLBACK)

void PictureRecorder::RegisterNatives(tonic::DartLibraryNatives* natives) {
  natives->Register(
      {{"PictureRecorder_constructor", PictureRecorder_constructor, 1, true},
       FOR_EACH_BINDING(DART_REGISTER_NATIVE)});
}

fml::RefPtr<PictureRecorder> PictureRecorder::Create() {
  return fml::MakeRefCounted<PictureRecorder>();
}

PictureRecorder::PictureRecorder() {}

PictureRecorder::~PictureRecorder() {}

bool PictureRecorder::isRecording() {
  return canvas_ && canvas_->IsRecording();
}

SkCanvas* PictureRecorder::BeginRecording(SkRect bounds) {
  return picture_recorder_.beginRecording(bounds, &rtree_factory_);
}

fml::RefPtr<Picture> PictureRecorder::endRecording() {
  if (!isRecording())
    return nullptr;

  fml::RefPtr<Picture> picture = Picture::Create(UIDartState::CreateGPUObject(
      picture_recorder_.finishRecordingAsPicture()));
  canvas_->Clear();
  canvas_->ClearDartWrapper();
  canvas_ = nullptr;
  ClearDartWrapper();
  return picture;
}

}  // namespace flutter
