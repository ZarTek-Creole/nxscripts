/* LibTomCrypt, modular cryptographic library -- Tom St Denis
 *
 * LibTomCrypt is a library that provides various cryptographic
 * algorithms in a highly modular and flexible manner.
 *
 * The library is free for all purposes without any express
 * guarantee it works.
 *
 * Tom St Denis, tomstdenis@gmail.com, http://libtomcrypt.org
 */
#include "tomcrypt.h"

/**
   @file rng_get_bytes.c
   portable way to get secure random bits to feed a PRNG (Tom St Denis)
*/

#ifdef DEVRANDOM
/* on *NIX read /dev/random */
static unsigned long rng_nix(unsigned char *buf, unsigned long len,
                             void (*callback)(void))
{
    FILE *f;
    unsigned long x;
#ifdef TRY_URANDOM_FIRST
    f = fopen("/dev/urandom", "rb");
    if (f == NULL)
#endif /* TRY_URANDOM_FIRST */
       f = fopen("/dev/random", "rb");

    if (f == NULL) {
       return 0;
    }

    /* disable buffering */
    if (setvbuf(f, NULL, _IONBF, 0) != 0) {
       fclose(f);
       return 0;
    }

    x = (unsigned long)fread(buf, 1, (size_t)len, f);
    fclose(f);
    return x;
}

#endif /* DEVRANDOM */

/* Try the Microsoft CSP */
#ifdef WIN32
#define _WIN32_WINNT 0x0400
#include <windows.h>
#include <wincrypt.h>

static unsigned long rng_win32(unsigned char *buf, unsigned long len,
                               void (*callback)(void))
{
   HCRYPTPROV hProv = 0;
   if (!CryptAcquireContext(&hProv, NULL, MS_DEF_PROV, PROV_RSA_FULL,
                            (CRYPT_VERIFYCONTEXT | CRYPT_MACHINE_KEYSET)) &&
       !CryptAcquireContext (&hProv, NULL, MS_DEF_PROV, PROV_RSA_FULL,
                            CRYPT_VERIFYCONTEXT | CRYPT_MACHINE_KEYSET | CRYPT_NEWKEYSET))
      return 0;

   if (CryptGenRandom(hProv, len, buf) == TRUE) {
      CryptReleaseContext(hProv, 0);
      return len;
   } else {
      CryptReleaseContext(hProv, 0);
      return 0;
   }
}

#endif /* WIN32 */

/**
  Read the system RNG
  @param out       Destination
  @param outlen    Length desired (octets)
  @param callback  Pointer to void function to act as "callback" when RNG is slow.  This can be NULL
  @return Number of octets read
*/
unsigned long rng_get_bytes(unsigned char *out, unsigned long outlen,
                            void (*callback)(void))
{
   unsigned long x;

   LTC_ARGCHK(out != NULL);

#if defined(DEVRANDOM)
   x = rng_nix(out, outlen, callback);   if (x != 0) { return x; }
#endif
#ifdef WIN32
   x = rng_win32(out, outlen, callback); if (x != 0) { return x; }
#endif
   return 0;
}

/* $Source: /cvs/libtom/libtomcrypt/src/prngs/rng_get_bytes.c,v $ */
/* $Revision: 1.3 $ */
/* $Date: 2005/05/05 14:35:59 $ */
