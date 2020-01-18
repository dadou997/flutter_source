// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/lib/ui/window/pointer_data_packet_converter.h"
#include "gtest/gtest.h"

namespace flutter {
namespace testing {

void CreateSimulatedPointerData(PointerData& data,
                                PointerData::Change change,
                                int64_t device,
                                double dx,
                                double dy) {
  data.time_stamp = 0;
  data.change = change;
  data.kind = PointerData::DeviceKind::kTouch;
  data.signal_kind = PointerData::SignalKind::kNone;
  data.device = device;
  data.pointer_identifier = 0;
  data.physical_x = dx;
  data.physical_y = dy;
  data.physical_delta_x = 0.0;
  data.physical_delta_y = 0.0;
  data.buttons = 0;
  data.obscured = 0;
  data.synthesized = 0;
  data.pressure = 0.0;
  data.pressure_min = 0.0;
  data.pressure_max = 0.0;
  data.distance = 0.0;
  data.distance_max = 0.0;
  data.size = 0.0;
  data.radius_major = 0.0;
  data.radius_minor = 0.0;
  data.radius_min = 0.0;
  data.radius_max = 0.0;
  data.orientation = 0.0;
  data.tilt = 0.0;
  data.platformData = 0;
  data.scroll_delta_x = 0.0;
  data.scroll_delta_y = 0.0;
}

void CreateSimulatedMousePointerData(PointerData& data,
                                     PointerData::Change change,
                                     PointerData::SignalKind signal_kind,
                                     int64_t device,
                                     double dx,
                                     double dy,
                                     double scroll_delta_x,
                                     double scroll_delta_y) {
  data.time_stamp = 0;
  data.change = change;
  data.kind = PointerData::DeviceKind::kMouse;
  data.signal_kind = signal_kind;
  data.device = device;
  data.pointer_identifier = 0;
  data.physical_x = dx;
  data.physical_y = dy;
  data.physical_delta_x = 0.0;
  data.physical_delta_y = 0.0;
  data.buttons = 0;
  data.obscured = 0;
  data.synthesized = 0;
  data.pressure = 0.0;
  data.pressure_min = 0.0;
  data.pressure_max = 0.0;
  data.distance = 0.0;
  data.distance_max = 0.0;
  data.size = 0.0;
  data.radius_major = 0.0;
  data.radius_minor = 0.0;
  data.radius_min = 0.0;
  data.radius_max = 0.0;
  data.orientation = 0.0;
  data.tilt = 0.0;
  data.platformData = 0;
  data.scroll_delta_x = scroll_delta_x;
  data.scroll_delta_y = scroll_delta_y;
}

void UnpackPointerPacket(std::vector<PointerData>& output,
                         std::unique_ptr<PointerDataPacket> packet) {
  size_t kBytesPerPointerData = kPointerDataFieldCount * kBytesPerField;
  auto buffer = packet->data();
  size_t buffer_length = buffer.size();

  for (size_t i = 0; i < buffer_length / kBytesPerPointerData; i++) {
    PointerData pointer_data;
    memcpy(&pointer_data, &buffer[i * kBytesPerPointerData],
           sizeof(PointerData));
    output.push_back(pointer_data);
  }
  packet.reset();
}

TEST(PointerDataPacketConverterTest, CanConvetPointerDataPacket) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(6);
  PointerData data;
  CreateSimulatedPointerData(data, PointerData::Change::kAdd, 0, 0.0, 0.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kHover, 0, 3.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 3.0, 0.0);
  packet->SetPointerData(2, data);
  CreateSimulatedPointerData(data, PointerData::Change::kMove, 0, 3.0, 4.0);
  packet->SetPointerData(3, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 3.0, 4.0);
  packet->SetPointerData(4, data);
  CreateSimulatedPointerData(data, PointerData::Change::kRemove, 0, 3.0, 4.0);
  packet->SetPointerData(5, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)6);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].synthesized, 0);

  ASSERT_EQ(result[1].change, PointerData::Change::kHover);
  ASSERT_EQ(result[1].synthesized, 0);
  ASSERT_EQ(result[1].physical_delta_x, 3.0);
  ASSERT_EQ(result[1].physical_delta_y, 0.0);

  ASSERT_EQ(result[2].change, PointerData::Change::kDown);
  ASSERT_EQ(result[2].pointer_identifier, 1);
  ASSERT_EQ(result[2].synthesized, 0);

  ASSERT_EQ(result[3].change, PointerData::Change::kMove);
  ASSERT_EQ(result[3].pointer_identifier, 1);
  ASSERT_EQ(result[3].synthesized, 0);
  ASSERT_EQ(result[3].physical_delta_x, 0.0);
  ASSERT_EQ(result[3].physical_delta_y, 4.0);

  ASSERT_EQ(result[4].change, PointerData::Change::kUp);
  ASSERT_EQ(result[4].pointer_identifier, 1);
  ASSERT_EQ(result[4].synthesized, 0);

  ASSERT_EQ(result[5].change, PointerData::Change::kRemove);
  ASSERT_EQ(result[5].synthesized, 0);
}

