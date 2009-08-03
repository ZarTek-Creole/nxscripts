/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006-2009 neoxed

Module Name:
    Debugging

Author:
    neoxed (neoxed@gmail.com) Aug 3, 2009

Abstract:
    Debugging function and macro declarations.

*/

#ifndef DEBUG_H_INCLUDED
#define DEBUG_H_INCLUDED

#ifdef DEBUG

BOOL FCALL CriticalSectionIsOwned(CRITICAL_SECTION *critSection);
BOOL FCALL CriticalSectionIsOwner(CRITICAL_SECTION *critSection);
#define CRITICAL_SECTION_IS_OWNER(x) (ASSERT(CriticalSectionIsOwner(x)))

VOID FCALL WaitForDebugger(VOID);

#else // DEBUG

#define CriticalSectionIsOwned(x)    ((VOID)0)
#define CriticalSectionIsOwner(x)    ((VOID)0)
#define CRITICAL_SECTION_IS_OWNER(x) ((VOID)0)

#define WaitForDebugger()            ((VOID)0)

#endif // DEBUG

#endif // DEBUG_H_INCLUDED