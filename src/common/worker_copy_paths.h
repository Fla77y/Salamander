// SPDX-FileCopyrightText: 2026 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include "utf16_disk_path.h"
#include "win32_long_path.h"

#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace Salamander
{
// COperation is byte-relocated by TDirectArray. It retains only malloc-owned
// diagnostic tokens; these independently owned identities never live in it.
// A token contains a forbidden Win32 control character. Accidentally passing
// one to an unconverted A API fails instead of accessing a best-fit alias.
struct WorkerCopyPaths
{
    std::wstring Source;
    std::wstring Target;
    std::wstring SourceExtended;
    std::wstring TargetExtended;
    std::string SourceToken;
    std::string TargetToken;
    DWORD IoFailure = ERROR_SUCCESS; // worker-only failure that prevents further path I/O
    bool HasSourceIdentity = false;
    BY_HANDLE_FILE_INFORMATION SourceIdentity = {}; // worker-only, pinned across retries/ADS

    const wchar_t* Resolve(const char* token) const
    {
        if (IoFailure != ERROR_SUCCESS)
        {
            SetLastError(IoFailure);
            return nullptr;
        }
        if (token != nullptr && SourceToken == token)
            return SourceExtended.c_str();
        if (token != nullptr && TargetToken == token)
            return TargetExtended.c_str();
        SetLastError(ERROR_INVALID_NAME);
        return nullptr;
    }

    bool GetDisplayPath(const char* token, std::wstring& output) const
    {
        if (token == nullptr)
            return false;
        const std::string* keys[] = {&SourceToken, &TargetToken};
        const std::wstring* paths[] = {&Source, &Target};
        for (int i = 0; i < 2; ++i)
        {
            const std::size_t length = keys[i]->size();
            if (std::strncmp(token, keys[i]->c_str(), length) != 0)
                continue;
            if (token[length] == 0)
            {
                output = *paths[i];
                return true;
            }
            // ADS diagnostics append an exact UTF-8 stream name to the token;
            // this text is display-only, never a second filesystem identity.
            if (token[length] == ':')
            {
                const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                    token + length, -1, nullptr, 0);
                if (count == 0)
                    return false;
                std::wstring suffix(static_cast<std::size_t>(count), L'\0');
                if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                        token + length, -1, &suffix[0], count) != count)
                    return false;
                suffix.pop_back();
                output = *paths[i] + suffix;
                return true;
            }
        }
        return false;
    }
};

// Populated only before StartProgressDialog/StartWorker. Pair addresses remain
// stable when the store grows or the separate COperation array is relocated.
// The owning COperations object outlives the worker and its synchronous dialogs.
class WorkerCopyPathStore
{
public:
    WorkerCopyPaths* Add(const Utf16DiskPath& source, const Utf16DiskPath& target, DWORD& error)
    {
        try
        {
            std::unique_ptr<WorkerCopyPaths> pair(new WorkerCopyPaths);
            pair->Source.assign(source.Value().begin(), source.Value().end());
            pair->Target.assign(target.Value().begin(), target.Value().end());
            if (!TryMakeExtendedLengthPath(pair->Source.c_str(), pair->SourceExtended, error) ||
                !TryMakeExtendedLengthPath(pair->Target.c_str(), pair->TargetExtended, error))
                return nullptr;
            if (CompareStringOrdinal(pair->SourceExtended.c_str(), -1,
                    pair->TargetExtended.c_str(), -1, TRUE) == CSTR_EQUAL)
            {
                error = ERROR_INVALID_PARAMETER;
                return nullptr;
            }
            const std::string prefix = "UTF16-" + std::string(1, '\x1f') + std::to_string(Pairs.size());
            pair->SourceToken = prefix + ":S";
            pair->TargetToken = prefix + ":T";
            Pairs.push_back(std::move(pair));
            error = ERROR_SUCCESS;
            return Pairs.back().get();
        }
        catch (const std::bad_alloc&)
        {
            error = ERROR_NOT_ENOUGH_MEMORY;
            return nullptr;
        }
    }

    WorkerCopyPaths* Find(const char* sourceToken, const char* targetToken) const
    {
        if (sourceToken == nullptr || targetToken == nullptr)
            return nullptr;
        for (const auto& pair : Pairs)
            if (pair->SourceToken == sourceToken && pair->TargetToken == targetToken)
                return pair.get();
        return nullptr;
    }

    bool GetDisplayPath(const char* token, std::wstring& output) const
    {
        output.clear();
        for (const auto& pair : Pairs)
            if (pair->GetDisplayPath(token, output))
                return true;
        return false;
    }

private:
    std::vector<std::unique_ptr<WorkerCopyPaths>> Pairs;
};
} // namespace Salamander
