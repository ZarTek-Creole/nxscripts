/*++

AlcoTools - Alcoholicz dupe checker, zipscript, and utilities.
Copyright (c) 2005-2006 Alcoholicz Scripting Team

Module Name:
    Common

Author:
    neoxed (neoxed@gmail.com) Jul 17, 2005

Abstract:
    Common header file that includes all necessary headers.

--*/

#ifndef _ALCOHOLICZ_H_
#define _ALCOHOLICZ_H_

//
// Header files
//

#ifdef HAVE_CONFIG_H
#   include "config.h"
#endif

#include "buildopts.h"

#if defined(_WIN32) || defined(_WIN64) || defined(WINDOWS) || defined(_WINDOWS)
#   include "platwin.h"
#else
#   include "platunix.h"
#endif

// APR library
#ifdef STATIC_LIB
#   define APR_DECLARE_STATIC 1
#endif
#include "apr.h"
#include "apr_env.h"
#include "apr_errno.h"
#include "apr_general.h"
#include "apr_file_info.h"
#include "apr_file_io.h"
#include "apr_strings.h"
#include "apr_pools.h"
#include "apr_time.h"
#ifdef WINDOWS
#   include "arch/win32/apr_arch_utf8.h"
#endif

// Boolean logic
typedef apr_byte_t bool_t;
#ifndef TRUE
#   define TRUE  1
#endif
#ifndef FALSE
#   define FALSE 0
#endif

// Third-party libraries
#include "queue.h"
#include "sqlite3.h"
#include "zlib.h"

// Functions and subsystems
#include "cfgread.h"
#include "crc32.h"
#include "dynstring.h"
#include "encoding.h"
#include "events.h"
#include "logging.h"
#include "stream.h"
#include "template.h"
#include "utfconvert.h"
#include "utils.h"


//
// Global variables
//

extern STREAM *streamErr;
extern STREAM *streamOut;

#endif // _ALCOHOLICZ_H_
