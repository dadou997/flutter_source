// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_FML_CONCURRENT_MESSAGE_LOOP_H_
#define FLUTTER_FML_CONCURRENT_MESSAGE_LOOP_H_

#include <condition_variable>
#include <queue>
#include <thread>

#include "flutter/fml/closure.h"
#include "flutter/fml/macros.h"

namespace fml {

class ConcurrentTaskRunner;

class ConcurrentMessageLoop
    : public std::enable_shared_from_this<ConcurrentMessageLoop> {
 public:
  static std::shared_ptr<ConcurrentMessageLoop> Create(
      size_t worker_count = std::thread::hardware_concurrency());

  ~ConcurrentMessageLoop();

  size_t GetWorkerCount() const;

  std::shared_ptr<ConcurrentTaskRunner> GetTaskRunner();

  void Terminate();

 private:
  friend ConcurrentTaskRunner;

  size_t worker_count_ = 0;
  std::vector<std::thread> workers_;
  std::mutex tasks_mutex_;
  std::condition_variable tasks_condition_;
  std::queue<fml::closure> tasks_;
  bool shutdown_ = false;

  ConcurrentMessageLoop(size_t worker_count);

  void WorkerMain();

  void PostTask(const fml::closure& task);

  FML_DISALLOW_COPY_AND_ASSIGN(ConcurrentMessageLoop);
};

class ConcurrentTaskRunner {
 public:
  ConcurrentTaskRunner(std::weak_ptr<ConcurrentMessageLoop> weak_loop);

  ~ConcurrentTaskRunner();

  void PostTask(const fml::closure& task);

 private:
  friend ConcurrentMessageLoop;

  std::weak_ptr<ConcurrentMessageLoop> weak_loop_;

  FML_DISALLOW_COPY_AND_ASSIGN(ConcurrentTaskRunner);
};

}  // namespace fml

#endif  // FLUTTER_FML_CONCURRENT_MESSAGE_LOOP_H_
