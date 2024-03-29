/*

nxSDK - ioFTPD Software Development Kit
Copyright (c) 2006 neoxed

Module Name:
    Group Module

Author:
    neoxed (neoxed@gmail.com) Jun 4, 2006

Abstract:
    Entry point and functions for group modules.

*/

#include "mod.h"

//
// Function and type declarations
//

static INT   MODULE_CALL GroupFinalize(void);
static INT32 MODULE_CALL GroupCreate(char *groupName);
static INT   MODULE_CALL GroupRename(char *groupName, INT32 groupId, char *newName);
static INT   MODULE_CALL GroupDelete(char *groupName, INT32 groupId);
static INT   MODULE_CALL GroupLock(GROUPFILE *groupFile);
static INT   MODULE_CALL GroupUnlock(GROUPFILE *groupFile);
static INT   MODULE_CALL GroupRead(char *filePath, GROUPFILE *groupFile);
static INT   MODULE_CALL GroupWrite(GROUPFILE *groupFile);
static INT   MODULE_CALL GroupOpen(char *groupName, GROUPFILE *groupFile);
static INT   MODULE_CALL GroupClose(GROUPFILE *groupFile);

typedef struct {
    HANDLE fileHandle;
    volatile LONG locked;
} GROUP_CONTEXT;

//
// Local variables
//

static GROUP_MODULE *groupModule = NULL;


