// Regression checks for null-terminated quick-search buffers.
// Compile with MSVC as a standalone C++17 program.
#include "../../src/common/buffer_bounds.h"

using Salamander::CanAppendNullTerminatedCharacter;

static_assert(!CanAppendNullTerminatedCharacter(0, 0));
static_assert(!CanAppendNullTerminatedCharacter(0, 1));
static_assert(CanAppendNullTerminatedCharacter(0, 2));
static_assert(!CanAppendNullTerminatedCharacter(1, 2));
static_assert(CanAppendNullTerminatedCharacter(258, 260));
static_assert(!CanAppendNullTerminatedCharacter(259, 260));
static_assert(!CanAppendNullTerminatedCharacter(260, 260));
static_assert(!CanAppendNullTerminatedCharacter(static_cast<std::size_t>(-1), 260));

int main()
{
    return CanAppendNullTerminatedCharacter(0, 260) ? 0 : 1;
}
