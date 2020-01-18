// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/flow/scene_update_context.h"

#include "flutter/flow/layers/layer.h"
#include "flutter/flow/matrix_decomposition.h"
#include "flutter/fml/trace_event.h"
#include "include/core/SkColor.h"

namespace flutter {

// Helper function to generate clip planes for a scenic::EntityNode.
static void SetEntityNodeClipPlanes(scenic::EntityNode& entity_node,
                                    const SkRect& bounds) {
  const float top = bounds.top();
  const float bottom = bounds.bottom();
  const float left = bounds.left();
  const float right = bounds.right();

  // We will generate 4 oriented planes, one for each edge of the bounding rect.
  std::vector<fuchsia::ui::gfx::Plane3> clip_planes;
  clip_planes.resize(4);

  // Top plane.
  clip_planes[0].dist = top;
  clip_planes[0].dir.x = 0.f;
  clip_planes[0].dir.y = 1.f;
  clip_planes[0].dir.z = 0.f;

  // Bottom plane.
  clip_planes[1].dist = -bottom;
  clip_planes[1].dir.x = 0.f;
  clip_planes[1].dir.y = -1.f;
  clip_planes[1].dir.z = 0.f;

  // Left plane.
  clip_planes[2].dist = left;
  clip_planes[2].dir.x = 1.f;
  clip_planes[2].dir.y = 0.f;
  clip_planes[2].dir.z = 0.f;

  // Right plane.
  clip_planes[3].dist = -right;
  clip_planes[3].dir.x = -1.f;
  clip_planes[3].dir.y = 0.f;
  clip_planes[3].dir.z = 0.f;

  entity_node.SetClipPlanes(std::move(clip_planes));
}

SceneUpdateContext::SceneUpdateContext(scenic::Session* session,
                                       SurfaceProducer* surface_producer)
    : session_(session), surface_producer_(surface_producer) {
  FML_DCHECK(surface_producer_ != nullptr);
}

void SceneUpdateContext::CreateFrame(scenic::EntityNode entity_node,
                                     scenic::ShapeNode shape_node,
                                     const SkRRect& rrect,
                                     SkColor color,
                                     float opacity,
                                     const SkRect& paint_bounds,
                                     std::vector<Layer*> paint_layers,
                                     Layer* layer) {
  // We don't need a shape if the frame is zero size.
  if (rrect.isEmpty())
    return;

  SetEntityNodeClipPlanes(entity_node, rrect.getBounds());

  // isEmpty should account for this, but we are adding these experimental
  // checks to validate if this is the root cause for b/144933519.
  if (std::isnan(rrect.width()) || std::isnan(rrect.height())) {
    FML_LOG(ERROR) << "Invalid RoundedRectangle";
    return;
  }

  // Add a part which represents the frame's geometry for clipping purposes
  // and possibly for its texture.
  // TODO(SCN-137): Need to be able to express the radii as vectors.
  SkRect shape_bounds = rrect.getBounds();
  scenic::RoundedRectangle shape(
      session_,                                      // session
      rrect.width(),                                 // width
      rrect.height(),                                // height
      rrect.radii(SkRRect::kUpperLeft_Corner).x(),   // top_left_radius
      rrect.radii(SkRRect::kUpperRight_Corner).x(),  // top_right_radius
      rrect.radii(SkRRect::kLowerRight_Corner).x(),  // bottom_right_radius
      rrect.radii(SkRRect::kLowerLeft_Corner).x()    // bottom_left_radius
  );
  shape_node.SetShape(shape);
  shape_node.SetTranslation(shape_bounds.width() * 0.5f + shape_bounds.left(),
                            shape_bounds.height() * 0.5f + shape_bounds.top(),
                            0.f);

  // Check whether the painted layers will be visible.
  if (paint_bounds.isEmpty() || !paint_bounds.intersects(shape_bounds))
    paint_layers.clear();

  // Check whether a solid color will suffice.
  if (paint_layers.empty()) {
    scenic::Material material(session_);
    SetMaterialColor(material, color, opacity);
    shape_node.SetMaterial(material);
    return;
  }

  // Apply current metrics and transformation scale factors.
  const float scale_x = ScaleX();
  const float scale_y = ScaleY();

  scenic::Image* image = GenerateImageIfNeeded(
      color, scale_x, scale_y, shape_bounds, std::move(paint_layers), layer,
      std::move(entity_node));
  if (image != nullptr) {
    scenic::Material material(session_);

    // The final shape's color is material_color * texture_color.  The passed in
    // material color was already used as a background when generating the
    // texture, so set the model color to |SK_ColorWHITE| in order to allow
    // using the texture's color unmodified.
    SetMaterialColor(material, SK_ColorWHITE, opacity);
    material.SetTexture(*image);
    shape_node.SetMaterial(material);
    return;
  }

  // No texture was needed, so apply a solid color to the whole shape.
  if (SkColorGetA(color) != 0 && opacity != 0.0f) {
    scenic::Material material(session_);

    SetMaterialColor(material, color, opacity);
    shape_node.SetMaterial(material);
    return;
  }
}

void SceneUpdateContext::SetMaterialColor(scenic::Material& material,
                                          SkColor color,
                                          float opacity) {
  const SkAlpha color_alpha = (SkAlpha)(SkColorGetA(color) * opacity);
  material.SetColor(SkColorGetR(color), SkColorGetG(color), SkColorGetB(color),
                    color_alpha);
}

scenic::Image* SceneUpdateContext::GenerateImageIfNeeded(
    SkColor color,
    SkScalar scale_x,
    SkScalar scale_y,
    const SkRect& paint_bounds,
    std::vector<Layer*> paint_layers,
    Layer* layer,
    scenic::EntityNode entity_node) {
  // Bail if there's nothing to paint.
  if (paint_layers.empty())
    return nullptr;

  // Bail if the physical bounds are empty after rounding.
  SkISize physical_size = SkISize::Make(paint_bounds.width() * scale_x,
                                        paint_bounds.height() * scale_y);
  if (physical_size.isEmpty())
    return nullptr;

  // Acquire a surface from the surface producer and register the paint tasks.
  std::unique_ptr<SurfaceProducerSurface> surface =
      surface_producer_->ProduceSurface(
          physical_size,
          LayerRasterCacheKey(
              // Root frame has a nullptr layer
              layer ? layer->unique_id() : 0, Matrix()),
          std::make_unique<scenic::EntityNode>(std::move(entity_node)));

  if (!surface) {
    FML_LOG(ERROR) << "Could not acquire a surface from the surface producer "
                      "of size: "
                   << physical_size.width() << "x" << physical_size.height();
    return nullptr;
  }

  auto image = surface->GetImage();

  // Enqueue the paint task.
  paint_tasks_.push_back({.surface = std::move(surface),
                          .left = paint_bounds.left(),
                          .top = paint_bounds.top(),
                          .scale_x = scale_x,
                          .scale_y = scale_y,
                          .background_color = color,
                          .layers = std::move(paint_layers)});
  return image;
}

std::vector<
    std::unique_ptr<flutter::SceneUpdateContext::SurfaceProducerSurface>>
SceneUpdateContext::ExecutePaintTasks(CompositorContext::ScopedFrame& frame) {
  TRACE_EVENT0("flutter", "SceneUpdateContext::ExecutePaintTasks");
  std::vector<std::unique_ptr<SurfaceProducerSurface>> surfaces_to_submit;
  for (auto& task : paint_tasks_) {
    FML_DCHECK(task.surface);
    SkCanvas* canvas = task.surface->GetSkiaSurface()->getCanvas();
    Layer::PaintContext context = {canvas,
                                   canvas,
                                   frame.gr_context(),
                                   nullptr,
                                   frame.context().raster_time(),
                                   frame.context().ui_time(),
                                   frame.context().texture_registry(),
                                   &frame.context().raster_cache(),
                                   false,
                                   frame_physical_depth_,
                                   frame_device_pixel_ratio_};
    canvas->restoreToCount(1);
    canvas->save();
    canvas->clear(task.background_color);
    canvas->scale(task.scale_x, task.scale_y);
    canvas->translate(-task.left, -task.top);
    for (Layer* layer : task.layers) {
      layer->Paint(context);
    }
    surfaces_to_submit.emplace_back(std::move(task.surface));
  }
  paint_tasks_.clear();
  return surfaces_to_submit;
}

SceneUpdateContext::Entity::Entity(SceneUpdateContext& context)
    : context_(context),
      previous_entity_(context.top_entity_),
      entity_node_(context.session()) {
  if (previous_entity_)
    previous_entity_->embedder_node().AddChild(entity_node_);

  context.top_entity_ = this;
}

SceneUpdateContext::Entity::~Entity() {
  FML_DCHECK(context_.top_entity_ == this);
  context_.top_entity_ = previous_entity_;
}

SceneUpdateContext::Transform::Transform(SceneUpdateContext& context,
                                         const SkMatrix& transform)
    : Entity(context),
      previous_scale_x_(context.top_scale_x_),
      previous_scale_y_(context.top_scale_y_) {
  if (!transform.isIdentity()) {
    // TODO(SCN-192): The perspective and shear components in the matrix
    // are not handled correctly.
    MatrixDecomposition decomposition(transform);
    if (decomposition.IsValid()) {
      entity_node().SetTranslation(decomposition.translation().x(),  //
                                   decomposition.translation().y(),  //
                                   -decomposition.translation().z()  //
      );

      entity_node().SetScale(decomposition.scale().x(),  //
                             decomposition.scale().y(),  //
                             decomposition.scale().z()   //
      );
      context.top_scale_x_ *= decomposition.scale().x();
      context.top_scale_y_ *= decomposition.scale().y();

      entity_node().SetRotation(decomposition.rotation().fData[0],  //
                                decomposition.rotation().fData[1],  //
                                decomposition.rotation().fData[2],  //
                                decomposition.rotation().fData[3]   //
      );
    }
  }
}

SceneUpdateContext::Transform::Transform(SceneUpdateContext& context,
                                         float scale_x,
                                         float scale_y,
                                         float scale_z)
    : Entity(context),
      previous_scale_x_(context.top_scale_x_),
      previous_scale_y_(context.top_scale_y_) {
  if (scale_x != 1.f || scale_y != 1.f || scale_z != 1.f) {
    entity_node().SetScale(scale_x, scale_y, scale_z);
    context.top_scale_x_ *= scale_x;
    context.top_scale_y_ *= scale_y;
  }
}

SceneUpdateContext::Transform::~Transform() {
  context().top_scale_x_ = previous_scale_x_;
  context().top_scale_y_ = previous_scale_y_;
}

SceneUpdateContext::Clip::Clip(SceneUpdateContext& context,
                               const SkRect& shape_bounds)
    : Entity(context) {
  SetEntityNodeClipPlanes(entity_node(), shape_bounds);
}

SceneUpdateContext::Frame::Frame(SceneUpdateContext& context,
                                 const SkRRect& rrect,
                                 SkColor color,
                                 float opacity,
                                 float elevation,
                                 Layer* layer)
    : Entity(context),
      opacity_node_(context.session()),
      shape_node_(context.session()),
      layer_(layer),
      rrect_(rrect),
      paint_bounds_(SkRect::MakeEmpty()),
      color_(color),
      opacity_(opacity) {
  entity_node().SetTranslation(0.f, 0.f, -elevation);

  entity_node().AddChild(shape_node_);
  entity_node().AddChild(opacity_node_);
  opacity_node_.SetOpacity(opacity_);
}

SceneUpdateContext::Frame::~Frame() {
  context().CreateFrame(std::move(entity_node()), std::move(shape_node_),
                        rrect_, color_, opacity_, paint_bounds_,
                        std::move(paint_layers_), layer_);
}

void SceneUpdateContext::Frame::AddPaintLayer(Layer* layer) {
  FML_DCHECK(layer->needs_painting());
  paint_layers_.push_back(layer);
  paint_bounds_.join(layer->paint_bounds());
}

}  // namespace flutter
