#
# AlcoBot - Alcoholicz site bot.
# Copyright (c) 2005 Alcoholicz Scripting Team
#
# Module Name:
#   nxTools Module
#
# Author:
#   neoxed (neoxed@gmail.com) Aug 30, 2005
#
# Abstract:
#   Implements a module to interact with nxTools' databases.
#

namespace eval ::alcoholicz::NxTools {
    if {![info exists dataPath]} {
        variable dataPath ""
        variable oneLines 5
        variable undupeChars 5
    }
    namespace import -force ::alcoholicz::*
    namespace import -force ::alcoholicz::FtpDaemon::GetFtpConnection
    namespace import -force ::alcoholicz::Invite::GetFtpUser
}

####
# DbOpenFile
#
# Open a nxTools SQLite database file.
#
proc ::alcoholicz::NxTools::DbOpenFile {fileName} {
    variable dataPath

    set filePath [file join $dataPath $fileName]
    if {![file isfile $filePath]} {
        LogError ModNxTools "Unable to open \"$filePath\": the file does not exist"
        return 0
    }
    if {[catch {sqlite3 [namespace current]::db $filePath} error]} {
        LogError ModNxTools "Unable to open \"$filePath\": $error"
        return 0
    }

    db busy [namespace current]::DbBusyHandler
    return 1
}

####
# DbBusyHandler
#
# Callback invoked by SQLite if it tries to open a locked database.
#
proc ::alcoholicz::NxTools::DbBusyHandler {tries} {
    # Give up after 50 attempts, although it should succeed after 1-5.
    if {$tries > 50} {return 1}
    after 200
    return 0
}

