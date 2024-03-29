/*

nxSDK - ioFTPD Software Development Kit
Copyright (c) 2006 neoxed

Module Name:
    Utilities

Author:
    neoxed (neoxed@gmail.com) Jun 4, 2006

Abstract:
    Miscellaneous utilities.

*/

#include "mod.h"

/*++

OutputDebugger

    Sends debug output to the debugger.

Arguments:
    format  - Pointer to a buffer containing a printf-style format string.

    ...     - Arguments to insert into "format".

Return Values:
    None.

--*/
#ifdef DEBUG
void
OutputDebugger(
    const char *format,
    ...
    )
{
    char output[1024];
    DWORD error;
    va_list argList;

    // Preserve system error code
    error = GetLastError();

    va_start(argList, format);
    StringCchVPrintfA(output, ARRAYSIZE(output), format, argList);
    OutputDebugStringA(output);
    va_end(argList);

    // Restore system error code
    SetLastError(error);
}
#endif // DEBUG

/*++

OutputFile

    Writes debug output to a file.

Arguments:
    format  - Pointer to a buffer containing a printf-style format string.

    ...     - Arguments to insert into "format".

Return Values:
    None.

--*/
#ifdef DEBUG
void
OutputFile(
    const char *format,
    ...
    )
{
    DWORD error;
    FILE *handle;
    SYSTEMTIME now;
    va_list argList;

    // Preserve system error code
    error = GetLastError();

    handle = fopen("nxMod.log", "a");
    if (handle != NULL) {
        GetSystemTime(&now);
        fprintf(handle, "%04d-%02d-%02d %02d:%02d:%02d ",
            now.wYear, now.wMonth, now.wDay,
            now.wHour, now.wMinute, now.wSecond);

        va_start(argList, format);
        vfprintf(handle, format, argList);
        va_end(argList);

        fclose(handle);
    }

    // Restore system error code
    SetLastError(error);
}
#endif // DEBUG