INT
MODULE_CALL
GroupModuleInit(
    GROUP_MODULE *module
    )
{
    DebugPrint("GroupInit: module=%p\n", module);

    // Initialize module structure
    module->tszModuleName = "NXMOD";
    module->DeInitialize  = GroupFinalize;
    module->Create        = GroupCreate;
    module->Delete        = GroupDelete;
    module->Rename        = GroupRename;
    module->Lock          = GroupLock;
    module->Write         = GroupWrite;
    module->Open          = GroupOpen;
    module->Close         = GroupClose;
    module->Unlock        = GroupUnlock;

    // Initialize procedure table
    if (!InitProcTable(module->GetProc)) {
        DebugPrint("GroupInit: Unable to initialize procedure table.\n");
        return GM_ERROR;
    }
    Io_Putlog(LOG_ERROR, "nxMod group module loaded.\r\n");

    groupModule = module;
    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupFinalize(
    void
    )
{
    DebugPrint("GroupFinalize: module=%p\n", groupModule);
    Io_Putlog(LOG_ERROR, "nxMod group module unloaded.\r\n");

    // Finalize procedure table
    FinalizeProcTable();
    groupModule = NULL;
    return GM_SUCCESS;
}

static
INT32
MODULE_CALL
GroupCreate(
    char *groupName
    )
{
    char buffer[_MAX_NAME + 12];
    char *sourcePath;
    char *tempPath;
    DWORD error;
    INT32 result;
    GROUPFILE groupFile;

    DebugPrint("GroupCreate: groupName=\"%s\"\n", groupName);

    // Retrieve default location
    sourcePath = Io_ConfigGetPath("Locations", "Group_Files", "Default.Group", NULL);
    if (sourcePath == NULL) {
        DebugPrint("GroupCreate: Unable to retrieve default file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return -1;
    }

    // Retrieve temporary location
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%s.tmp", groupName);
    tempPath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (tempPath == NULL) {
        DebugPrint("GroupCreate: Unable to retrieve temporary file location.\n");

        // Free resources
        Io_Free(sourcePath);

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return -1;
    }

    // Copy default file
    if (!CopyFileA(sourcePath, tempPath, FALSE)) {
        error = GetLastError();
        DebugPrint("GroupCreate: Unable to copy default file (error %lu).\n", error);

        // Free resources
        Io_Free(sourcePath);
        Io_Free(tempPath);

        // Restore system error code
        SetLastError(error);
        return -1;
    }

    // Initialize GROUPFILE structure
    ZeroMemory(&groupFile, sizeof(GROUPFILE));

    if (GroupRead(tempPath, &groupFile) != GM_SUCCESS) {
        error = GetLastError();

        // Free resources
        DeleteFileA(tempPath);
        Io_Free(sourcePath);
        Io_Free(tempPath);

        // Restore system error code
        SetLastError(error);
        return -1;
    }

    // Register group
    result = groupModule->Register(groupModule, groupName, &groupFile);
    if (result == -1) {
        error = GetLastError();

        GroupClose(&groupFile);
        DeleteFileA(tempPath);
    } else {
        char *offset;
        size_t sourceLength = strlen(sourcePath);

        // Terminate string after the last path separator
        offset = strrchr(sourcePath, '\\');
        if (offset != NULL) {
            offset[1] = '\0';
        } else {
            offset = strrchr(sourcePath, '/');
            if (offset != NULL) {
                offset[1] = '\0';
            }
        }

        // Append the group's ID
        StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", result);
        StringCchCatA(sourcePath, sourceLength, buffer);

        // Rename temporary file
        if (!MoveFileExA(tempPath, sourcePath, MOVEFILE_REPLACE_EXISTING)) {
            error = GetLastError();
            DebugPrint("GroupCreate: Unable to rename temporary file (error %lu).\n", error);

            // Unregister group and delete the group file
            if (groupModule->Unregister(groupModule, groupName) != GM_SUCCESS) {
                GroupClose(&groupFile);
            }
            DeleteFileA(tempPath);

            result = -1;
        } else {
            error = ERROR_SUCCESS;
        }
    }

    // Free resources
    Io_Free(sourcePath);
    Io_Free(tempPath);

    // Restore system error code
    SetLastError(error);
    return result;
}

static
INT
MODULE_CALL
GroupRename(
    char *groupName,
    INT32 groupId,
    char *newName
    )
{
    DebugPrint("GroupRename: groupName=\"%s\" groupId=%i newName=\"%s\"\n", groupName, groupId, newName);

    // Register the group under the new name
    if (groupModule->RegisterAs(groupModule, groupName, newName) != GM_SUCCESS) {
        DebugPrint("GroupRename: Unable to rename group, already exists?\n");
        return GM_ERROR;
    }

    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupDelete(
    char *groupName,
    INT32 groupId
    )
{
    char buffer[16];
    char *filePath;

    DebugPrint("GroupDelete: groupName=\"%s\" groupId=%i\n", groupName, groupId);

    // Format group ID
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", groupId);

    // Retrieve file location
    filePath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (filePath == NULL) {
        DebugPrint("GroupDelete: Unable to retrieve file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return GM_ERROR;
    }

    // Delete group file and free resources
    DeleteFileA(filePath);
    Io_Free(filePath);

    // Unregister group
    if (groupModule->Unregister(groupModule, groupName) != GM_SUCCESS) {
        DebugPrint("GroupDelete: Unable to unregister group.\n");
        return GM_ERROR;
    }

    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupLock(
    GROUPFILE *groupFile
    )
{
    GROUP_CONTEXT *context;
    DebugPrint("GroupLock: groupFile=%p\n", groupFile);

    // Actual implementations should use a proper locking mechanism.
    context = groupFile->lpInternal;
    if (InterlockedCompareExchange(&context->locked, 1, 0) == 1) {
        DebugPrint("GroupLock: Unable to aquire lock.\n");
        return GM_ERROR;
    }

    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupUnlock(
    GROUPFILE *groupFile
    )
{
    GROUP_CONTEXT *context;
    DebugPrint("GroupUnlock: groupFile=%p\n", groupFile);

    // Clear locked flag.
    context = groupFile->lpInternal;
    context->locked = 0;

    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupRead(
    char *filePath,
    GROUPFILE *groupFile
    )
{
    char *buffer = NULL;
    DWORD bytesRead;
    DWORD error;
    DWORD fileSize;
    INT result = GM_FATAL;
    GROUP_CONTEXT *context;

    DebugPrint("GroupRead: filePath=\"%s\" groupFile=%p\n", filePath, groupFile);

    // Allocate group context
    context = Io_Allocate(sizeof(GROUP_CONTEXT));
    if (context == NULL) {
        DebugPrint("GroupRead: Unable to allocate group context.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return GM_FATAL;
    }
    context->locked = 0;

    // Open the group file
    context->fileHandle = CreateFileA(filePath,
        GENERIC_READ|GENERIC_WRITE,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, 0, NULL);

    if (context->fileHandle == INVALID_HANDLE_VALUE) {
        result = (GetLastError() == ERROR_FILE_NOT_FOUND) ? GM_DELETED : GM_FATAL;
        DebugPrint("GroupRead: Unable to open file (error %lu).\n", GetLastError());
        goto end;
    }

    // Retrieve file size
    fileSize = GetFileSize(context->fileHandle, NULL);
    if (fileSize == INVALID_FILE_SIZE || fileSize < 5) {
        DebugPrint("GroupRead: Unable to retrieve file size, or file size is under 5 bytes.\n");
        goto end;
    }

    // Allocate read buffer
    buffer = Io_Allocate(fileSize + 1);
    if (buffer == NULL) {
        DebugPrint("GroupRead: Unable to allocate read buffer.\n");
        goto end;
    }

    // Read group file to buffer
    if (!ReadFile(context->fileHandle, buffer, fileSize, &bytesRead, NULL) || bytesRead < 5) {
        DebugPrint("GroupRead: Unable to read file, or the amount read is under 5 bytes.\n");
        goto end;
    }

    // Pad buffer with a new-line
    buffer[bytesRead] = '\n';
    bytesRead++;

    // Parse buffer, also initializing the GROUPFILE structure
    Io_Ascii2GroupFile(buffer, bytesRead, groupFile);
    groupFile->lpInternal = context;
    result                = GM_SUCCESS;

end:
    // Free objects and resources
    if (result != GM_SUCCESS) {
        error = GetLastError();
        if (context->fileHandle != INVALID_HANDLE_VALUE) {
            CloseHandle(context->fileHandle);
        }
        Io_Free(buffer);
        Io_Free(context);
        groupFile->lpInternal = NULL;

        // Restore system error code
        SetLastError(error);
    } else {
        Io_Free(buffer);
    }

    return result;
}

static
INT
MODULE_CALL
GroupWrite(
    GROUPFILE *groupFile
    )
{
    BUFFER buffer;
    DWORD bytesWritten;
    DWORD error;
    GROUP_CONTEXT *context;

    DebugPrint("GroupWrite: groupFile=%p\n", groupFile);

    // Retrieve group context
    context = groupFile->lpInternal;

    // Allocate write buffer
    ZeroMemory(&buffer, sizeof(BUFFER));
    buffer.dwType = TYPE_CHAR;
    buffer.size   = 4096;
    buffer.buf    = Io_Allocate(buffer.size);

    if (buffer.buf == NULL) {
        DebugPrint("GroupWrite: Unable to allocate write buffer.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return GM_ERROR;
    }

    // Dump group data to buffer
    Io_GroupFile2Ascii(&buffer, groupFile);

    // Write buffer to file
    SetFilePointer(context->fileHandle, 0, 0, FILE_BEGIN);
    if (!WriteFile(context->fileHandle, buffer.buf, buffer.len, &bytesWritten, NULL)) {
        error = GetLastError();
        DebugPrint("GroupWrite: Unable to write file (error %lu).\n", error);

        // Free resources
        Io_Free(buffer.buf);

        // Restore system error code
        SetLastError(error);
        return GM_ERROR;
    }

    // Truncate file at its current position and flush changes to disk
    SetEndOfFile(context->fileHandle);
    FlushFileBuffers(context->fileHandle);

    Io_Free(buffer.buf);
    return GM_SUCCESS;
}

static
INT
MODULE_CALL
GroupOpen(
    char *groupName,
    GROUPFILE *groupFile
    )
{
    char buffer[16];
    char *filePath;
    INT result;

    DebugPrint("GroupOpen: groupName=\"%s\" groupFile=%p\n", groupName, groupFile);

    // Format group ID
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", groupFile->Gid);

    // Retrieve file location
    filePath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (filePath == NULL) {
        DebugPrint("GroupOpen: Unable to retrieve file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return GM_FATAL;
    }

    // Read the group file
    result = GroupRead(filePath, groupFile);
    Io_Free(filePath);

    return result;
}

static
INT
MODULE_CALL
GroupClose(
    GROUPFILE *groupFile
    )
{
    GROUP_CONTEXT *context;

    DebugPrint("GroupClose: groupFile=%p\n", groupFile);

    // Verify group context
    context = groupFile->lpInternal;
    if (context == NULL) {
        DebugPrint("GroupClose: Group context already freed.\n");

        SetLastError(ERROR_INVALID_DATA);
        return GM_ERROR;
    }

    // Free objects and resources
    CloseHandle(context->fileHandle);
    Io_Free(context);
    groupFile->lpInternal = NULL;

    return GM_SUCCESS;
}
