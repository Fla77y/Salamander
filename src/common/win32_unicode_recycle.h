// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <string>

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
} // namespace UnicodeRecycleDetail

// Request a normal shell Recycle Bin operation. Never call DeleteFileW
// or fall back to permanent deletion in this helper. The shell is allowed
// to show its own warning if it cannot recycle the requested item
// (FOF_WANTNUKEWARNING). Only short absolute files on a fixed local drive
// are supported until the long-path shell identity is migrated.
inline bool TryRecycleUnicodeFile(const Utf16DiskPath& source,
                                  HWND owner,
                                  HRESULT& error)
{
    error = E_INVALIDARG;
    if (source.Value().empty())
        return false;

    static_assert(sizeof(wchar_t) == sizeof(char16_t),
                  "The shell requires Windows UTF-16 wchar_t");
    const std::wstring name(source.Value().begin(), source.Value().end());
    if (name.size() >= MAX_PATH)
    {
        error = HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
        return false;
    }

    // Restrict Shell deletion to absolute local drive files. UNC, USB,
    // reparse points and directories need separate recycle policies.
    if (name.size() < 4 || name[1] != L':' || name[2] != L'\\')
        return false;
    const std::wstring root = name.substr(0, 3);
    if (GetDriveTypeW(root.c_str()) != DRIVE_FIXED)
    {
        error = HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
        return false;
    }

    const DWORD attributes = GetFileAttributesW(name.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        error = HRESULT_FROM_WIN32(GetLastError());
        return false;
    }
    if ((attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0)
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
    if (FAILED(error))
        return false;
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
    if (GetFileAttributesW(name.c_str()) != INVALID_FILE_ATTRIBUTES)
    {
        error = HRESULT_FROM_WIN32(ERROR_GEN_FAILURE);
        return false;
    }
    return true;
}
} // namespace Salamander
