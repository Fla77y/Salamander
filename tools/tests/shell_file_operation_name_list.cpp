// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/shellfileopnames.h"

#include <array>
#include <cstdio>
#include <cstring>
#include <string>

static bool Check(bool condition, const char* description)
{
    if (!condition)
        std::fprintf(stderr, "FAIL: %s\n", description);
    return condition;
}

static bool AcceptsExactBoundaryAndDoubleTerminator()
{
    // Arrange
    std::array<char, 10> result;
    result.fill('X');

    // Act
    const bool accepted = BuildShellFileOperationNameList(
        "12345678", result.data(), result.size());

    // Assert
    return Check(accepted, "boundary path accepted") &&
           Check(std::memcmp(result.data(), "12345678\0\0", result.size()) == 0,
                 "boundary list has exactly two terminators");
}

static bool LeavesTrailingBufferUntouched()
{
    // Arrange
    std::array<char, 10> result;
    result.fill('X');

    // Act
    const bool accepted = BuildShellFileOperationNameList(
        "C:\\a", result.data(), result.size());

    // Assert
    return Check(accepted, "short path accepted") &&
           Check(std::strcmp(result.data(), "C:\\a") == 0,
                 "short path copied exactly") &&
           Check(result[4] == '\0' && result[5] == '\0' && result[6] == 'X',
                 "double NUL with untouched suffix");
}

static bool RejectsOversizeWithoutWrites()
{
    // Arrange
    std::array<char, 10> result;
    result.fill('X');

    // Act
    const bool accepted = BuildShellFileOperationNameList(
        "123456789", result.data(), result.size());

    // Assert
    if (!Check(!accepted, "overlong path rejected"))
        return false;
    for (char byte : result)
        if (!Check(byte == 'X', "destination unchanged on failure"))
            return false;
    return true;
}

static bool AcceptsLastValidMaxPathLength()
{
    // Arrange: MAX_PATH+1 bytes hold a 259-byte path and two NULs.
    std::array<char, 261> result;
    result.fill('X');
    const std::string source(259, 'a');

    // Act
    const bool accepted = BuildShellFileOperationNameList(
        source.c_str(), result.data(), result.size());

    // Assert
    return Check(accepted, "259-byte path fits 261-byte destination") &&
           Check(std::memcmp(result.data(), source.data(), source.size()) == 0,
                 "full boundary path copied") &&
           Check(result[259] == '\0' && result[260] == '\0',
                 "last two bytes are terminators");
}

static bool RejectsMaxPathBoundaryWithoutWrites()
{
    // Arrange: original worker allocated MAX_PATH+1 and wrote at [261]
    // for a 260-byte path. The regression uses that exact boundary.
    std::array<char, 261> result;
    result.fill('X');
    const std::string source(260, 'a');

    // Act
    const bool accepted = BuildShellFileOperationNameList(
        source.c_str(), result.data(), result.size());

    // Assert
    if (!Check(!accepted, "260-byte path must not overrun 261-byte buffer"))
        return false;
    for (char byte : result)
        if (!Check(byte == 'X', "MAX_PATH failure preserves destination"))
            return false;
    return true;
}

static bool RejectsInvalidArgumentsWithoutWrites()
{
    // Arrange
    std::array<char, 4> result;
    result.fill('X');

    // Act
    const bool nullPath = BuildShellFileOperationNameList(
        nullptr, result.data(), result.size());
    const bool emptyPath = BuildShellFileOperationNameList(
        "", result.data(), result.size());
    const bool nullDestination = BuildShellFileOperationNameList(
        "a", nullptr, result.size());
    const bool insufficientCapacity = BuildShellFileOperationNameList(
        "a", result.data(), 2);

    // Assert
    if (!Check(!nullPath && !emptyPath && !nullDestination &&
               !insufficientCapacity, "invalid arguments rejected"))
        return false;
    for (char byte : result)
        if (!Check(byte == 'X', "invalid input leaves destination intact"))
            return false;
    return true;
}

int main()
{
    if (!AcceptsExactBoundaryAndDoubleTerminator() ||
        !LeavesTrailingBufferUntouched() ||
        !RejectsOversizeWithoutWrites() ||
        !AcceptsLastValidMaxPathLength() ||
        !RejectsMaxPathBoundaryWithoutWrites() ||
        !RejectsInvalidArgumentsWithoutWrites())
        return 1;

    std::puts("PASS: shell recycle name list rejects overflow and preserves double terminator");
    return 0;
}
