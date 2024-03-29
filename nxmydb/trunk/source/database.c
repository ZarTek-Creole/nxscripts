/*

nxMyDB - MySQL Database for ioFTPD
Copyright (c) 2006-2009 neoxed

Module Name:
    Database Connection

Author:
    neoxed (neoxed@gmail.com) Jun 13, 2006

Abstract:
    Database connection and management functions.

*/

#include <base.h>
#include <backends.h>
#include <config.h>
#include <database.h>
#include <pool.h>

//
// Database variables
//

static DB_SYNC  dbSync; // Database synchronization
static POOL     dbPool; // Database connection pool

static LONG volatile dbIndex  = 0; // Server configuration index
static LONG volatile refCount = 0; // Reference count initialization calls

//
// Function declarations
//

static POOL_CONSTRUCTOR_PROC ConnectionOpen;
static POOL_VALIDATOR_PROC   ConnectionCheck;
static POOL_DESTRUCTOR_PROC  ConnectionClose;

static Io_TimerProc SyncTimer;


/*++

ConnectionOpen

    Opens a server connection.

Arguments:
    context - Opaque context passed to <PoolCreate>.

    data    - Pointer to a pointer that receives the DB_CONTEXT structure.

Return Values:
    If the function succeeds, the return value is nonzero (true).

    If the function fails, the return value is zero (false).

--*/
static BOOL FCALL ConnectionOpen(VOID *context, VOID **data)
{
    DB_CONTEXT          *db;
    DB_CONFIG_SERVER    *server;
    DWORD               error;
    DWORD               i;
    INT                 attempt;
    INT                 attemptMax;
    LONG                serverIndex;
    LONG                serverNextIndex;
    MYSQL               *connection;
    my_bool             optReconnect;
    UINT                optTimeout;

    UNREFERENCED_PARAMETER(context);
    ASSERT(data != NULL);
    TRACE("context=%p data=%p", context, data);

    db = MemAllocate(sizeof(DB_CONTEXT));
    if (db == NULL) {
        LOG_ERROR("Unable to allocate memory for database context.");

        error = ERROR_NOT_ENOUGH_MEMORY;
        goto failed;
    }
    ZeroMemory(db, sizeof(DB_CONTEXT));

    //
    // Have the MySQL client library allocate the handle structure for us. This is
    // in case the MYSQL structure changes in a future version of the client library.
    //
    db->handle = mysql_init(NULL);
    if (db->handle == NULL) {
        LOG_ERROR("Unable to allocate memory for MySQL handle.");

        error = ERROR_NOT_ENOUGH_MEMORY;
        goto failed;
    }

    // If the maximum number of attempts were not specified, try all servers
    if (dbConfigGlobal.connAttempts > 0) {
        attemptMax = dbConfigGlobal.connAttempts;
    } else {
        attemptMax = dbConfigServerCount;
    }

    for (attempt = 0; attempt < attemptMax; attempt++) {
        // Use the most recent server for the connection attempt
        serverIndex = dbIndex;
        server      = &dbConfigServers[serverIndex];

        TRACE("Connecting to server #%d [%s] on attempt %lu/%lu.",
            serverIndex, server->name, attempt+1, attemptMax);

        // Set connection options
        optTimeout = (UINT)dbConfigGlobal.connTimeout;
        if (mysql_options(db->handle, MYSQL_OPT_CONNECT_TIMEOUT, &optTimeout) != 0) {
            TRACE("Failed to set connection timeout option.");
        }

        optReconnect = FALSE;
        if (mysql_options(db->handle, MYSQL_OPT_RECONNECT, &optReconnect) != 0) {
            TRACE("Failed to set reconnection option.");
        }

        if (server->compression) {
            if (mysql_options(db->handle, MYSQL_OPT_COMPRESS, 0) != 0) {
                TRACE("Failed to set compression option.");
            }
        }

        if (server->sslEnable) {
            //
            // This function always returns 0. If the SSL setup is incorrect,
            // the call to mysql_real_connect() will return an error.
            //
            mysql_ssl_set(db->handle, server->sslKeyFile, server->sslCertFile,
                server->sslCAFile, server->sslCAPath, server->sslCiphers);
        }

        // Attempt connection with server
        connection = mysql_real_connect(db->handle,
            server->host, server->user, server->password,
            server->database, server->port, NULL, CLIENT_INTERACTIVE);

        if (connection == NULL) {
            LOG_ERROR("Unable to connect to server [%s]: %s",
                server->name, mysql_error(db->handle));

        } else if (mysql_get_server_version(db->handle) < 50019) {
            LOG_ERROR("Unsupported version of MySQL Server [%s]: running v%s, must be v5.0.19 or newer.",
                server->name, mysql_get_server_info(db->handle));

        } else {
            // Pointer values should be the same as from mysql_init()
            ASSERT(connection == db->handle);

            // Allocate pre-compiled statement structures
            for (i = 0; i < ELEMENT_COUNT(db->stmt); i++) {
                db->stmt[i] = mysql_stmt_init(db->handle);
                if (db->stmt[i] == NULL) {
                    LOG_ERROR("Unable to allocate memory for statement structure.");

                    error = ERROR_NOT_ENOUGH_MEMORY;
                    goto failed;
                }
            }

            // Successfully connected, set the global server index
            InterlockedExchange(&dbIndex, serverIndex);

            // Update context's server index and time stamps
            db->index = serverIndex;
            GetSystemTimeAsFileTime(&db->created.fileTime);
            db->used.value = db->created.value;

            LOG_INFO("Connected to %s [%s], running MySQL Server v%s.",
                mysql_get_host_info(db->handle), server->name,
                mysql_get_server_info(db->handle));

            *data = db;
            return TRUE;
        }

        // Unsuccessful connection, continue to the next server
        serverNextIndex = serverIndex + 1;
        if (serverNextIndex >= (LONG)dbConfigServerCount) {
            serverNextIndex = 0;
        }

        //
        // Compare the current server index before swapping values in the
        // event that another thread has already changed the index.
        //
        InterlockedCompareExchange(&dbIndex, serverNextIndex, serverIndex);
    }

    // Unable to connect to any servers
    error = ERROR_CONNECTION_REFUSED;

failed:
    if (db != NULL) {
        ConnectionClose(NULL, db);
    }
    SetLastError(error);
    return FALSE;
}

