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
}

int main()
{
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
