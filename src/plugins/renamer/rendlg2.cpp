// SPDX-FileCopyrightText: 2023 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later

#include "precomp.h"

// ****************************************************************************
//
// CRenameScriptEntry
//

struct CRenameScriptEntry
{
    CSourceFile* Source;
    char* NewName;
    char* NewPart;
    char* CycleTemp; // owned only by the first entry of a closed cycle
    int CycleLength;
    int Blocks : 28;            // script construction: index of an item depending on this one
                                // script processing: the following item depends on this entry
    unsigned int Overwrite : 1; // the user confirmed overwriting the existing file

    // helper variables for building the script
    unsigned int Skip : 1;    // will not be renamed
    unsigned int Done : 1;    // the item has already been added to the script
    unsigned int Blocked : 1; // the item depends on another item

    CRenameScriptEntry()
    {
        Source = NULL;
        NewName = NULL;
        CycleTemp = NULL;
        CycleLength = 0;
        Blocks = -1;
        Overwrite = 0;
        Skip = 0;
        Done = 0;
        Blocked = 0;
    }
    ~CRenameScriptEntry()
    {
        if (NewName)
            free(NewName);
        if (CycleTemp)
            free(CycleTemp);
    }
    static int __cdecl CompareOldNames(const void* elem1, const void* elem2)
    {
        return SG->StrICmp(
            ((CRenameScriptEntry*)elem1)->Source->FullName,
            ((CRenameScriptEntry*)elem2)->Source->FullName);
    }
    static int __cdecl CompareOldName(const void* key, const void* elem2)
    {
        return SG->StrICmp((const char*)key, ((CRenameScriptEntry*)elem2)->Source->FullName);
    }
    static int __cdecl CompareNewNames(const void* elem1, const void* elem2)
    {
        if (((CRenameScriptEntry*)elem1)->NewName && ((CRenameScriptEntry*)elem2)->NewName)
        {
            return SG->StrICmp(
                ((CRenameScriptEntry*)elem1)->NewName,
                ((CRenameScriptEntry*)elem2)->NewName);
        }
        else
        {
            if (((CRenameScriptEntry*)elem1)->NewName)
                return 1;
            if (((CRenameScriptEntry*)elem2)->NewName)
                return -1;
            return 0;
        }
    }
};

// ****************************************************************************
//
// CUndoStackEntry
//

CUndoStackEntry::CUndoStackEntry(char* source, char* target, CSourceFile* renamedFile,
                                 BOOL isDir, BOOL blocks)
{
    CALL_STACK_MESSAGE_NONE
    Source = SG->DupStr(source);
    if (target)
        Target = SG->DupStr(target);
    else
        Target = NULL;
    RenamedFile = renamedFile;
    IsDir = isDir ? 1 : 0;
    Blocks = blocks ? 1 : 0;
    Independent = 0;
    CycleMove = 0;
    CycleStage = 0;
    Intermediate = 0;
}

CUndoStackEntry::~CUndoStackEntry()
{
    CALL_STACK_MESSAGE_NONE
    if (Source)
        free(Source);
    if (Target)
        free(Target);
}

// ****************************************************************************
//
// CRenamerDialog
//

