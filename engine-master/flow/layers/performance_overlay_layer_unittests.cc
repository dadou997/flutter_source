// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/flow/layers/performance_overlay_layer.h"

#include "flutter/flow/flow_test_utils.h"
#include "flutter/flow/raster_cache.h"
#include "flutter/flow/testing/layer_test.h"
#include "flutter/flow/testing/mock_layer.h"
#include "flutter/fml/build_config.h"
#include "flutter/fml/macros.h"
#include "flutter/testing/mock_canvas.h"
#include "gtest/gtest.h"
#include "third_party/skia/include/core/SkData.h"
#include "third_party/skia/include/core/SkSerialProcs.h"
#include "third_party/skia/include/core/SkSurface.h"
#include "third_party/skia/include/core/SkTextBlob.h"
#include "third_party/skia/include/utils/SkBase64.h"

#include <cstdint>
#include <sstream>

namespace flutter {
namespace testing {
namespace {

// To get the size of kMockedTimes in compile time.
template <class T, std::size_t N>
constexpr int size(const T (&array)[N]) noexcept {
  return N;
}

constexpr int kMockedTimes[] = {17, 1,  4,  24, 4,  25, 30, 4,  13, 34,
                                14, 0,  18, 9,  32, 36, 26, 23, 5,  8,
                                32, 18, 29, 16, 29, 18, 0,  36, 33, 10};

static std::string GetGoldenFilePath(int refresh_rate, bool is_new) {
  std::stringstream ss;
  // This unit test should only be run on Linux (not even on Mac since it's a
  // golden test). Hence we don't have to worry about the "/" vs. "\".
  ss << flutter::GetGoldenDir() << "/"
     << "performance_overlay_gold_" << refresh_rate << "fps"
     << (is_new ? "_new" : "") << ".png";
  return ss.str();
}

static void TestPerformanceOverlayLayerGold(int refresh_rate) {
  std::string golden_file_path = GetGoldenFilePath(refresh_rate, false);
  std::string new_golden_file_path = GetGoldenFilePath(refresh_rate, true);

  flutter::Stopwatch mock_stopwatch(
      fml::RefreshRateToFrameBudget(refresh_rate));
  for (int i = 0; i < size(kMockedTimes); ++i) {
    mock_stopwatch.SetLapTime(
        fml::TimeDelta::FromMilliseconds(kMockedTimes[i]));
  }

  const SkImageInfo image_info = SkImageInfo::MakeN32Premul(1000, 1000);
  sk_sp<SkSurface> surface = SkSurface::MakeRaster(image_info);

  ASSERT_TRUE(surface != nullptr);

  flutter::TextureRegistry unused_texture_registry;
  flutter::Layer::PaintContext paintContext = {
      nullptr,        surface->getCanvas(),    nullptr, nullptr, mock_stopwatch,
      mock_stopwatch, unused_texture_registry, nullptr, false};

  // Specify font file to ensure the same font across different operation
  // systems.
  flutter::PerformanceOverlayLayer layer(
      flutter::kDisplayRasterizerStatistics |
          flutter::kVisualizeRasterizerStatistics |
          flutter::kDisplayEngineStatistics |
          flutter::kVisualizeEngineStatistics,
      flutter::GetFontFile().c_str());
  layer.set_paint_bounds(SkRect::MakeWH(1000, 400));
  surface->getCanvas()->clear(SK_ColorTRANSPARENT);
  layer.Paint(paintContext);

  sk_sp<SkImage> snapshot = surface->makeImageSnapshot();
  sk_sp<SkData> snapshot_data = snapshot->encodeToData();

  sk_sp<SkData> golden_data =
      SkData::MakeFromFileName(golden_file_path.c_str());
  EXPECT_TRUE(golden_data != nullptr)
      << "Golden file not found: " << golden_file_path << ".\n"
      << "Please either set --golden-dir, or make sure that the unit test is "
      << "run from the right directory (e.g., flutter/engine/src).";

#if !defined(OS_LINUX)
  GTEST_SKIP() << "Skipping golden tests on non-Linux OSes";
#endif  // OS_LINUX
  const bool golden_data_matches = golden_data->equals(snapshot_data.get());
  if (!golden_data_matches) {
    SkFILEWStream wstream(new_golden_file_path.c_str());
    wstream.write(snapshot_data->data(), snapshot_data->size());
    wstream.flush();

    size_t b64_size =
        SkBase64::Encode(snapshot_data->data(), snapshot_data->size(), nullptr);
    sk_sp<SkData> b64_data = SkData::MakeUninitialized(b64_size + 1);
    char* b64_char = static_cast<char*>(b64_data->writable_data());
    SkBase64::Encode(snapshot_data->data(), snapshot_data->size(), b64_char);
    b64_char[b64_size] = 0;  // make it null terminated for printing

    EXPECT_TRUE(golden_data_matches)
        << "Golden file mismatch. Please check "
        << "the difference between " << golden_file_path << " and "
        << new_golden_file_path << ", and  replace the former "
        << "with the latter if the difference looks good.\nS\n"
        << "See also the base64 encoded " << new_golden_file_path << ":\n"
        << b64_char;
  }
}

}  // namespace

using PerformanceOverlayLayerTest = LayerTest;

TEST_F(PerformanceOverlayLayerTest, PaintingEmptyLayerDies) {
  const uint64_t overlay_opts = kVisualizeRasterizerStatistics;
  auto layer = std::make_shared<PerformanceOverlayLayer>(overlay_opts);

  layer->Preroll(preroll_context(), SkMatrix());
  EXPECT_EQ(layer->paint_bounds(), SkRect::MakeEmpty());
  EXPECT_FALSE(layer->needs_painting());

  // Crashes reading a nullptr.
  EXPECT_DEATH_IF_SUPPORTED(layer->Paint(paint_context()), "");
}

TEST_F(PerformanceOverlayLayerTest, InvalidOptions) {
  const SkRect layer_bounds = SkRect::MakeLTRB(0.0f, 0.0f, 64.0f, 64.0f);
  const uint64_t overlay_opts = 0;
  auto layer = std::make_shared<PerformanceOverlayLayer>(overlay_opts);

  // TODO(): Note calling code has to call set_paint_bounds right now.  Make
  // this a constructor parameter and move the set_paint_bounds into Preroll
  layer->set_paint_bounds(layer_bounds);

  layer->Preroll(preroll_context(), SkMatrix());
  EXPECT_EQ(layer->paint_bounds(), layer_bounds);
  EXPECT_TRUE(layer->needs_painting());

  // Nothing is drawn if options are invalid (0).
  layer->Paint(paint_context());
  EXPECT_EQ(mock_canvas().draw_calls(), std::vector<MockCanvas::DrawCall>());
}

TEST_F(PerformanceOverlayLayerTest, SimpleRasterizerStatistics) {
  const SkRect layer_bounds = SkRect::MakeLTRB(0.0f, 0.0f, 64.0f, 64.0f);
  const uint64_t overlay_opts = kDisplayRasterizerStatistics;
  auto layer = std::make_shared<PerformanceOverlayLayer>(overlay_opts);

  // TODO(): Note calling code has to call set_paint_bounds right now.  Make
  // this a constructor parameter and move the set_paint_bounds into Preroll
  layer->set_paint_bounds(layer_bounds);

  layer->Preroll(preroll_context(), SkMatrix());
  EXPECT_EQ(layer->paint_bounds(), layer_bounds);
  EXPECT_TRUE(layer->needs_painting());

  layer->Paint(paint_context());
  auto overlay_text = PerformanceOverlayLayer::MakeStatisticsText(
      paint_context().raster_time, "GPU", "");
  auto overlay_text_data = overlay_text->serialize(SkSerialProcs{});
  SkPaint text_paint;
  text_paint.setColor(SK_ColorGRAY);
  SkPoint text_position = SkPoint::Make(16.0f, 22.0f);
  EXPECT_EQ(mock_canvas().draw_calls(),
            std::vector({MockCanvas::DrawCall{
                0, MockCanvas::DrawTextData{overlay_text_data, text_paint,
                                            text_position}}}));
}

TEST(PerformanceOverlayLayerDefault, Gold) {
  TestPerformanceOverlayLayerGold(60);
}

TEST(PerformanceOverlayLayer90fps, Gold) {
  TestPerformanceOverlayLayerGold(90);
}

TEST(PerformanceOverlayLayer120fps, Gold) {
  TestPerformanceOverlayLayerGold(120);
}

}  // namespace testing
}  // namespace flutter
