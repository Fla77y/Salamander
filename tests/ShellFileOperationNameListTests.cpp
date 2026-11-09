// SPDX-FileCopyrightText: 2026 Open Salamander contributors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../src/common/shellfileopnames.h"

#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>

// Reports a failed assertion even in Release builds where assert is disabled.
static void Check(bool condition, const char* message)
{
    if (!condition)
        throw std::runtime_error(message);
}

// Verifies that ordinary paths receive the required double terminator.
static void CopiesValidPathAndAppendsDoubleNull()
{
    // Arrange
    std::array<char, 10> destination{};
    destination.fill('X');

    // Act
    const bool success = BuildShellFileOperationNameList("C:\\a", destination.data(), destination.size());

    // Assert
    Check(success, "Expected a valid path to fit");
    Check(std::strcmp(destination.data(), "C:\\a") == 0, "Incorrect copied path");
    Check(destination[4] == '\0' && destination[5] == '\0', "Missing double terminator");
    Check(destination[6] == 'X', "Unexpected write beyond the terminator");
}

// Verifies that the final two available bytes can both be terminators.
static void AcceptsBoundaryLength()
{
    // Arrange
    std::array<char, 10> destination{};
    destination.fill('X');

    // Act
    const bool success = BuildShellFileOperationNameList("12345678", destination.data(), destination.size());

    // Assert
    Check(success, "Boundary-length path was rejected");
    Check(destination[8] == '\0' && destination[9] == '\0', "Boundary terminators missing");
}

// Verifies that oversized paths are rejected without modifying the destination.
static void RejectsOversizedPathWithoutOverflow()
{
    // Arrange
    std::array<char, 10> destination{};
    destination.fill('X');

    // Act
    const bool success = BuildShellFileOperationNameList("123456789", destination.data(), destination.size());

    // Assert
    Check(!success, "Oversized path was accepted");
    for (char byte : destination)
        Check(byte == 'X', "Buffer modified after rejection");
}

// Verifies that invalid parameters do not change memory.
static void RejectsInvalidInputs()
{
    // Arrange
    std::array<char, 4> destination{};
    destination.fill('X');

    // Act
    const bool nullPath = BuildShellFileOperationNameList(nullptr, destination.data(), destination.size());
    const bool emptyPath = BuildShellFileOperationNameList("", destination.data(), destination.size());
    const bool nullDestination = BuildShellFileOperationNameList("abc", nullptr, destination.size());
    const bool tinyDestination = BuildShellFileOperationNameList("abc", destination.data(), 1);

    // Assert
    Check(!nullPath && !emptyPath && !nullDestination && !tinyDestination, "Invalid argument accepted");
    for (char byte : destination)
        Check(byte == 'X', "Buffer modified after invalid argument");
}

// Runs the standalone regression tests and returns a nonzero exit status on failure.
int main()
{
    try
    {
        CopiesValidPathAndAppendsDoubleNull();
        AcceptsBoundaryLength();
        RejectsOversizedPathWithoutOverflow();
        RejectsInvalidInputs();
        std::cout << "ShellFileOperationNameListTests: PASS\n";
        return 0;
    }
    catch (const std::exception& error)
    {
        std::cerr << "ShellFileOperationNameListTests: FAIL: " << error.what() << '\n';
        return 1;
    }
}
