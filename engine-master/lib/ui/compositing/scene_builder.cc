// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/lib/ui/compositing/scene_builder.h"

#include "flutter/flow/layers/backdrop_filter_layer.h"
#include "flutter/flow/layers/clip_path_layer.h"
#include "flutter/flow/layers/clip_rect_layer.h"
#include "flutter/flow/layers/clip_rrect_layer.h"
#include "flutter/flow/layers/color_filter_layer.h"
#include "flutter/flow/layers/container_layer.h"
#include "flutter/flow/layers/image_filter_layer.h"
#include "flutter/flow/layers/layer.h"
#include "flutter/flow/layers/layer_tree.h"
#include "flutter/flow/layers/opacity_layer.h"
#include "flutter/flow/layers/performance_overlay_layer.h"
#include "flutter/flow/layers/physical_shape_layer.h"
#include "flutter/flow/layers/picture_layer.h"
#include "flutter/flow/layers/platform_view_layer.h"
#include "flutter/flow/layers/shader_mask_layer.h"
#include "flutter/flow/layers/texture_layer.h"
#include "flutter/flow/layers/transform_layer.h"
#include "flutter/fml/build_config.h"
#include "flutter/lib/ui/painting/matrix.h"
#include "flutter/lib/ui/painting/shader.h"
#include "third_party/skia/include/core/SkColorFilter.h"
#include "third_party/tonic/converter/dart_converter.h"
#include "third_party/tonic/dart_args.h"
#include "third_party/tonic/dart_binding_macros.h"
#include "third_party/tonic/dart_library_natives.h"

#if defined(OS_FUCHSIA)
#include "flutter/flow/layers/child_scene_layer.h"
#endif

