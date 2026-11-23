// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "worker_copy_paths.h"
#include <Aclapi.h>

namespace Salamander
{
namespace WorkerCopyIo
{
// The legacy copy helpers run on one worker thread, including retry callbacks.
// This explicit scope binds their non-path tokens to the owning script's W
// identities. Unknown tokens NEVER fall back to A APIs inside a W operation.
inline thread_local WorkerCopyPaths* Current = nullptr;

class Scope
{
public:
    explicit Scope(WorkerCopyPaths* paths) : Previous(Current) { Current = paths; }
    ~Scope() { Current = Previous; }
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;

private:
    WorkerCopyPaths* Previous;
};

inline bool SameIdentity(const BY_HANDLE_FILE_INFORMATION& first, const BY_HANDLE_FILE_INFORMATION& second)
{
    return first.dwVolumeSerialNumber == second.dwVolumeSerialNumber &&
        first.nFileIndexHigh == second.nFileIndexHigh && first.nFileIndexLow == second.nFileIndexLow;
}

inline HANDLE CreateNewAlternateStream(const wchar_t* streamPath)
{
    HANDLE stream = CreateFileW(streamPath, GENERIC_WRITE, 0, nullptr, CREATE_NEW,
        FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (stream != INVALID_HANDLE_VALUE || GetLastError() != ERROR_FILE_EXISTS)
        return stream;

    // CREATE_NEW may report the existing base file even when the named
    // stream is absent. OPEN_ALWAYS distinguishes creation from opening
    // without truncating anything or racing a separate existence check.
    stream = CreateFileW(streamPath, GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS,
        FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    const DWORD openError = GetLastError();
    if (stream == INVALID_HANDLE_VALUE || openError == ERROR_SUCCESS)
        return stream;

    CloseHandle(stream);
    SetLastError(openError == ERROR_ALREADY_EXISTS ? ERROR_FILE_EXISTS : openError);
    return INVALID_HANDLE_VALUE;
}

inline bool BeforeTargetMutation(const char* token, const wchar_t* path)
{
    if (Current->TargetToken != token)
    {
        SetLastError(ERROR_ACCESS_DENIED); // a copy may never mutate its source
        return false;
    }
    const DWORD attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        const DWORD error = GetLastError();
        return error == ERROR_FILE_NOT_FOUND; // other uncertainty is not absence
    }
    if ((attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0)
    {
        SetLastError(ERROR_REPARSE_TAG_INVALID);
        return false;
    }
    if (!Current->HasSourceIdentity)
        return true;
    HANDLE check = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (check == INVALID_HANDLE_VALUE)
        return false;
    BY_HANDLE_FILE_INFORMATION target;
    const BOOL read = GetFileInformationByHandle(check, &target);
    const DWORD error = read ? ERROR_SUCCESS : GetLastError();
    CloseHandle(check);
    if (!read)
    {
        SetLastError(error);
        return false;
    }
    if (SameIdentity(Current->SourceIdentity, target))
    {
        SetLastError(ERROR_INVALID_PARAMETER); // includes a different hard-link name
        return false;
    }
    return true;
}

inline HANDLE OpenRaw(const char* name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES security,
                      DWORD disposition, DWORD attributes, HANDLE templateFile)
{
    if (Current == nullptr)
        return CreateFileA(name, access, share, security, disposition, attributes, templateFile);
    const wchar_t* path = Current->Resolve(name);
    if (path == nullptr)
        return INVALID_HANDLE_VALUE;
    if (Current->SourceToken == name &&
        ((access & (GENERIC_WRITE | FILE_WRITE_DATA | FILE_APPEND_DATA | WRITE_DAC | WRITE_OWNER | DELETE)) != 0 ||
            disposition != OPEN_EXISTING))
    {
        SetLastError(ERROR_ACCESS_DENIED);
        return INVALID_HANDLE_VALUE;
    }
    if (Current->TargetToken == name && disposition != CREATE_NEW &&
        ((access & (GENERIC_WRITE | FILE_WRITE_DATA | FILE_APPEND_DATA | WRITE_DAC | WRITE_OWNER | DELETE)) != 0 ||
            disposition == CREATE_ALWAYS || disposition == TRUNCATE_EXISTING) &&
        !BeforeTargetMutation(name, path))
        return INVALID_HANDLE_VALUE;
    // Validate the opened object before truncation. A name can be replaced
    // between the attribute probe and CreateFile; a source hard link must
    // never be truncated by CREATE_ALWAYS before its identity is checked.
    const bool truncate = disposition == CREATE_ALWAYS || disposition == TRUNCATE_EXISTING;
    const DWORD safeDisposition = disposition == CREATE_ALWAYS ? OPEN_ALWAYS :
        disposition == TRUNCATE_EXISTING ? OPEN_EXISTING : disposition;
    HANDLE file = CreateFileW(path, access, share, security, safeDisposition,
        attributes | FILE_FLAG_OPEN_REPARSE_POINT, templateFile);
    const DWORD openError = GetLastError();
    if (file != INVALID_HANDLE_VALUE)
    {
        BY_HANDLE_FILE_INFORMATION information;
        const BOOL read = GetFileInformationByHandle(file, &information);
        const DWORD error = read ? ERROR_REPARSE_TAG_INVALID : GetLastError();
        if (!read || (information.dwFileAttributes &
                (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0)
        {
            CloseHandle(file);
            SetLastError(error);
            return INVALID_HANDLE_VALUE;
        }
        if (Current->SourceToken == name)
        {
            if (Current->HasSourceIdentity && !SameIdentity(Current->SourceIdentity, information))
            {
                CloseHandle(file);
                SetLastError(ERROR_FILE_INVALID);
                return INVALID_HANDLE_VALUE;
            }
            Current->SourceIdentity = information;
            Current->HasSourceIdentity = true;
        }
        else if (Current->HasSourceIdentity && SameIdentity(Current->SourceIdentity, information))
        {
            CloseHandle(file);
            SetLastError(ERROR_INVALID_PARAMETER);
            return INVALID_HANDLE_VALUE;
        }
        // F6's copy-then-delete is allowed only for the exact destination
        // object opened for writing by the copy worker. Retain the first
        // created identity; a replacement during retries must fail closed.
        if (Current->CaptureTargetIdentity && Current->TargetToken == name &&
            (access & (GENERIC_WRITE | FILE_WRITE_DATA | FILE_APPEND_DATA |
                       FILE_WRITE_ATTRIBUTES | WRITE_DAC | WRITE_OWNER)) != 0)
        {
            if (information.nFileIndexHigh == 0 && information.nFileIndexLow == 0)
            {
                CloseHandle(file);
                SetLastError(ERROR_FILE_INVALID);
                return INVALID_HANDLE_VALUE;
            }
            if (Current->HasTargetIdentity &&
                !SameIdentity(Current->TargetIdentity, information))
            {
                CloseHandle(file);
                SetLastError(ERROR_FILE_INVALID);
                return INVALID_HANDLE_VALUE;
            }
            Current->TargetIdentity = information;
            Current->HasTargetIdentity = true;
        }
        if (truncate && !SetEndOfFile(file)) // a newly opened handle is positioned at zero
        {
            const DWORD truncateError = GetLastError();
            CloseHandle(file);
            SetLastError(truncateError);
            return INVALID_HANDLE_VALUE;
        }
        SetLastError(openError);
    }
    return file;
}

inline DWORD Attributes(const char* name)
{
    if (Current == nullptr)
        return GetFileAttributesA(name);
    const wchar_t* path = Current->Resolve(name);
    return path == nullptr ? INVALID_FILE_ATTRIBUTES : GetFileAttributesW(path);
}

inline BOOL SetAttributes(const char* name, DWORD attributes)
{
    if (Current == nullptr)
        return SetFileAttributesA(name, attributes);
    const wchar_t* path = Current->Resolve(name);
    return path != nullptr && BeforeTargetMutation(name, path) && SetFileAttributesW(path, attributes);
}

inline BOOL Delete(const char* name)
{
    if (Current == nullptr)
        return DeleteFileA(name);
    const wchar_t* path = Current->Resolve(name);
    return path != nullptr && BeforeTargetMutation(name, path) && DeleteFileW(path);
}

inline BOOL Encrypt(const char* name)
{
    if (Current == nullptr)
        return EncryptFileA(name);
    const wchar_t* path = Current->Resolve(name);
    return path != nullptr && BeforeTargetMutation(name, path) && EncryptFileW(path);
}

inline BOOL Decrypt(const char* name, DWORD flags)
{
    if (Current == nullptr)
        return DecryptFileA(name, flags);
    const wchar_t* path = Current->Resolve(name);
    return path != nullptr && BeforeTargetMutation(name, path) && DecryptFileW(path, flags);
}

inline DWORD GetSecurity(char* name, SE_OBJECT_TYPE type, SECURITY_INFORMATION requested,
                         PSID* owner, PSID* group, PACL* dacl, PACL* sacl, PSECURITY_DESCRIPTOR* descriptor)
{
    if (Current == nullptr)
        return GetNamedSecurityInfoA(name, type, requested, owner, group, dacl, sacl, descriptor);
    const wchar_t* path = Current->Resolve(name);
    return path == nullptr ? GetLastError() : GetNamedSecurityInfoW(const_cast<wchar_t*>(path),
        type, requested, owner, group, dacl, sacl, descriptor);
}

inline DWORD SetSecurity(char* name, SE_OBJECT_TYPE type, SECURITY_INFORMATION requested,
                         PSID owner, PSID group, PACL dacl, PACL sacl)
{
    if (Current == nullptr)
        return SetNamedSecurityInfoA(name, type, requested, owner, group, dacl, sacl);
    const wchar_t* path = Current->Resolve(name);
    return path == nullptr || !BeforeTargetMutation(name, path) ? GetLastError() : SetNamedSecurityInfoW(const_cast<wchar_t*>(path),
        type, requested, owner, group, dacl, sacl);
}
} // namespace WorkerCopyIo
} // namespace Salamander
