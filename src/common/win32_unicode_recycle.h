// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"
#include "win32_long_path.h"

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>
#include <string_view>

namespace Salamander
{
namespace UnicodeRecycleDetail
{
template <class Interface>
class OwnedComInterface
{
public:
    OwnedComInterface() = default;
    ~OwnedComInterface()
    {
        if (value_ != nullptr)
            value_->Release();
    }

    OwnedComInterface(const OwnedComInterface&) = delete;
    OwnedComInterface& operator=(const OwnedComInterface&) = delete;

    Interface** Receive() { return &value_; }
    Interface* operator->() const { return value_; }

private:
    Interface* value_ = nullptr;
};

class StaComApartment
{
public:
    StaComApartment() : result_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
    ~StaComApartment()
    {
        if (SUCCEEDED(result_))
            CoUninitialize();
    }

    HRESULT Result() const { return result_; }

private:
    HRESULT result_;
};

inline bool IsExactShellPath(const wchar_t* resolved, const std::wstring& path,
                             const std::wstring& extendedPath)
{
    if (resolved == nullptr)
        return false;
    if (path == resolved || extendedPath == resolved)
        return true;

    // Explorer can expose a long shell item through its 8.3 spelling.
    // Expand that spelling to the complete original path before trusting it.
    const std::wstring_view spelling(resolved);
    if (spelling.substr(0, 4) == L"\\\\?\\")
        resolved += 4;
    std::wstring extendedResolved;
    DWORD error;
    if (!TryMakeExtendedLengthPath(resolved, extendedResolved, error))
        return false;
    const DWORD capacity = GetLongPathNameW(extendedResolved.c_str(), nullptr, 0);
    if (capacity == 0 || capacity > 32767)
        return false;
    std::wstring expanded(capacity, L'\0');
    const DWORD length = GetLongPathNameW(extendedResolved.c_str(), expanded.data(), capacity);
    if (length == 0 || length >= capacity)
        return false;
    expanded.resize(length);
    return expanded == extendedPath;
}
} // namespace UnicodeRecycleDetail

// Request a native shell Recycle Bin operation for one exact UTF-16 entry.
// Never silently fall back to permanent deletion. A shell item must resolve
// to the exact selected path before it can be queued.
inline bool TryRecycleUnicodeEntry(const Utf16DiskPath& source,
                                   HWND owner,
                                   HRESULT& error,
                                   bool directory)
{
    error = E_INVALIDARG;
    if (source.Value().empty())
        return false;

    static_assert(sizeof(wchar_t) == sizeof(char16_t),
                  "The shell requires Windows UTF-16 wchar_t");
    const std::wstring name(source.Value().begin(), source.Value().end());
    std::wstring extended;
    DWORD pathError;
    if (!TryMakeExtendedLengthPath(name.c_str(), extended, pathError))
    {
        error = HRESULT_FROM_WIN32(pathError);
        return false;
    }

    // Restrict Shell deletion to absolute fixed-drive entries. UNC, USB,
    // and reparse-point roots need separate recycle policies.
    if (name.size() < 4 || name[1] != L':' || name[2] != L'\\')
        return false;
    const std::wstring root = name.substr(0, 3);
    if (GetDriveTypeW(root.c_str()) != DRIVE_FIXED)
    {
        error = HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
        return false;
    }

    const DWORD attributes = GetFileAttributesW(extended.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        error = HRESULT_FROM_WIN32(GetLastError());
        return false;
    }
    if ((attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0 ||
        ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) != directory)
    {
        error = HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
        return false;
    }

    UnicodeRecycleDetail::StaComApartment apartment;
    error = apartment.Result();
    if (FAILED(error))
        return false; // never attempt an MTA shell operation from the GUI

    UnicodeRecycleDetail::OwnedComInterface<IFileOperation> operation;
    error = CoCreateInstance(CLSID_FileOperation, nullptr, CLSCTX_INPROC_SERVER,
                             IID_PPV_ARGS(operation.Receive()));
    if (FAILED(error))
        return false;

    // FOFX_RECYCLEONDELETE requests recycling; WANTNUKEWARNING leaves the
    // shell's permanent-delete fallback explicitly visible to the user.
    // No FOF_NOCONFIRMATION or FOF_SILENT here.
    error = operation->SetOperationFlags(
        FOF_ALLOWUNDO | FOFX_RECYCLEONDELETE | FOF_WANTNUKEWARNING);
    if (FAILED(error))
        return false;
    if (owner != nullptr)
    {
        error = operation->SetOwnerWindow(owner);
        if (FAILED(error))
            return false;
    }

    UnicodeRecycleDetail::OwnedComInterface<IShellItem> item;
    error = SHCreateItemFromParsingName(name.c_str(), nullptr,
                                        IID_PPV_ARGS(item.Receive()));
    if (FAILED(error) && name.size() >= MAX_PATH)
        error = SHCreateItemFromParsingName(extended.c_str(), nullptr, IID_PPV_ARGS(item.Receive()));
    if (FAILED(error))
        return false;
    PWSTR resolved = nullptr;
    error = item->GetDisplayName(SIGDN_FILESYSPATH, &resolved);
    const bool exact = SUCCEEDED(error) &&
        UnicodeRecycleDetail::IsExactShellPath(resolved, name, extended);
    CoTaskMemFree(resolved);
    if (!exact)
    {
        if (SUCCEEDED(error))
            error = HRESULT_FROM_WIN32(ERROR_INVALID_NAME);
        return false;
    }
    error = operation->DeleteItem(item.operator->(), nullptr);
    if (FAILED(error))
        return false;

    const HRESULT performed = operation->PerformOperations();
    BOOL aborted = FALSE;
    const HRESULT queried = operation->GetAnyOperationsAborted(&aborted);
    error = FAILED(performed) ? performed :
            FAILED(queried) ? queried :
            aborted ? HRESULT_FROM_WIN32(ERROR_CANCELLED) : S_OK;
    if (FAILED(error))
        return false;

    // Successful shell completion must also have removed the original
    // directory entry. The shell may return success for a skipped operation.
    const DWORD remaining = GetFileAttributesW(extended.c_str());
    const DWORD lookupError = remaining == INVALID_FILE_ATTRIBUTES ? GetLastError() : ERROR_GEN_FAILURE;
    if (lookupError != ERROR_FILE_NOT_FOUND && lookupError != ERROR_PATH_NOT_FOUND)
    {
        error = HRESULT_FROM_WIN32(lookupError);
        return false;
    }
    return true;
}

// Preserve the original file-only public contract.
inline bool TryRecycleUnicodeFile(const Utf16DiskPath& source,
                                  HWND owner, HRESULT& error)
{
    return TryRecycleUnicodeEntry(source, owner, error, false);
}

// Request recycling of an ordinary directory as one shell item, preserving
// the user's Recycle Bin policy even when descendants have long paths.
inline bool TryRecycleUnicodeDirectory(const Utf16DiskPath& source,
                                       HWND owner, HRESULT& error)
{
    return TryRecycleUnicodeEntry(source, owner, error, true);
}
} // namespace Salamander
