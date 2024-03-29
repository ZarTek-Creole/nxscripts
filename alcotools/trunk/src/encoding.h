/*++

AlcoTools - Alcoholicz dupe checker, zipscript, and utilities.
Copyright (c) 2005-2006 Alcoholicz Scripting Team

Module Name:
    Encoding

Author:
    neoxed (neoxed@gmail.com) Jun 30, 2006

Abstract:
    Encoding function prototypes.

--*/

#ifndef _ENCODING_H_
#define _ENCODING_H_

//
// UTF data types
//

typedef apr_uint32_t        utf32_t;
typedef apr_uint16_t        utf16_t;
typedef apr_byte_t          utf8_t;

//
// Encoding types
//

typedef signed char         encoding_t;

#define ENCODING_UNKNOWN    -1
#define ENCODING_DEFAULT    0
#define ENCODING_ASCII      1
#define ENCODING_LATIN1     2
#define ENCODING_UTF8       3
#define ENCODING_UTF16_BE   4
#define ENCODING_UTF16_LE   5
#define ENCODING_UTF32_BE   6
#define ENCODING_UTF32_LE   7


apr_status_t
EncInit(
    apr_pool_t *pool
    );

apr_status_t
EncConvert(
    encoding_t inEnc,
    const apr_byte_t *inBuffer,
    apr_size_t inLength,
    encoding_t outEnc,
    apr_byte_t **outBuffer,
    apr_size_t *outLength,
    apr_pool_t *pool
    );

encoding_t
EncDetect(
    const apr_byte_t *buffer,
    apr_size_t length,
    apr_size_t *offset
    );

encoding_t
EncGetCurrent(
    void
    );

const
char *
EncGetName(
    encoding_t type
    );

#endif // _ENCODING_H_