TEST(PointerDataPacketConverterTest, CanSynthesizeDownAndUp) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(4);
  PointerData data;
  CreateSimulatedPointerData(data, PointerData::Change::kAdd, 0, 0.0, 0.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 3.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 3.0, 4.0);
  packet->SetPointerData(2, data);
  CreateSimulatedPointerData(data, PointerData::Change::kRemove, 0, 3.0, 4.0);
  packet->SetPointerData(3, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)6);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].synthesized, 0);

  // A hover should be synthesized.
  ASSERT_EQ(result[1].change, PointerData::Change::kHover);
  ASSERT_EQ(result[1].synthesized, 1);
  ASSERT_EQ(result[1].physical_delta_x, 3.0);
  ASSERT_EQ(result[1].physical_delta_y, 0.0);

  ASSERT_EQ(result[2].change, PointerData::Change::kDown);
  ASSERT_EQ(result[2].pointer_identifier, 1);
  ASSERT_EQ(result[2].synthesized, 0);

  // A move should be synthesized.
  ASSERT_EQ(result[3].change, PointerData::Change::kMove);
  ASSERT_EQ(result[3].pointer_identifier, 1);
  ASSERT_EQ(result[3].synthesized, 1);
  ASSERT_EQ(result[3].physical_delta_x, 0.0);
  ASSERT_EQ(result[3].physical_delta_y, 4.0);

  ASSERT_EQ(result[4].change, PointerData::Change::kUp);
  ASSERT_EQ(result[4].pointer_identifier, 1);
  ASSERT_EQ(result[4].synthesized, 0);

  ASSERT_EQ(result[5].change, PointerData::Change::kRemove);
  ASSERT_EQ(result[5].synthesized, 0);
}

TEST(PointerDataPacketConverterTest, CanUpdatePointerIdentifier) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(7);
  PointerData data;
  CreateSimulatedPointerData(data, PointerData::Change::kAdd, 0, 0.0, 0.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 0.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 0.0, 0.0);
  packet->SetPointerData(2, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 0.0, 0.0);
  packet->SetPointerData(3, data);
  CreateSimulatedPointerData(data, PointerData::Change::kMove, 0, 3.0, 0.0);
  packet->SetPointerData(4, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 3.0, 0.0);
  packet->SetPointerData(5, data);
  CreateSimulatedPointerData(data, PointerData::Change::kRemove, 0, 3.0, 0.0);
  packet->SetPointerData(6, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)7);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].synthesized, 0);

  ASSERT_EQ(result[1].change, PointerData::Change::kDown);
  ASSERT_EQ(result[1].pointer_identifier, 1);
  ASSERT_EQ(result[1].synthesized, 0);

  ASSERT_EQ(result[2].change, PointerData::Change::kUp);
  ASSERT_EQ(result[2].pointer_identifier, 1);
  ASSERT_EQ(result[2].synthesized, 0);

  // Pointer count increase to 2.
  ASSERT_EQ(result[3].change, PointerData::Change::kDown);
  ASSERT_EQ(result[3].pointer_identifier, 2);
  ASSERT_EQ(result[3].synthesized, 0);

  ASSERT_EQ(result[4].change, PointerData::Change::kMove);
  ASSERT_EQ(result[4].pointer_identifier, 2);
  ASSERT_EQ(result[4].synthesized, 0);
  ASSERT_EQ(result[4].physical_delta_x, 3.0);
  ASSERT_EQ(result[4].physical_delta_y, 0.0);

  ASSERT_EQ(result[5].change, PointerData::Change::kUp);
  ASSERT_EQ(result[5].pointer_identifier, 2);
  ASSERT_EQ(result[5].synthesized, 0);

  ASSERT_EQ(result[6].change, PointerData::Change::kRemove);
  ASSERT_EQ(result[6].synthesized, 0);
}

