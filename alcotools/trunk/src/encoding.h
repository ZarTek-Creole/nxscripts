/*++

AlcoTools - Alcoholicz dupe checker, zipscript, and utilities.
Copyright (c) 2005-2006 Alcoholicz Scripting Team

Module Name:
    UTF

Author:
    neoxed (neoxed@gmail.com) Jun 30, 2006

Abstract:
    Encoding function prototypes.

--*/

#ifndef _ENCODING_H_
#define _ENCODING_H_

typedef apr_uint32_t    UTF32;
typedef apr_uint16_t    UTF16;
typedef apr_byte_t      UTF8;

typedef enum {
    ENCODING_ASCII = 0,
    ENCODING_UTF8,
    ENCODING_UTF16_BE,
    ENCODING_UTF16_LE,
    ENCODING_UTF32_BE,
    ENCODING_UTF32_LE
} ENCODING_TYPE;


ENCODING_TYPE
EncDetect(
    const apr_byte_t *buffer,
    apr_size_t length,
    apr_size_t *offset
    );

const
char *
EncGetName(
    ENCODING_TYPE type
    );

#endif // _ENCODING_H_
