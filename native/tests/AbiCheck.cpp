#include <Windows.h>
#include <stddef.h>

// Verify the managed explicit ABI offsets against the actual Windows SDK,
// without making any power changes or starting the application.
static_assert(sizeof(SYSTEM_POWER_CAPABILITIES) == 76, "SYSTEM_POWER_CAPABILITIES size mismatch");
static_assert(offsetof(SYSTEM_POWER_CAPABILITIES, LidPresent) == 2, "LidPresent ABI mismatch");
static_assert(offsetof(SYSTEM_POWER_CAPABILITIES, HiberFilePresent) == 8, "HiberFilePresent ABI mismatch");
static_assert(offsetof(SYSTEM_POWER_CAPABILITIES, AoAc) == 20, "AoAc ABI mismatch");
static_assert(offsetof(SYSTEM_POWER_CAPABILITIES, SystemBatteriesPresent) == 30, "SystemBatteriesPresent ABI mismatch");
static_assert(sizeof(SYSTEM_POWER_STATUS) == 12, "SYSTEM_POWER_STATUS size mismatch");