TEST(PointerDataPacketConverterTest, CanWorkWithDifferentDevices) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(12);
  PointerData data;
  CreateSimulatedPointerData(data, PointerData::Change::kAdd, 0, 0.0, 0.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 0.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedPointerData(data, PointerData::Change::kAdd, 1, 0.0, 0.0);
  packet->SetPointerData(2, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 1, 0.0, 0.0);
  packet->SetPointerData(3, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 0.0, 0.0);
  packet->SetPointerData(4, data);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 0.0, 0.0);
  packet->SetPointerData(5, data);
  CreateSimulatedPointerData(data, PointerData::Change::kMove, 1, 0.0, 4.0);
  packet->SetPointerData(6, data);
  CreateSimulatedPointerData(data, PointerData::Change::kMove, 0, 3.0, 0.0);
  packet->SetPointerData(7, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 1, 0.0, 4.0);
  packet->SetPointerData(8, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 3.0, 0.0);
  packet->SetPointerData(9, data);
  CreateSimulatedPointerData(data, PointerData::Change::kRemove, 0, 3.0, 0.0);
  packet->SetPointerData(10, data);
  CreateSimulatedPointerData(data, PointerData::Change::kRemove, 1, 0.0, 4.0);
  packet->SetPointerData(11, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)12);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].device, 0);
  ASSERT_EQ(result[0].synthesized, 0);

  ASSERT_EQ(result[1].change, PointerData::Change::kDown);
  ASSERT_EQ(result[1].device, 0);
  ASSERT_EQ(result[1].pointer_identifier, 1);
  ASSERT_EQ(result[1].synthesized, 0);

  ASSERT_EQ(result[2].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[2].device, 1);
  ASSERT_EQ(result[2].synthesized, 0);

  ASSERT_EQ(result[3].change, PointerData::Change::kDown);
  ASSERT_EQ(result[3].device, 1);
  ASSERT_EQ(result[3].pointer_identifier, 2);
  ASSERT_EQ(result[3].synthesized, 0);

  ASSERT_EQ(result[4].change, PointerData::Change::kUp);
  ASSERT_EQ(result[4].device, 0);
  ASSERT_EQ(result[4].pointer_identifier, 1);
  ASSERT_EQ(result[4].synthesized, 0);

  ASSERT_EQ(result[5].change, PointerData::Change::kDown);
  ASSERT_EQ(result[5].device, 0);
  ASSERT_EQ(result[5].pointer_identifier, 3);
  ASSERT_EQ(result[5].synthesized, 0);

  ASSERT_EQ(result[6].change, PointerData::Change::kMove);
  ASSERT_EQ(result[6].device, 1);
  ASSERT_EQ(result[6].pointer_identifier, 2);
  ASSERT_EQ(result[6].synthesized, 0);
  ASSERT_EQ(result[6].physical_delta_x, 0.0);
  ASSERT_EQ(result[6].physical_delta_y, 4.0);

  ASSERT_EQ(result[7].change, PointerData::Change::kMove);
  ASSERT_EQ(result[7].device, 0);
  ASSERT_EQ(result[7].pointer_identifier, 3);
  ASSERT_EQ(result[7].synthesized, 0);
  ASSERT_EQ(result[7].physical_delta_x, 3.0);
  ASSERT_EQ(result[7].physical_delta_y, 0.0);

  ASSERT_EQ(result[8].change, PointerData::Change::kUp);
  ASSERT_EQ(result[8].device, 1);
  ASSERT_EQ(result[8].pointer_identifier, 2);
  ASSERT_EQ(result[8].synthesized, 0);

  ASSERT_EQ(result[9].change, PointerData::Change::kUp);
  ASSERT_EQ(result[9].device, 0);
  ASSERT_EQ(result[9].pointer_identifier, 3);
  ASSERT_EQ(result[9].synthesized, 0);

  ASSERT_EQ(result[10].change, PointerData::Change::kRemove);
  ASSERT_EQ(result[10].device, 0);
  ASSERT_EQ(result[10].synthesized, 0);

  ASSERT_EQ(result[11].change, PointerData::Change::kRemove);
  ASSERT_EQ(result[11].device, 1);
  ASSERT_EQ(result[11].synthesized, 0);
}

