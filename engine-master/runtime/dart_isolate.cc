// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "flutter/runtime/dart_isolate.h"

#include <cstdlib>
#include <tuple>

#include "flutter/fml/paths.h"
#include "flutter/fml/trace_event.h"
#include "flutter/lib/io/dart_io.h"
#include "flutter/lib/ui/dart_runtime_hooks.h"
#include "flutter/lib/ui/dart_ui.h"
#include "flutter/runtime/dart_isolate_group_data.h"
#include "flutter/runtime/dart_service_isolate.h"
#include "flutter/runtime/dart_vm.h"
#include "flutter/runtime/dart_vm_lifecycle.h"
#include "third_party/dart/runtime/include/dart_api.h"
#include "third_party/dart/runtime/include/dart_tools_api.h"
#include "third_party/tonic/converter/dart_converter.h"
#include "third_party/tonic/dart_class_library.h"
#include "third_party/tonic/dart_class_provider.h"
#include "third_party/tonic/dart_message_handler.h"
#include "third_party/tonic/dart_state.h"
#include "third_party/tonic/file_loader/file_loader.h"
#include "third_party/tonic/logging/dart_invoke.h"
#include "third_party/tonic/scopes/dart_api_scope.h"
#include "third_party/tonic/scopes/dart_isolate_scope.h"

namespace flutter {

namespace {

class DartErrorString {
 public:
  DartErrorString() : str_(nullptr) {}
  ~DartErrorString() {
    if (str_) {
      ::free(str_);
    }
  }
  char** error() { return &str_; }
  const char* str() const { return str_; }
  operator bool() const { return str_ != nullptr; }

