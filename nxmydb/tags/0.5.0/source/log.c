/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006-2008 neoxed

Module Name:
    Logging

Author:
    neoxed (neoxed@gmail.com) Sep 30, 2007

Abstract:
    Logging interface.

*/

#include <base.h>
#include <logging.h>

#if (LOG_OPTION_BACKEND == LOG_BACKEND_DEBUG)
#   define BACKEND_INIT     LogDebuggerInit
#   define BACKEND_FINAL    LogDebuggerFinalize
#   define BACKEND_FORMAT   LogDebuggerFormatV
#   define BACKEND_TRACE    LogDebuggerTraceV
#elif (LOG_OPTION_BACKEND == LOG_BACKEND_FILE)
#   define BACKEND_INIT     LogFileInit
#   define BACKEND_FINAL    LogFileFinalize
#   define BACKEND_FORMAT   LogFileFormatV
#   define BACKEND_TRACE    LogFileTraceV
#else
#   error Unknown logging backend.
#endif

static LOG_LEVEL logLevel;


DWORD SCALL LogInit(VOID)
{
    // Default to the error log level
    logLevel = LOG_LEVEL_ERROR;

    return BACKEND_INIT();
}

DWORD SCALL LogFinalize(VOID)
{
    return BACKEND_FINAL();
}

DWORD SCALL LogSetLevel(LOG_LEVEL level)
{
    logLevel = level;
    return ERROR_SUCCESS;
}

const CHAR *LogFileName(const CHAR *path)
{
    const CHAR *base;

    // Find the end of the string
    base = path;
    while (*base++ != '\0');

    // Find the last path separator
    while (--base != path && *base != '\\' && *base != '/');

    if (*base == '\\' || *base == '/') {
        base++;
    } else {
        // No path separator found, the path must already be a base name
        base = path;
    }

    return base;
}

VOID CCALL LogFormat(LOG_LEVEL level, const CHAR *format, ...)
{
    va_list argList;

    va_start(argList, format);
    LogFormatV(level, format, argList);
    va_end(argList);
}

VOID SCALL LogFormatV(LOG_LEVEL level, const CHAR *format, va_list argList)
{
    if (level <= logLevel) {
        BACKEND_FORMAT(format, argList);
    }
}

VOID CCALL LogTrace(const CHAR *file, const CHAR *func, INT line, LOG_LEVEL level, const CHAR *format, ...)
{
    va_list argList;

    va_start(argList, format);
    LogTraceV(file, func, line, level, format, argList);
    va_end(argList);
}

VOID SCALL LogTraceV(const CHAR *file, const CHAR *func, INT line, LOG_LEVEL level, const CHAR *format, va_list argList)
{
    if (level <= logLevel) {
        BACKEND_TRACE(file, func, line, format, argList);
    }
}