TEST(PointerDataPacketConverterTest, CanSynthesizeAdd) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(2);
  PointerData data;
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 330.0, 450.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kUp, 0, 0.0, 0.0);
  packet->SetPointerData(1, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)4);
  // A add should be synthesized.
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].physical_x, 330.0);
  ASSERT_EQ(result[0].physical_y, 450.0);
  ASSERT_EQ(result[0].synthesized, 1);

  ASSERT_EQ(result[1].change, PointerData::Change::kDown);
  ASSERT_EQ(result[1].physical_x, 330.0);
  ASSERT_EQ(result[1].physical_y, 450.0);
  ASSERT_EQ(result[1].synthesized, 0);

  // A move should be synthesized.
  ASSERT_EQ(result[2].change, PointerData::Change::kMove);
  ASSERT_EQ(result[2].physical_delta_x, -330.0);
  ASSERT_EQ(result[2].physical_delta_y, -450.0);
  ASSERT_EQ(result[2].physical_x, 0.0);
  ASSERT_EQ(result[2].physical_y, 0.0);
  ASSERT_EQ(result[2].synthesized, 1);

  ASSERT_EQ(result[3].change, PointerData::Change::kUp);
  ASSERT_EQ(result[3].physical_x, 0.0);
  ASSERT_EQ(result[3].physical_y, 0.0);
  ASSERT_EQ(result[3].synthesized, 0);
}

TEST(PointerDataPacketConverterTest, CanHandleThreeFingerGesture) {
  // Regression test https://github.com/flutter/flutter/issues/20517.
  PointerDataPacketConverter converter;
  PointerData data;
  std::vector<PointerData> result;
  // First finger down.
  auto packet = std::make_unique<PointerDataPacket>(1);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 0, 0.0, 0.0);
  packet->SetPointerData(0, data);
  auto converted_packet = converter.Convert(std::move(packet));
  UnpackPointerPacket(result, std::move(converted_packet));
  // Second finger down.
  packet = std::make_unique<PointerDataPacket>(1);
  CreateSimulatedPointerData(data, PointerData::Change::kDown, 1, 33.0, 44.0);
  packet->SetPointerData(0, data);
  converted_packet = converter.Convert(std::move(packet));
  UnpackPointerPacket(result, std::move(converted_packet));
  // Triggers three cancels.
  packet = std::make_unique<PointerDataPacket>(3);
  CreateSimulatedPointerData(data, PointerData::Change::kCancel, 1, 33.0, 44.0);
  packet->SetPointerData(0, data);
  CreateSimulatedPointerData(data, PointerData::Change::kCancel, 0, 0.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedPointerData(data, PointerData::Change::kCancel, 2, 40.0, 50.0);
  packet->SetPointerData(2, data);
  converted_packet = converter.Convert(std::move(packet));
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)6);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].device, 0);
  ASSERT_EQ(result[0].physical_x, 0.0);
  ASSERT_EQ(result[0].physical_y, 0.0);
  ASSERT_EQ(result[0].synthesized, 1);

  ASSERT_EQ(result[1].change, PointerData::Change::kDown);
  ASSERT_EQ(result[1].device, 0);
  ASSERT_EQ(result[1].physical_x, 0.0);
  ASSERT_EQ(result[1].physical_y, 0.0);
  ASSERT_EQ(result[1].synthesized, 0);

  ASSERT_EQ(result[2].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[2].device, 1);
  ASSERT_EQ(result[2].physical_x, 33.0);
  ASSERT_EQ(result[2].physical_y, 44.0);
  ASSERT_EQ(result[2].synthesized, 1);

  ASSERT_EQ(result[3].change, PointerData::Change::kDown);
  ASSERT_EQ(result[3].device, 1);
  ASSERT_EQ(result[3].physical_x, 33.0);
  ASSERT_EQ(result[3].physical_y, 44.0);
  ASSERT_EQ(result[3].synthesized, 0);

  ASSERT_EQ(result[4].change, PointerData::Change::kCancel);
  ASSERT_EQ(result[4].device, 1);
  ASSERT_EQ(result[4].physical_x, 33.0);
  ASSERT_EQ(result[4].physical_y, 44.0);
  ASSERT_EQ(result[4].synthesized, 0);

  ASSERT_EQ(result[5].change, PointerData::Change::kCancel);
  ASSERT_EQ(result[5].device, 0);
  ASSERT_EQ(result[5].physical_x, 0.0);
  ASSERT_EQ(result[5].physical_y, 0.0);
  ASSERT_EQ(result[5].synthesized, 0);
  // Third cancel should be dropped
}