namespace flutter {

static void SceneBuilder_constructor(Dart_NativeArguments args) {
  DartCallConstructor(&SceneBuilder::create, args);
}

IMPLEMENT_WRAPPERTYPEINFO(ui, SceneBuilder);

#define FOR_EACH_BINDING(V)                         \
  V(SceneBuilder, pushOffset)                       \
  V(SceneBuilder, pushTransform)                    \
  V(SceneBuilder, pushClipRect)                     \
  V(SceneBuilder, pushClipRRect)                    \
  V(SceneBuilder, pushClipPath)                     \
  V(SceneBuilder, pushOpacity)                      \
  V(SceneBuilder, pushColorFilter)                  \
  V(SceneBuilder, pushImageFilter)                  \
  V(SceneBuilder, pushBackdropFilter)               \
  V(SceneBuilder, pushShaderMask)                   \
  V(SceneBuilder, pushPhysicalShape)                \
  V(SceneBuilder, pop)                              \
  V(SceneBuilder, addPlatformView)                  \
  V(SceneBuilder, addRetained)                      \
  V(SceneBuilder, addPicture)                       \
  V(SceneBuilder, addTexture)                       \
  V(SceneBuilder, addPerformanceOverlay)            \
  V(SceneBuilder, setRasterizerTracingThreshold)    \
  V(SceneBuilder, setCheckerboardOffscreenLayers)   \
  V(SceneBuilder, setCheckerboardRasterCacheImages) \
  V(SceneBuilder, build)

FOR_EACH_BINDING(DART_NATIVE_CALLBACK)
#if defined(OS_FUCHSIA)
DART_NATIVE_CALLBACK(SceneBuilder, addChildScene)
#endif

void SceneBuilder::RegisterNatives(tonic::DartLibraryNatives* natives) {
  natives->Register({
    {"SceneBuilder_constructor", SceneBuilder_constructor, 1, true},
        FOR_EACH_BINDING(DART_REGISTER_NATIVE)
#if defined(OS_FUCHSIA)
            DART_REGISTER_NATIVE(SceneBuilder, addChildScene)
#endif
  });
}

SceneBuilder::SceneBuilder() {
  // Add a ContainerLayer as the root layer, so that AddLayer operations are
  // always valid.
  PushLayer(std::make_shared<flutter::ContainerLayer>());
}

SceneBuilder::~SceneBuilder() = default;

fml::RefPtr<EngineLayer> SceneBuilder::pushTransform(
    tonic::Float64List& matrix4) {
  SkMatrix sk_matrix = ToSkMatrix(matrix4);
  auto layer = std::make_shared<flutter::TransformLayer>(sk_matrix);
  PushLayer(layer);
  // matrix4 has to be released before we can return another Dart object
  matrix4.Release();
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushOffset(double dx, double dy) {
  SkMatrix sk_matrix = SkMatrix::MakeTrans(dx, dy);
  auto layer = std::make_shared<flutter::TransformLayer>(sk_matrix);
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushClipRect(double left,
                                                    double right,
                                                    double top,
                                                    double bottom,
                                                    int clipBehavior) {
  SkRect clipRect = SkRect::MakeLTRB(left, top, right, bottom);
  flutter::Clip clip_behavior = static_cast<flutter::Clip>(clipBehavior);
  auto layer =
      std::make_shared<flutter::ClipRectLayer>(clipRect, clip_behavior);
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushClipRRect(const RRect& rrect,
                                                     int clipBehavior) {
  flutter::Clip clip_behavior = static_cast<flutter::Clip>(clipBehavior);
  auto layer =
      std::make_shared<flutter::ClipRRectLayer>(rrect.sk_rrect, clip_behavior);
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushClipPath(const CanvasPath* path,
                                                    int clipBehavior) {
  flutter::Clip clip_behavior = static_cast<flutter::Clip>(clipBehavior);
  FML_DCHECK(clip_behavior != flutter::Clip::none);
  auto layer =
      std::make_shared<flutter::ClipPathLayer>(path->path(), clip_behavior);
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushOpacity(int alpha,
                                                   double dx,
                                                   double dy) {
  auto layer =
      std::make_shared<flutter::OpacityLayer>(alpha, SkPoint::Make(dx, dy));
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushColorFilter(
    const ColorFilter* color_filter) {
  auto layer =
      std::make_shared<flutter::ColorFilterLayer>(color_filter->filter());
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushImageFilter(
    const ImageFilter* image_filter) {
  auto layer =
      std::make_shared<flutter::ImageFilterLayer>(image_filter->filter());
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushBackdropFilter(ImageFilter* filter) {
  auto layer = std::make_shared<flutter::BackdropFilterLayer>(filter->filter());
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushShaderMask(Shader* shader,
                                                      double maskRectLeft,
                                                      double maskRectRight,
                                                      double maskRectTop,
                                                      double maskRectBottom,
                                                      int blendMode) {
  SkRect rect = SkRect::MakeLTRB(maskRectLeft, maskRectTop, maskRectRight,
                                 maskRectBottom);
  auto layer = std::make_shared<flutter::ShaderMaskLayer>(
      shader->shader(), rect, static_cast<SkBlendMode>(blendMode));
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

fml::RefPtr<EngineLayer> SceneBuilder::pushPhysicalShape(const CanvasPath* path,
                                                         double elevation,
                                                         int color,
                                                         int shadow_color,
                                                         int clipBehavior) {
  auto layer = std::make_shared<flutter::PhysicalShapeLayer>(
      static_cast<SkColor>(color), static_cast<SkColor>(shadow_color),
      static_cast<float>(elevation), path->path(),
      static_cast<flutter::Clip>(clipBehavior));
  PushLayer(layer);
  return EngineLayer::MakeRetained(layer);
}

void SceneBuilder::addRetained(fml::RefPtr<EngineLayer> retainedLayer) {
  AddLayer(retainedLayer->Layer());
}

void SceneBuilder::pop() {
  PopLayer();
}

void SceneBuilder::addPicture(double dx,
                              double dy,
                              Picture* picture,
                              int hints) {
  SkPoint offset = SkPoint::Make(dx, dy);
  SkRect pictureRect = picture->picture()->cullRect();
  pictureRect.offset(offset.x(), offset.y());
  auto layer = std::make_unique<flutter::PictureLayer>(
      offset, UIDartState::CreateGPUObject(picture->picture()), !!(hints & 1),
      !!(hints & 2));
  AddLayer(std::move(layer));
}

void SceneBuilder::addTexture(double dx,
                              double dy,
                              double width,
                              double height,
                              int64_t textureId,
                              bool freeze) {
  auto layer = std::make_unique<flutter::TextureLayer>(
      SkPoint::Make(dx, dy), SkSize::Make(width, height), textureId, freeze);
  AddLayer(std::move(layer));
}

void SceneBuilder::addPlatformView(double dx,
                                   double dy,
                                   double width,
                                   double height,
                                   int64_t viewId) {
  auto layer = std::make_unique<flutter::PlatformViewLayer>(
      SkPoint::Make(dx, dy), SkSize::Make(width, height), viewId);
  AddLayer(std::move(layer));
}

#if defined(OS_FUCHSIA)
void SceneBuilder::addChildScene(double dx,
                                 double dy,
                                 double width,
                                 double height,
                                 SceneHost* sceneHost,
                                 bool hitTestable) {
  auto layer = std::make_unique<flutter::ChildSceneLayer>(
      sceneHost->id(), SkPoint::Make(dx, dy), SkSize::Make(width, height),
      hitTestable);
  AddLayer(std::move(layer));
}
#endif  // defined(OS_FUCHSIA)

void SceneBuilder::addPerformanceOverlay(uint64_t enabledOptions,
                                         double left,
                                         double right,
                                         double top,
                                         double bottom) {
  SkRect rect = SkRect::MakeLTRB(left, top, right, bottom);
  auto layer =
      std::make_unique<flutter::PerformanceOverlayLayer>(enabledOptions);
  layer->set_paint_bounds(rect);
  AddLayer(std::move(layer));
}

void SceneBuilder::setRasterizerTracingThreshold(uint32_t frameInterval) {
  rasterizer_tracing_threshold_ = frameInterval;
}

void SceneBuilder::setCheckerboardRasterCacheImages(bool checkerboard) {
  checkerboard_raster_cache_images_ = checkerboard;
}

void SceneBuilder::setCheckerboardOffscreenLayers(bool checkerboard) {
  checkerboard_offscreen_layers_ = checkerboard;
}

fml::RefPtr<Scene> SceneBuilder::build() {
  FML_DCHECK(layer_stack_.size() >= 1);

  fml::RefPtr<Scene> scene = Scene::create(
      layer_stack_[0], rasterizer_tracing_threshold_,
      checkerboard_raster_cache_images_, checkerboard_offscreen_layers_);
  ClearDartWrapper();  // may delete this object.
  return scene;
}

void SceneBuilder::AddLayer(std::shared_ptr<Layer> layer) {
  FML_DCHECK(layer);

  if (!layer_stack_.empty()) {
    layer_stack_.back()->Add(std::move(layer));
  }
}

void SceneBuilder::PushLayer(std::shared_ptr<ContainerLayer> layer) {
  AddLayer(layer);
  layer_stack_.push_back(std::move(layer));
}

void SceneBuilder::PopLayer() {
  // We never pop the root layer, so that AddLayer operations are always valid.
  if (layer_stack_.size() > 1) {
    layer_stack_.pop_back();
  }
}

}  // namespace flutter
