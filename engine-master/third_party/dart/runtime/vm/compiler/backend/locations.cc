// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#if !defined(DART_PRECOMPILED_RUNTIME)

#include "vm/compiler/backend/locations.h"

#include "vm/compiler/assembler/assembler.h"
#include "vm/compiler/backend/il_printer.h"
#include "vm/log.h"
#include "vm/stack_frame.h"

namespace dart {

intptr_t RegisterSet::RegisterCount(intptr_t registers) {
  // Brian Kernighan's algorithm for counting the bits set.
  intptr_t count = 0;
  while (registers != 0) {
    ++count;
    registers &= (registers - 1);  // Clear the least significant bit set.
  }
  return count;
}

void RegisterSet::DebugPrint() {
  for (intptr_t i = 0; i < kNumberOfCpuRegisters; i++) {
    Register r = static_cast<Register>(i);
    if (ContainsRegister(r)) {
      THR_Print("%s %s\n", RegisterNames::RegisterName(r),
                IsTagged(r) ? "tagged" : "untagged");
    }
  }

  for (intptr_t i = 0; i < kNumberOfFpuRegisters; i++) {
    FpuRegister r = static_cast<FpuRegister>(i);
    if (ContainsFpuRegister(r)) {
      THR_Print("%s\n", RegisterNames::FpuRegisterName(r));
    }
  }
}

LocationSummary::LocationSummary(Zone* zone,
                                 intptr_t input_count,
                                 intptr_t temp_count,
                                 LocationSummary::ContainsCall contains_call)
    : num_inputs_(input_count),
      num_temps_(temp_count),
      stack_bitmap_(NULL),
      contains_call_(contains_call),
      live_registers_() {
#if defined(DEBUG)
  writable_inputs_ = 0;
#endif
  input_locations_ = zone->Alloc<Location>(num_inputs_);
  temp_locations_ = zone->Alloc<Location>(num_temps_);
}

LocationSummary* LocationSummary::Make(
    Zone* zone,
    intptr_t input_count,
    Location out,
    LocationSummary::ContainsCall contains_call) {
  LocationSummary* summary =
      new (zone) LocationSummary(zone, input_count, 0, contains_call);
  for (intptr_t i = 0; i < input_count; i++) {
    summary->set_in(i, Location::RequiresRegister());
  }
  summary->set_out(0, out);
  return summary;
}

template <class Register, class FpuRegister>
TemplateLocation<Register, FpuRegister>
TemplateLocation<Register, FpuRegister>::Pair(
    TemplateLocation<Register, FpuRegister> first,
    TemplateLocation<Register, FpuRegister> second) {
  TemplatePairLocation<TemplateLocation<Register, FpuRegister>>* pair_location =
      new TemplatePairLocation<TemplateLocation<Register, FpuRegister>>();
  ASSERT((reinterpret_cast<intptr_t>(pair_location) & kLocationTagMask) == 0);
  pair_location->SetAt(0, first);
  pair_location->SetAt(1, second);
  TemplateLocation<Register, FpuRegister> loc(
      reinterpret_cast<uword>(pair_location) | kPairLocationTag);
  return loc;
}

template <class Register, class FpuRegister>
TemplatePairLocation<TemplateLocation<Register, FpuRegister>>*
TemplateLocation<Register, FpuRegister>::AsPairLocation() const {
  ASSERT(IsPairLocation());
  return reinterpret_cast<
      TemplatePairLocation<TemplateLocation<Register, FpuRegister>>*>(
      value_ & ~kLocationTagMask);
}

Location LocationRegisterOrConstant(Value* value) {
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) && compiler::Assembler::IsSafe(constant->value()))
             ? Location::Constant(constant)
             : Location::RequiresRegister();
}

Location LocationRegisterOrSmiConstant(Value* value) {
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) &&
          compiler::Assembler::IsSafeSmi(constant->value()))
             ? Location::Constant(constant)
             : Location::RequiresRegister();
}

Location LocationWritableRegisterOrSmiConstant(Value* value) {
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) &&
          compiler::Assembler::IsSafeSmi(constant->value()))
             ? Location::Constant(constant)
             : Location::WritableRegister();
}

Location LocationFixedRegisterOrConstant(Value* value, Register reg) {
  ASSERT(((1 << reg) & kDartAvailableCpuRegs) != 0);
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) && compiler::Assembler::IsSafe(constant->value()))
             ? Location::Constant(constant)
             : Location::RegisterLocation(reg);
}