 private:
  FML_DISALLOW_COPY_AND_ASSIGN(DartErrorString);
  char* str_;
};

}  // anonymous namespace

std::weak_ptr<DartIsolate> DartIsolate::CreateRootIsolate(
    const Settings& settings,
    fml::RefPtr<const DartSnapshot> isolate_snapshot,
    TaskRunners task_runners,
    std::unique_ptr<Window> window,
    fml::WeakPtr<SnapshotDelegate> snapshot_delegate,
    fml::WeakPtr<IOManager> io_manager,
    fml::RefPtr<SkiaUnrefQueue> unref_queue,
    fml::WeakPtr<ImageDecoder> image_decoder,
    std::string advisory_script_uri,
    std::string advisory_script_entrypoint,
    Dart_IsolateFlags* flags,
    const fml::closure& isolate_create_callback,
    const fml::closure& isolate_shutdown_callback) {
  TRACE_EVENT0("flutter", "DartIsolate::CreateRootIsolate");

  // The child isolate preparer is null but will be set when the isolate is
  // being prepared to run.
  auto isolate_group_data =
      std::make_unique<std::shared_ptr<DartIsolateGroupData>>(
          std::shared_ptr<DartIsolateGroupData>(new DartIsolateGroupData(
              settings,                     // settings
              std::move(isolate_snapshot),  // isolate snapshot
              advisory_script_uri,          // advisory URI
              advisory_script_entrypoint,   // advisory entrypoint
              nullptr,                      // child isolate preparer
              isolate_create_callback,      // isolate create callback
              isolate_shutdown_callback     // isolate shutdown callback
              )));

  auto isolate_data = std::make_unique<std::shared_ptr<DartIsolate>>(
      std::shared_ptr<DartIsolate>(new DartIsolate(
          settings,                      // settings
          task_runners,                  // task runners
          std::move(snapshot_delegate),  // snapshot delegate
          std::move(io_manager),         // IO manager
          std::move(unref_queue),        // Skia unref queue
          std::move(image_decoder),      // Image Decoder
          advisory_script_uri,           // advisory URI
          advisory_script_entrypoint,    // advisory entrypoint
          true                           // is_root_isolate
          )));

  DartErrorString error;
  Dart_Isolate vm_isolate =
      CreateDartIsolateGroup(std::move(isolate_group_data),
                             std::move(isolate_data), flags, error.error());

  if (error) {
    FML_LOG(ERROR) << "CreateDartIsolateGroup failed: " << error.str();
  }

  if (vm_isolate == nullptr) {
    return {};
  }

  std::shared_ptr<DartIsolate>* root_isolate_data =
      static_cast<std::shared_ptr<DartIsolate>*>(Dart_IsolateData(vm_isolate));

  (*root_isolate_data)->SetWindow(std::move(window));

  return (*root_isolate_data)->GetWeakIsolatePtr();
}

DartIsolate::DartIsolate(const Settings& settings,
                         TaskRunners task_runners,
                         fml::WeakPtr<SnapshotDelegate> snapshot_delegate,
                         fml::WeakPtr<IOManager> io_manager,
                         fml::RefPtr<SkiaUnrefQueue> unref_queue,
                         fml::WeakPtr<ImageDecoder> image_decoder,
                         std::string advisory_script_uri,
                         std::string advisory_script_entrypoint,
                         bool is_root_isolate)
    : UIDartState(std::move(task_runners),
                  settings.task_observer_add,
                  settings.task_observer_remove,
                  std::move(snapshot_delegate),
                  std::move(io_manager),
                  std::move(unref_queue),
                  std::move(image_decoder),
                  advisory_script_uri,
                  advisory_script_entrypoint,
                  settings.log_tag,
                  settings.unhandled_exception_callback,
                  DartVMRef::GetIsolateNameServer()),
      is_root_isolate_(is_root_isolate) {
  phase_ = Phase::Uninitialized;
}

DartIsolate::~DartIsolate() {
  if (IsRootIsolate() && GetMessageHandlingTaskRunner()) {
    FML_DCHECK(GetMessageHandlingTaskRunner()->RunsTasksOnCurrentThread());
  }
}

DartIsolate::Phase DartIsolate::GetPhase() const {
  return phase_;
}

std::string DartIsolate::GetServiceId() {
  const char* service_id_buf = Dart_IsolateServiceId(isolate());
  std::string service_id(service_id_buf);
  free(const_cast<char*>(service_id_buf));
  return service_id;
}

bool DartIsolate::Initialize(Dart_Isolate dart_isolate) {
  TRACE_EVENT0("flutter", "DartIsolate::Initialize");
  if (phase_ != Phase::Uninitialized) {
    return false;
  }

  if (dart_isolate == nullptr) {
    return false;
  }

  if (Dart_CurrentIsolate() != dart_isolate) {
    return false;
  }

  // After this point, isolate scopes can be safely used.
  SetIsolate(dart_isolate);

  // We are entering a new scope (for the first time since initialization) and
  // we want to restore the current scope to null when we exit out of this
  // method. This balances the implicit Dart_EnterIsolate call made by
  // Dart_CreateIsolateGroup (which calls the Initialize).
  Dart_ExitIsolate();

  tonic::DartIsolateScope scope(isolate());

  SetMessageHandlingTaskRunner(GetTaskRunners().GetUITaskRunner());

  if (tonic::LogIfError(
          Dart_SetLibraryTagHandler(tonic::DartState::HandleLibraryTag))) {
    return false;
  }

  if (!UpdateThreadPoolNames()) {
    return false;
  }

  phase_ = Phase::Initialized;
  return true;
}

fml::RefPtr<fml::TaskRunner> DartIsolate::GetMessageHandlingTaskRunner() const {
  return message_handling_task_runner_;
}

void DartIsolate::SetMessageHandlingTaskRunner(
    fml::RefPtr<fml::TaskRunner> runner) {
  if (!IsRootIsolate() || !runner) {
    return;
  }

  message_handling_task_runner_ = runner;

  message_handler().Initialize(
      [runner](std::function<void()> task) { runner->PostTask(task); });
}

// Updating thread names here does not change the underlying OS thread names.
// Instead, this is just additional metadata for the Observatory to show the
// thread name of the isolate.
bool DartIsolate::UpdateThreadPoolNames() const {
  // TODO(chinmaygarde): This implementation does not account for multiple
  // shells sharing the same (or subset of) threads.
  const auto& task_runners = GetTaskRunners();

  if (auto task_runner = task_runners.GetGPUTaskRunner()) {
    task_runner->PostTask(
        [label = task_runners.GetLabel() + std::string{".gpu"}]() {
          Dart_SetThreadName(label.c_str());
        });
  }

  if (auto task_runner = task_runners.GetUITaskRunner()) {
    task_runner->PostTask(
        [label = task_runners.GetLabel() + std::string{".ui"}]() {
          Dart_SetThreadName(label.c_str());
        });
  }

  if (auto task_runner = task_runners.GetIOTaskRunner()) {
    task_runner->PostTask(
        [label = task_runners.GetLabel() + std::string{".io"}]() {
          Dart_SetThreadName(label.c_str());
        });
  }

  if (auto task_runner = task_runners.GetPlatformTaskRunner()) {
    task_runner->PostTask(
        [label = task_runners.GetLabel() + std::string{".platform"}]() {
          Dart_SetThreadName(label.c_str());
        });
  }

  return true;
}

bool DartIsolate::LoadLibraries() {
  TRACE_EVENT0("flutter", "DartIsolate::LoadLibraries");
  if (phase_ != Phase::Initialized) {
    return false;
  }

  tonic::DartState::Scope scope(this);

  DartIO::InitForIsolate();

  DartUI::InitForIsolate(IsRootIsolate());

  const bool is_service_isolate = Dart_IsServiceIsolate(isolate());

  DartRuntimeHooks::Install(IsRootIsolate() && !is_service_isolate,
                            GetAdvisoryScriptURI());

  if (!is_service_isolate) {
    class_library().add_provider(
        "ui", std::make_unique<tonic::DartClassProvider>(this, "dart:ui"));
  }

  phase_ = Phase::LibrariesSetup;
  return true;
}

bool DartIsolate::PrepareForRunningFromPrecompiledCode() {
  TRACE_EVENT0("flutter", "DartIsolate::PrepareForRunningFromPrecompiledCode");
  if (phase_ != Phase::LibrariesSetup) {
    return false;
  }

  tonic::DartState::Scope scope(this);

  if (Dart_IsNull(Dart_RootLibrary())) {
    return false;
  }

  if (!MarkIsolateRunnable()) {
    return false;
  }

  GetIsolateGroupData().SetChildIsolatePreparer([](DartIsolate* isolate) {
    return isolate->PrepareForRunningFromPrecompiledCode();
  });

  const fml::closure& isolate_create_callback =
      GetIsolateGroupData().GetIsolateCreateCallback();
  if (isolate_create_callback) {
    isolate_create_callback();
  }

  phase_ = Phase::Ready;
  return true;
}

bool DartIsolate::LoadKernel(std::shared_ptr<const fml::Mapping> mapping,
                             bool last_piece) {
  if (!Dart_IsKernel(mapping->GetMapping(), mapping->GetSize())) {
    return false;
  }

  // Mapping must be retained until isolate shutdown.
  kernel_buffers_.push_back(mapping);

  Dart_Handle library =
      Dart_LoadLibraryFromKernel(mapping->GetMapping(), mapping->GetSize());
  if (tonic::LogIfError(library)) {
    return false;
  }

  if (!last_piece) {
    // More to come.
    return true;
  }

  Dart_SetRootLibrary(library);
  if (tonic::LogIfError(Dart_FinalizeLoading(false))) {
    return false;
  }
  return true;
}

FML_WARN_UNUSED_RESULT
bool DartIsolate::PrepareForRunningFromKernel(
    std::shared_ptr<const fml::Mapping> mapping,
    bool last_piece) {
  TRACE_EVENT0("flutter", "DartIsolate::PrepareForRunningFromKernel");
  if (phase_ != Phase::LibrariesSetup) {
    return false;
  }

  if (DartVM::IsRunningPrecompiledCode()) {
    return false;
  }

  if (!mapping || mapping->GetSize() == 0) {
    return false;
  }

  tonic::DartState::Scope scope(this);

  // Use root library provided by kernel in favor of one provided by snapshot.
  Dart_SetRootLibrary(Dart_Null());

  if (!LoadKernel(mapping, last_piece)) {
    return false;
  }

  if (!last_piece) {
    // More to come.
    return true;
  }

  if (Dart_IsNull(Dart_RootLibrary())) {
    return false;
  }

  if (!MarkIsolateRunnable()) {
    return false;
  }

  // Child isolate shares root isolate embedder_isolate (lines 691 and 693
  // below). Re-initializing child_isolate_preparer_ lambda while it is being
  // executed leads to crashes.
  if (GetIsolateGroupData().GetChildIsolatePreparer() == nullptr) {
    GetIsolateGroupData().SetChildIsolatePreparer(
        [buffers = kernel_buffers_](DartIsolate* isolate) {
          for (unsigned long i = 0; i < buffers.size(); i++) {
            bool last_piece = i + 1 == buffers.size();
            const std::shared_ptr<const fml::Mapping>& buffer = buffers.at(i);
            if (!isolate->PrepareForRunningFromKernel(buffer, last_piece)) {
              return false;
            }
          }
          return true;
        });
  }

  const fml::closure& isolate_create_callback =
      GetIsolateGroupData().GetIsolateCreateCallback();
  if (isolate_create_callback) {
    isolate_create_callback();
  }

  phase_ = Phase::Ready;

  return true;
}

FML_WARN_UNUSED_RESULT
bool DartIsolate::PrepareForRunningFromKernels(
    std::vector<std::shared_ptr<const fml::Mapping>> kernels) {
  const auto count = kernels.size();
  if (count == 0) {
    return false;
  }

  for (size_t i = 0; i < count; ++i) {
    bool last = (i == (count - 1));
    if (!PrepareForRunningFromKernel(kernels[i], last)) {
      return false;
    }
  }

  return true;
}

FML_WARN_UNUSED_RESULT
bool DartIsolate::PrepareForRunningFromKernels(
    std::vector<std::unique_ptr<const fml::Mapping>> kernels) {
  std::vector<std::shared_ptr<const fml::Mapping>> shared_kernels;
  for (auto& kernel : kernels) {
    shared_kernels.emplace_back(std::move(kernel));
  }
  return PrepareForRunningFromKernels(shared_kernels);
}

bool DartIsolate::MarkIsolateRunnable() {
  TRACE_EVENT0("flutter", "DartIsolate::MarkIsolateRunnable");
  if (phase_ != Phase::LibrariesSetup) {
    return false;
  }

  // This function may only be called from an active isolate scope.
  if (Dart_CurrentIsolate() != isolate()) {
    return false;
  }

  // There must be no current isolate to mark an isolate as being runnable.
  Dart_ExitIsolate();

  char* error = Dart_IsolateMakeRunnable(isolate());
  if (error) {
    FML_DLOG(ERROR) << error;
    ::free(error);
    // Failed. Restore the isolate.
    Dart_EnterIsolate(isolate());
    return false;
  }
  // Success. Restore the isolate.
  Dart_EnterIsolate(isolate());
  return true;
}

FML_WARN_UNUSED_RESULT
static bool InvokeMainEntrypoint(Dart_Handle user_entrypoint_function,
                                 Dart_Handle args) {
  if (tonic::LogIfError(user_entrypoint_function)) {
    FML_LOG(ERROR) << "Could not resolve main entrypoint function.";
    return false;
  }

  Dart_Handle start_main_isolate_function =
      tonic::DartInvokeField(Dart_LookupLibrary(tonic::ToDart("dart:isolate")),
                             "_getStartMainIsolateFunction", {});

  if (tonic::LogIfError(start_main_isolate_function)) {
    FML_LOG(ERROR) << "Could not resolve main entrypoint trampoline.";
    return false;
  }

  if (tonic::LogIfError(tonic::DartInvokeField(
          Dart_LookupLibrary(tonic::ToDart("dart:ui")), "_runMainZoned",
          {start_main_isolate_function, user_entrypoint_function, args}))) {
    FML_LOG(ERROR) << "Could not invoke the main entrypoint.";
    return false;
  }

  return true;
}

/// @note Procedure doesn't copy all closures.
FML_WARN_UNUSED_RESULT
bool DartIsolate::Run(const std::string& entrypoint_name,
                      const std::vector<std::string>& args,
                      const fml::closure& on_run) {
  TRACE_EVENT0("flutter", "DartIsolate::Run");
  if (phase_ != Phase::Ready) {
    return false;
  }

  tonic::DartState::Scope scope(this);

  auto user_entrypoint_function =
      Dart_GetField(Dart_RootLibrary(), tonic::ToDart(entrypoint_name.c_str()));

  auto entrypoint_args = tonic::ToDart(args);

  if (!InvokeMainEntrypoint(user_entrypoint_function, entrypoint_args)) {
    return false;
  }

  phase_ = Phase::Running;
  FML_DLOG(INFO) << "New isolate is in the running state.";

  if (on_run) {
    on_run();
  }
  return true;
}

/// @note Procedure doesn't copy all closures.
FML_WARN_UNUSED_RESULT
bool DartIsolate::RunFromLibrary(const std::string& library_name,
                                 const std::string& entrypoint_name,
                                 const std::vector<std::string>& args,
                                 const fml::closure& on_run) {
  TRACE_EVENT0("flutter", "DartIsolate::RunFromLibrary");
  if (phase_ != Phase::Ready) {
    return false;
  }

  tonic::DartState::Scope scope(this);

  auto user_entrypoint_function =
      Dart_GetField(Dart_LookupLibrary(tonic::ToDart(library_name.c_str())),
                    tonic::ToDart(entrypoint_name.c_str()));

  auto entrypoint_args = tonic::ToDart(args);

  if (!InvokeMainEntrypoint(user_entrypoint_function, entrypoint_args)) {
    return false;
  }

  phase_ = Phase::Running;
  FML_DLOG(INFO) << "New isolate is in the running state.";

  if (on_run) {
    on_run();
  }
  return true;
}

bool DartIsolate::Shutdown() {
  TRACE_EVENT0("flutter", "DartIsolate::Shutdown");
  // This call may be re-entrant since Dart_ShutdownIsolate can invoke the
  // cleanup callback which deletes the embedder side object of the dart isolate
  // (a.k.a. this).
  if (phase_ == Phase::Shutdown) {
    return false;
  }
  phase_ = Phase::Shutdown;
  Dart_Isolate vm_isolate = isolate();
  // The isolate can be nullptr if this instance is the stub isolate data used
  // during root isolate creation.
  if (vm_isolate != nullptr) {
    // We need to enter the isolate because Dart_ShutdownIsolate does not take
    // the isolate to shutdown as a parameter.
    FML_DCHECK(Dart_CurrentIsolate() == nullptr);
    Dart_EnterIsolate(vm_isolate);
    Dart_ShutdownIsolate();
    FML_DCHECK(Dart_CurrentIsolate() == nullptr);
  }
  return true;
}

Dart_Isolate DartIsolate::DartCreateAndStartServiceIsolate(
    const char* package_root,
    const char* package_config,
    Dart_IsolateFlags* flags,
    char** error) {
  auto vm_data = DartVMRef::GetVMData();

  if (!vm_data) {
    *error = strdup(
        "Could not access VM data to initialize isolates. This may be because "
        "the VM has initialized shutdown on another thread already.");
    return nullptr;
  }

  const auto& settings = vm_data->GetSettings();

  if (!settings.enable_observatory) {
    FML_DLOG(INFO) << "Observatory is disabled.";
    return nullptr;
  }

  TaskRunners null_task_runners("io.flutter." DART_VM_SERVICE_ISOLATE_NAME,
                                nullptr, nullptr, nullptr, nullptr);

  flags->load_vmservice_library = true;

  std::weak_ptr<DartIsolate> weak_service_isolate =
      DartIsolate::CreateRootIsolate(
          vm_data->GetSettings(),         // settings
          vm_data->GetIsolateSnapshot(),  // isolate snapshot
          null_task_runners,              // task runners
          nullptr,                        // window
          {},                             // snapshot delegate
          {},                             // IO Manager
          {},                             // Skia unref queue
          {},                             // Image Decoder
          DART_VM_SERVICE_ISOLATE_NAME,   // script uri
          DART_VM_SERVICE_ISOLATE_NAME,   // script entrypoint
          flags,                          // flags
          nullptr,                        // isolate create callback
          nullptr                         // isolate shutdown callback
      );

  std::shared_ptr<DartIsolate> service_isolate = weak_service_isolate.lock();
  if (!service_isolate) {
    *error = strdup("Could not create the service isolate.");
    FML_DLOG(ERROR) << *error;
    return nullptr;
  }

  tonic::DartState::Scope scope(service_isolate);
  if (!DartServiceIsolate::Startup(
          settings.observatory_host,           // server IP address
          settings.observatory_port,           // server observatory port
          tonic::DartState::HandleLibraryTag,  // embedder library tag handler
          false,  //  disable websocket origin check
          settings.disable_service_auth_codes,  // disable VM service auth codes
          error                                 // error (out)
          )) {
    // Error is populated by call to startup.
    FML_DLOG(ERROR) << *error;
    return nullptr;
  }

  if (auto service_protocol = DartVMRef::GetServiceProtocol()) {
    service_protocol->ToggleHooks(true);
  } else {
    FML_DLOG(ERROR)
        << "Could not acquire the service protocol handlers. This might be "
           "because the VM has already begun teardown on another thread.";
  }

  return service_isolate->isolate();
}

DartIsolateGroupData& DartIsolate::GetIsolateGroupData() {
  std::shared_ptr<DartIsolateGroupData>* isolate_group_data =
      static_cast<std::shared_ptr<DartIsolateGroupData>*>(
          Dart_IsolateGroupData(isolate()));
  return **isolate_group_data;
}

// |Dart_IsolateGroupCreateCallback|
Dart_Isolate DartIsolate::DartIsolateGroupCreateCallback(
    const char* advisory_script_uri,
    const char* advisory_script_entrypoint,
    const char* package_root,
    const char* package_config,
    Dart_IsolateFlags* flags,
    std::shared_ptr<DartIsolate>* parent_isolate_data,
    char** error) {
  TRACE_EVENT0("flutter", "DartIsolate::DartIsolateGroupCreateCallback");
  if (parent_isolate_data == nullptr &&
      strcmp(advisory_script_uri, DART_VM_SERVICE_ISOLATE_NAME) == 0) {
    // The VM attempts to start the VM service for us on |Dart_Initialize|. In
    // such a case, the callback data will be null and the script URI will be
    // DART_VM_SERVICE_ISOLATE_NAME. In such cases, we just create the service
    // isolate like normal but dont hold a reference to it at all. We also start
    // this isolate since we will never again reference it from the engine.
    return DartCreateAndStartServiceIsolate(package_root,    //
                                            package_config,  //
                                            flags,           //
                                            error            //
    );
  }

  DartIsolateGroupData& parent_group_data =
      (*parent_isolate_data)->GetIsolateGroupData();

  auto isolate_group_data =
      std::make_unique<std::shared_ptr<DartIsolateGroupData>>(
          std::shared_ptr<DartIsolateGroupData>(new DartIsolateGroupData(
              parent_group_data.GetSettings(),
              parent_group_data.GetIsolateSnapshot(), advisory_script_uri,
              advisory_script_entrypoint,
              parent_group_data.GetChildIsolatePreparer(),
              parent_group_data.GetIsolateCreateCallback(),
              parent_group_data.GetIsolateShutdownCallback())));

  TaskRunners null_task_runners(advisory_script_uri,
                                /* platform= */ nullptr, /* gpu= */ nullptr,
                                /* ui= */ nullptr,
                                /* io= */ nullptr);

  auto isolate_data = std::make_unique<std::shared_ptr<DartIsolate>>(
      std::shared_ptr<DartIsolate>(new DartIsolate(
          (*isolate_group_data)->GetSettings(),  // settings
          null_task_runners,                     // task_runners
          fml::WeakPtr<SnapshotDelegate>{},      // snapshot_delegate
          fml::WeakPtr<IOManager>{},             // io_manager
          fml::RefPtr<SkiaUnrefQueue>{},         // unref_queue
          fml::WeakPtr<ImageDecoder>{},          // image_decoder
          advisory_script_uri,                   // advisory_script_uri
          advisory_script_entrypoint,            // advisory_script_entrypoint
          false)));                              // is_root_isolate

  Dart_Isolate vm_isolate = CreateDartIsolateGroup(
      std::move(isolate_group_data), std::move(isolate_data), flags, error);

  if (*error) {
    FML_LOG(ERROR) << "CreateDartIsolateGroup failed: " << error;
  }

  return vm_isolate;
}

// |Dart_IsolateInitializeCallback|
bool DartIsolate::DartIsolateInitializeCallback(void** child_callback_data,
                                                char** error) {
  TRACE_EVENT0("flutter", "DartIsolate::DartIsolateInitializeCallback");
  Dart_Isolate isolate = Dart_CurrentIsolate();
  if (isolate == nullptr) {
    *error = strdup("Isolate should be available in initialize callback.");
    FML_DLOG(ERROR) << *error;
    return false;
  }

  auto* isolate_group_data =
      static_cast<std::shared_ptr<DartIsolateGroupData>*>(
          Dart_CurrentIsolateGroupData());

  TaskRunners null_task_runners((*isolate_group_data)->GetAdvisoryScriptURI(),
                                /* platform= */ nullptr, /* gpu= */ nullptr,
                                /* ui= */ nullptr,
                                /* io= */ nullptr);

  auto embedder_isolate = std::make_unique<std::shared_ptr<DartIsolate>>(
      std::shared_ptr<DartIsolate>(new DartIsolate(
          (*isolate_group_data)->GetSettings(),           // settings
          null_task_runners,                              // task_runners
          fml::WeakPtr<SnapshotDelegate>{},               // snapshot_delegate
          fml::WeakPtr<IOManager>{},                      // io_manager
          fml::RefPtr<SkiaUnrefQueue>{},                  // unref_queue
          fml::WeakPtr<ImageDecoder>{},                   // image_decoder
          (*isolate_group_data)->GetAdvisoryScriptURI(),  // advisory_script_uri
          (*isolate_group_data)
              ->GetAdvisoryScriptEntrypoint(),  // advisory_script_entrypoint
          false)));                             // is_root_isolate

  // root isolate should have been created via CreateRootIsolate
  if (!InitializeIsolate(*embedder_isolate, isolate, error)) {
    return false;
  }

  // The ownership of the embedder object is controlled by the Dart VM. So the
  // only reference returned to the caller is weak.
  *child_callback_data = embedder_isolate.release();

  Dart_EnterIsolate(isolate);
  return true;
}

Dart_Isolate DartIsolate::CreateDartIsolateGroup(
    std::unique_ptr<std::shared_ptr<DartIsolateGroupData>> isolate_group_data,
    std::unique_ptr<std::shared_ptr<DartIsolate>> isolate_data,
    Dart_IsolateFlags* flags,
    char** error) {
  TRACE_EVENT0("flutter", "DartIsolate::CreateDartIsolateGroup");

  // Create the Dart VM isolate and give it the embedder object as the baton.
  Dart_Isolate isolate = Dart_CreateIsolateGroup(
      (*isolate_group_data)->GetAdvisoryScriptURI().c_str(),
      (*isolate_group_data)->GetAdvisoryScriptEntrypoint().c_str(),
      (*isolate_group_data)->GetIsolateSnapshot()->GetDataMapping(),
      (*isolate_group_data)->GetIsolateSnapshot()->GetInstructionsMapping(),
      flags, isolate_group_data.get(), isolate_data.get(), error);

  if (isolate == nullptr) {
    return nullptr;
  }

  // Ownership of the isolate data objects has been transferred to the Dart VM.
  std::shared_ptr<DartIsolate> embedder_isolate(*isolate_data);
  isolate_group_data.release();
  isolate_data.release();

  if (!InitializeIsolate(std::move(embedder_isolate), isolate, error)) {
    return nullptr;
  }

  return isolate;
}

bool DartIsolate::InitializeIsolate(
    std::shared_ptr<DartIsolate> embedder_isolate,
    Dart_Isolate isolate,
    char** error) {
  TRACE_EVENT0("flutter", "DartIsolate::InitializeIsolate");
  if (!embedder_isolate->Initialize(isolate)) {
    *error = strdup("Embedder could not initialize the Dart isolate.");
    FML_DLOG(ERROR) << *error;
    return false;
  }

  if (!embedder_isolate->LoadLibraries()) {
    *error =
        strdup("Embedder could not load libraries in the new Dart isolate.");
    FML_DLOG(ERROR) << *error;
    return false;
  }

  // Root isolates will be setup by the engine and the service isolate (which is
  // also a root isolate) by the utility routines in the VM. However, secondary
  // isolates will be run by the VM if they are marked as runnable.
  if (!embedder_isolate->IsRootIsolate()) {
    const ChildIsolatePreparer& child_isolate_preparer =
        embedder_isolate->GetIsolateGroupData().GetChildIsolatePreparer();
    FML_DCHECK(child_isolate_preparer);
    if (!child_isolate_preparer(embedder_isolate.get())) {
      *error = strdup("Could not prepare the child isolate to run.");
      FML_DLOG(ERROR) << *error;
      return false;
    }
  }

  return true;
}

// |Dart_IsolateShutdownCallback|
void DartIsolate::DartIsolateShutdownCallback(
    std::shared_ptr<DartIsolateGroupData>* isolate_group_data,
    std::shared_ptr<DartIsolate>* isolate_data) {
  TRACE_EVENT0("flutter", "DartIsolate::DartIsolateShutdownCallback");
  FML_DLOG(INFO) << "DartIsolateShutdownCallback"
                 << " isolate_group_data " << isolate_group_data
                 << " isolate_data " << isolate_data;
  isolate_data->get()->OnShutdownCallback();
}

// |Dart_IsolateGroupCleanupCallback|
void DartIsolate::DartIsolateGroupCleanupCallback(
    std::shared_ptr<DartIsolateGroupData>* isolate_data) {
  TRACE_EVENT0("flutter", "DartIsolate::DartIsolateGroupCleanupCallback");
  FML_DLOG(INFO) << "DartIsolateGroupCleanupCallback isolate_data "
                 << isolate_data;

  delete isolate_data;
}

// |Dart_IsolateCleanupCallback|
void DartIsolate::DartIsolateCleanupCallback(
    std::shared_ptr<DartIsolateGroupData>* isolate_group_data,
    std::shared_ptr<DartIsolate>* isolate_data) {
  TRACE_EVENT0("flutter", "DartIsolate::DartIsolateCleanupCallback");

  FML_DLOG(INFO) << "DartIsolateCleanupCallback cleaned up isolate_data "
                 << isolate_data;
  delete isolate_data;
}

std::weak_ptr<DartIsolate> DartIsolate::GetWeakIsolatePtr() {
  return std::static_pointer_cast<DartIsolate>(shared_from_this());
}

void DartIsolate::AddIsolateShutdownCallback(const fml::closure& closure) {
  shutdown_callbacks_.emplace_back(std::make_unique<AutoFireClosure>(closure));
}

void DartIsolate::OnShutdownCallback() {
  {
    tonic::DartApiScope api_scope;
    Dart_Handle sticky_error = Dart_GetStickyError();
    if (!Dart_IsNull(sticky_error) && !Dart_IsFatalError(sticky_error)) {
      FML_LOG(ERROR) << Dart_GetError(sticky_error);
    }
  }

  shutdown_callbacks_.clear();

  const fml::closure& isolate_shutdown_callback =
      GetIsolateGroupData().GetIsolateShutdownCallback();
  if (isolate_shutdown_callback) {
    isolate_shutdown_callback();
  }
}

DartIsolate::AutoFireClosure::AutoFireClosure(const fml::closure& closure)
    : closure_(closure) {}

DartIsolate::AutoFireClosure::~AutoFireClosure() {
  if (closure_) {
    closure_();
  }
}

}  // namespace flutter