/*++

ConnectionCheck

    Validates the server connection.

Arguments:
    context - Opaque context passed to <PoolCreate>.

    data    - Pointer to the DB_CONTEXT structure.

Return Values:
    If the connection is valid, the return is nonzero (true).

    If the connection is invalid, the return is zero (false).

--*/
static BOOL FCALL ConnectionCheck(VOID *context, VOID *data)
{
    DB_CONTEXT  *db = data;
    DB_TIME     timeCurrent;
    DB_TIME     timeDelta;

    UNREFERENCED_PARAMETER(context);
    ASSERT(data != NULL);
    TRACE("context=%p data=%p", context, data);

    // Check if server changed
    if (db->index != dbIndex) {
        LOG_INFO("Closing connection for server configuration change.");
        SetLastError(ERROR_BAD_DEV_TYPE);
        return FALSE;
    }

    GetSystemTimeAsFileTime(&timeCurrent.fileTime);

    // Check if the context has exceeded the expiration time
    timeDelta.value = timeCurrent.value - db->created.value;
    if (timeDelta.value > dbConfigPool.expireNano) {
        LOG_INFO("Expiring server connection after %I64u seconds (%d second limit).",
            timeDelta.value/10000000, dbConfigPool.expire);
        SetLastError(ERROR_CONTEXT_EXPIRED);
        return FALSE;
    }

    // Check if the connection is still alive
    timeDelta.value = timeCurrent.value - db->used.value;
    if (timeDelta.value > dbConfigPool.checkNano) {
        LOG_INFO("Connection has not been used in %I64u seconds (%d second limit), pinging it.",
            timeDelta.value/10000000, dbConfigPool.check);

        if (mysql_ping(db->handle) != 0) {
            LOG_WARN("Lost server connection: %s", mysql_error(db->handle));
            SetLastError(ERROR_NOT_CONNECTED);
            return FALSE;
        }

        // Update last-use time stamp
        GetSystemTimeAsFileTime(&db->used.fileTime);
    }

    return TRUE;
}

