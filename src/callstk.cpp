// SPDX-FileCopyrightText: 2023 Open Salamander Authors
// SPDX-License-Identifier: GPL-2.0-or-later
// CommentsTranslationProject: TRANSLATED

#include "precomp.h"

#include "mainwnd.h"
#include "usermenu.h"
#include "snooper.h"
#include "cfgdlg.h"
#include "dialogs.h"
#include "tasklist.h"

#ifndef CALLSTK_DISABLE

// The order here is important.
// Section names must be 8 characters or less.
// The sections with the same name before the $
// are merged into one section. The order that
// they are merged is determined by sorting
// the characters after the $.
// i_callstk and i_callstk_end are used to set
// boundaries so we can find the real functions
// that we need to call for initialization.

#pragma warning(disable : 4075) // we want to define the module initialization order

typedef void(__cdecl* _PVFV)(void);

#pragma section(".i_cst$a", read)
__declspec(allocate(".i_cst$a")) const _PVFV i_callstk = (_PVFV)1; // place i_callstk variable at the start of the .i_cst section

#pragma section(".i_cst$z", read)
__declspec(allocate(".i_cst$z")) const _PVFV i_callstk_end = (_PVFV)1; // place i_callstk_end variable at the end of the .i_cst section

void Initialize__CallStk()
{
    const _PVFV* x = &i_callstk;
    for (++x; x < &i_callstk_end; ++x)
        if (*x != NULL)
            (*x)();
}

#pragma init_seg(".i_cst$m")

BOOL CCallStack::SectionOK = FALSE;
DWORD CCallStack::TlsIndex = 0;
CRITICAL_SECTION CCallStack::Section;
TIndirectArray<CCallStack> CCallStack::CallStacks(10, 10, dtNoDelete);
BOOL CCallStack::ExceptionExists = FALSE;
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
LARGE_INTEGER CCallStack::SavedPerfFreq = {1};
DWORD CCallStack::SpeedBenchmark = 0;
BOOL __CallStk_T = TRUE;
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)

CCallStack MainThreadStack; // ensure the call-stack object is created before constructors run in the main thread

//
// ****************************************************************************
// CCallStack
//

void BenchmarkCallStkTestFunction(int counter, const char* string)
{
    CALL_STACK_MESSAGE3("BenchmarkCallStkTestFunction(%d, %s)", counter, string);
}

CCallStack::CCallStack(BOOL dontSuspend)
{
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    PushesCounter = 0;
    PushPerfTimeCounter.QuadPart = 0;
    IgnoredPushPerfTimeCounter.QuadPart = 0;
    MonitoredItems = NULL;
    MonitoredItemsSize = 0;
    NewestItemIndex = -1;
    OldestItemIndex = -1;
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)

    DontSuspend = dontSuspend;
    FirstCallstack = (TlsIndex == 0);
    if (TlsIndex == 0)
        TlsIndex = HANDLES(TlsAlloc());
    TlsSetValue(TlsIndex, this);

    if (!SectionOK)
    {
        HANDLES(InitializeCriticalSection(&Section));
        SectionOK = TRUE;
    }

    ThreadID = GetCurrentThreadId();

    if (HANDLES(DuplicateHandle(GetCurrentProcess(), GetCurrentThread(),
                                GetCurrentProcess(), &ThreadHandle,
                                0, FALSE, DUPLICATE_SAME_ACCESS)) == 0)
    {
        TRACE_E("DuplicateHandle failed.");
        ThreadHandle = NULL;
    }

    PluginDLLName = NULL;
    PluginDLLNameUses = 0;

    HANDLES(EnterCriticalSection(&Section));
    CallStacks.Add(this);
    HANDLES(LeaveCriticalSection(&Section));

    Text[0] = 0;
    End = Text;
    Skipped = 0;
    Reset();


