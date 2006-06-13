/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006 neoxed

Module Name:
    Group File Backend

Author:
    neoxed (neoxed@gmail.com) Jun 5, 2006

Abstract:
    Group file storage backend.

*/

#include "mydb.h"

static
BOOL
FileGroupRead(
    char *filePath,
    GROUPFILE *groupFile
    )
{
    char *buffer = NULL;
    DWORD bytesRead;
    DWORD error;
    DWORD fileSize;
    INT_CONTEXT *context = groupFile->lpInternal;

    DebugPrint("FileGroupRead", "filePath=\"%s\" groupFile=%p\n", filePath, groupFile);

    // Open the group file
    context->fileHandle = CreateFileA(filePath,
        GENERIC_READ|GENERIC_WRITE,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, 0, NULL);

    if (context->fileHandle == INVALID_HANDLE_VALUE) {
        DebugPrint("FileGroupRead", "Unable to open file (error %lu).\n", GetLastError());
        goto error;
    }

    // Retrieve file size
    fileSize = GetFileSize(context->fileHandle, NULL);
    if (fileSize == INVALID_FILE_SIZE || fileSize < 5) {
        DebugPrint("FileGroupRead", "Unable to retrieve file size, or file size is under 5 bytes.\n");
        goto error;
    }

    // Allocate read buffer
    buffer = Io_Allocate(fileSize + 1);
    if (buffer == NULL) {
        DebugPrint("FileGroupRead", "Unable to allocate read buffer.\n");
        goto error;
    }

    // Read group file to buffer
    if (!ReadFile(context->fileHandle, buffer, fileSize, &bytesRead, NULL) || bytesRead < 5) {
        DebugPrint("FileGroupRead", "Unable to read file, or the amount read is under 5 bytes.\n");
        goto error;
    }

    // Pad buffer with a new-line
    buffer[bytesRead] = '\n';
    bytesRead++;

    // Parse buffer, also initializing the GROUPFILE structure
    Io_Ascii2GroupFile(buffer, bytesRead, groupFile);

    // Free resources
    Io_Free(buffer);

    return TRUE;

error:
    // Free objects and resources
    error = GetLastError();
    if (context->fileHandle != INVALID_HANDLE_VALUE) {
        CloseHandle(context->fileHandle);
    }
    Io_Free(buffer);
    Io_Free(context);
    groupFile->lpInternal = NULL;

    // Restore system error code
    SetLastError(error);
    return FALSE;
}

