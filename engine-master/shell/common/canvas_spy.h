
// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
//
#include "flutter/fml/macros.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkCanvasVirtualEnforcer.h"
#include "third_party/skia/include/utils/SkNWayCanvas.h"
#include "third_party/skia/include/utils/SkNoDrawCanvas.h"

#ifndef FLUTTER_SHELL_COMMON_CANVAS_SPY_H_
#define FLUTTER_SHELL_COMMON_CANVAS_SPY_H_

namespace flutter {

class DidDrawCanvas;

//------------------------------------------------------------------------------
/// Facilitates spying on drawing commands to an SkCanvas.
///
/// This is used to determine whether anything was drawn into
/// a canvas so it is possible to implement optimizations that
/// are specific to empty canvases.
class CanvasSpy {
 public:
  CanvasSpy(SkCanvas* target_canvas);

  //------------------------------------------------------------------------------
  /// @brief      Returns true if any non trasnparent content has been drawn
  /// into
  ///             the spying canvas. Note that this class does tries to detect
  ///             empty canvases but in some cases may return true even for
  ///             empty canvases (e.g when a transparent image is drawn into the
  ///             canvas).
  bool DidDrawIntoCanvas();

  //------------------------------------------------------------------------------
  /// @brief      The returned canvas delegate all operations to the target
  /// canvas
  ///             while spying on them.
  SkCanvas* GetSpyingCanvas();

 private:
  std::unique_ptr<SkNWayCanvas> n_way_canvas_;
  std::unique_ptr<DidDrawCanvas> did_draw_canvas_;

  FML_DISALLOW_COPY_AND_ASSIGN(CanvasSpy);
};

class DidDrawCanvas final : public SkCanvasVirtualEnforcer<SkNoDrawCanvas> {
 public:
  DidDrawCanvas(int width, int height);
  ~DidDrawCanvas() override;
  bool DidDrawIntoCanvas();

 private:
  bool did_draw_ = false;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void willSave() override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  SaveLayerStrategy getSaveLayerStrategy(const SaveLayerRec&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  bool onDoSaveBehind(const SkRect*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void willRestore() override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void didConcat(const SkMatrix&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void didSetMatrix(const SkMatrix&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawDRRect(const SkRRect&, const SkRRect&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  virtual void onDrawTextBlob(const SkTextBlob* blob,
                              SkScalar x,
                              SkScalar y,
                              const SkPaint& paint) override;
  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  virtual void onDrawPatch(const SkPoint cubics[12],
                           const SkColor colors[4],
                           const SkPoint texCoords[4],
                           SkBlendMode,
                           const SkPaint& paint) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawPaint(const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawBehind(const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawPoints(PointMode,
                    size_t count,
                    const SkPoint pts[],
                    const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawRect(const SkRect&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawRegion(const SkRegion&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawOval(const SkRect&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawArc(const SkRect&,
                 SkScalar,
                 SkScalar,
                 bool,
                 const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawRRect(const SkRRect&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawPath(const SkPath&, const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawBitmap(const SkBitmap&,
                    SkScalar left,
                    SkScalar top,
                    const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawBitmapRect(const SkBitmap&,
                        const SkRect* src,
                        const SkRect& dst,
                        const SkPaint*,
                        SrcRectConstraint) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawImage(const SkImage*,
                   SkScalar left,
                   SkScalar top,
                   const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawImageRect(const SkImage*,
                       const SkRect* src,
                       const SkRect& dst,
                       const SkPaint*,
                       SrcRectConstraint) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawBitmapLattice(const SkBitmap&,
                           const Lattice&,
                           const SkRect&,
                           const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawImageLattice(const SkImage*,
                          const Lattice&,
                          const SkRect&,
                          const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawImageNine(const SkImage*,
                       const SkIRect& center,
                       const SkRect& dst,
                       const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawBitmapNine(const SkBitmap&,
                        const SkIRect& center,
                        const SkRect& dst,
                        const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawVerticesObject(const SkVertices*,
                            const SkVertices::Bone bones[],
                            int boneCount,
                            SkBlendMode,
                            const SkPaint&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawAtlas(const SkImage*,
                   const SkRSXform[],
                   const SkRect[],
                   const SkColor[],
                   int,
                   SkBlendMode,
                   const SkRect*,
                   const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawShadowRec(const SkPath&, const SkDrawShadowRec&) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onClipRect(const SkRect&, SkClipOp, ClipEdgeStyle) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onClipRRect(const SkRRect&, SkClipOp, ClipEdgeStyle) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onClipPath(const SkPath&, SkClipOp, ClipEdgeStyle) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onClipRegion(const SkRegion&, SkClipOp) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawPicture(const SkPicture*,
                     const SkMatrix*,
                     const SkPaint*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawDrawable(SkDrawable*, const SkMatrix*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawAnnotation(const SkRect&, const char[], SkData*) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawEdgeAAQuad(const SkRect&,
                        const SkPoint[4],
                        SkCanvas::QuadAAFlags,
                        const SkColor4f&,
                        SkBlendMode) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onDrawEdgeAAImageSet(const ImageSetEntry[],
                            int count,
                            const SkPoint[],
                            const SkMatrix[],
                            const SkPaint*,
                            SrcRectConstraint) override;

  // |SkCanvasVirtualEnforcer<SkNoDrawCanvas>|
  void onFlush() override;

  void MarkDrawIfNonTransparentPaint(const SkPaint& paint);

  FML_DISALLOW_COPY_AND_ASSIGN(DidDrawCanvas);
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_COMMON_SKIA_EVENT_TRACER_IMPL_H_
