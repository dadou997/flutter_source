// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_CLASS_TABLE_H_
#define RUNTIME_VM_CLASS_TABLE_H_

#include "platform/assert.h"
#include "platform/atomic.h"

#include "vm/bitfield.h"
#include "vm/class_id.h"
#include "vm/globals.h"

namespace dart {

class Class;
class ClassTable;
class Isolate;
class IsolateGroup;
class IsolateGroupReloadContext;
class IsolateReloadContext;
class JSONArray;
class JSONObject;
class JSONStream;
template <typename T>
class MallocGrowableArray;
class ObjectPointerVisitor;
class RawClass;

// Registry of all known classes and their sizes.
//
// The GC will only need the information in this shared class table to scan
// object pointers.
class SharedClassTable {
 public:
  SharedClassTable();
  ~SharedClassTable();

  // Thread-safe.
  intptr_t SizeAt(intptr_t index) const {
    ASSERT(IsValidIndex(index));
    return table_[index];
  }

  bool HasValidClassAt(intptr_t index) const {
    ASSERT(IsValidIndex(index));
    ASSERT(table_[index] >= 0);
    return table_[index] != 0;
  }

  void SetSizeAt(intptr_t index, intptr_t size) {
    ASSERT(IsValidIndex(index));
    // Ensure we never change size for a given cid from one non-zero size to
    // another non-zero size.
    RELEASE_ASSERT(table_[index] == 0 || table_[index] == size);
    table_[index] = size;
  }

  bool IsValidIndex(intptr_t index) const { return index > 0 && index < top_; }

  intptr_t NumCids() const { return top_; }
  intptr_t Capacity() const { return capacity_; }

  // Used to drop recently added classes.
  void SetNumCids(intptr_t num_cids) {
    ASSERT(num_cids <= top_);
    top_ = num_cids;
  }

#if !defined(PRODUCT)
  void SetTraceAllocationFor(intptr_t cid, bool trace) {
    ASSERT(cid > 0);
    ASSERT(cid < top_);
    trace_allocation_table_[cid] = trace ? 1 : 0;
  }
  bool TraceAllocationFor(intptr_t cid) {
    ASSERT(cid > 0);
    ASSERT(cid < top_);
    return trace_allocation_table_[cid] != 0;
  }
#endif  // !defined(PRODUCT)

  void CopyBeforeHotReload(intptr_t** copy, intptr_t* copy_num_cids) {
    // The [IsolateGroupReloadContext] will need to maintain a copy of the old
    // class table until instances have been morphed.
    const intptr_t num_cids = NumCids();
    const intptr_t bytes = sizeof(intptr_t) * num_cids;
    auto size_table = static_cast<intptr_t*>(malloc(bytes));
    memmove(size_table, table_, sizeof(intptr_t) * num_cids);
    *copy_num_cids = num_cids;
    *copy = size_table;
  }

  void ResetBeforeHotReload() {
    // The [IsolateReloadContext] is now source-of-truth for GC.
    memset(table_, 0, sizeof(intptr_t) * top_);
  }

  void ResetAfterHotReload(intptr_t* old_table,
                           intptr_t num_old_cids,
                           bool is_rollback) {
    // The [IsolateReloadContext] is no longer source-of-truth for GC after we
    // return, so we restore size information for all classes.
    if (is_rollback) {
      SetNumCids(num_old_cids);
      memmove(table_, old_table, sizeof(intptr_t) * num_old_cids);
    }

    // Can't free this table immediately as another thread (e.g., concurrent
    // marker or sweeper) may be between loading the table pointer and loading
    // the table element. The table will be freed at the next major GC or
    // isolate shutdown.
    AddOldTable(old_table);
  }

  // Deallocates table copies. Do not call during concurrent access to table.
  void FreeOldTables();

#if !defined(DART_PRECOMPILED_RUNTIME)
  bool IsReloading() const { return reload_context_ != nullptr; }

  IsolateGroupReloadContext* reload_context() { return reload_context_; }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

  // Returns the newly allocated cid.
  //
  // [index] is kIllegalCid or a predefined cid.
  intptr_t Register(intptr_t index, intptr_t size);
  void AllocateIndex(intptr_t index);
  void Unregister(intptr_t index);

  void Remap(intptr_t* old_to_new_cids);

  // Used by the generated code.
#ifndef PRODUCT
  static intptr_t class_heap_stats_table_offset() {
    return OFFSET_OF(SharedClassTable, trace_allocation_table_);
  }
#endif

  // Used by the generated code.
  static intptr_t ClassOffsetFor(intptr_t cid);

  static const int kInitialCapacity = 512;
  static const int kCapacityIncrement = 256;

 private:
  friend class ClassTable;
  friend class GCMarker;
  friend class MarkingWeakVisitor;
  friend class Scavenger;
  friend class ScavengerWeakVisitor;

  static bool ShouldUpdateSizeForClassId(intptr_t cid);

#ifndef PRODUCT
  uint8_t* trace_allocation_table_ = nullptr;
#endif  // !PRODUCT

  void AddOldTable(intptr_t* old_table);

  void Grow(intptr_t new_capacity);

  intptr_t top_;
  intptr_t capacity_;