#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    if (CCallStack::SavedPerfFreq.QuadPart == 1)
    {
        if (!QueryPerformanceFrequency(&CCallStack::SavedPerfFreq))
            CCallStack::SavedPerfFreq.QuadPart = 1;
        if (CCallStack::SavedPerfFreq.QuadPart == 0)
            CCallStack::SavedPerfFreq.QuadPart = 1; // unlikely, but check just in case (we divide by this value)
    }
    static BOOL doBenchmark = TRUE;
    if (doBenchmark)
    {
        doBenchmark = FALSE;
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL); // try to catch system attention (avoid measuring e.g. another process's swapping)
        LARGE_INTEGER startTime, ti, endTime;
        if (QueryPerformanceCounter(&startTime))
        {
            endTime.QuadPart = CALLSTK_BENCHMARKTIME * CCallStack::SavedPerfFreq.QuadPart / 1000 + startTime.QuadPart;
            int counter = 0;
            while (1)
            {
                int i;
                for (i = 0; i < 1000; i++)
                    BenchmarkCallStkTestFunction(i, "this is just speed measurement");
                counter++;
                QueryPerformanceCounter(&ti);
                if (ti.QuadPart >= endTime.QuadPart)
                {
                    SpeedBenchmark = (DWORD)((__int64)counter * 1000 * CALLSTK_BENCHMARKTIME / (((ti.QuadPart - startTime.QuadPart) * 1000) / CCallStack::SavedPerfFreq.QuadPart));
                    TRACE_I("CCallStack::CCallStack(): Speed Benchmark: " << SpeedBenchmark << " calls in " << CALLSTK_BENCHMARKTIME << "ms");
                    break;
                }
            }
        }
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL);
        if (SpeedBenchmark == 0)
            TRACE_E("CCallStack::CCallStack(): unable to compute Speed Benchmark!");
    }
#else  // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    static BOOL doBenchmark = TRUE;
    if (doBenchmark)
    {
        doBenchmark = FALSE;
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL); // try to catch system attention (avoid measuring e.g. another process's swapping)
        LARGE_INTEGER startTime, ti, endTime, freq;
        if (QueryPerformanceCounter(&startTime) && QueryPerformanceFrequency(&freq))
        {
            endTime.QuadPart = 100 * freq.QuadPart / 1000 + startTime.QuadPart;
            int counter = 0;
            while (1)
            {
                int i;
                for (i = 0; i < 1000; i++)
                    BenchmarkCallStkTestFunction(i, "this is just speed measurement");
                counter++;
                QueryPerformanceCounter(&ti);
                if (ti.QuadPart >= endTime.QuadPart)
                {
                    DWORD speedBenchmark = (DWORD)((__int64)counter * 1000 * 100 / (((ti.QuadPart - startTime.QuadPart) * 1000) / freq.QuadPart));
                    TRACE_I("CCallStack::CCallStack(): Speed Benchmark: " << speedBenchmark << " calls in " << 100 << "ms");
                    break;
                }
            }
        }
        SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_NORMAL);
    }
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
}

