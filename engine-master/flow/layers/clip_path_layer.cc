// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/flow/layers/clip_path_layer.h"

#if defined(OS_FUCHSIA)

#include "lib/ui/scenic/cpp/commands.h"

#endif  // defined(OS_FUCHSIA)

namespace flutter {

ClipPathLayer::ClipPathLayer(const SkPath& clip_path, Clip clip_behavior)
    : clip_path_(clip_path), clip_behavior_(clip_behavior) {
  FML_DCHECK(clip_behavior != Clip::none);
}

void ClipPathLayer::Preroll(PrerollContext* context, const SkMatrix& matrix) {
  SkRect previous_cull_rect = context->cull_rect;
  SkRect clip_path_bounds = clip_path_.getBounds();
  children_inside_clip_ = context->cull_rect.intersect(clip_path_bounds);
  if (children_inside_clip_) {
    Layer::AutoPrerollSaveLayerState save =
        Layer::AutoPrerollSaveLayerState::Create(context, UsesSaveLayer());
    context->mutators_stack.PushClipPath(clip_path_);
    SkRect child_paint_bounds = SkRect::MakeEmpty();
    PrerollChildren(context, matrix, &child_paint_bounds);

    if (child_paint_bounds.intersect(clip_path_bounds)) {
      set_paint_bounds(child_paint_bounds);
    }
    context->mutators_stack.Pop();
  }
  context->cull_rect = previous_cull_rect;
}

#if defined(OS_FUCHSIA)

void ClipPathLayer::UpdateScene(SceneUpdateContext& context) {
  FML_DCHECK(needs_system_composite());

  // TODO(liyuqian): respect clip_behavior_
  SceneUpdateContext::Clip clip(context, clip_path_.getBounds());
  UpdateSceneChildren(context);
}

#endif  // defined(OS_FUCHSIA)

void ClipPathLayer::Paint(PaintContext& context) const {
  TRACE_EVENT0("flutter", "ClipPathLayer::Paint");
  FML_DCHECK(needs_painting());

  if (!children_inside_clip_)
    return;

  SkAutoCanvasRestore save(context.internal_nodes_canvas, true);
  context.internal_nodes_canvas->clipPath(clip_path_,
                                          clip_behavior_ != Clip::hardEdge);

  if (UsesSaveLayer()) {
    context.internal_nodes_canvas->saveLayer(paint_bounds(), nullptr);
  }
  PaintChildren(context);
  if (UsesSaveLayer()) {
    context.internal_nodes_canvas->restore();
  }
}

}  // namespace flutter