void CRenamerDialog::Rename(BOOL validate)
{
    CALL_STACK_MESSAGE2("CRenamerDialog::Rename(%d)", validate);
    Progress = NULL;

    // A partial cycle still owns a temporary filename. Do not discard the
    // only in-dialog recovery mapping when starting another rename.
    if (!validate)
    {
        for (int i = 0; i < UndoStack.Count; ++i)
        {
            CUndoStackEntry* entry = UndoStack[i];
            if (entry->CycleStage && entry->RenamedFile &&
                strcmp(entry->RenamedFile->FullName, entry->Source) == 0)
            {
                SG->SalMessageBox(HWindow, LoadStr(IDS_DEPENDENCE),
                                  LoadStr(IDS_ERROR), MB_ICONERROR);
                return;
            }
        }
    }

    CRenameScriptEntry* script;
    int count;
    BOOL somethingToDo;
    if (BuildScript(script, count, validate, somethingToDo))
    {
        if (validate || !somethingToDo)
        {
            if (Progress)
            {
                EnableWindow(HWindow, TRUE);
                DestroyWindow(Progress->HWindow);
            }
            if (validate)
            {
                SG->SalMessageBox(HWindow, LoadStr(IDS_VALIDATEOK),
                                  LoadStr(IDS_PLUGINNAME), MB_ICONINFORMATION);
            }
            else
            {
                delete[] script;
                SG->SalMessageBox(HWindow, LoadStr(IDS_NOTTODO),
                                  LoadStr(IDS_PLUGINNAME), MB_ICONINFORMATION);
            }
            return;
        }

        Errors = FALSE;
        // always clear the undo stack
        // if (ProcessRenamed)
        // {
        RenamedFiles.DestroyMembers();
        UndoStack.DestroyMembers();
        // }

        ExecuteScript(script, count);

        delete[] script;

        NotRenamedFiles.DestroyMembers();
        if (Errors || count < SourceFiles.Count)
        {
            SG->SalMessageBox(HWindow, LoadStr(IDS_SOMEERRORS),
                              LoadStr(IDS_PLUGINNAME), MB_ICONINFORMATION);
            int i;
            for (i = 0; i < SourceFiles.Count; i++)
                if (SourceFiles[i]->State == 0)
                    NotRenamedFiles.Add(new CSourceFile(SourceFiles[i]));

            ProcessRenamed = FALSE;
            ProcessNotRenamed = TRUE;
            // Also expose actual temporary names if a cycle was interrupted.
            for (int j = 0; j < UndoStack.Count; ++j)
                if (UndoStack[j]->CycleStage &&
                    strcmp(UndoStack[j]->RenamedFile->FullName, UndoStack[j]->Source) == 0)
                    ProcessRenamed = TRUE;
        }
        else
        {
            ProcessRenamed = TRUE;
            ProcessNotRenamed = FALSE;
            strcpy(DefMask, "*.*");
            ResetOptions(TRUE);
        }

        if (RenamerOptions.Spec == rsFullPath)
        {
            Root[0] = 0;
            RootLen = 0;
        }

        ReloadSourceFiles();
    }

    if (Progress)
    {
        EnableWindow(HWindow, TRUE);
        DestroyWindow(Progress->HWindow);
    }

    if (MinBeepWhenDone && IsIconic(HWindow))
        MessageBeep(0);
}