CCallStack::~CCallStack()
{
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    if (MonitoredItems != NULL)
    {
        //    TRACE_I("CCallStack::~CCallStack(): MonitoredItemsSize=" << MonitoredItemsSize);
        if (OldestItemIndex != -1)
        {
            while (1) // Process the queue once more and print the final states of critical call-stack calls
            {
                if (!MonitoredItems[OldestItemIndex].NotAlreadyReported) // if it was already reported, print final values
                {
                    TRACE_I("Info for Too Frequently Used Call Stack Message: call address: 0x" << std::hex << MonitoredItems[OldestItemIndex].CallerAddress << std::dec << ", total push-time: " << (DWORD)(MonitoredItems[OldestItemIndex].PushesPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, total number of calls in monitored period: " << MonitoredItems[OldestItemIndex].NumberOfCalls);
                }
                if (OldestItemIndex == NewestItemIndex)
                {
                    OldestItemIndex = NewestItemIndex = -1; // the queue emptied
                    break;
                }
                OldestItemIndex++;
                if (OldestItemIndex >= MonitoredItemsSize)
                    OldestItemIndex = 0;
            }
        }
        free(MonitoredItems);
        MonitoredItemsSize = 0;
    }
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    HANDLES(EnterCriticalSection(&Section));
    int i;
    for (i = 0; i < CallStacks.Count; i++)
    {
        if (CallStacks[i] == this)
        {
            CallStacks.Delete(i);
            i = -1;
            break;
        }
    }
    if (i == CallStacks.Count)
        TRACE_E("This should never happen.");
    if (ThreadHandle != NULL)
    {
        HANDLES(CloseHandle(ThreadHandle));
        ThreadHandle = NULL;
    }
    HANDLES(LeaveCriticalSection(&Section));
    if (FirstCallstack)
    {
        HANDLES(DeleteCriticalSection(&Section));
        SectionOK = FALSE;
        HANDLES(TlsFree(TlsIndex));
        TlsIndex = 0;
    }
}

void CCallStack::ReleaseBeforeExitThread()
{
    CCallStack* stack = CCallStack::GetThis();
    if (stack != NULL)
        stack->ReleaseBeforeExitThreadBody(); // unhandled threads have TLS set to NULL
    else
    {
        TRACE_E("Incorrect call to CCallStack::ReleaseBeforeExitThread(): call-stack object was not defined in this thread.");
    }
}

void CCallStack::ReleaseBeforeExitThreadBody()
{
    while (!DontSuspend && CCallStack::ExceptionExists)
        Sleep(1000); // instead of suspend-thread in the exception handler
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    if (MonitoredItems != NULL)
    {
        //    TRACE_I("CCallStack::~CCallStack(): MonitoredItemsSize=" << MonitoredItemsSize);
        if (OldestItemIndex != -1)
        {
            while (1) // go through the queue again and print the final values of critical call-stack invocations
            {
                if (!MonitoredItems[OldestItemIndex].NotAlreadyReported) // if it was already reported, print final values
                {
                    TRACE_I("Info for Too Frequently Used Call Stack Message: call address: 0x" << std::hex << MonitoredItems[OldestItemIndex].CallerAddress << std::dec << ", total push-time: " << (DWORD)(MonitoredItems[OldestItemIndex].PushesPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, total number of calls in monitored period: " << MonitoredItems[OldestItemIndex].NumberOfCalls);
                }
                if (OldestItemIndex == NewestItemIndex)
                {
                    OldestItemIndex = NewestItemIndex = -1; // the queue emptied
                    break;
                }
                OldestItemIndex++;
                if (OldestItemIndex >= MonitoredItemsSize)
                    OldestItemIndex = 0;
            }
        }
        free(MonitoredItems);
        MonitoredItemsSize = 0;
    }
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    HANDLES(EnterCriticalSection(&Section));
    int i;
    for (i = 0; i < CallStacks.Count; i++)
    {
        if (CallStacks[i] == this)
        {
            CallStacks.Delete(i);
            i = -1;
            break;
        }
    }
    if (i == CallStacks.Count)
        TRACE_E("This should never happen.");
    if (ThreadHandle != NULL)
    {
        HANDLES(CloseHandle(ThreadHandle));
        ThreadHandle = NULL;
    }
    HANDLES(LeaveCriticalSection(&Section));
}

void CCallStack::Push(const char* format, va_list args)
{
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    PushesCounter++;
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    while (!DontSuspend && CCallStack::ExceptionExists)
        Sleep(1000); // instead of SuspendThread in the exception handler
    if (STACK_CALLS_BUF_SIZE - (End - Text) >= STACK_CALLS_MAX_MESSAGE_LEN + 4)
    {
        char* backup = End;
        int ret;
        __try
        {
            ret = _vsnprintf_s(End, STACK_CALLS_MAX_MESSAGE_LEN + 1, _TRUNCATE, format, args);
            if (ret >= 0)
                End += ret + 1;
            else
            {
                strcpy(backup, "vsprintf error in: ");
                int len = (int)strlen(backup);
                lstrcpyn(backup + len, format, STACK_CALLS_MAX_MESSAGE_LEN + 1 - len);
                ret = (int)strlen(backup);
                End = backup + ret + 1;
            }
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            strcpy(backup, "exception in: ");
            int len = (int)strlen(backup);
            lstrcpyn(backup + len, format, STACK_CALLS_MAX_MESSAGE_LEN + 1 - len);
            ret = (int)strlen(backup);
            End = backup + ret + 1;
        }
        *(short*)End = (short)ret;
        End += 2;
        *End = 0; // double null terminated
    }
    else
    {
        Skipped++;
    }
}

void
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
CCallStack::Pop(BOOL printCallStackTop)
#else  // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
CCallStack::Pop()
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
{
    while (!DontSuspend && CCallStack::ExceptionExists)
        Sleep(1000); // instead of SuspendThread in the exception handler
    if (Skipped == 0)
    {
        if (End > Text)
        {
            End -= 2;
            End -= 1 + *(short*)End;
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
            if (printCallStackTop)
                TRACE_I("Top of Call Stack: " << End);
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
            *End = 0;
        }
        else
            TRACE_E("Incorrect call to CCallStack::Pop()!");
    }
    else
    {
        Skipped--;
    }
}

const char*
CCallStack::GetNextLine()
{
    if (Enum < End)
    {
        char* s = Enum;
        while (*Enum++ != 0)
            ;
        Enum += 2;
        return s;
    }
    else
    {
        return NULL;
    }
}

void InformAboutIconOvrlsHanCrash(const char* iconOvrlsHanName)
{
    __try
    {
        static char buf[900];
        _snprintf_s(buf, _TRUNCATE, LoadStr(IDS_ICONOVRLS_CRASH), iconOvrlsHanName);

        MSGBOXEX_PARAMS params;
        memset(&params, 0, sizeof(params));
        params.HParent = NULL;
        params.Flags = MB_ABORTRETRYIGNORE | MB_ICONERROR | MB_SETFOREGROUND;
        params.Caption = SALAMANDER_TEXT_VERSION;
        params.Text = buf;
        static char aliasBtnNames[200];
        /* used by the export_mnu.py script which generates salmenu.mnu for the Translator
   we let message box buttons handle hotkey collisions by simulating that they belong to a menu
MENU_TEMPLATE_ITEM MsgBoxButtons[] = 
{
  {MNTT_PB, 0
  {MNTT_IT, IDS_ICONOVRLS_DISTHIS
  {MNTT_IT, IDS_ICONOVRLS_DISALL
  {MNTT_PE, 0
};
*/
        sprintf(aliasBtnNames, "%d\t%s\t%d\t%s",
                DIALOG_ABORT, LoadStr(IDS_ICONOVRLS_DISTHIS),
                DIALOG_RETRY, LoadStr(IDS_ICONOVRLS_DISALL));
        params.AliasBtnNames = aliasBtnNames;
        int res = SalMessageBoxEx(&params);
        switch (res)
        {
        case DIALOG_ABORT:
        {
            if (!IsNameInListOfDisabledCustomIconOverlays(iconOvrlsHanName))
                AddToListOfDisabledCustomIconOverlays(iconOvrlsHanName);
            break;
        }

        case DIALOG_RETRY:
        {
            Configuration.EnableCustomIconOverlays = FALSE;
            break;
        }
        }
        if (res != DIALOG_IGNORE)
        {
            HKEY hSalamander;
            if (OpenKey(HKEY_CURRENT_USER, SalamanderConfigurationRoots[0], hSalamander)) // write data only if a configuration exists in the registry (which should almost always be the case)
            {
                HKEY actKey;
                if (OpenKey(hSalamander, SALAMANDER_CONFIG_REG, actKey)) // write data only if a configuration exists in the registry (which should almost always be the case)
                {
                    CloseKey(actKey);
                    if (CreateKey(hSalamander, SALAMANDER_CONFIG_REG, actKey))
                    {
                        // NOTE: normally, these values are written in CMainWindow::SaveConfig()
                        SetValue(actKey, CONFIG_ENABLECUSTICOVRLS_REG, REG_DWORD,
                                 &Configuration.EnableCustomIconOverlays, sizeof(DWORD));
                        SetValue(actKey, CONFIG_DISABLEDCUSTICOVRLS_REG, REG_SZ,
                                 Configuration.DisabledCustomIconOverlays != NULL ? Configuration.DisabledCustomIconOverlays : "", -1);

                        CloseKey(actKey);
                    }
                }
                CloseKey(hSalamander);
            }
        }
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
    }
}

int CCallStack::HandleException(EXCEPTION_POINTERS*, DWORD, const char*)
{
    // Existing SEH call sites use this return value as their filter expression.
    // Do not swallow the exception or terminate the process here: Windows
    // Error Reporting needs the original, unhandled exception to create a dump.
    return EXCEPTION_CONTINUE_SEARCH;
}

#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
void CCallStack::CheckCallFrequency(DWORD_PTR callerAddress, LARGE_INTEGER* pushTime, LARGE_INTEGER* afterPushTime)
{
    __int64 monitoringPeriod = CALLSTACK_MONITORINGPERIOD * CCallStack::SavedPerfFreq.QuadPart / 1000;
    __int64 oldestPerfTime = pushTime->QuadPart - monitoringPeriod;
    if (NewestItemIndex != -1) // try to find a record of a previous call of the same call-stack macro
    {
        int act = NewestItemIndex;
        while (1)
        {
            if (MonitoredItems[act].CallerAddress == callerAddress) // found
            {
                CCallStackMonitoredItem* item = &MonitoredItems[act];
                if (item->MonitoringStartPerfTime >= oldestPerfTime) // we still monitor it
                {
                    item->NumberOfCalls++;
                    item->PushesPerfTime += afterPushTime->QuadPart - pushTime->QuadPart;
                    __int64 totalTime = pushTime->QuadPart - item->MonitoringStartPerfTime;
                    if (item->NotAlreadyReported &&
                        totalTime > monitoringPeriod / 2 && item->PushesPerfTime > totalTime / CALLSTK_MONITOR_SHOWINFORATIO)
                    {                                                                                                                                                                                 // this trace is printed only once (after exceeding the critical time, the final state is printed later)
                        DWORD aproxMinCallsCount = (DWORD)((SpeedBenchmark * totalTime / (CALLSTK_BENCHMARKTIME * CCallStack::SavedPerfFreq.QuadPart / 1000)) / (3 * CALLSTK_MONITOR_SHOWINFORATIO)); // counting 3x slower than the measured call-stack macro
                        if (SpeedBenchmark != 0 && item->NumberOfCalls > aproxMinCallsCount)
                        { // suppress the case of increased time when the process/thread is rescheduled (it can measure 9ms for 4 call-stack invocations)
                            item->NotAlreadyReported = FALSE;
                            if (item->PushesPerfTime > totalTime / CALLSTK_MONITOR_SHOWERRORRATIO)
                            {
                                TRACE_E("Too Frequently Used Call Stack Message: time ratio callstack/total: " << (totalTime > 0 ? (DWORD)(100 * item->PushesPerfTime / totalTime) : 0) << "%, call address: 0x" << std::hex << item->CallerAddress << std::dec << " (see next line in trace-server for text), current push-time: " << (DWORD)(item->PushesPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, current total time: " << (DWORD)(totalTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, current number of calls in monitored period: " << item->NumberOfCalls);
                            }
                            else
                            {
                                TRACE_I("Maybe Too Frequently Used Call Stack Message: time ratio callstack/total: " << (totalTime > 0 ? (DWORD)(100 * item->PushesPerfTime / totalTime) : 0) << "%, call address: 0x" << std::hex << item->CallerAddress << std::dec << " (see next line in trace-server for text), current push-time: " << (DWORD)(item->PushesPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, current total time: " << (DWORD)(totalTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, current number of calls in monitored period: " << item->NumberOfCalls);
                            }
                            if (Skipped == 0 && End > Text) // print the text of the last push
                            {
                                char* end = End;
                                end -= 2;
                                end -= 1 + *(short*)end;
                                TRACE_I("Top of Call Stack: " << end);
                            }
                        }
                    }
                    return; // done
                }
                else
                    break; // add this call back to the queue
            }
            if (act == OldestItemIndex)
                break; // not found
            act--;
            if (act < 0)
                act = MonitoredItemsSize - 1;
        }
    }
    if (OldestItemIndex != -1) // first remove stale items (make room for a new one)
    {
        while (1)
        {
            if (MonitoredItems[OldestItemIndex].MonitoringStartPerfTime >= oldestPerfTime) // still within monitoring period
                break;
            else
            {
                if (!MonitoredItems[OldestItemIndex].NotAlreadyReported) // if it was already reported, log the final values
                {
                    TRACE_I("Info for Too Frequently Used Call Stack Message: call address: 0x" << std::hex << MonitoredItems[OldestItemIndex].CallerAddress << std::dec << ", total push-time: " << (DWORD)(MonitoredItems[OldestItemIndex].PushesPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, total number of calls in monitored period: " << MonitoredItems[OldestItemIndex].NumberOfCalls);
                }
            }
            if (OldestItemIndex == NewestItemIndex)
            {
                OldestItemIndex = NewestItemIndex = -1; // the queue emptied
                break;
            }
            OldestItemIndex++;
            if (OldestItemIndex >= MonitoredItemsSize)
                OldestItemIndex = 0;
        }
    }
    if (MonitoredItemsSize == 0) // the queue is not allocated yet; allocate it now
    {
        MonitoredItems = (CCallStackMonitoredItem*)malloc(CALLSTACK_MONITOREDITEMS_BASE * sizeof(CCallStackMonitoredItem));
        if (MonitoredItems == NULL)
        {
            TRACE_E(LOW_MEMORY);
            return;
        }
        MonitoredItemsSize = CALLSTACK_MONITOREDITEMS_BASE;
    }
    if (NewestItemIndex != -1 &&
        (NewestItemIndex < MonitoredItemsSize - 1 && NewestItemIndex + 1 == OldestItemIndex ||
         NewestItemIndex == MonitoredItemsSize - 1 && OldestItemIndex == 0))
    { // the queue is full; it needs to be enlarged
        CCallStackMonitoredItem* newMonitoredItems = (CCallStackMonitoredItem*)malloc((MonitoredItemsSize +
                                                                                       CALLSTACK_MONITOREDITEMS_DELTA) *
                                                                                      sizeof(CCallStackMonitoredItem));
        if (newMonitoredItems == NULL)
        {
            TRACE_E(LOW_MEMORY);
            return;
        }

        memcpy(newMonitoredItems, MonitoredItems, (NewestItemIndex + 1) * sizeof(CCallStackMonitoredItem));
        if (OldestItemIndex > 0)
        {
            memcpy(newMonitoredItems + OldestItemIndex + CALLSTACK_MONITOREDITEMS_DELTA,
                   MonitoredItems + OldestItemIndex, (MonitoredItemsSize - OldestItemIndex) * sizeof(CCallStackMonitoredItem));
            OldestItemIndex += CALLSTACK_MONITOREDITEMS_DELTA;
        }
        free(MonitoredItems);
        MonitoredItems = newMonitoredItems;
        MonitoredItemsSize += CALLSTACK_MONITOREDITEMS_DELTA;
    }
    if (NewestItemIndex == -1)
        NewestItemIndex = OldestItemIndex = 0;
    else
    {
        NewestItemIndex++;
        if (NewestItemIndex == MonitoredItemsSize)
            NewestItemIndex = 0;
    }
    CCallStackMonitoredItem* item = &MonitoredItems[NewestItemIndex];
    item->MonitoringStartPerfTime = pushTime->QuadPart;
    item->CallerAddress = callerAddress;
    item->NumberOfCalls = 1;
    item->PushesPerfTime = afterPushTime->QuadPart - pushTime->QuadPart;
    item->NotAlreadyReported = TRUE;
}
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)

//
// ****************************************************************************
// CCallStackMessage
//

// to avoid including the entire intrin.h
extern "C"
{
    void* _AddressOfReturnAddress(void);
}

#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
CCallStackMessage::CCallStackMessage(BOOL doNotMeasureTimes, int dummy, const char* format, ...)
#else  // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
CCallStackMessage::CCallStackMessage(const char* format, ...)
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
{
    va_list args;
    va_start(args, format);
    CCallStack* stack = CCallStack::GetThis();
    if (stack != NULL)
    {
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        LARGE_INTEGER pushTime;
        QueryPerformanceCounter(&pushTime);
#endif                             // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        stack->Push(format, args); // unhandled threads have TLS set to NULL
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        QueryPerformanceCounter(&StartTime);
        PushesCounterStart = stack->PushesCounter;
        if (!doNotMeasureTimes)
            stack->PushPerfTimeCounter.QuadPart += StartTime.QuadPart - pushTime.QuadPart;
        else
            stack->IgnoredPushPerfTimeCounter.QuadPart += StartTime.QuadPart - pushTime.QuadPart;
        PushPerfTimeCounterStart.QuadPart = stack->PushPerfTimeCounter.QuadPart;
        IgnoredPushPerfTimeCounterStart.QuadPart = stack->IgnoredPushPerfTimeCounter.QuadPart;

        __try
        {
            PushCallerAddress = *(DWORD_PTR*)_AddressOfReturnAddress();
            if (!doNotMeasureTimes)
                stack->CheckCallFrequency(PushCallerAddress, &pushTime, &StartTime);
        }
        __except (EXCEPTION_EXECUTE_HANDLER)
        {
            PushCallerAddress = 0;
        }
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    }
    else
    {
        TRACE_E("Invalid use of CALL_STACK_MESSAGE: call-stack object was not defined in this thread. Format=\"" << format << "\"");
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        PushesCounterStart = 0;
        StartTime.QuadPart = 0;
        PushCallerAddress = 0;
        PushPerfTimeCounterStart.QuadPart = 0;
        IgnoredPushPerfTimeCounterStart.QuadPart = 0;
#endif // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    }
    va_end(args);
}

CCallStackMessage::~CCallStackMessage()
{
    DWORD savedLastErr = GetLastError();
    CCallStack* stack = CCallStack::GetThis();
    if (stack != NULL)
    {
#if (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        BOOL printCallStackTop = FALSE;
        __int64 internalPushPerfTime = stack->PushPerfTimeCounter.QuadPart - PushPerfTimeCounterStart.QuadPart;
        if (internalPushPerfTime > 0) // only if Push was called recursively
        {
            LARGE_INTEGER endTime;
            QueryPerformanceCounter(&endTime);
            __int64 realPerfTime = (endTime.QuadPart - StartTime.QuadPart) -
                                   (stack->IgnoredPushPerfTimeCounter.QuadPart - IgnoredPushPerfTimeCounterStart.QuadPart); // subtract the time of ignored (unmeasured) Pushes, otherwise they would artificially improve the ratio
            if (realPerfTime / internalPushPerfTime < CALLSTK_MINRATIO && realPerfTime > 0 &&
                ((realPerfTime * 1000) / CCallStack::SavedPerfFreq.QuadPart) > CALLSTK_MINWARNTIME)
            {
                DWORD aproxMinCallsCount = (DWORD)(((CCallStack::SpeedBenchmark * (internalPushPerfTime + stack->IgnoredPushPerfTimeCounter.QuadPart - IgnoredPushPerfTimeCounterStart.QuadPart) * 1000) /
                                                    (CALLSTK_BENCHMARKTIME * CCallStack::SavedPerfFreq.QuadPart)) /
                                                   3); // counting 3x slower than the measured call-stack macro
                if (CCallStack::SpeedBenchmark != 0 && aproxMinCallsCount < stack->PushesCounter - PushesCounterStart)
                { // suppress the case of increased time when the process/thread is rescheduled (it can measure 50ms for 280 call-stack invocations)
                    TRACE_E("Call Stack Messages Slowdown Detected: time ratio callstack/total: " << (DWORD)(100 * internalPushPerfTime / realPerfTime) << "%, total time: " << (DWORD)((realPerfTime * 1000) / CCallStack::SavedPerfFreq.QuadPart) << "ms, push time: " << (DWORD)(internalPushPerfTime * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, ignored pushes: " << (DWORD)((stack->IgnoredPushPerfTimeCounter.QuadPart - IgnoredPushPerfTimeCounterStart.QuadPart) * 1000 / CCallStack::SavedPerfFreq.QuadPart) << "ms, call address: 0x" << std::hex << PushCallerAddress << std::dec << " (see next line in trace-server for text), count: " << (stack->PushesCounter - PushesCounterStart));
                    printCallStackTop = TRUE;
                }
            }
        }
        stack->Pop(printCallStackTop); // unhandled threads have TLS set to NULL
#else                                  // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
        stack->Pop(); // unhandled threads have TLS set to NULL
#endif                                 // (defined(_DEBUG) || defined(CALLSTK_MEASURETIMES)) && !defined(CALLSTK_DISABLEMEASURETIMES)
    }
    else
    {
        TRACE_E("Invalid use of CALL_STACK_MESSAGE: call-stack object was not defined in this thread.");
    }
    SetLastError(savedLastErr);
}

#endif // CALLSTK_DISABLE