/*++

ConnectionClose

    Closes the server connection.

Arguments:
    context - Opaque context passed to <PoolCreate>.

    data    - Pointer to the DB_CONTEXT structure.

Return Values:
    None.

--*/
static VOID FCALL ConnectionClose(VOID *context, VOID *data)
{
    DB_CONTEXT  *db = data;
    DWORD       i;

    UNREFERENCED_PARAMETER(context);
    ASSERT(data != NULL);
    TRACE("context=%p data=%p", context, data);

    // Free pre-compiled statement structures
    for (i = 0; i < ELEMENT_COUNT(db->stmt); i++) {
        if (db->stmt[i] != NULL) {
            mysql_stmt_close(db->stmt[i]);
        }
    }

    // Free handle structure
    if (db->handle != NULL) {
        mysql_close(db->handle);
    }

    // Free context structure
    ZeroMemory(db, sizeof(DB_CONTEXT));
    MemFree(db);
}


/*++

SyncGetTime

    Retrieves the current server time, as a UNIX timestamp.

Arguments:
    timePtr - Pointer to a variable to receive the server time.

Return Values:
    Windows error code.

--*/
static DWORD SyncGetTime(DB_CONTEXT *db, ULONG *timePtr)
{
    CHAR        *query;
    INT         result;
    MYSQL_BIND  bind[1];
    MYSQL_RES   *metadata;
    MYSQL_STMT  *stmt;

    ASSERT(db != NULL);
    ASSERT(timePtr != NULL);

    stmt = db->stmt[0];

    //
    // Prepare statement and bind parameters
    //

    query = "SELECT UNIX_TIMESTAMP()";

    result = mysql_stmt_prepare(stmt, query, strlen(query));
    if (result != 0) {
        LOG_WARN("Unable to prepare statement: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    metadata = mysql_stmt_result_metadata(stmt);
    if (metadata == NULL) {
        LOG_WARN("Unable to retrieve result metadata: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    result = mysql_stmt_execute(stmt);
    if (result != 0) {
        LOG_ERROR("Unable to execute statement: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    //
    // Bind and fetch results
    //

    DB_CHECK_RESULTS(bind, metadata);
    ZeroMemory(&bind, sizeof(bind));

    bind[0].buffer_type = MYSQL_TYPE_LONG;
    bind[0].buffer      = timePtr;
    bind[0].is_unsigned = TRUE;

    result = mysql_stmt_bind_result(stmt, bind);
    if (result != 0) {
        LOG_WARN("Unable to bind results: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    result = mysql_stmt_store_result(stmt);
    if (result != 0) {
        LOG_WARN("Unable to buffer results: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    result = mysql_stmt_fetch(stmt);
    if (result != 0) {
        LOG_WARN("Unable to fetch results: %s", mysql_stmt_error(stmt));
        return DbMapErrorFromStmt(stmt);
    }

    mysql_free_result(metadata);

    return ERROR_SUCCESS;
}

/*++

SyncTimer

    Synchronizes the local user and group cache.

Arguments:
    context - Pointer to the timer context.

    timer   - Pointer to the current TIMER structure.

Return Values:
    Number of milliseconds in which to execute this timer again.

--*/
static DWORD SyncTimer(VOID *context, TIMER *timer)
{
    DB_CONTEXT  *db;
    DWORD       result;
    ULONG       currentTime;

    UNREFERENCED_PARAMETER(context);
    UNREFERENCED_PARAMETER(timer);

    TRACE("context=%p timer=%p", context, timer);

    if (DbAcquire(&db)) {
        // Retrieve the current server time
        result = SyncGetTime(db, &currentTime);
        if (result != ERROR_SUCCESS) {
            LOG_ERROR("Unable to retrieve server timestamp (error %lu).", result);

        } else {
            // Update the current time
            dbSync.currUpdate = currentTime;

            // Groups must be updated before users
            DbGroupSync(db, &dbSync);
            DbUserSync(db, &dbSync);

            // Update the previous time
            dbSync.prevUpdate = currentTime;
        }

        DbRelease(db);
    }

    // Execute the timer again
    return dbConfigSync.interval;
}


/*++

DbInit

    Initializes the procedure table and database connection pool.

Arguments:
    getProc - Pointer to ioFTPD's GetProc function.

Return Values:
    If the function succeeds, the return value is nonzero (true).

    If the function fails, the return value is zero (false).

--*/
BOOL FCALL DbInit(Io_GetProc *getProc)
{
    DWORD result;

#if 0
    // Wait for debugger to be attached before proceeding
    WaitForDebugger();
#endif

    TRACE("refCount=%d", refCount);

    // Only initialize the database pool once
    if (InterlockedIncrement(&refCount) > 1) {
        TRACE("Already initialized, returning.");
        return TRUE;
    }

    // Initialize procedure table
    result = ProcTableInit(getProc);
    if (result != ERROR_SUCCESS) {
        TRACE("Unable to initialize procedure table (error %lu).", result);
        return FALSE;
    }

    // Initialize configuration structures
    result = ConfigInit();
    if (result != ERROR_SUCCESS) {
        TRACE("Unable to initialize configuration system (error %lu).", result);
        return FALSE;
    }

    // Initialize logging system
    result = LogInit();
    if (result != ERROR_SUCCESS) {
        TRACE("Unable to initialize logging system (error %lu).", result);
        return FALSE;
    }

    //
    // Now that the logging system has been initialized, the LOG_* macros are
    // available for use. Prior to this point, the TRACE macro must be used.
    //

    // Load configuration options
    result = ConfigLoad();
    if (result != ERROR_SUCCESS) {
        TRACE("Unable to load configuration (error %lu).", result);

        DbFinalize();
        return FALSE;
    }

    // Create connection pool
    result = PoolCreate(&dbPool,
        dbConfigPool.minimum, dbConfigPool.average,
        dbConfigPool.maximum, dbConfigPool.timeoutMili,
        ConnectionOpen, ConnectionCheck, ConnectionClose, NULL);
    if (result != ERROR_SUCCESS) {
        LOG_ERROR("Unable to initialize connection pool (error %lu).", result);

        DbFinalize();
        return FALSE;
    }

    LOG_INFO("nxMyDB v%s loaded, using MySQL Client Library v%s.",
        STRINGIFY(VERSION), mysql_get_client_info());

    return TRUE;
}

/*++

DbFinalize

    Finalizes the procedure table and database connection pool.

Arguments:
    None.

Return Values:
    None.

Remarks:
    This function must be called once by each module exit point.

--*/
VOID FCALL DbFinalize(VOID)
{
    TRACE("refCount=%d", refCount);

    //
    // If the reference counter is already zero, or less, the finalization
    // function has been called more than the initialization function (very bad).
    //
    ASSERT(refCount >= 0);

    // Finalize once the reference count reaches zero
    if (InterlockedDecrement(&refCount) == 0) {
        TRACE("Finalizing subsystems for shut down.");

        // Stop the sync timer
        DbSyncStop();

        // Destroy connection pool
        PoolDestroy(&dbPool);

        // Free configuration options
        ConfigFinalize();

        // Stop logging system
        LOG_INFO("nxMyDB v%s unloaded.", STRINGIFY(VERSION));
        LogFinalize();

        ProcTableFinalize();
    }
}

/*++

DbSyncPurge

    Purges old entries from the changes tables.

Arguments:
    None.

Return Values:
    None.

--*/
VOID FCALL DbSyncPurge(VOID)
{
    DB_CONTEXT *db;

    TRACE("enabled=%d", dbConfigSync.enabled);

    if (dbConfigSync.enabled && DbAcquire(&db)) {
        // Purge changes tables for groups and users
        DbGroupPurge(db, dbConfigSync.purge);
        DbUserPurge(db, dbConfigSync.purge);

        DbRelease(db);
    }
}

/*++

DbSyncStart

    Starts the database synchronization timer.

Arguments:
    None.

Return Values:
    None.

--*/
VOID FCALL DbSyncStart(VOID)
{
    TRACE("enabled=%d", dbConfigSync.enabled);

    if (dbConfigSync.enabled) {
        ZeroMemory(&dbSync, sizeof(DB_SYNC));
        dbSync.timer = Io_StartIoTimer(NULL, SyncTimer, NULL, dbConfigSync.first);
    }
}

/*++

DbSyncStop

    Stops the database synchronization timer.

Arguments:
    None.

Return Values:
    None.

--*/
VOID FCALL DbSyncStop(VOID)
{
    TRACE("enabled=%d", dbConfigSync.enabled);

    if (dbSync.timer != NULL) {
        Io_StopIoTimer(dbSync.timer, FALSE);
        dbSync.timer = NULL;
    }
}

/*++

DbAcquire

    Acquires a database context from the connection pool.

Arguments:
    dbPtr   - Pointer to a pointer that receives the DB_CONTEXT structure.

Return Values:
    If the function succeeds, the return value is nonzero (true).

    If the function fails, the return value is zero (false).

--*/
BOOL FCALL DbAcquire(DB_CONTEXT **dbPtr)
{
    ASSERT(dbPtr != NULL);
    TRACE("dbPtr=%p", dbPtr);

    // Acquire a database context
    if (!PoolAcquire(&dbPool, dbPtr)) {
        LOG_ERROR("Unable to acquire a database context from the connection pool (error %lu).", GetLastError());
        return FALSE;
    }

    return TRUE;
}

/*++

DbRelease

    Releases a database context back into the connection pool.

Arguments:
    db  - Pointer to the DB_CONTEXT structure.

Return Values:
    None.

--*/
VOID FCALL DbRelease(DB_CONTEXT *db)
{
    ASSERT(db != NULL);
    TRACE("db=%p", db);

    if (db->index != dbIndex) {
        // Server changed, invalidate connection
        PoolInvalidate(&dbPool, db);

    } else {
        // Update last-use time stamp
        GetSystemTimeAsFileTime(&db->used.fileTime);

        // Release the database context
        if (!PoolRelease(&dbPool, db)) {
            LOG_ERROR("Unable to release a database context to the connection pool (error %lu).", GetLastError());
        }
    }
}

/*++

DbMapError

    Maps a MySQL result code to the closest Windows error code.

Arguments:
    error   - MySQL client library error code.

Return Values:
    The closest Windows error code.

--*/
DWORD FCALL DbMapError(UINT error)
{
    switch (error) {
        case CR_COMMANDS_OUT_OF_SYNC:
        case CR_NOT_IMPLEMENTED:
            return ERROR_INTERNAL_ERROR;

        case CR_OUT_OF_MEMORY:
            return ERROR_NOT_ENOUGH_MEMORY;

        case CR_UNKNOWN_ERROR:
            return ERROR_INVALID_FUNCTION;

        case CR_SERVER_GONE_ERROR:
        case CR_SERVER_LOST:
        case CR_SERVER_LOST_EXTENDED:
            return ERROR_NOT_CONNECTED;

        case CR_PARAMS_NOT_BOUND:
        case CR_NO_PARAMETERS_EXISTS:
        case CR_INVALID_PARAMETER_NO:
        case CR_INVALID_BUFFER_USE:
        case CR_UNSUPPORTED_PARAM_TYPE:
            return ERROR_INVALID_PARAMETER;
    }

    LOG_INFO("Unmapped MySQL result error %lu.", error);
    return ERROR_INVALID_FUNCTION;
}
