// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "../../src/common/worker_copy_paths.h"
#include <cassert>
#include <cstdio>

namespace
{
Salamander::Utf16DiskPath Path(const std::u16string& text)
{
    Salamander::Utf16DiskPath path;
    Salamander::Utf16PathError error;
    assert(Salamander::Utf16DiskPath::TryCreateAbsolute(text, path, error));
    return path;
}

void Store_WhenGrowing_KeepsOriginalIdentityAndTokens()
{
    // Arrange
    Salamander::WorkerCopyPathStore store;
    DWORD error = ERROR_SUCCESS;
    const auto source = Path(u"C:\\東京\\" + std::u16string(200, u'a') + u"\\😀.bin");
    const auto target = Path(u"C:\\大阪\\" + std::u16string(200, u'b') + u"\\😀.bin");
    // Act
    auto* first = store.Add(source, target, error);
    assert(first != nullptr && error == ERROR_SUCCESS);
    const std::string sourceToken = first->SourceToken, targetToken = first->TargetToken;
    for (int i = 0; i < 128; ++i)
        assert(store.Add(source, target, error) != nullptr);
    // Assert
    assert(store.Find(sourceToken.c_str(), targetToken.c_str()) == first);
    assert(first->Source == std::wstring(source.Value().begin(), source.Value().end()));
    assert(first->Target == std::wstring(target.Value().begin(), target.Value().end()));
    assert(first->Resolve(sourceToken.c_str()) == first->SourceExtended.c_str());
    assert(sourceToken.find('\x1f') != std::string::npos);
    assert(store.Find(sourceToken.c_str(), first->SourceToken.c_str()) == nullptr);
}

void Resolve_WhenUnknown_RefusesWithoutAliasFallback()
{
    // Arrange
    Salamander::WorkerCopyPathStore store;
    DWORD error;
    auto* pair = store.Add(Path(u"C:\\東京\\😀.bin"), Path(u"C:\\大阪\\😀.bin"), error);
    assert(pair != nullptr);
    // Act / Assert
    SetLastError(ERROR_SUCCESS);
    assert(pair->Resolve("C:\\??\\??.bin") == nullptr);
    assert(GetLastError() == ERROR_INVALID_NAME);
    assert(pair->Resolve(nullptr) == nullptr);
    assert(store.Add(Path(u"C:\\same.bin"), Path(u"c:\\SAME.bin"), error) == nullptr);
    assert(error == ERROR_INVALID_PARAMETER);
}

void Display_WhenStreamNameIsUnicode_PreservesUtf16()
{
    // Arrange
    Salamander::WorkerCopyPathStore store;
    DWORD error;
    auto* pair = store.Add(Path(u"C:\\東京\\😀.bin"), Path(u"C:\\大阪\\😀.bin"), error);
    assert(pair != nullptr);
    std::wstring display;
    // Act / Assert
    assert(store.GetDisplayPath(pair->SourceToken.c_str(), display));
    assert(display == pair->Source);
    const std::string stream = pair->TargetToken + u8":識別😀";
    assert(store.GetDisplayPath(stream.c_str(), display));
    assert(display == pair->Target + L":識別😀");
    assert(!store.GetDisplayPath("unknown", display) && display.empty());
}
} // namespace

int main()
{
    Store_WhenGrowing_KeepsOriginalIdentityAndTokens();
    Resolve_WhenUnknown_RefusesWithoutAliasFallback();
    Display_WhenStreamNameIsUnicode_PreservesUtf16();
    return std::puts("PASS: owned worker copy paths, stable tokens, safe lookup and Unicode diagnostics"), 0;
}
