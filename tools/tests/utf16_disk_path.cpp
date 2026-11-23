// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Portable C++17 contract tests. No Windows desktop or plugin ABI required.
#include "../../src/common/utf16_disk_path.h"

#include <cstdio>
#include <string>
#include <string_view>

using Salamander::Utf16DiskPath;
using Salamander::Utf16FileName;
using Salamander::Utf16PathError;

namespace
{
int Fail(const char* scenario)
{
    std::fprintf(stderr, "FAIL: %s\n", scenario);
    return 1;
}

bool NameAccepted(std::u16string_view input)
{
    Utf16FileName name;
    Utf16PathError error = Utf16PathError::InvalidInput;
    return Utf16FileName::TryCreate(input, name, error) &&
           error == Utf16PathError::None && name.Value() == input;
}

bool NameRejected(std::u16string_view input, Utf16PathError expected)
{
    Utf16FileName name;
    Utf16PathError error = Utf16PathError::None;
    return !Utf16FileName::TryCreate(input, name, error) &&
           error == expected && name.Value().empty();
}

bool PathRejected(std::u16string_view input, Utf16PathError expected)
{
    Utf16DiskPath path;
    Utf16PathError error = Utf16PathError::None;
    return !Utf16DiskPath::TryCreateAbsolute(input, path, error) &&
           error == expected && path.Value().empty();
}

bool FileName_WhenInputAliasesOutput_PreservesExactUtf16()
{
    // Arrange
    const std::u16string inputs[] = {u"東\U0001F600", std::u16string(251, u'東') + u".txt"};
    for (const auto& expected : inputs)
    {
        Utf16FileName name;
        Utf16PathError error;
        if (!Utf16FileName::TryCreate(expected, name, error))
            return false;
        // Act
        const bool accepted = Utf16FileName::TryCreate(name.Value(), name, error);
        // Assert
        if (!accepted || error != Utf16PathError::None || name.Value() != expected)
            return false;
    }
    return true;
}

bool DiskPath_WhenInputAliasesOutput_PreservesExactUtf16()
{
    // Arrange
    const std::u16string expected = u"\\\\server\\share\\東京-\U0001F600";
    Utf16DiskPath path;
    Utf16PathError error;
    if (!Utf16DiskPath::TryCreateAbsolute(expected, path, error))
        return false;
    // Act
    const bool accepted = Utf16DiskPath::TryCreateAbsolute(path.Value(), path, error);
    // Assert
    return accepted && error == Utf16PathError::None && path.Value() == expected;
}

bool FileName_WhenInputIsOutputSubview_PreservesExactUtf16()
{
    // Arrange
    Utf16FileName name;
    Utf16PathError error;
    if (!Utf16FileName::TryCreate(u"prefix-東京-\U0001F600.txt", name, error))
        return false;
    const auto suffix = std::u16string_view(name.Value()).substr(7);
    // Act
    const bool accepted = Utf16FileName::TryCreate(suffix, name, error);
    // Assert
    return accepted && error == Utf16PathError::None && name.Value() == u"東京-\U0001F600.txt";
}

bool FileName_WhenAliasedSubviewSplitsSurrogate_ClearsOutput()
{
    // Arrange
    Utf16FileName name;
    Utf16PathError error;
    if (!Utf16FileName::TryCreate(u"\U0001F600.txt", name, error))
        return false;
    const auto invalid = std::u16string_view(name.Value()).substr(0, 1);
    // Act
    const bool accepted = Utf16FileName::TryCreate(invalid, name, error);
    // Assert
    return !accepted && error == Utf16PathError::InvalidUtf16 && name.Value().empty();
}

bool DiskPath_WhenAliasedPrefixIsRelative_ClearsOutput()
{
    // Arrange
    Utf16DiskPath path;
    Utf16PathError error;
    if (!Utf16DiskPath::TryCreateAbsolute(u"C:\\東京", path, error))
        return false;
    const auto relative = std::u16string_view(path.Value()).substr(0, 2);
    // Act
    const bool accepted = Utf16DiskPath::TryCreateAbsolute(relative, path, error);
    // Assert
    return !accepted && error == Utf16PathError::InvalidInput && path.Value().empty();
}
}

