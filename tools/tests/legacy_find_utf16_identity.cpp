// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

// Arrange / Act / Assert: search results must retain their original UTF-16
// filesystem identity, independently of display buffers and ANSI code pages.
#include "../../src/common/legacy_find_utf16_identity.h"

#include <cassert>
#include <iostream>
#include <string>

namespace
{
bool FindIdentity_WhenInputsAliasOutput_PreservesExactUtf16()
{
    // Arrange
    Salamander::LegacyFindUtf16Identity identity;
    Salamander::Utf16PathError error;
    const std::u16string directory = u"C:\\";
    const std::u16string name = u"東\U0001F600";
    if (!Salamander::LegacyFindUtf16Identity::TryCreate(directory, name, identity, error))
        return false;
    // Act
    const bool accepted = Salamander::LegacyFindUtf16Identity::TryCreate(
        identity.Directory(), identity.Name(), identity, error);
    // Assert
    return accepted && error == Salamander::Utf16PathError::None &&
           identity.Directory() == directory && identity.Name() == name &&
           identity.FullPath() == directory + name;
}

bool FindIdentity_WhenAliasedNameSplitsSurrogate_ClearsOutput()
{
    // Arrange
    Salamander::LegacyFindUtf16Identity identity;
    Salamander::Utf16PathError error;
    if (!Salamander::LegacyFindUtf16Identity::TryCreate(u"C:\\", u"\U0001F600", identity, error))
        return false;
    const auto invalid = std::u16string_view(identity.Name()).substr(0, 1);
    // Act
    const bool accepted = Salamander::LegacyFindUtf16Identity::TryCreate(
        identity.Directory(), invalid, identity, error);
    // Assert
    return !accepted && error == Salamander::Utf16PathError::InvalidUtf16 &&
           !identity.IsValid() && identity.Directory().empty() && identity.Name().empty() &&
           identity.FullPath().empty();
}
}

int main()
{
    if (!FindIdentity_WhenInputsAliasOutput_PreservesExactUtf16())
    {
        std::cerr << "FAIL: legacy Find identity must support inputs aliasing its output\n";
        return 1;
    }
    if (!FindIdentity_WhenAliasedNameSplitsSurrogate_ClearsOutput())
    {
        std::cerr << "FAIL: invalid aliased Find name must clear identity with the correct error\n";
        return 1;
    }

    using Salamander::LegacyFindUtf16Identity;
    using Salamander::Utf16PathError;

    // Arrange: supplementary-plane code point, CJK and non-ASCII directory.
    const std::u16string root = u"C:\\Data\\東京";
    const std::u16string name = u"Größe-大阪-\U0001F600.txt";
    LegacyFindUtf16Identity identity;
    Utf16PathError error = Utf16PathError::InvalidInput;

    // Act
    assert(LegacyFindUtf16Identity::TryCreate(root, name, identity, error));
    // Assert
    assert(error == Utf16PathError::None);
    assert(identity.Directory() == root);
    assert(identity.Name() == name);
    assert(identity.FullPath() == root + u"\\" + name);

    // Long paths are not capped at MAX_PATH; the Win32 extended limit is
    // checked by the shared Utf16DiskPath value object.
    std::u16string deep = u"C:\\";
    for (int i = 0; i != 85; ++i)
        deep += std::u16string(60, u'x') + u"\\";
    assert(deep.size() > 260);
    assert(LegacyFindUtf16Identity::TryCreate(deep, name, identity, error));
    assert(identity.FullPath().size() > 260);

    // Invalid input MUST clear old identity so it cannot accidentally be
    // reused for a different search result.
    assert(!LegacyFindUtf16Identity::TryCreate(
        u"C:\\Data\\..\\Other", name, identity, error));
    assert(!identity.IsValid());
    assert(identity.FullPath().empty());

    // The name is a component, never a relative path or wildcard.
    assert(!LegacyFindUtf16Identity::TryCreate(
        root, u"..\\secret.txt", identity, error));
    assert(!LegacyFindUtf16Identity::TryCreate(
        root, u"file?.txt", identity, error));
    assert(!LegacyFindUtf16Identity::TryCreate(
        root, std::u16string(256, u'a'), identity, error));
    assert(!LegacyFindUtf16Identity::TryCreate(
        root, std::u16string(1, static_cast<char16_t>(0xD800)), identity, error));

    // Root delimiters must not cause doubled backslashes in full paths.
    assert(LegacyFindUtf16Identity::TryCreate(
        u"C:\\", u"file.txt", identity, error));
    assert(identity.FullPath() == u"C:\\file.txt");

    // Refuse paths beyond the NT-wide limit rather than truncating them.
    std::u16string excessive = u"C:\\";
    for (int i = 0; i < 132; ++i)
        excessive += std::u16string(250, u'z') + u"\\";
    assert(excessive.size() > 30000);
    assert(!LegacyFindUtf16Identity::TryCreate(
        excessive, std::u16string(250, u'z'), identity, error));
    assert(!identity.IsValid());

    std::cout << "PASS: legacy Find result identities retain validated UTF-16 and long paths\n";
}