BOOL CRenamerDialog::BuildScript(CRenameScriptEntry*& script, int& count,
                                 BOOL validate, BOOL& somethingToDo)
{
    CALL_STACK_MESSAGE4("CRenamerDialog::BuildScript(, %d, %d, %d)", count,
                        validate, somethingToDo);
    BOOL ret = FALSE;
    CRenameScriptEntry* tmpScript = NULL;
    script = NULL;
    char newName[MAX_PATH];
    char* newPart;
    BOOL skip;
    BOOL skipAllLongNames = FALSE,
         skipAllBadNames = FALSE,
         skipAllDuplicateNames = FALSE,
         skipDifferentDirRoots = FALSE;
    SkipAllFileDir = FALSE;
    SkipAllDependingNames = FALSE;
    Silent = ::Silent;
    somethingToDo = FALSE;
    int i = 0;
    BOOL usrBreak = FALSE;

    // set the options
    CRenamer renamer(Root, RootLen);
    if (!ManualMode && !renamer.SetOptions(&RenamerOptions))
    {
        int error, errorPos1, errorPos2;
        CRenamerErrorType errorType;
        renamer.GetError(error, errorPos1, errorPos2, errorType);
        Error(error);
        int id;
        switch (errorType)
        {
        case retNewName:
            id = IDC_NEWNAME;
            break;
        case retBMSearch:
            id = IDC_SEARCH;
            break;
        case retRegExp:
            id = IDC_SEARCH;
            break;
        case retReplacePattern:
            id = IDC_REPLACE;
            break;
        default:
            id = -1;
            break;
        }
        if (id != -1)
        {
            HWND ctrl = GetDlgItem(HWindow, id);
            HWND wnd = GetFocus();
            while (wnd != NULL && wnd != ctrl)
                wnd = GetParent(wnd);
            if (wnd == NULL) // focus only if the control is not an ancestor of GetFocus
            {                // such as the edit line in a combo box
                SendMessage(HWindow, WM_NEXTDLGCTL, (WPARAM)ctrl, TRUE);
            }
            SendMessage(ctrl, CB_SETEDITSEL, 0, MAKELONG(errorPos1, errorPos2));
        }
        goto LBUILD_SCRIPT_ERROR;
    }

    // create the progress dialog
    Progress = new CProgressDialog(HWindow);
    Progress->Create();
    EnableWindow(HWindow, FALSE);
    Progress->SetText(LoadStr(IDS_PREPARING));
    Progress->EmptyMessageLoop();

    // create the helper script
    tmpScript = new CRenameScriptEntry[SourceFiles.Count];
    for (i = 0; i < SourceFiles.Count; i++)
    {
        tmpScript[i].Source = SourceFiles[i];
        // create a new name
        int l = ManualMode ? GetManualModeNewName(SourceFiles[i], i, newName, newPart) : renamer.Rename(SourceFiles[i], i, newName, &newPart);
        if (l < 0)
        {
            FileError(HWindow, SourceFiles[i]->FullName, IDS_EXP_SMALLBUFFER,
                      FALSE, &skip, &skipAllLongNames, IDS_ERROR);
            if (!skip)
                goto LBUILD_SCRIPT_ERROR;
            tmpScript[i].Skip = 1;
            continue;
        }
        // verify the correctness of the name
        if (!ValidateFileName(newPart, l, RenamerOptions.Spec, &skip, &skipAllBadNames))
        {
            if (!skip)
                goto LBUILD_SCRIPT_ERROR;
            tmpScript[i].Skip = 1;
            continue;
        }
        CutTrailingDots(newPart, l, RenamerOptions.Spec);
        tmpScript[i].NewName = SG->DupStr(newName);
        tmpScript[i].NewPart = tmpScript[i].NewName + (newPart - newName);
        somethingToDo = somethingToDo || strcmp(SourceFiles[i]->FullName, newName);
    }

    // remove duplicate names
    qsort(tmpScript, SourceFiles.Count, sizeof(*tmpScript), CRenameScriptEntry::CompareNewNames);
    for (i = 1; i < SourceFiles.Count; i++)
        if (!tmpScript[i - 1].Skip && !tmpScript[i].Skip &&
            SG->StrICmp(tmpScript[i - 1].NewName, tmpScript[i].NewName) == 0)
        {
            FileError(HWindow, tmpScript[i].NewName, IDS_DUPLICATENAME,
                      FALSE, &skip, &skipAllDuplicateNames, IDS_ERROR);
            if (!skip)
                goto LBUILD_SCRIPT_ERROR;
            tmpScript[i - 1].Skip = 1;
            do
                tmpScript[i].Skip = 1;
            while (++i < SourceFiles.Count &&
                   SG->StrICmp(tmpScript[i - 1].NewName, tmpScript[i].NewName) == 0);
            continue;
        }

    // sort the script by the original name (for binary search)
    qsort(tmpScript, SourceFiles.Count, sizeof(*tmpScript), CRenameScriptEntry::CompareOldNames);

    // test the helper script for correctness
    for (i = 0; i < SourceFiles.Count; i++)
    {
        if (!tmpScript[i].Skip)
        {
            // verify that directories share the same root (we cannot handle recursive directory copies)
            if (tmpScript[i].Source->IsDir &&
                !SG->HasTheSameRootPath(tmpScript[i].Source->FullName, tmpScript[i].NewName))
            {
                FileError(HWindow, tmpScript[i].Source->FullName, IDS_DIRNOTSAMEROOT,
                          FALSE, &skip, &skipDifferentDirRoots, IDS_ERROR);
                if (!skip)
                    goto LBUILD_SCRIPT_ERROR;
                tmpScript[i].Skip = 1;
                continue;
            }
            // verify that target names do not exist and request overwrite confirmation
            DWORD attr = SG->SalGetFileAttributes(tmpScript[i].NewName);
            if (attr != 0xFFFFFFFF)
            {
                if ((attr & FILE_ATTRIBUTE_DIRECTORY) ||
                    !(Silent & (SILENT_OVERWRITE_FILE_EXIST | SILENT_SKIP_FILE_EXIST)) ||
                    (attr & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) &&
                        !(Silent & (SILENT_OVERWRITE_FILE_SYSHID | SILENT_SKIP_FILE_SYSHID)))
                {
                    // the new name is not among the files that will be renamed
                    if (!bsearch(tmpScript[i].NewName, tmpScript, SourceFiles.Count,
                                 sizeof(*tmpScript), CRenameScriptEntry::CompareOldName))
                    {
                        if (attr & FILE_ATTRIBUTE_DIRECTORY) // cannot overwrite a directory
                        {
                            FileError(HWindow, tmpScript[i].Source->FullName,
                                      tmpScript[i].Source->IsDir ? IDS_DIRDIR : IDS_FILEDIR,
                                      FALSE, &skip, &SkipAllFileDir, IDS_ERROR);
                            if (!skip)
                                goto LBUILD_SCRIPT_ERROR;
                            tmpScript[i].Skip = 1;
                            continue;
                        }
                        if (!FileOverwrite(HWindow, tmpScript[i].NewName, NULL,
                                           tmpScript[i].Source->FullName, NULL, attr,
                                           IDS_CNFRM_SHOVERWRITE, IDS_OVEWWRITETITLE, &skip, &Silent))
                        {
                            if (!skip)
                                goto LBUILD_SCRIPT_ERROR;
                            tmpScript[i].Skip = 1;
                            continue;
                        }
                        tmpScript[i].Overwrite = 1;
                    }
                }
                else
                {
                    if (Silent & SILENT_SKIP_FILE_EXIST)
                    {
                        tmpScript[i].Skip = 1;
                        continue;
                    }
                    if ((attr & (FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM)) &&
                        (Silent & SILENT_SKIP_FILE_SYSHID))
                    {
                        tmpScript[i].Skip = 1;
                        continue;
                    }
                    tmpScript[i].Overwrite = 1;
                }
            }
        }
        if ((usrBreak = Progress->Update(min((i + 1) * 1000 / SourceFiles.Count, 990))) != 0)
            goto LBUILD_SCRIPT_ERROR;
    }

    // find the optimal order for performing the rename operation
    // and create the script according to which we will rename
    if (!validate)
        script = new CRenameScriptEntry[SourceFiles.Count];
    count = 0;
    int skipped;
    skipped = 0;
    for (i = 0; i < SourceFiles.Count; i++) // detect dependency chains
    {
        if (tmpScript[i].Skip)
            skipped++;
        else
        {
            CRenameScriptEntry* blocker = (CRenameScriptEntry*)bsearch(
                tmpScript[i].NewName, tmpScript, SourceFiles.Count, sizeof(*tmpScript),
                CRenameScriptEntry::CompareOldName);
            if (blocker && blocker != tmpScript + i)
            {
                blocker->Blocks = i;
                tmpScript[i].Blocked = 1;
            }
        }
    }
    for (i = 0; i < SourceFiles.Count; i++) // build the script
    {
        // find the start of the dependency chain and add its members
        // to the script
        if (!tmpScript[i].Skip && !tmpScript[i].Done && !tmpScript[i].Blocked)
        {
            int prev = i;
            do
            {
                if (!validate)
                {
                    script[count].Source = tmpScript[prev].Source;
                    script[count].NewName = tmpScript[prev].NewName;
                    script[count].NewPart = tmpScript[prev].NewPart;
                    script[count].Blocks = tmpScript[prev].Blocks != -1;
                    script[count].Overwrite = tmpScript[prev].Overwrite;
                    tmpScript[prev].NewName = NULL;
                }
                tmpScript[prev].Done = 1;
                count++;
                prev = tmpScript[prev].Blocks;
            } while (prev != -1);
        }
    }

    // A remaining closed dependency cycle can be rotated via a vacant
    // temporary name. Restrict this path to regular files in one directory:
    // no directory creation, directory moves or cross-volume copy/delete.
    for (i = 0; i < SourceFiles.Count; ++i)
    {
        if (tmpScript[i].Skip || tmpScript[i].Done)
            continue;
        CSourceFile* first = tmpScript[i].Source;
        const int parentLen = (int)(first->Name - first->FullName);
        int length = 0;
        int current = i;
        do
        {
            if (current < 0 || current >= SourceFiles.Count ||
                tmpScript[current].Skip || tmpScript[current].Done ||
                !tmpScript[current].Blocked || !tmpScript[current].NewName)
                break;
            CSourceFile* file = tmpScript[current].Source;
            if (file->IsDir || (file->Attr & FILE_ATTRIBUTE_REPARSE_POINT) ||
                file->Name - file->FullName != parentLen ||
                SG->StrNICmp(file->FullName, first->FullName, parentLen) != 0)
                break;
            ++length;
            current = tmpScript[current].Blocks;
        } while (current != i && length < SourceFiles.Count);
        if (current != i || length < 2)
            continue;

        char temp[MAX_PATH];
        if (parentLen + sizeof("~osren-00000000-00.tmp") > sizeof(temp))
            continue;
        bool vacant = false;
        for (unsigned int attempt = 0; attempt < 256; ++attempt)
        {
            const int len = sprintf_s(temp, sizeof(temp), "%.*s~osren-%08lX-%02X.tmp",
                                      parentLen, first->FullName, GetTickCount(), attempt);
            if (len <= 0)
                break;
            bool conflicts = false;
            for (int j = 0; j < SourceFiles.Count && !conflicts; ++j)
                conflicts = SG->StrICmp(temp, tmpScript[j].Source->FullName) == 0 ||
                            (tmpScript[j].NewName && SG->StrICmp(temp, tmpScript[j].NewName) == 0);
            if (!validate)
                for (int j = 0; j < count && !conflicts; ++j)
                    conflicts = SG->StrICmp(temp, script[j].NewName) == 0 ||
                                (script[j].CycleTemp && SG->StrICmp(temp, script[j].CycleTemp) == 0);
            if (!conflicts && GetFileAttributesA(temp) == INVALID_FILE_ATTRIBUTES &&
                GetLastError() == ERROR_FILE_NOT_FOUND)
            {
                vacant = true;
                break;
            }
        }
        if (!vacant)
            continue;

        if (!validate)
        {
            script[count].CycleTemp = SG->DupStr(temp);
            if (!script[count].CycleTemp)
                goto LBUILD_SCRIPT_ERROR;
            script[count].CycleLength = length;
        }
        // Move the entries which depend on the staged file first. The
        // staged file itself is moved from its temporary name last.
        current = tmpScript[i].Blocks;
        for (int j = 0; j < length; ++j)
        {
            if (!validate)
            {
                script[count].Source = tmpScript[current].Source;
                script[count].NewName = tmpScript[current].NewName;
                script[count].NewPart = tmpScript[current].NewPart;
                script[count].Blocks = j + 1 < length;
                tmpScript[current].NewName = NULL;
            }
            tmpScript[current].Done = 1;
            ++count;
            current = tmpScript[current].Blocks;
        }
    }

    // if there are items that cannot be renamed, display them
    if (count < SourceFiles.Count - skipped)
    {
        for (i = 0; i < SourceFiles.Count; i++)
        {
            if (!tmpScript[i].Skip && !tmpScript[i].Done)
            {
                FileError(HWindow, tmpScript[i].Source->FullName, IDS_DEPENDENCE,
                          FALSE, &skip, &SkipAllDependingNames, IDS_ERROR);
                if (!skip)
                    goto LBUILD_SCRIPT_ERROR;
            }
        }
    }

    ret = TRUE; // if we got here, everything is OK
    Progress->Update(1000);

LBUILD_SCRIPT_ERROR:

    if (!ret && !usrBreak)
    {
        // focus the item with the error
        ListView_SetItemState(Preview->HWindow, i,
                              LVIS_FOCUSED | LVIS_SELECTED,
                              LVIS_FOCUSED | LVIS_SELECTED);
        ListView_EnsureVisible(Preview->HWindow, i, FALSE);

        // position the cursor on the line with the error
        if (ManualMode)
        {
            int charIndex = (int)SendMessage(ManualEdit.HWindow, EM_LINEINDEX, i, 0);
            if (charIndex >= 0)
            {
                HWND wnd = GetFocus();
                if (wnd != ManualEdit.HWindow)
                {
                    if (Progress) // so the focus can be set to the edit control
                    {
                        EnableWindow(HWindow, TRUE);
                        DestroyWindow(Progress->HWindow);
                        Progress = NULL;
                    }

                    SendMessage(HWindow, WM_NEXTDLGCTL, (WPARAM)ManualEdit.HWindow, TRUE);
                }
                SendMessage(ManualEdit.HWindow, EM_SETSEL, charIndex, charIndex);
                SendMessage(ManualEdit.HWindow, EM_SCROLLCARET, 0, 0);
            }
        }
    }

    if (tmpScript)
        delete[] tmpScript;
    if (!ret && script)
        delete[] script;

    return ret;
}