Location LocationFixedRegisterOrSmiConstant(Value* value, Register reg) {
  ASSERT(((1 << reg) & kDartAvailableCpuRegs) != 0);
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) &&
          compiler::Assembler::IsSafeSmi(constant->value()))
             ? Location::Constant(constant)
             : Location::RegisterLocation(reg);
}

Location LocationAnyOrConstant(Value* value) {
  ConstantInstr* constant = value->definition()->AsConstant();
  return ((constant != NULL) && compiler::Assembler::IsSafe(constant->value()))
             ? Location::Constant(constant)
             : Location::Any();
}

compiler::Address LocationToStackSlotAddress(Location loc) {
  return compiler::Address(loc.base_reg(), loc.ToStackSlotOffset());
}

template <class Register, class FpuRegister>
intptr_t TemplateLocation<Register, FpuRegister>::ToStackSlotOffset() const {
  return stack_index() * compiler::target::kWordSize;
}

template <class Register, class FpuRegister>
const Object& TemplateLocation<Register, FpuRegister>::constant() const {
  return constant_instruction()->value();
}

template <class Register, class FpuRegister>
const char* TemplateLocation<Register, FpuRegister>::Name() const {
  switch (kind()) {
    case kInvalid:
      return "?";
    case kRegister:
      return RegisterNames::RegisterName(reg());
    case kFpuRegister:
      return RegisterNames::FpuRegisterName(fpu_reg());
    case kStackSlot:
      return "S";
    case kDoubleStackSlot:
      return "DS";
    case kQuadStackSlot:
      return "QS";
    case kUnallocated:
      switch (policy()) {
        case kAny:
          return "A";
        case kPrefersRegister:
          return "P";
        case kRequiresRegister:
          return "R";
        case kRequiresFpuRegister:
          return "DR";
        case kWritableRegister:
          return "WR";
        case kSameAsFirstInput:
          return "0";
      }
      UNREACHABLE();
    default:
      if (IsConstant()) {
        return "C";
      } else {
        ASSERT(IsPairLocation());
        return "2P";
      }
  }
  return "?";
}

template <class Register, class FpuRegister>
void TemplateLocation<Register, FpuRegister>::PrintTo(
    BufferFormatter* f) const {
  if (!FLAG_support_il_printer) {
    return;
  }
  if (kind() == kStackSlot) {
    f->Print("S%+" Pd "", stack_index());
  } else if (kind() == kDoubleStackSlot) {
    f->Print("DS%+" Pd "", stack_index());
  } else if (kind() == kQuadStackSlot) {
    f->Print("QS%+" Pd "", stack_index());
  } else if (IsPairLocation()) {
    f->Print("(");
    AsPairLocation()->At(0).PrintTo(f);
    f->Print(", ");
    AsPairLocation()->At(1).PrintTo(f);
    f->Print(")");
  } else {
    f->Print("%s", Name());
  }
}

template <class Register, class FpuRegister>
const char* TemplateLocation<Register, FpuRegister>::ToCString() const {
  char buffer[1024];
  BufferFormatter bf(buffer, 1024);
  PrintTo(&bf);
  return Thread::Current()->zone()->MakeCopyOfString(buffer);
}

template <class Register, class FpuRegister>
void TemplateLocation<Register, FpuRegister>::Print() const {
  if (kind() == kStackSlot) {
    THR_Print("S%+" Pd "", stack_index());
  } else {
    THR_Print("%s", Name());
  }
}

template <class Register, class FpuRegister>
TemplateLocation<Register, FpuRegister>
TemplateLocation<Register, FpuRegister>::Copy() const {
  if (IsPairLocation()) {
    TemplatePairLocation<TemplateLocation<Register, FpuRegister>>* pair =
        AsPairLocation();
    ASSERT(!pair->At(0).IsPairLocation());
    ASSERT(!pair->At(1).IsPairLocation());
    return TemplateLocation::Pair(pair->At(0).Copy(), pair->At(1).Copy());
  } else {
    // Copy by value.
    return *this;
  }
}

Location LocationArgumentsDescriptorLocation() {
  return Location::RegisterLocation(ARGS_DESC_REG);
}

Location LocationExceptionLocation() {
  return Location::RegisterLocation(kExceptionObjectReg);
}

Location LocationStackTraceLocation() {
  return Location::RegisterLocation(kStackTraceObjectReg);
}

