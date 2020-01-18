// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/lib/ui/isolate_name_server/isolate_name_server.h"

namespace flutter {

IsolateNameServer::IsolateNameServer() {}

IsolateNameServer::~IsolateNameServer() = default;

Dart_Port IsolateNameServer::LookupIsolatePortByName(const std::string& name) {
  std::scoped_lock lock(mutex_);
  return LookupIsolatePortByNameUnprotected(name);
}

Dart_Port IsolateNameServer::LookupIsolatePortByNameUnprotected(
    const std::string& name) {
  auto port_iterator = port_mapping_.find(name);
  if (port_iterator != port_mapping_.end()) {
    return port_iterator->second;
  }
  return ILLEGAL_PORT;
}

bool IsolateNameServer::RegisterIsolatePortWithName(Dart_Port port,
                                                    const std::string& name) {
  std::scoped_lock lock(mutex_);
  if (LookupIsolatePortByNameUnprotected(name) != ILLEGAL_PORT) {
    // Name is already registered.
    return false;
  }
  port_mapping_[name] = port;
  return true;
}

bool IsolateNameServer::RemoveIsolateNameMapping(const std::string& name) {
  std::scoped_lock lock(mutex_);
  auto port_iterator = port_mapping_.find(name);
  if (port_iterator == port_mapping_.end()) {
    return false;
  }
  port_mapping_.erase(port_iterator);
  return true;
}

}  // namespace flutter