TEST(PointerDataPacketConverterTest, CanConvetScroll) {
  PointerDataPacketConverter converter;
  auto packet = std::make_unique<PointerDataPacket>(5);
  PointerData data;
  CreateSimulatedMousePointerData(data, PointerData::Change::kAdd,
                                  PointerData::SignalKind::kNone, 0, 0.0, 0.0,
                                  0.0, 0.0);
  packet->SetPointerData(0, data);
  CreateSimulatedMousePointerData(data, PointerData::Change::kAdd,
                                  PointerData::SignalKind::kNone, 1, 0.0, 0.0,
                                  0.0, 0.0);
  packet->SetPointerData(1, data);
  CreateSimulatedMousePointerData(data, PointerData::Change::kDown,
                                  PointerData::SignalKind::kNone, 1, 0.0, 0.0,
                                  0.0, 0.0);
  packet->SetPointerData(2, data);
  CreateSimulatedMousePointerData(data, PointerData::Change::kHover,
                                  PointerData::SignalKind::kScroll, 0, 34.0,
                                  34.0, 30.0, 0.0);
  packet->SetPointerData(3, data);
  CreateSimulatedMousePointerData(data, PointerData::Change::kHover,
                                  PointerData::SignalKind::kScroll, 1, 49.0,
                                  49.0, 50.0, 0.0);
  packet->SetPointerData(4, data);
  auto converted_packet = converter.Convert(std::move(packet));

  std::vector<PointerData> result;
  UnpackPointerPacket(result, std::move(converted_packet));

  ASSERT_EQ(result.size(), (size_t)7);
  ASSERT_EQ(result[0].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[0].signal_kind, PointerData::SignalKind::kNone);
  ASSERT_EQ(result[0].device, 0);
  ASSERT_EQ(result[0].physical_x, 0.0);
  ASSERT_EQ(result[0].physical_y, 0.0);
  ASSERT_EQ(result[0].synthesized, 0);

  ASSERT_EQ(result[1].change, PointerData::Change::kAdd);
  ASSERT_EQ(result[1].signal_kind, PointerData::SignalKind::kNone);
  ASSERT_EQ(result[1].device, 1);
  ASSERT_EQ(result[1].physical_x, 0.0);
  ASSERT_EQ(result[1].physical_y, 0.0);
  ASSERT_EQ(result[1].synthesized, 0);

  ASSERT_EQ(result[2].change, PointerData::Change::kDown);
  ASSERT_EQ(result[2].signal_kind, PointerData::SignalKind::kNone);
  ASSERT_EQ(result[2].device, 1);
  ASSERT_EQ(result[2].physical_x, 0.0);
  ASSERT_EQ(result[2].physical_y, 0.0);
  ASSERT_EQ(result[2].synthesized, 0);

  // Converter will synthesize a hover to position.
  ASSERT_EQ(result[3].change, PointerData::Change::kHover);
  ASSERT_EQ(result[3].signal_kind, PointerData::SignalKind::kNone);
  ASSERT_EQ(result[3].device, 0);
  ASSERT_EQ(result[3].physical_x, 34.0);
  ASSERT_EQ(result[3].physical_y, 34.0);
  ASSERT_EQ(result[3].physical_delta_x, 34.0);
  ASSERT_EQ(result[3].physical_delta_y, 34.0);
  ASSERT_EQ(result[3].synthesized, 1);

  ASSERT_EQ(result[4].change, PointerData::Change::kHover);
  ASSERT_EQ(result[4].signal_kind, PointerData::SignalKind::kScroll);
  ASSERT_EQ(result[4].device, 0);
  ASSERT_EQ(result[4].physical_x, 34.0);
  ASSERT_EQ(result[4].physical_y, 34.0);
  ASSERT_EQ(result[4].scroll_delta_x, 30.0);
  ASSERT_EQ(result[4].scroll_delta_y, 0.0);

  // Converter will synthesize a move to position.
  ASSERT_EQ(result[5].change, PointerData::Change::kMove);
  ASSERT_EQ(result[5].signal_kind, PointerData::SignalKind::kNone);
  ASSERT_EQ(result[5].device, 1);
  ASSERT_EQ(result[5].physical_x, 49.0);
  ASSERT_EQ(result[5].physical_y, 49.0);
  ASSERT_EQ(result[5].physical_delta_x, 49.0);
  ASSERT_EQ(result[5].physical_delta_y, 49.0);
  ASSERT_EQ(result[5].synthesized, 1);

  ASSERT_EQ(result[6].change, PointerData::Change::kHover);
  ASSERT_EQ(result[6].signal_kind, PointerData::SignalKind::kScroll);
  ASSERT_EQ(result[6].device, 1);
  ASSERT_EQ(result[6].physical_x, 49.0);
  ASSERT_EQ(result[6].physical_y, 49.0);
  ASSERT_EQ(result[6].scroll_delta_x, 50.0);
  ASSERT_EQ(result[6].scroll_delta_y, 0.0);
}

}  // namespace testing
}  // namespace flutter
