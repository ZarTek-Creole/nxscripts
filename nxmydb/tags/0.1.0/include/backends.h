/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006-2007 neoxed

Module Name:
    Backends

Author:
    neoxed (neoxed@gmail.com) Jun 5, 2006

Abstract:
    User and group storage backend declarations.

*/

#include <database.h>

#ifndef BACKENDS_H_INCLUDED
#define BACKENDS_H_INCLUDED

//
// Module context structure
//

typedef struct {
    HANDLE  file;   // Handle to the user/group file
} MOD_CONTEXT;

//
// Group database backend
//

DWORD DbGroupCreate(DB_CONTEXT *dbContext, CHAR *groupName, GROUPFILE *groupFile);
DWORD DbGroupRename(DB_CONTEXT *dbContext, CHAR *groupName, CHAR *newName);
DWORD DbGroupDelete(DB_CONTEXT *dbContext, CHAR *groupName);
DWORD DbGroupLock(DB_CONTEXT *dbContext, CHAR *groupName, GROUPFILE *groupFile);
DWORD DbGroupUnlock(DB_CONTEXT *dbContext, CHAR *groupName);
DWORD DbGroupOpen(DB_CONTEXT *dbContext, CHAR *groupName, GROUPFILE *groupFile);
DWORD DbGroupWrite(DB_CONTEXT *dbContext, CHAR *groupName, GROUPFILE *groupFile);
DWORD DbGroupClose(GROUPFILE *groupFile);

DWORD DbGroupRefresh(DB_CONTEXT *dbContext);

//
// Group file backend
//

DWORD FileGroupDefault(GROUPFILE *groupFile);
DWORD FileGroupCreate(INT32 groupId, GROUPFILE *groupFile);
DWORD FileGroupDelete(INT32 groupId);
DWORD FileGroupOpen(INT32 groupId, GROUPFILE *groupFile);
DWORD FileGroupWrite(GROUPFILE *groupFile);
DWORD FileGroupClose(GROUPFILE *groupFile);

//
// User database backend
//

DWORD DbUserCreate(DB_CONTEXT *dbContext, CHAR *userName, USERFILE *userFile);
DWORD DbUserRename(DB_CONTEXT *dbContext, CHAR *userName, CHAR *newName);
DWORD DbUserDelete(DB_CONTEXT *dbContext, CHAR *userName);
DWORD DbUserLock(DB_CONTEXT *dbContext, CHAR *userName, USERFILE *userFile);
DWORD DbUserUnlock(DB_CONTEXT *dbContext, CHAR *userName);
DWORD DbUserOpen(DB_CONTEXT *dbContext, CHAR *userName, USERFILE *userFile);
DWORD DbUserWrite(DB_CONTEXT *dbContext, CHAR *userName, USERFILE *userFile);
DWORD DbUserClose(USERFILE *userFile);

DWORD DbUserRefresh(DB_CONTEXT *dbContext);

//
// User file backend
//

DWORD FileUserDefault(USERFILE *userFile);
DWORD FileUserCreate(INT32 userId, USERFILE *userFile);
DWORD FileUserDelete(INT32 userId);
DWORD FileUserOpen(INT32 userId, USERFILE *userFile);
DWORD FileUserWrite(USERFILE *userFile);
DWORD FileUserClose(USERFILE *userFile);

#endif // BACKENDS_H_INCLUDED