int CRenamerDialog::GetManualModeNewName(CSourceFile* file, int index, char* newName, char*& newPart)
{
    CALL_STACK_MESSAGE_NONE
    int pathLen = 0;
    switch (RenamerOptions.Spec)
    {
    case rsFileName:
    {
        pathLen = (int)(file->Name - file->FullName);
        if (pathLen < 0 || pathLen >= MAX_PATH)
            return -1;
        memcpy(newName, file->FullName, pathLen);
        break;
    }
    case rsRelativePath:
    {
        pathLen = RootLen;
        if (pathLen <= 0 || pathLen >= MAX_PATH)
            return -1;
        memcpy(newName, Root, pathLen);
        if (newName[pathLen - 1] != '\\')
            newName[pathLen++] = '\\';
        break;
    }
    case rsFullPath:
        break;
    }
    if (pathLen < 0 || pathLen >= MAX_PATH)
        return -1;
    newName += pathLen;
    newPart = newName;
    return ReadManualLineAnsi(ManualEdit.HWindow, index, newName, MAX_PATH - pathLen);
}

// Exchange only the owned pathname and its interior pointers. The replacement
// is allocated before touching the filesystem; its destructor frees the old name.
static void SwapCycleName(CSourceFile* file, CSourceFile* replacement)
{
    char* full = file->FullName;
    char* name = file->Name;
    char* ext = file->Ext;
    unsigned int len = file->NameLen;
    file->FullName = replacement->FullName;
    file->Name = replacement->Name;
    file->Ext = replacement->Ext;
    file->NameLen = replacement->NameLen;
    replacement->FullName = full;
    replacement->Name = name;
    replacement->Ext = ext;
    replacement->NameLen = len;
}

