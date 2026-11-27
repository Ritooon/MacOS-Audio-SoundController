#ifndef ORPHEUS_ATOMICS_H
#define ORPHEUS_ATOMICS_H

#include <stdint.h>

/// Lock-free 32-bit load and store, used to pass parameters (such as a gain stored as a
/// float bit pattern) between the main thread and the real-time audio thread.
/// Swift cannot use C11 `_Atomic` types directly, so these wrap the clang atomic builtins.

static inline uint32_t orpheus_atomic_load_u32(const uint32_t *pointer) {
    return __atomic_load_n(pointer, __ATOMIC_ACQUIRE);
}

static inline void orpheus_atomic_store_u32(uint32_t *pointer, uint32_t value) {
    __atomic_store_n(pointer, value, __ATOMIC_RELEASE);
}

#endif