int main()
{
    bool aliasesPreserved = true;
    if (!FileName_WhenInputAliasesOutput_PreservesExactUtf16())
    {
        Fail("UTF-16 filename must support input aliasing its output");
        aliasesPreserved = false;
    }
    if (!DiskPath_WhenInputAliasesOutput_PreservesExactUtf16())
    {
        Fail("UTF-16 disk path must support input aliasing its output");
        aliasesPreserved = false;
    }
    if (!FileName_WhenInputIsOutputSubview_PreservesExactUtf16())
    {
        Fail("UTF-16 filename must support a view into its output");
        aliasesPreserved = false;
    }
    if (!aliasesPreserved)
        return 1;
    if (!FileName_WhenAliasedSubviewSplitsSurrogate_ClearsOutput())
        return Fail("invalid aliased UTF-16 name must clear output with the correct error");
    if (!DiskPath_WhenAliasedPrefixIsRelative_ClearsOutput())
        return Fail("invalid aliased path must clear output with the correct error");

    // Arrange: Unicode names are distinct, even when ANSI would replace them.
    const std::u16string tokyo = u"Größe_東京_\U0001F600.txt";
    const std::u16string osaka = u"Größe_大阪_\U0001F600.txt";
    // Act / Assert: no case folding, replacement or normalization.
    if (!NameAccepted(tokyo) || !NameAccepted(osaka) || tokyo == osaka)
        return Fail("preserve distinct supplementary UTF-16 names");

    // Arrange: a component at the NTFS maximum and one beyond it.
    std::u16string maxName(251, u'n');
    maxName += u".txt";
    std::u16string overName(252, u'n');
    overName += u".txt";
    // Act / Assert.
    if (!NameAccepted(maxName) ||
        !NameRejected(overName, Utf16PathError::ComponentTooLong))
        return Fail("255/256 UTF-16 code-unit component boundary");

    // Arrange / Act / Assert: malformed UTF-16 cannot identify a file.
    if (!NameRejected(std::u16string(1, char16_t(0xD800)), Utf16PathError::InvalidUtf16) ||
        !NameRejected(std::u16string(1, char16_t(0xDC00)), Utf16PathError::InvalidUtf16) ||
        !NameRejected(std::u16string{char16_t(0xD83D), u'A'}, Utf16PathError::InvalidUtf16))
        return Fail("reject unpaired UTF-16 surrogates");

    // Arrange / Act / Assert: deny invalid, ambiguous and device file names.
    if (!NameRejected(u"", Utf16PathError::InvalidComponent) ||
        !NameRejected(u".", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"..", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"a\\b", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"a/b", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"a:b", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"trail.", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"trail ", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"CON.txt", Utf16PathError::InvalidComponent) ||
        !NameRejected(u"lpt1", Utf16PathError::InvalidComponent) ||
        !NameRejected(std::u16string_view(u"file\0rest", 9), Utf16PathError::InvalidComponent))
        return Fail("reject invalid Win32 file name components");

    // Arrange: a Unicode path longer than MAX_PATH but with valid components.
    const std::u16string longInput = u"C:\\Data\\" + std::u16string(240, u'x') +
                                     u"\\folder\\Größe_東京_\U0001F600.txt";
    Utf16DiskPath longPath;
    Utf16PathError error = Utf16PathError::InvalidInput;
    // Act / Assert: the model owns the complete path with no truncation.
    if (!Utf16DiskPath::TryCreateAbsolute(longInput, longPath, error) ||
        error != Utf16PathError::None || longPath.Value() != longInput ||
        longPath.Value().size() <= 260)
        return Fail("own a dynamic UTF-16 long drive path");

    // Arrange / Act / Assert: UNC and root boundaries remain unambiguous.
    Utf16DiskPath unc;
    if (!Utf16DiskPath::TryCreateAbsolute(u"\\\\server\\share\\東京", unc, error) ||
        unc.Value() != u"\\\\server\\share\\東京" ||
        !PathRejected(u"relative\\path", Utf16PathError::InvalidInput) ||
        !PathRejected(u"C:relative", Utf16PathError::InvalidInput) ||
        !PathRejected(u"\\\\server", Utf16PathError::InvalidInput) ||
        !PathRejected(u"C:\\a\\..\\b", Utf16PathError::InvalidComponent) ||
        !PathRejected(u"C:\\a\\\\b", Utf16PathError::InvalidComponent) ||
        !PathRejected(u"\\\\?\\C:\\a", Utf16PathError::InvalidInput))
        return Fail("accept valid UNC and reject ambiguous paths");

    // Arrange: the extended Win32 namespace permits at most 32,767 UTF-16
    // code units INCLUDING the inserted prefix and terminating NUL.
    // Validate both drive (4-unit prefix) and UNC (6-unit expansion) paths.
    const auto buildBoundaryPath = [](std::u16string path, std::size_t requestedLength) {
        while (path.size() < requestedLength)
        {
            if (path.back() != u'\\')
                path.push_back(u'\\');
            const std::size_t available = requestedLength - path.size();
            path.append(available < 200 ? available : 200, u'x');
        }
        return path;
    };
    const auto longestDrive = buildBoundaryPath(u"C:\\", 32762);
    const auto overlongDrive = buildBoundaryPath(u"C:\\", 32763);
    const auto longestUnc = buildBoundaryPath(u"\\\\server\\share", 32760);
    const auto overlongUnc = buildBoundaryPath(u"\\\\server\\share", 32761);
    Utf16DiskPath boundary;
    Utf16PathError boundaryError = Utf16PathError::InvalidInput;
    // Act / Assert: reject excess lengths without truncation or stale output.
    if (longestDrive.size() != 32762 || longestUnc.size() != 32760 ||
        !Utf16DiskPath::TryCreateAbsolute(longestDrive, boundary, boundaryError) ||
        boundaryError != Utf16PathError::None ||
        boundary.Value() != longestDrive ||
        !PathRejected(overlongDrive, Utf16PathError::PathTooLong) ||
        !Utf16DiskPath::TryCreateAbsolute(longestUnc, boundary, boundaryError) ||
        boundary.Value() != longestUnc ||
        !PathRejected(overlongUnc, Utf16PathError::PathTooLong))
        return Fail("32,767-unit extended namespace boundary for drive and UNC paths");

    // An otherwise valid append must fail rather than produce a path that
    // cannot fit the Win32 prefix and NUL.
    Utf16DiskPath nearLimit;
    Utf16DiskPath appended;
    Utf16FileName suffix;
    if (!Utf16DiskPath::TryCreateAbsolute(
            buildBoundaryPath(u"C:\\", 32761), nearLimit, boundaryError) ||
        !Utf16FileName::TryCreate(u"x", suffix, boundaryError) ||
        nearLimit.TryAppend(suffix, appended, boundaryError) ||
        boundaryError != Utf16PathError::PathTooLong || !appended.Value().empty())
        return Fail("append beyond Win32 total-path boundary must fail closed");

    // Arrange: an already validated absolute disk path and a distinct name.
    Utf16DiskPath parent;
    Utf16FileName filename;
    if (!Utf16DiskPath::TryCreateAbsolute(u"C:\\Data", parent, error) ||
        !Utf16FileName::TryCreate(tokyo, filename, error))
        return Fail("arrange safe path append");
    Utf16DiskPath joined;
    // Act / Assert: append exactly one validated name.
    if (!parent.TryAppend(filename, joined, error) ||
        joined.Value() != u"C:\\Data\\Größe_東京_\U0001F600.txt")
        return Fail("append Unicode component without loss");

    // Arrange: a file name must not be a directory path.
    // Act / Assert: reject unsafe characters instead of altering them.
    if (!NameRejected(u"..\\sensitive.txt", Utf16PathError::InvalidComponent))
        return Fail("reject traversal as a component");

    std::puts("PASS: owned UTF-16 filenames and paths, Unicode identity, boundaries, UNC and traversal");
    return 0;
}