BOOL CRenamerDialog::MoveCycleFile(const char* source, const char* target)
{
    // Never replace a destination, even if it appeared after planning.
    // MOVEFILE_COPY_ALLOWED is deliberately not set.
    while (true)
    {
        DWORD attr = GetFileAttributesA(source);
        if (attr != INVALID_FILE_ATTRIBUTES)
        {
            if (attr & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))
                SetLastError(ERROR_ACCESS_DENIED);
            else if (MoveFileExA(source, target, 0))
                return TRUE;
        }
        BOOL skip;
        if (!FileError(HWindow, source, IDS_MOVEERROR,
                       TRUE, &skip, &SkipAllMove, IDS_ERROR))
            return FALSE;
    }
}

BOOL CRenamerDialog::ExecuteCycleMove(CSourceFile* source, CSourceFile*& renamed,
                                      const char* target, BOOL stage, BOOL blocks)
{
    char* oldName = renamed ? renamed->FullName : source->FullName;
    CSourceFile* result = new CSourceFile(source, target);
    CUndoStackEntry* undo = new CUndoStackEntry(result->FullName, oldName,
                                               renamed ? renamed : result, FALSE, blocks);
    undo->CycleMove = 1;
    undo->CycleStage = stage ? 1 : 0;
    undo->Intermediate = renamed != NULL;

    // Publish bookkeeping before the physical move. On failure remove only
    // the tentative entries; previous successful steps remain undoable.
    const int added = renamed ? -1 : RenamedFiles.Add(result);
    if ((!renamed && added < 0) || !undo->Source || !undo->Target)
    {
        if (added >= 0)
            RenamedFiles.Detach(added);
        if (!RenamedFiles.IsGood())
            RenamedFiles.ResetState();
        delete undo;
        delete result;
        return Error(IDS_LOWMEM);
    }
    const int undoIndex = UndoStack.Add(undo);
    if (undoIndex < 0)
    {
        UndoStack.ResetState();
        if (added >= 0)
            RenamedFiles.Detach(added);
        delete undo;
        delete result;
        return Error(IDS_LOWMEM);
    }
    if (!MoveCycleFile(oldName, target))
    {
        UndoStack.Delete(undoIndex);
        if (added >= 0)
            RenamedFiles.Detach(added);
        delete result;
        return FALSE;
    }
    if (renamed)
    {
        SwapCycleName(renamed, result);
        delete result;
    }
    else
        renamed = result;
    source->State = 1;
    return TRUE;
}

