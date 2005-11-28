/* This is the build config file.
 *
 * With this you can setup what to inlcude/exclude automatically during any build.  Just comment
 * out the line that #define's the word for the thing you want to remove.  phew!
 */

#ifndef TOMCRYPT_CFG_H
#define TOMCRYPT_CFG_H

/* you can change how memory allocation works ... */
void *XMALLOC(size_t n);
void *XREALLOC(void *p, size_t n);
void *XCALLOC(size_t n, size_t s);
void XFREE(void *p);

void XQSORT(void *base, size_t nmemb, size_t size, int(*compar)(const void *, const void *));


/* change the clock function too */
clock_t XCLOCK(void);

/* various other functions */
void *XMEMCPY(void *dest, const void *src, size_t n);
int   XMEMCMP(const void *s1, const void *s2, size_t n);
void *XMEMSET(void *s, int c, size_t n);

/* type of argument checking, 0=default, 1=fatal and 2=error+continue, 3=nothing */
#ifndef ARGTYPE
   #define ARGTYPE  0
#endif

/* Controls endianess and size of registers.  Leave uncommented to get platform neutral [slower] code
 *
 * Note: in order to use the optimized macros your platform must support unaligned 32 and 64 bit read/writes.
 * The x86 platforms allow this but some others [ARM for instance] do not.  On those platforms you **MUST**
 * use the portable [slower] macros.
 */

/* detect x86-32 machines somewhat */
#if defined(INTEL_CC) || (defined(_MSC_VER) && defined(WIN32)) || (defined(__GNUC__) && (defined(__DJGPP__) || defined(__CYGWIN__) || defined(__MINGW32__) || defined(__i386__)))
   #define ENDIAN_LITTLE
   #define ENDIAN_32BITWORD
   #define LTC_FAST
   #define LTC_FAST_TYPE    unsigned long
#endif

/* detects MIPS R5900 processors (PS2) */
#if (defined(__R5900) || defined(R5900) || defined(__R5900__)) && (defined(_mips) || defined(__mips__) || defined(mips))
   #define ENDIAN_LITTLE
   #define ENDIAN_64BITWORD
#endif

/* detect amd64 */
#if defined(__x86_64__)
   #define ENDIAN_LITTLE
   #define ENDIAN_64BITWORD
   #define LTC_FAST
   #define LTC_FAST_TYPE    unsigned long
#endif

/* detect PPC32 */
#if defined(LTC_PPC32)
   #define ENDIAN_BIG
   #define ENDIAN_32BITWORD
   #define LTC_FAST
   #define LTC_FAST_TYPE    unsigned long
#endif

/* detect sparc and sparc64 */
#if defined(__sparc__)
  #define ENDIAN_BIG
  #if defined(__arch64__)
    #define ENDIAN_64BITWORD
  #else
    #define ENDIAN_32BITWORD
  #endif
#endif


#ifdef LTC_NO_FAST
   #ifdef LTC_FAST
      #undef LTC_FAST
   #endif
#endif

/* No asm is a quick way to disable anything "not portable" */
#ifdef LTC_NO_ASM
   #undef ENDIAN_LITTLE
   #undef ENDIAN_BIG
   #undef ENDIAN_32BITWORD
   #undef ENDIAN_64BITWORD
   #undef LTC_FAST
   #undef LTC_FAST_TYPE
   #define LTC_NO_ROLC
	#define LTC_NO_BSWAP
#endif

/* #define ENDIAN_LITTLE */
/* #define ENDIAN_BIG */

/* #define ENDIAN_32BITWORD */
/* #define ENDIAN_64BITWORD */

#if (defined(ENDIAN_BIG) || defined(ENDIAN_LITTLE)) && !(defined(ENDIAN_32BITWORD) || defined(ENDIAN_64BITWORD))
    #error You must specify a word size as well as endianess in mycrypt_cfg.h
#endif

#if !(defined(ENDIAN_BIG) || defined(ENDIAN_LITTLE))
   #define ENDIAN_NEUTRAL
#endif

#endif


/* $Source: /cvs/libtom/libtomcrypt/src/headers/tomcrypt_cfg.h,v $ */
/* $Revision: 1.14 $ */
/* $Date: 2005/11/23 01:15:05 $ */
