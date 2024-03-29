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
proc ::alcoholicz::NxTools::Approved {user host handle channel target argc argv} {
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
proc ::alcoholicz::NxTools::Latest {user host handle channel target argc argv} {
    upvar ::alcoholicz::pathSections pathSections

    # Parse command options.
    set option(limit) -1
    if {[catch {set section [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {$section eq ""} {
        set sectionQuery ""
    } else {
        # Validate the specified section name.
        set names [lsort [array names pathSections]]
        if {[catch {set section [GetElementFromList $names $section section]} message]} {
            CmdSendHelp $channel channel $::lastbind $message
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
proc ::alcoholicz::NxTools::Search {user host handle channel target argc argv} {
    upvar ::alcoholicz::pathSections pathSections

    # Parse command options.
    set option(limit) -1
    set optList [list {limit integer} [list section arg [lsort [array names pathSections]]]]

    if {[catch {set pattern [GetOptions $argv $optList option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    } elseif {$pattern eq ""} {
        CmdSendHelp $channel channel $::lastbind "you must specify a pattern"
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
proc ::alcoholicz::NxTools::Nukes {user host handle channel target argc argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set pattern [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {$pattern eq ""} {
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
proc ::alcoholicz::NxTools::NukeTop {user host handle channel target argc argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set group [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {$group eq ""} {
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
proc ::alcoholicz::NxTools::Unnukes {user host handle channel target argc argv} {
    # Parse command options.
    set option(limit) -1
    if {[catch {set pattern [GetOptions $argv {{limit integer}} option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    }
    set option(limit) [GetResultLimit $option(limit)]

    if {$pattern eq ""} {
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
proc ::alcoholicz::NxTools::OneLines {user host handle channel target argc argv} {
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
proc ::alcoholicz::NxTools::Requests {user host handle channel target argc argv} {
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
proc ::alcoholicz::NxTools::Undupe {user host handle channel target argc argv} {
    variable undupeChars

    # Parse command options.
    if {[catch {set pattern [GetOptions $argv {directory} option]} message]} {
        CmdSendHelp $channel channel $::lastbind $message
        return
    } elseif {[regexp {[\*\?]} $pattern] && [regexp -all {[[:alnum:]]} $pattern] < $undupeChars} {
        CmdSendHelp $channel channel $::lastbind "you must specify at least $undupeChars alphanumeric chars with wildcards"
        return
    } elseif {$pattern eq ""} {
        CmdSendHelp $channel channel $::lastbind "you must specify a pattern"
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
    interp invokehidden $slave source $configFile

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
    CmdCreate channel ${prefix}dupe     [namespace current]::Search \
        Stats "Search for a release." "\[-limit <num>\] \[-section <name>\] <pattern>"

    CmdCreate channel ${prefix}new      [namespace current]::Latest \
        Stats "Display new releases." "\[-limit <num>\] \[section\]"

    CmdCreate channel ${prefix}undupe   [namespace current]::Undupe \
        Stats "Undupe files and directories." "\[-directory\] <pattern>"

    # Nuke commands.
    CmdCreate channel ${prefix}nukes    [namespace current]::Nukes \
        Stats "Display recent nukes." "\[-limit <num>\] \[pattern\]"

    CmdCreate channel ${prefix}nuketop  [namespace current]::NukeTop \
        Stats "Display top nuked users." "\[-limit <num>\] \[group\]"

    CmdCreate channel ${prefix}unnukes  [namespace current]::Unnukes \
        Stats "Display recent unnukes." "\[-limit <num>\] \[pattern\]"

    # Other commands.
    CmdCreate channel ${prefix}approved [namespace current]::Approved \
        General "Display approved releases."

    CmdCreate channel ${prefix}onel     [namespace current]::OneLines \
        General "Display recent one-lines."

    CmdCreate channel ${prefix}requests [namespace current]::Requests \
        General "Display current requests."

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