####
# Approved
#
# Display approved releases, command: !approved.
#
proc ::alcoholicz::NxTools::Approved {command target user host handle channel argv} {
    SendTargetTheme $target approveHead

    set count 0
    if {[DbOpenFile "Approves.db"]} {
        db eval {SELECT * FROM Approves ORDER BY Release ASC} values {
            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target approveBody [list $values(UserName) \
                $values(GroupName) $values(Release) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target approveNone}
    SendTargetTheme $target approveFoot
    return
}

####
# Latest
#
# Display recent releases, command: !new [-limit <num>] [section].
#
proc ::alcoholicz::NxTools::Latest {command target user host handle channel argv} {
    upvar ::alcoholicz::pathSections pathSections

    # Parse command options.
    set option(limit) -1
    if {[catch {set section [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {[set section [join $section]] eq ""} {
        set sectionQuery ""
    } else {
        # Validate the specified section name.
        set names [lsort [array names pathSections]]
        if {[catch {set section [GetElementFromList $names $section section]} message]} {
            CmdSendHelp $channel channel $command $message
            return
        }
        set matchPath [SqlToLike [lindex $pathSections($section) 0]]
        set sectionQuery "WHERE DirPath LIKE '${matchPath}%' ESCAPE '\\'"
    }
    SendTargetTheme $target latestHead

    set count 0
    if {[DbOpenFile "DupeDirs.db"]} {
        db eval "SELECT * FROM DupeDirs $sectionQuery ORDER BY TimeStamp DESC LIMIT $option(limit)" values {
            # Retrieve the section name.
            set virtualPath [file join $values(DirPath) $values(DirName)]
            if {$sectionQuery eq "" && [set section [GetSectionFromPath $virtualPath]] eq ""} {
                set section $::alcoholicz::defaultSection
            }

            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target latestBody [list $values(UserName) $values(GroupName) \
                $section $virtualPath $values(TimeStamp) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target latestNone}
    SendTargetTheme $target latestFoot
    return
}

####
# Search
#
# Search for a release, command: !dupe [-limit <num>] [-section <name>] <pattern>.
#
proc ::alcoholicz::NxTools::Search {command target user host handle channel argv} {
    upvar ::alcoholicz::pathSections pathSections

    # Parse command options.
    set option(limit) -1
    set optList [list {limit integer} [list section arg [lsort [array names pathSections]]]]

    if {[catch {set pattern [GetOptions $argv $optList option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    if {[set pattern [join $pattern]] eq ""} {
        CmdSendHelp $channel channel $command "you must specify a pattern"
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {[info exists option(section)]} {
        set section $option(section)
        set matchPath [SqlToLike [lindex $pathSections($section) 0]]
        set sectionQuery "AND DirPath LIKE '${matchPath}%' ESCAPE '\\'"
    } else {
        set sectionQuery ""
    }
    SendTargetTheme $target searchHead [list $pattern]

    set count 0
    if {[DbOpenFile "DupeDirs.db"]} {
        db eval "SELECT * FROM DupeDirs WHERE DirName LIKE '[SqlGetPattern $pattern]' ESCAPE '\\' \
                $sectionQuery ORDER BY TimeStamp DESC LIMIT $option(limit)" values {
            # Retrieve the section name.
            set virtualPath [file join $values(DirPath) $values(DirName)]
            if {$sectionQuery eq "" && [set section [GetSectionFromPath $virtualPath]] eq ""} {
                set section $::alcoholicz::defaultSection
            }

            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target searchBody [list $values(UserName) $values(GroupName) \
                $section $virtualPath $values(TimeStamp) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target searchNone [list $pattern]}
    SendTargetTheme $target searchFoot
    return
}

####
# Nukes
#
# Display recent nukes, command: !nukes [-limit <num>] [pattern].
#
proc ::alcoholicz::NxTools::Nukes {command target user host handle channel argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set pattern [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {[set pattern [join $pattern]] eq ""} {
        set matchQuery ""
    } else {
        set matchQuery "AND Release LIKE '[SqlGetPattern $pattern]' ESCAPE '\\'"
    }
    SendTargetTheme $target nukesHead

    set count 0
    if {[DbOpenFile "Nukes.db"]} {
        db eval "SELECT * FROM Nukes WHERE Status=0 $matchQuery \
                ORDER BY TimeStamp DESC LIMIT $option(limit)" values {
            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target nukesBody [list $values(UserName) $values(GroupName) \
                $values(Release) $values(TimeStamp) $values(Multi) $values(Reason) \
                $values(Files) $values(Size) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target nukesNone}
    SendTargetTheme $target nukesFoot
    return
}

####
# NukeTop
#
# Display top nuked users, command: !nukes [-limit <num>] [group].
#
proc ::alcoholicz::NxTools::NukeTop {command target user host handle channel argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set group [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {[set group [join $group]] eq ""} {
        set groupQuery ""
    } else {
        set groupQuery "GroupName='[SqlEscape $group]' AND"
    }
    SendTargetTheme $target nuketopHead

    set count 0
    if {[DbOpenFile "Nukes.db"]} {
        db eval "SELECT UserName, GroupName, count(*) AS Nuked, sum(Amount) AS Credits FROM Users \
                WHERE $groupQuery (SELECT count(*) FROM Nukes WHERE NukeId=Users.NukeId AND Status=0) \
                GROUP BY UserName ORDER BY Nuked DESC LIMIT $option(limit)" values {
            incr count
            SendTargetTheme $target nuketopBody [list $values(UserName) \
                $values(GroupName) $values(Credits) $values(Nuked) $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target nuketopNone}
    SendTargetTheme $target nuketopFoot
    return
}

####
# Unnukes
#
# Display recent unnukes, command: !unnukes [-limit <num>] [pattern].
#
proc ::alcoholicz::NxTools::Unnukes {command target user host handle channel argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set pattern [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {[set pattern [join $pattern]] eq ""} {
        set matchQuery ""
    } else {
        set matchQuery "AND Release LIKE '[SqlGetPattern $pattern]' ESCAPE '\\'"
    }
    SendTargetTheme $target unnukesHead

    set count 0
    if {[DbOpenFile "Nukes.db"]} {
        db eval "SELECT * FROM Nukes WHERE Status=1 $matchQuery \
                ORDER BY TimeStamp DESC LIMIT $option(limit)" values {
            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target unnukesBody [list $values(UserName) $values(GroupName) \
                $values(Release) $values(TimeStamp) $values(Multi) $values(Reason) \
                $values(Files) $values(Size) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target unnukesNone}
    SendTargetTheme $target unnukesFoot
    return
}

####
# OneLines
#
# Display recent one-lines, command: !onel.
#
proc ::alcoholicz::NxTools::OneLines {command target user host handle channel argv} {
    variable oneLines
    SendTargetTheme $target oneLinesHead

    set count 0
    if {[DbOpenFile "OneLines.db"]} {
        db eval {SELECT * FROM OneLines ORDER BY TimeStamp DESC LIMIT $oneLines} values {
            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target oneLinesBody [list $values(UserName) \
                $values(GroupName) $values(Message) $values(TimeStamp) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target oneLinesNone}
    SendTargetTheme $target oneLinesFoot
    return
}

####
# Requests
#
# Display current requests, command: !requests.
#
proc ::alcoholicz::NxTools::Requests {command target user host handle channel argv} {
    SendTargetTheme $target requestsHead

    set count 0
    if {[DbOpenFile "Requests.db"]} {
        db eval {SELECT * FROM Requests WHERE Status=0 ORDER BY RequestId DESC} values {
            incr count
            set age [expr {[clock seconds] - $values(TimeStamp)}]
            SendTargetTheme $target requestsBody [list $values(UserName) \
                $values(GroupName) $values(Request) $values(RequestId) $age $count]
        }
        db close
    }

    if {!$count} {SendTargetTheme $target requestsNone}
    SendTargetTheme $target requestsFoot
    return
}

####
# Undupe
#
# Remove a file or directory from the dupe database, command: !undupe [-directory] <pattern>.
#
proc ::alcoholicz::NxTools::Undupe {command target user host handle channel argv} {
    variable undupeChars

    # Parse command options.
    if {[catch {set pattern [GetOptions $argv {directory} option]} message]} {
        CmdSendHelp $channel channel $command $message
        return
    }
    set pattern [join $pattern]
    if {[regexp {[\*\?]} $pattern] && [regexp -all {[[:alnum:]]} $pattern] < $undupeChars} {
        CmdSendHelp $channel channel $command "you must specify at least $undupeChars alphanumeric chars with wildcards"
        return
    }
    if {$pattern eq ""} {
        CmdSendHelp $channel channel $command "you must specify a pattern"
        return
    }
    SendTargetTheme $target undupeHead [list $pattern]

    if {[info exists option(directory)]} {
        set colName "DirName"
        set tableName "DupeDirs"
    } else {
        set colName "FileName"
        set tableName "DupeFiles"
    }

    set count 0
    if {[DbOpenFile "${tableName}.db"]} {
        db eval {BEGIN}
        db eval "SELECT $colName,rowid FROM $tableName WHERE $colName \
                LIKE '[SqlToLike $pattern]' ESCAPE '\\' ORDER BY $colName ASC" values {
            incr count
            SendTargetTheme $target undupeBody [list $values($colName) $count]
            db eval "DELETE FROM $tableName WHERE rowid=$values(rowid)"
        }
        db eval {COMMIT}
        db close
    }

    if {!$count} {SendTargetTheme $target undupeNone [list $pattern]}
    SendTargetTheme $target undupeFoot
    return
}

####
# SiteCmd
#
# Send SITE commands to the FTP server and display the response.
#
proc ::alcoholicz::NxTools::SiteCmd {event command target user host handle channel argv} {
    if {[llength $argv] != 1} {
        CmdSendHelp $channel channel $command
        return
    }
    switch -- $event {
        APPROVE {
            set command "SITE APPROVE BOT ADD"
            set theme "approveAdd"
        }
        REQADD {
            set command "SITE REQBOT ADD"
            set theme "requestAdd"
        }
        REQDEL {
            set command "SITE REQBOT DEL"
            set theme "requestDel"
        }
        REQFILL {
            set command "SITE REQBOT FILL"
            set theme "requestFill"
        }
        default {
            LogError ModNxTools "Unknown status event \"$event\"."
            return
        }
    }
    if {[catch {set ftpUser [GetFtpUser $user]} message]} {
        SendTargetTheme $target $theme [list $message]
        return
    }
    append command " $ftpUser \"[lindex $argv 0]\""

    # Send the SITE command.
    set connection [GetFtpConnection]
    if {[FtpGetStatus $connection] == 2} {
        FtpCommand $connection $command [list [namespace current]::SiteCallback $target $theme]
    } else {
        SendTargetTheme $target $theme [list "Not connected to the FTP server."]
    }
    return
}

####
# SiteCallback
#
# SITE command callback, display the server's response.
#
proc ::alcoholicz::NxTools::SiteCallback {target theme buffer} {
    # Ignore the header, foot, and the "command successful" message.
    foreach {code message} [lrange $buffer 2 end-4] {
        set message [string trim $message "| \t"]
        SendTargetTheme $target $theme [list $message]
    }
}

####
# ReadConfig
#
# Reads required options from the nxTools configuration file.
#
proc ::alcoholicz::NxTools::ReadConfig {configFile} {
    variable oneLines 5
    variable undupeChars 5

    if {![file isfile $configFile]} {
        error "the file \"$configFile\" does not exist"
    }

    # Evaluate the source file in a slave interpreter
    # to retrieve the required configuration options.
    set slave [interp create -safe]
    interp invokehidden $slave source [list $configFile]

    foreach varName {oneLines undupeChars} option {misc(OneLines) dupe(AlphaNumChars)} {
        if {[$slave eval info exists $option]} {
            set $varName [$slave eval set $option]
        } else {
            LogWarning ModNxTools "The option \"$option\" is not defined in \"$configFile\"."
        }
    }

    interp delete $slave
    return
}

####
# Load
#
# Module initialisation procedure, called when the module is loaded.
#
proc ::alcoholicz::NxTools::Load {firstLoad} {
    variable dataPath
    upvar ::alcoholicz::configHandle configHandle

    if {$firstLoad} {
        package require sqlite3
    }

    # Check defined file and directory paths.
    set configFile [ConfigGet $configHandle Module::NxTools configFile]
    if {[catch {ReadConfig $configFile} message]} {
        LogError ModNxTools "Unable to read nxTools configuration: $message"
    }

    set dataPath [ConfigGet $configHandle Module::NxTools dataPath]
    if {![file isdirectory $dataPath]} {
        LogError ModNxTools "The database directory \"$dataPath\" does not exist."
    }

    if {[ConfigExists $configHandle Module::NxTools cmdPrefix]} {
        set prefix [ConfigGet $configHandle Module::NxTools cmdPrefix]
    } else {
        set prefix $::alcoholicz::cmdPrefix
    }

    # Directory commands.
    CmdCreate channel dupe   [namespace current]::Search \
        -category "Stats" -args "\[-limit <num>\] \[-section <name>\] <pattern>" \
        -prefix   $prefix -desc "Search for a release."

    CmdCreate channel new    [namespace current]::Latest \
        -category "Stats" -args "\[-limit <num>\] \[section\]" \
        -prefix   $prefix -desc "Display new releases."

    CmdCreate channel undupe [namespace current]::Undupe \
        -category "Stats" -args "\[-directory\] <pattern>" \
        -prefix   $prefix -desc "Undupe files and directories."

    # Nuke commands.
    CmdCreate channel nukes   [namespace current]::Nukes \
        -category "Stats" -args "\[-limit <num>\] \[pattern\]" \
        -prefix   $prefix -desc "Display recent nukes."

    CmdCreate channel nuketop [namespace current]::NukeTop \
        -category "Stats" -args "\[-limit <num>\] \[group\]" \
        -prefix   $prefix -desc "Display top nuked users."

    CmdCreate channel unnukes [namespace current]::Unnukes \
        -category "Stats" -args "\[-limit <num>\] \[pattern\]" \
        -prefix   $prefix -desc "Display recent unnukes."

    # Request commands.
    CmdCreate channel requests [namespace current]::Requests \
        -category "Request" -desc "Display current requests." -prefix $prefix

    CmdCreate channel request [list [namespace current]::SiteCmd REQADD] \
        -category "Request" -args "<request/id>" \
        -prefix $prefix     -desc "Add a request."

    CmdCreate channel reqdel  [list [namespace current]::SiteCmd REQDEL] \
        -category "Request" -args "<request/id>" \
        -prefix $prefix     -desc "Remove a request."

    CmdCreate channel reqfill [list [namespace current]::SiteCmd REQFILL] \
        -category "Request" -args "<request/id>" \
        -prefix $prefix     -desc "Mark a request as filled."

    # Other commands.
    CmdCreate channel approve [list [namespace current]::SiteCmd APPROVE] \
        -category "General" -args "<release>" \
        -prefix $prefix     -desc "Approve a release."

    CmdCreate channel approved [namespace current]::Approved \
        -category "General" -desc "Display approved releases." -prefix $prefix

    CmdCreate channel onel     [namespace current]::OneLines \
        -category "General" -desc "Display recent one-lines." -prefix $prefix

    return
}

####
# Unload
#
# Module finalisation procedure, called before the module is unloaded.
#
proc ::alcoholicz::NxTools::Unload {} {
    return
}