BOOL
FileGroupCreate(
    char *groupName,
    INT32 groupId,
    GROUPFILE *groupFile
    )
{
    char *defaultPath;
    char *targetPath;
    char buffer[12];
    DWORD error;

    DebugPrint("FileGroupCreate", "groupName=\"%s\"\n", groupName);

    // Retrieve default group location
    defaultPath = Io_ConfigGetPath("Locations", "Group_Files", "Default.Group", NULL);
    if (defaultPath == NULL) {
        DebugPrint("FileGroupCreate", "Unable to retrieve default file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    // Retrieve group location
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", groupId);
    targetPath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (targetPath == NULL) {
        DebugPrint("FileGroupCreate", "Unable to retrieve file location.\n");

        // Free resources
        Io_Free(defaultPath);

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    // Copy default file to target file
    if (!CopyFileA(defaultPath, targetPath, FALSE)) {
        error = GetLastError();
        DebugPrint("FileGroupCreate", "Unable to copy default file (error %lu).\n", error);

        // Free resources
        Io_Free(defaultPath);
        Io_Free(targetPath);

        // Restore system error code
        SetLastError(error);
        return FALSE;
    }

    // Read group file (copy of "Default.Group")
    if (!FileGroupRead(targetPath, groupFile)) {
        error = GetLastError();
        DebugPrint("FileGroupCreate", "Unable read target file (error %lu).\n", error);

        // Free resources
        Io_Free(defaultPath);
        Io_Free(targetPath);

        // Restore system error code
        SetLastError(error);
        return FALSE;
    }

    // Free resources
    Io_Free(defaultPath);
    Io_Free(targetPath);

    return TRUE;
}

BOOL
FileGroupRename(
    char *groupName,
    INT32 groupId,
    char *newName
    )
{
    DebugPrint("FileGroupRename", "groupName=\"%s\" groupId=%i newName=\"%s\"\n", groupName, groupId, newName);
    // Not used
    return TRUE;
}

BOOL
FileGroupDelete(
    char *groupName,
    INT32 groupId
    )
{
    char buffer[12];
    char *filePath;

    DebugPrint("FileGroupDelete", "groupName=\"%s\" groupId=%i\n", groupName, groupId);

    // Retrieve group file location
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", groupId);
    filePath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (filePath == NULL) {
        DebugPrint("FileGroupDelete", "Unable to retrieve file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    // Delete group file and free resources
    DeleteFileA(filePath);
    Io_Free(filePath);

    return TRUE;
}

BOOL
FileGroupLock(
    GROUPFILE *groupFile
    )
{
    DebugPrint("FileGroupLock", "groupFile=%p\n", groupFile);
    // Not used
    return TRUE;
}

BOOL
FileGroupUnlock(
    GROUPFILE *groupFile
    )
{
    DebugPrint("FileGroupUnlock", "groupFile=%p\n", groupFile);
    // Not used
    return TRUE;
}

BOOL
FileGroupOpen(
    char *groupName,
    GROUPFILE *groupFile
    )
{
    char buffer[12];
    char *filePath;
    DWORD error;
    INT_CONTEXT *context = groupFile->lpInternal;

    DebugPrint("FileGroupOpen", "groupName=\"%s\" groupFile=%p\n", groupName, groupFile);

    // Retrieve group file location
    StringCchPrintfA(buffer, ARRAYSIZE(buffer), "%i", groupFile->Gid);
    filePath = Io_ConfigGetPath("Locations", "Group_Files", buffer, NULL);
    if (filePath == NULL) {
        DebugPrint("FileGroupOpen", "Unable to retrieve file location.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    // Open group file
    context->fileHandle = CreateFileA(filePath,
        GENERIC_READ|GENERIC_WRITE,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, 0, NULL);

    if (context->fileHandle == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        DebugPrint("FileGroupOpen", "Unable to open file (error %lu).\n", error);

        // Free resources
        Io_Free(filePath);

        // Restore system error code
        SetLastError(error);
        return FALSE;
    }

    // Free resources
    Io_Free(filePath);

    return TRUE;
}

BOOL
FileGroupWrite(
    GROUPFILE *groupFile
    )
{
    BUFFER buffer;
    DWORD bytesWritten;
    DWORD error;
    INT_CONTEXT *context = groupFile->lpInternal;

    DebugPrint("FileGroupWrite", "groupFile=%p\n", groupFile);

    // Allocate write buffer
    ZeroMemory(&buffer, sizeof(BUFFER));
    buffer.dwType = TYPE_CHAR;
    buffer.size   = 4096;
    buffer.buf    = Io_Allocate(buffer.size);

    if (buffer.buf == NULL) {
        DebugPrint("FileGroupWrite", "Unable to allocate write buffer.\n");

        SetLastError(ERROR_NOT_ENOUGH_MEMORY);
        return FALSE;
    }

    // Dump group data to buffer
    Io_GroupFile2Ascii(&buffer, groupFile);

    // Write buffer to file
    SetFilePointer(context->fileHandle, 0, 0, FILE_BEGIN);
    if (!WriteFile(context->fileHandle, buffer.buf, buffer.len, &bytesWritten, NULL)) {
        error = GetLastError();
        DebugPrint("FileGroupWrite", "Unable to write file (error %lu).\n", error);

        // Free resources
        Io_Free(buffer.buf);

        // Restore system error code
        SetLastError(error);
        return FALSE;
    }

    // Truncate file at its current position and flush changes to disk
    SetEndOfFile(context->fileHandle);
    FlushFileBuffers(context->fileHandle);

    // Free resources
    Io_Free(buffer.buf);

    return TRUE;
}

BOOL
FileGroupClose(
    INT_CONTEXT *context
    )
{
    DebugPrint("FileGroupClose", "context=%p\n", context);

    // Close group file handle
    if (context->fileHandle != INVALID_HANDLE_VALUE) {
        CloseHandle(context->fileHandle);
        context->fileHandle = INVALID_HANDLE_VALUE;
    }

    return TRUE;
}