  // Copy-on-write is used for table_, with old copies stored in old_tables_.
  intptr_t* table_;  // Maps the cid to the instance size.
  MallocGrowableArray<intptr_t*>* old_tables_;

  IsolateGroupReloadContext* reload_context_ = nullptr;

  DISALLOW_COPY_AND_ASSIGN(SharedClassTable);
};

class ClassTable {
 public:
  explicit ClassTable(SharedClassTable* shared_class_table_);

  // Creates a shallow copy of the original class table for some read-only
  // access, without support for stats data.
  ClassTable(ClassTable* original, SharedClassTable* shared_class_table);
  ~ClassTable();

  SharedClassTable* shared_class_table() const { return shared_class_table_; }

  void CopyBeforeHotReload(RawClass*** copy, intptr_t* copy_num_cids) {
    // The [IsolateReloadContext] will need to maintain a copy of the old class
    // table until instances have been morphed.
    const intptr_t num_cids = NumCids();
    const intptr_t bytes = sizeof(RawClass*) * num_cids;
    auto class_table = static_cast<RawClass**>(malloc(bytes));
    memmove(class_table, table_, sizeof(RawClass*) * num_cids);
    *copy_num_cids = num_cids;
    *copy = class_table;
  }

  void ResetBeforeHotReload() {
    // We cannot clear out the class pointers, because a hot-reload
    // contains only a diff: If e.g. a class included in the hot-reload has a
    // super class not included in the diff, it will look up in this class table
    // to find the super class (e.g. `cls.SuperClass` will cause us to come
    // here).
  }

  void ResetAfterHotReload(RawClass** old_table,
                           intptr_t num_old_cids,
                           bool is_rollback) {
    // The [IsolateReloadContext] is no longer source-of-truth for GC after we
    // return, so we restore size information for all classes.
    if (is_rollback) {
      SetNumCids(num_old_cids);
      memmove(table_, old_table, sizeof(RawClass*) * num_old_cids);
    } else {
      CopySizesFromClassObjects();
    }

    // Can't free this table immediately as another thread (e.g., concurrent
    // marker or sweeper) may be between loading the table pointer and loading
    // the table element. The table will be freed at the next major GC or
    // isolate shutdown.
    AddOldTable(old_table);
  }

  // Thread-safe.
  RawClass* At(intptr_t index) const {
    ASSERT(IsValidIndex(index));
    return table_[index];
  }

  intptr_t SizeAt(intptr_t index) const {
    return shared_class_table_->SizeAt(index);
  }

  void SetAt(intptr_t index, RawClass* raw_cls);

  bool IsValidIndex(intptr_t index) const {
    return shared_class_table_->IsValidIndex(index);
  }

  bool HasValidClassAt(intptr_t index) const {
    ASSERT(IsValidIndex(index));
    return table_[index] != nullptr;
  }

  intptr_t NumCids() const { return shared_class_table_->NumCids(); }
  intptr_t Capacity() const { return shared_class_table_->Capacity(); }

  // Used to drop recently added classes.
  void SetNumCids(intptr_t num_cids) {
    shared_class_table_->SetNumCids(num_cids);

    ASSERT(num_cids <= top_);
    top_ = num_cids;
  }

  void Register(const Class& cls);
  void AllocateIndex(intptr_t index);
  void Unregister(intptr_t index);

  void Remap(intptr_t* old_to_new_cids);

  void VisitObjectPointers(ObjectPointerVisitor* visitor);

  // If a snapshot reader has populated the class table then the
  // sizes in the class table are not correct. Iterates through the
  // table, updating the sizes.
  void CopySizesFromClassObjects();

  void Validate();

  void Print();

  // Used by the generated code.
  static intptr_t table_offset() { return OFFSET_OF(ClassTable, table_); }

  // Used by the generated code.
  static intptr_t shared_class_table_offset() {
    return OFFSET_OF(ClassTable, shared_class_table_);
  }

#ifndef PRODUCT
  // Describes layout of heap stats for code generation. See offset_extractor.cc
  struct ArrayLayout {
    static intptr_t elements_start_offset() { return 0; }

    static constexpr intptr_t kElementSize = sizeof(uint8_t);
  };
#endif

#ifndef PRODUCT

  void AllocationProfilePrintJSON(JSONStream* stream, bool internal);

  void PrintToJSONObject(JSONObject* object);
#endif  // !PRODUCT

  // Deallocates table copies. Do not call during concurrent access to table.
  void FreeOldTables();

 private:
  friend class GCMarker;
  friend class MarkingWeakVisitor;
  friend class Scavenger;
  friend class ScavengerWeakVisitor;
  static const int kInitialCapacity = SharedClassTable::kInitialCapacity;
  static const int kCapacityIncrement = SharedClassTable::kCapacityIncrement;

  void AddOldTable(RawClass** old_table);

  void Grow(intptr_t index);

  intptr_t top_;
  intptr_t capacity_;

  // Copy-on-write is used for table_, with old copies stored in
  // old_class_tables_.
  RawClass** table_;
  MallocGrowableArray<RawClass**>* old_class_tables_;
  SharedClassTable* shared_class_table_;

  DISALLOW_COPY_AND_ASSIGN(ClassTable);
};

}  // namespace dart

#endif  // RUNTIME_VM_CLASS_TABLE_H_
