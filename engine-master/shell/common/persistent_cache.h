// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_SHELL_COMMON_PERSISTENT_CACHE_H_
#define FLUTTER_SHELL_COMMON_PERSISTENT_CACHE_H_

#include <memory>
#include <mutex>
#include <set>

#include "flutter/fml/macros.h"
#include "flutter/fml/task_runner.h"
#include "flutter/fml/unique_fd.h"
#include "third_party/skia/include/gpu/GrContextOptions.h"

namespace flutter {

/// A cache of SkData that gets stored to disk.
///
/// This is mainly used for Shaders but is also written to by Dart.  It is
/// thread-safe for reading and writing from multiple threads.
class PersistentCache : public GrContextOptions::PersistentCache {
 public:
  // Mutable static switch that can be set before GetCacheForProcess. If true,
  // we'll only read existing caches but not generate new ones. Some clients
  // (e.g., embedded devices) prefer generating persistent cache files for the
  // specific device beforehand, and ship them as readonly files in OTA
  // packages.
  static bool gIsReadOnly;

  static PersistentCache* GetCacheForProcess();
  static void ResetCacheForProcess();

  static void SetCacheDirectoryPath(std::string path);

  ~PersistentCache() override;

  void AddWorkerTaskRunner(fml::RefPtr<fml::TaskRunner> task_runner);

  void RemoveWorkerTaskRunner(fml::RefPtr<fml::TaskRunner> task_runner);

  // Whether Skia tries to store any shader into this persistent cache after
  // |ResetStoredNewShaders| is called. This flag is usually reset before each
  // frame so we can know if Skia tries to compile new shaders in that frame.
  bool StoredNewShaders() const { return stored_new_shaders_; }
  void ResetStoredNewShaders() { stored_new_shaders_ = false; }
  void DumpSkp(const SkData& data);
  bool IsDumpingSkp() const { return is_dumping_skp_; }
  void SetIsDumpingSkp(bool value) { is_dumping_skp_ = value; }

  // |GrContextOptions::PersistentCache|
  sk_sp<SkData> load(const SkData& key) override;

  using SkSLCache = std::pair<sk_sp<SkData>, sk_sp<SkData>>;

  /// Load all the SkSL shader caches in the right directory.
  std::vector<SkSLCache> LoadSkSLs();

  static bool cache_sksl() { return cache_sksl_; }
  static void SetCacheSkSL(bool value);
  static void MarkStrategySet() { strategy_set_ = true; }

 private:
  static std::string cache_base_path_;

  static std::mutex instance_mutex_;
  static std::unique_ptr<PersistentCache> gPersistentCache;

  // Mutable static switch that can be set before GetCacheForProcess is called
  // and GrContextOptions.fShaderCacheStrategy is set. If true, it means that
  // we'll set `GrContextOptions::fShaderCacheStrategy` to `kSkSL`, and all the
  // persistent cache should be stored and loaded from the "sksl" directory.
  static std::atomic<bool> cache_sksl_;

  // Guard flag to make sure that cache_sksl_ is not modified after
  // strategy_set_ becomes true.
  static std::atomic<bool> strategy_set_;

  const bool is_read_only_;
  const std::shared_ptr<fml::UniqueFD> cache_directory_;
  const std::shared_ptr<fml::UniqueFD> sksl_cache_directory_;
  mutable std::mutex worker_task_runners_mutex_;
  std::multiset<fml::RefPtr<fml::TaskRunner>> worker_task_runners_;

  bool stored_new_shaders_ = false;
  bool is_dumping_skp_ = false;

  static sk_sp<SkData> LoadFile(const fml::UniqueFD& dir,
                                const std::string& filen_ame);

  bool IsValid() const;

  PersistentCache(bool read_only = false);

  // |GrContextOptions::PersistentCache|
  void store(const SkData& key, const SkData& data) override;

  fml::RefPtr<fml::TaskRunner> GetWorkerTaskRunner() const;

  FML_DISALLOW_COPY_AND_ASSIGN(PersistentCache);
};

}  // namespace flutter

#endif  // FLUTTER_SHELL_COMMON_PERSISTENT_CACHE_H_