BOOL CRenamerDialog::UndoCycleMove(CUndoStackEntry* entry)
{
    int index = RenamedFiles.Count - 1;
    while (index >= 0 && RenamedFiles[index] != entry->RenamedFile)
        --index;
    if (index < 0 || strcmp(entry->RenamedFile->FullName, entry->Source) != 0)
        return Error(IDS_DEPENDENCE);

    CSourceFile* restored = new CSourceFile(entry->RenamedFile, entry->Target);
    int added = -1;
    if (!entry->Intermediate)
    {
        added = NotRenamedFiles.Add(restored);
        if (added < 0)
        {
            NotRenamedFiles.ResetState();
            delete restored;
            return Error(IDS_LOWMEM);
        }
    }
    if (!MoveCycleFile(entry->Source, entry->Target))
    {
        if (added >= 0)
            NotRenamedFiles.Detach(added);
        delete restored;
        return FALSE;
    }
    if (entry->Intermediate)
    {
        SwapCycleName(entry->RenamedFile, restored);
        delete restored;
    }
    else
        RenamedFiles.Delete(index);
    return TRUE;
}

void CRenamerDialog::ExecuteScript(CRenameScriptEntry* script, int count)
{
    CALL_STACK_MESSAGE2("CRenamerDialog::ExecuteScript(, %d)", count);
    BOOL skip;
    SkipAllOverwrite = SkipAllMove = SkipAllDeleteErr = SkipAllBadWrite =
        SkipAllBadRead = SkipAllOpenOut = SkipAllOpenIn =
            SkipAllDirChangeCase = SkipAllCreateDir = FALSE;

    Progress->SetText(LoadStr(IDS_RENAMING));

    // perform the rename
    BOOL blocked = FALSE;
    BOOL success = TRUE;
    int i;
    for (i = 0; i < count; i++)
    {
        if (script[i].CycleLength)
        {
            const int end = i + script[i].CycleLength - 1;
            CSourceFile* staged = NULL;
            if (!ExecuteCycleMove(script[end].Source, staged, script[i].CycleTemp, TRUE, FALSE))
            {
                Errors = TRUE;
                break;
            }
            for (; i <= end; ++i)
            {
                if (Progress->Update(i * 1000 / count))
                {
                    Errors = TRUE;
                    return;
                }
                CSourceFile* renamed = i == end ? staged : NULL;
                if (!ExecuteCycleMove(script[i].Source, renamed, script[i].NewName, FALSE, TRUE))
                {
                    Errors = TRUE;
                    return;
                }
            }
            i = end;
            success = TRUE;
            blocked = FALSE;
            if (Progress->Update((i + 1) * 1000 / count))
            {
                Errors = TRUE;
                break;
            }
            continue;
        }
        if (success || !blocked)
        {
            success = MoveFile(script[i].Source->FullName, script[i].NewName, script[i].NewPart,
                               script[i].Overwrite, script[i].Source->IsDir, skip);
        }
        else
        {
            FileError(HWindow, script[i].Source->FullName, IDS_DEPENDENCE,
                      FALSE, &skip, &SkipAllDependingNames, IDS_ERROR);
        }
        if (success)
        {
            if (RemoveSourcePath)
            {
                char dir[MAX_PATH];
                strcpy(dir, script[i].Source->FullName);
                do
                {
                    SG->CutDirectory(dir);
                    SG->ClearReadOnlyAttr(dir); // so it can be deleted
                } while (RemoveDirectory(dir));
            }
            script[i].Source->State = 1;
            CSourceFile* f = new CSourceFile(script[i].Source, script[i].NewName);
            RenamedFiles.Add(f);
            UndoStack.Add(new CUndoStackEntry(script[i].NewName, script[i].Source->FullName,
                                              f, script[i].Source->IsDir, blocked));
        }
        else
        {
            Errors = TRUE;
            if (!skip)
                return;
        }
        blocked = script[i].Blocks;
        if (Progress->Update((i + 1) * 1000 / count))
        {
            Errors = TRUE;
            break;
        }
    }
}

