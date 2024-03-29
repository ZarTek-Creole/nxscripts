/*++

AlcoTcld - Alcoholicz Tcl daemon.
Copyright (c) 2005-2008 Alcoholicz Scripting Team

Module Name:
    Tcl Initialisation

Author:
    neoxed (neoxed@gmail.com) Jul 17, 2005

Abstract:
    Tcl scripting host.

--*/

#include <tcld.h>

int inBackground = 0;


/*++

LogError

    Displays an error message to stderr if running interactively, otherwise
    the message is written to error.log.

Arguments:
    format  - Pointer to a buffer containing a printf-style format string.

    ...     - Arguments to insert into 'format'.

Return Value:
    None.

--*/
void
LogError(
    const char *format,
    ...
    )
{
    va_list argList;

    va_start(argList, format);
    if (!inBackground) {
        // Write message to stderr.
        vfprintf(stderr, format, argList);
    } else {
        FILE *handle;

        // Write message to error.log.
        handle = fopen("error.log", "a");
        if (handle != NULL) {
            WriteTime(handle);
            vfprintf(handle, format, argList);
            fclose(handle);
        }
    }
    va_end(argList);
}

/*++

LogErrorObj

    Displays an error message to stderr if running interactively, otherwise
    the message is written to error.log.

Arguments:
    message  - Pointer to a buffer containing a string which explains the error.

    errorObj - Pointer to a Tcl object containing the error text.

Return Value:
    None.

--*/
void
LogErrorObj(
    const char *message,
    Tcl_Obj *errorObj
    )
{
    if (!inBackground) {
        Tcl_Channel channel;

        // Write message to stderr.
        channel = Tcl_GetStdChannel(TCL_STDERR);
        if (channel != NULL) {
            Tcl_WriteChars(channel, message, -1);
            Tcl_WriteObj(channel, errorObj);
            Tcl_WriteChars(channel, "\n", 1);
        }
    } else {
        char *stringPtr;
        FILE *handle;

        // Write message to error.log.
        handle = fopen("error.log", "a");
        if (handle != NULL) {
            WriteTime(handle);
            fputs(message, handle);

            stringPtr = Tcl_GetString(errorObj);
            if (*stringPtr) {
                char *format = "                    %.*s\n";
                char *p;

                // Align the error message after the timestamp (column wise).
                while (*stringPtr && (p = strchr(stringPtr, '\n')) != NULL) {
                    fprintf(handle, format, p - stringPtr, stringPtr);
                    stringPtr = p + 1;
                }
                fprintf(handle, format, p - stringPtr, stringPtr);
            }

            fclose(handle);
        }
    }
}

/*++

TclInit

    Initialises a Tcl interpeter and evaluates the Tcl script in argv.

Arguments:
    argc     - Number of command-line arguments.

    argv     - Array of pointers to strings that represent command-line arguments.

    service  - Boolean to indicate whether the process is running as an NT service.

    exitProc - Pointer to a Tcl exit handler function. This argument can be NULL.

Return Value:
    If the function succeeds, the return value is pointer to a Tcl interpeter
    structure. If the function fails, the return value is NULL.

Remarks:
    The caller should delete the returned interpeter when finished.

--*/
Tcl_Interp *TclInit(int argc, char **argv, int service, Tcl_ExitProc *exitProc)
{
    char *argList;
    Tcl_DString argString;
    Tcl_Interp *interp;
    Tcl_Obj *objPtr;

    // The second command-line argument must be a Tcl script.
    if (argc < 2) {
        LogError("Usage: %s <script file> [arguments]\n", argv[0]);
        return NULL;
    }
    if (!FileExists(argv[1])) {
        LogError("The file \"%s\" does not exist.\n", argv[1]);
        return NULL;
    }

    // Initialise Tcl and create an interpreter.
    Tcl_FindExecutable(argv[0]);
    interp = Tcl_CreateInterp();
    Tcl_InitMemory(interp);

    //
    // Source the init.tcl script. If this operation fails, we can
    // continue and function normally (for the most part anyway).
    //
    if (Tcl_Init(interp) != TCL_OK) {
        LogErrorObj("Tcl initialisation failed:\n", Tcl_GetObjResult(interp));
    }

    // Set the "argc", "argv", and "argv0" global variables.
    objPtr = Tcl_NewIntObj(argc-1);
    Tcl_IncrRefCount(objPtr);
    Tcl_SetVar2Ex(interp, "argc", NULL, objPtr, TCL_GLOBAL_ONLY);
    Tcl_DecrRefCount(objPtr);

    argList = Tcl_Merge(argc-1, (CONST char **) argv+1);
    Tcl_ExternalToUtfDString(NULL, argList, -1, &argString);
    Tcl_SetVar(interp, "argv", Tcl_DStringValue(&argString), TCL_GLOBAL_ONLY);
    Tcl_DStringFree(&argString);
    ckfree(argList);

    Tcl_ExternalToUtfDString(NULL, argv[0], -1, &argString);
    Tcl_SetVar(interp, "argv0", Tcl_DStringValue(&argString), TCL_GLOBAL_ONLY);
    Tcl_DStringFree(&argString);

    // Set tcl_service, to indicate whether the process is running as a NT service.
    objPtr = Tcl_NewBooleanObj(service);
    Tcl_IncrRefCount(objPtr);
    Tcl_SetVar2Ex(interp, "tcl_service", NULL, objPtr, TCL_GLOBAL_ONLY);
    Tcl_DecrRefCount(objPtr);

    //
    // Create an exit callback to handle unexpected exit requests, allowing
    // us to clean up. For example, if the script being evaluated invokes
    // the "exit" command.
    //
    if (exitProc != NULL) {
        Tcl_CreateExitHandler(exitProc, NULL);
    }

    if (Tcl_EvalFile(interp, argv[1]) != TCL_OK) {
        LogErrorObj("Script evaluation failed:\n",
            Tcl_GetVar2Ex(interp, "errorInfo", NULL, TCL_GLOBAL_ONLY));

        // Delete the interpreter if it still exists.
        if (!Tcl_InterpDeleted(interp)) {
            Tcl_DeleteInterp(interp);
        }
        return NULL;
    }

    //
    // Nothing must be done to obstruct the interpreter's result object if
    // Tcl_EvalFile() succeeds. The result is used to determine whether or
    // not we fork the process into the background (nix only).
    //
    return interp;
}