Location LocationRemapForSlowPath(Location loc,
                                  Definition* def,
                                  intptr_t* cpu_reg_slots,
                                  intptr_t* fpu_reg_slots) {
  if (loc.IsRegister()) {
    intptr_t index = cpu_reg_slots[loc.reg()];
    ASSERT(index >= 0);
    return Location::StackSlot(
        compiler::target::frame_layout.FrameSlotForVariableIndex(-index),
        FPREG);
  } else if (loc.IsFpuRegister()) {
    intptr_t index = fpu_reg_slots[loc.fpu_reg()];
    ASSERT(index >= 0);
    switch (def->representation()) {
      case kUnboxedDouble:  // SlowPathEnvironmentFor sees _one_ register
      case kUnboxedFloat:   // both for doubles and floats.
        return Location::DoubleStackSlot(
            compiler::target::frame_layout.FrameSlotForVariableIndex(-index),
            FPREG);

      case kUnboxedFloat32x4:
      case kUnboxedInt32x4:
      case kUnboxedFloat64x2:
        return Location::QuadStackSlot(
            compiler::target::frame_layout.FrameSlotForVariableIndex(-index),
            FPREG);

      default:
        UNREACHABLE();
    }
  } else if (loc.IsPairLocation()) {
    ASSERT(def->representation() == kUnboxedInt64);
    PairLocation* value_pair = loc.AsPairLocation();
    intptr_t index_lo;
    intptr_t index_hi;

    if (value_pair->At(0).IsRegister()) {
      index_lo = compiler::target::frame_layout.FrameSlotForVariableIndex(
          -cpu_reg_slots[value_pair->At(0).reg()]);
    } else {
      ASSERT(value_pair->At(0).IsStackSlot());
      index_lo = value_pair->At(0).stack_index();
    }

    if (value_pair->At(1).IsRegister()) {
      index_hi = compiler::target::frame_layout.FrameSlotForVariableIndex(
          -cpu_reg_slots[value_pair->At(1).reg()]);
    } else {
      ASSERT(value_pair->At(1).IsStackSlot());
      index_hi = value_pair->At(1).stack_index();
    }

    return Location::Pair(Location::StackSlot(index_lo, FPREG),
                          Location::StackSlot(index_hi, FPREG));
  } else if (loc.IsInvalid() && def->IsMaterializeObject()) {
    def->AsMaterializeObject()->RemapRegisters(cpu_reg_slots, fpu_reg_slots);
    return loc;
  }

  return loc;
}

void LocationSummary::PrintTo(BufferFormatter* f) const {
  if (!FLAG_support_il_printer) {
    return;
  }
  if (input_count() > 0) {
    f->Print(" (");
    for (intptr_t i = 0; i < input_count(); i++) {
      if (i != 0) f->Print(", ");
      in(i).PrintTo(f);
    }
    f->Print(")");
  }

  if (temp_count() > 0) {
    f->Print(" [");
    for (intptr_t i = 0; i < temp_count(); i++) {
      if (i != 0) f->Print(", ");
      temp(i).PrintTo(f);
    }
    f->Print("]");
  }

  if (!out(0).IsInvalid()) {
    f->Print(" => ");
    out(0).PrintTo(f);
  }

  if (always_calls()) f->Print(" C");
}

#if defined(DEBUG)
void LocationSummary::DiscoverWritableInputs() {
  if (!HasCallOnSlowPath()) {
    return;
  }

  for (intptr_t i = 0; i < input_count(); i++) {
    if (in(i).IsUnallocated() &&
        (in(i).policy() == Location::kWritableRegister)) {
      writable_inputs_ |= 1 << i;
    }
  }
}

void LocationSummary::CheckWritableInputs() {
  ASSERT(HasCallOnSlowPath());
  for (intptr_t i = 0; i < input_count(); i++) {
    if ((writable_inputs_ & (1 << i)) != 0) {
      // Writable registers have to be manually preserved because
      // with the right representation because register allocator does not know
      // how they are used within the instruction template.
      ASSERT(in(i).IsMachineRegister());
      ASSERT(live_registers()->Contains(in(i)));
    }
  }
}
#endif

template class TemplateLocation<dart::Register, dart::FpuRegister>;
template class TemplatePairLocation<Location>;

#if !defined(HOST_ARCH_EQUALS_TARGET_ARCH)
template class TemplateLocation<dart::host::Register, dart::host::FpuRegister>;
template class TemplatePairLocation<HostLocation>;
#endif  // !defined(HOST_ARCH_EQUALS_TARGET_ARCH)

}  // namespace dart

#endif  // !defined(DART_PRECOMPILED_RUNTIME)