void CRenamerDialog::Undo()
{
    CALL_STACK_MESSAGE1("CRenamerDialog::Undo()");
    Undoing = TRUE;
    SkipAllOverwrite = SkipAllMove = SkipAllDeleteErr = SkipAllBadWrite =
        SkipAllBadRead = SkipAllOpenOut = SkipAllOpenIn =
            SkipAllDirChangeCase = SkipAllCreateDir = SkipAllFileDir =
                SkipAllDependingNames = SkipAllRemoveDir = FALSE;

    // create the progress dialog
    Progress = new CProgressDialog(HWindow);
    Progress->Create();
    EnableWindow(HWindow, FALSE);
    Progress->SetText(LoadStr(IDS_UNDOING));
    Progress->EmptyMessageLoop();

    int total = UndoStack.Count;
    int done = 0;
    BOOL skip;
    BOOL blocked = FALSE;
    BOOL success = TRUE;
    BOOL pathSuccess = TRUE;
    int i;
    for (i = UndoStack.Count - 1; i >= 0; i--, done++)
    {
        CUndoStackEntry* entry = UndoStack[i];
        if (entry->RenamedFile)
        {
            if (Progress->Update(done * 1000 / total))
                break;

            // Save dependency metadata before deleting an owning array entry.
            const BOOL nextBlocked = entry->Blocks;
            if (entry->CycleMove)
            {
                // A failed/declined cycle step must not release its predecessor.
                // Stop even on Skip; the remaining stack can be retried later.
                if ((!success && blocked) || !UndoCycleMove(entry))
                    goto LUNDONE;
                UndoStack.Delete(i);
                blocked = nextBlocked;
                success = pathSuccess = TRUE;
                continue;
            }

            // undo move file
            if (success || !blocked)
            {
                success = MoveFile(entry->Source, entry->Target, entry->Target,
                                   FALSE, entry->IsDir, skip);
            }
            else
            {
                FileError(HWindow, entry->Source, IDS_DEPENDENCE,
                          FALSE, &skip, &SkipAllDependingNames, IDS_ERROR);
            }
            if (success)
            {
                int j;
                for (j = RenamedFiles.Count - 1; j >= 0; j--)
                {
                    if (RenamedFiles[j] == entry->RenamedFile)
                    {
                        RenamedFiles.Detach(j);
                        NotRenamedFiles.Add(entry->RenamedFile->SetName(entry->Target));
                        break;
                    }
                }
                UndoStack.Delete(i);
            }
            else
            {
                if (!skip)
                    goto LUNDONE;
            }
            blocked = nextBlocked;
            pathSuccess = success;
        }
        else
        {
            if (Progress->Update(done * 1000 / total))
            {
                if (pathSuccess)
                    entry->Independent = 1; // to allow continuing later
                break;
            }

            // clean up the path only when the file was successfully removed
            if (pathSuccess || entry->Independent)
            {
                if (entry->Target)
                {
                    // undo change directory case
                    while (1)
                    {
                        pathSuccess = SG->SalMoveFile(entry->Source, entry->Target, NULL);
                        if (pathSuccess)
                        {
                            UndoStack.Delete(i);
                            break;
                        }

                        if (!FileError(HWindow, entry->Source, IDS_DIRCASEERROR,
                                       TRUE, &skip, &SkipAllDirChangeCase, IDS_ERROR))
                        {
                            entry->Independent = 1; // to allow continuing later
                            if (!skip)
                                goto LUNDONE;
                            break;
                        }
                    }
                }
                else
                {
                    // undo create directory
                    while (1)
                    {
                        pathSuccess = RemoveDirectory(entry->Source);
                        if (pathSuccess)
                        {
                            UndoStack.Delete(i);
                            break;
                        }

                        if (!FileError(HWindow, entry->Source, IDS_REMOVEDIR,
                                       TRUE, &skip, &SkipAllRemoveDir, IDS_ERROR))
                        {
                            entry->Independent = 1; // to allow continuing later
                            if (!skip)
                                goto LUNDONE;
                            break;
                        }
                    }
                }
            }
        }
    }

    Progress->Update(done * 1000 / total);

LUNDONE:

    EnableWindow(HWindow, TRUE);
    DestroyWindow(Progress->HWindow);
    Undoing = FALSE;

    if (NotRenamedFiles.Count)
    {
        ProcessRenamed = FALSE;
        ProcessNotRenamed = TRUE;
    }
    for (int j = 0; j < UndoStack.Count; ++j)
        if (UndoStack[j]->CycleStage &&
            strcmp(UndoStack[j]->RenamedFile->FullName, UndoStack[j]->Source) == 0)
            ProcessRenamed = TRUE;
    ReloadSourceFiles();
}
