/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006-2009 neoxed

Module Name:
    Logging

Author:
    neoxed (neoxed@gmail.com) Sep 15, 2007

Abstract:
    Logging function and macro declarations.

*/

#ifndef LOGGING_H_INCLUDED
#define LOGGING_H_INCLUDED

//
// Debugger logging
//

#define LOG_BACKEND_DEBUG 1

DWORD FCALL LogDebuggerInit(VOID);
DWORD FCALL LogDebuggerFinalize(VOID);

VOID  CCALL LogDebuggerFormat(const CHAR *format, ...);
VOID  FCALL LogDebuggerFormatV(const CHAR *format, va_list argList);

VOID  CCALL LogDebuggerTrace(const CHAR *file, const CHAR *func, INT line, const CHAR *format, ...);
VOID  SCALL LogDebuggerTraceV(const CHAR *file, const CHAR *func, INT line, const CHAR *format, va_list argList);


//
// File logging
//

#define LOG_BACKEND_FILE 2

DWORD FCALL LogFileInit(VOID);
DWORD FCALL LogFileFinalize(VOID);

VOID  CCALL LogFileFormat(const CHAR *format, ...);
VOID  FCALL LogFileFormatV(const CHAR *format, va_list argList);

VOID  CCALL LogFileTrace(const CHAR *file, const CHAR *func, INT line, const CHAR *format, ...);
VOID  SCALL LogFileTraceV(const CHAR *file, const CHAR *func, INT line, const CHAR *format, va_list argList);


//
// Logging
//

typedef enum {
    LOG_LEVEL_OFF   = 0,
    LOG_LEVEL_ERROR = 1,
    LOG_LEVEL_WARN  = 2,
    LOG_LEVEL_INFO  = 3,
} LOG_LEVEL;

DWORD FCALL LogInit(VOID);
DWORD FCALL LogFinalize(VOID);
const CHAR *LogFileName(const CHAR *path);

VOID  CCALL LogFormat(LOG_LEVEL level, const CHAR *format, ...);
VOID  FCALL LogFormatV(LOG_LEVEL level, const CHAR *format, va_list argList);

VOID  CCALL LogTrace(const CHAR *file, const CHAR *func, INT line, LOG_LEVEL level, const CHAR *format, ...);
VOID  SCALL LogTraceV(const CHAR *file, const CHAR *func, INT line, LOG_LEVEL level, const CHAR *format, va_list argList);


//
// Logging macros
//

#ifndef CRLF
#   define CRLF "\r\n"
#endif

#ifdef DEBUG
#   define LOG_OPTION_BACKEND  LOG_BACKEND_FILE
#   define LOG_OPTION_TRACE    1
#else
#   define LOG_OPTION_BACKEND  LOG_BACKEND_FILE
#   define LOG_OPTION_TRACE    0
#endif

#if LOG_OPTION_TRACE
#   define LOG_ERROR(format, ...)  LogTrace(__FILE__, __FUNCTION__, __LINE__, LOG_LEVEL_ERROR, format CRLF, __VA_ARGS__)
#   define LOG_WARN(format, ...)   LogTrace(__FILE__, __FUNCTION__, __LINE__, LOG_LEVEL_WARN,  format CRLF, __VA_ARGS__)
#   define LOG_INFO(format, ...)   LogTrace(__FILE__, __FUNCTION__, __LINE__, LOG_LEVEL_INFO,  format CRLF, __VA_ARGS__)
#else
#   define LOG_ERROR(format, ...)  LogFormat(LOG_LEVEL_ERROR, format CRLF, __VA_ARGS__)
#   define LOG_WARN(format, ...)   LogFormat(LOG_LEVEL_WARN,  format CRLF, __VA_ARGS__)
#   define LOG_INFO(format, ...)   LogFormat(LOG_LEVEL_INFO,  format CRLF, __VA_ARGS__)
#endif


//
// Debug tracing
//

#if LOG_OPTION_TRACE
#   define TRACE(format, ...)  LogDebuggerTrace(__FILE__, __FUNCTION__, __LINE__, format CRLF, __VA_ARGS__)
#else
#   define TRACE(format, ...)  ((VOID)0)
#endif

#endif // LOGGING_H_INCLUDED
