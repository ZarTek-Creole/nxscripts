################################################################################
# nxTools - Dupe Checking and Force Forcing                                    #
################################################################################
# Author  : $-66(AUTHOR) #
# Date    : $-66(TIMESTAMP) #
# Version : $-66(VERSION) #
################################################################################

if {[IsTrue $misc(ReloadConfig)] && [catch {source "../scripts/init.itcl"} ErrorMsg]} {
    iputs "Unable to load script configuration, contact a siteop."
    return -code error $ErrorMsg
}

namespace eval ::nxTools::Dupe {
    namespace import -force ::nxLib::*
}

# Dupe Procedures
######################################################################

proc ::nxTools::Dupe::CheckDirs {VirtualPath} {
    global dupe
    ## Check exempts and ignores
    if {[ListMatch $dupe(CheckExempts) $VirtualPath] || [ListMatchI $dupe(IgnoreDirs) $VirtualPath]} {return 0}
    set Result 0
    if {![catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        set DirName [file tail $VirtualPath]
        DirDb function StrEq {string equal -nocase}

        DirDb eval {SELECT * FROM DupeDirs WHERE StrEq(DirName,$DirName) LIMIT 1} values {
            set DupeAge [FormatDuration [expr {[clock seconds] - $values(TimeStamp)}]]
            set DupePath [file join $values(DirPath) $values(DirName)]
            iputs -noprefix "553-.-\[DupeCheck\]-------------------------------------------------."
            iputs -noprefix "553-| [format %-59s "Dupe: $DupePath"] |"
            iputs -noprefix "553-| [format %-59s "Created $DupeAge ago by $values(UserName)."] |"
            iputs -noprefix "553 '-------------------------------------------------------------'"
            set Result 1
        }
        DirDb close
    } else {ErrorLog DupeCheckDirs $ErrorMsg}
    return $Result
}

proc ::nxTools::Dupe::CheckFiles {VirtualPath} {
    global dupe
    ## Check exempts and ignores
    if {[ListMatch $dupe(CheckExempts) $VirtualPath] || [ListMatchI $dupe(IgnoreFiles) $VirtualPath]} {return 0}
    set Result 0
    if {![catch {DbOpenFile FileDb "DupeFiles.db"} ErrorMsg]} {
        set FileName [file tail $VirtualPath]
        FileDb function StrEq {string equal -nocase}

        FileDb eval {SELECT * FROM DupeFiles WHERE StrEq(FileName,$FileName) LIMIT 1} values {
            set DupeAge [FormatDuration [expr {[clock seconds] - $values(TimeStamp)}]]
            iputs -noprefix "553-.-\[DupeCheck\]-------------------------------------------------."
            iputs -noprefix "553-| [format %-59s "Dupe: $values(FileName)"] |"
            iputs -noprefix "553-| [format %-59s "Uploaded $DupeAge ago by $values(UserName)."] |"
            iputs -noprefix "553 '-------------------------------------------------------------'"
            set Result 1
        }
        FileDb close
    } else {ErrorLog DupeCheckFiles $ErrorMsg}
    return $Result
}

proc ::nxTools::Dupe::UpdateLog {Action VirtualPath} {
    global dupe
    if {[ListMatch $dupe(LoggingExempts) $VirtualPath]} {return 0}
    set Action [string toupper $Action]

    ## Check if the virtual path is a file or directory.
    if {[string equal "DELE" $Action] || [string equal "UPLD" $Action] || [file isfile [resolve pwd $VirtualPath]]} {
        if {[IsTrue $dupe(CheckFiles)] && ![ListMatchI $dupe(IgnoreFiles) $VirtualPath]} {
            return [UpdateFiles $Action $VirtualPath]
        }
    } elseif {[IsTrue $dupe(CheckDirs)] && ![ListMatchI $dupe(IgnoreDirs) $VirtualPath]} {
        return [UpdateDirs $Action $VirtualPath]
    }
    return 0
}

proc ::nxTools::Dupe::UpdateDirs {Action VirtualPath} {
    global dupe group user
    if {[catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        ErrorLog DupeUpdateDirs $ErrorMsg
        return 1
    }
    set DirName [file tail $VirtualPath]
    set DirPath [string range $VirtualPath 0 [string last "/" $VirtualPath]]

    if {[string equal "MKD" $Action] || [string equal "RNTO" $Action]} {
        set TimeStamp [clock seconds]
        DirDb eval {INSERT INTO DupeDirs (TimeStamp,UserName,GroupName,DirPath,DirName) VALUES($TimeStamp,$user,$group,$DirPath,$DirName)}
    } elseif {[lsearch -sorted "RMD RNFR WIPE" $Action] != -1} {
        ## Append a slash to improve the accuracy of StrEqN.
        ## Ex. /Dir/Blah matches /Dir/Blah.Blah but /Dir/Blah/ doesn't.
        append VirtualPath "/"
        DirDb function StrEq {string equal -nocase}
        DirDb function StrEqN {string equal -nocase -length}
        DirDb eval {DELETE FROM DupeDirs WHERE StrEqN(length($VirtualPath),DirPath,$VirtualPath) OR (StrEq(DirPath,$DirPath) AND StrEq(DirName,$DirName))}
    }
    DirDb close
    return 0
}

proc ::nxTools::Dupe::UpdateFiles {Action VirtualPath} {
    global dupe group user
    if {[catch {DbOpenFile FileDb "DupeFiles.db"} ErrorMsg]} {
        ErrorLog DupeUpdateFiles $ErrorMsg
        return 1
    }
    set FileName [file tail $VirtualPath]

    if {[string equal "UPLD" $Action] || [string equal "RNTO" $Action]} {
        set TimeStamp [clock seconds]
        FileDb eval {INSERT INTO DupeFiles (TimeStamp,UserName,GroupName,FileName) VALUES($TimeStamp,$user,$group,$FileName)}
    } elseif {[string equal "DELE" $Action] || [string equal "RNFR" $Action]} {
        FileDb function StrEq {string equal -nocase}
        FileDb eval {DELETE FROM DupeFiles WHERE StrEq(FileName,$FileName)}
    }
    FileDb close
    return 0
}

proc ::nxTools::Dupe::CleanDb {} {
    global dupe misc user group
    ## A userfile and VFS file will have to be opened so that resolve works under ioFTPD's scheduler
    if {![info exists user] && ![info exists group]} {
        if {[userfile open $misc(MountUser)] != 0} {
            ErrorLog DupeClean "unable to open the user \"$misc(MountUser)\""; return 1
        } elseif {[mountfile open $misc(MountFile)] != 0} {
            ErrorLog DupeClean "unable to mount the VFS-file \"$misc(MountFile)\""; return 1
        }
    }
    iputs ".-\[CleanLogs\]------------------------------------------------------------."
    if {$dupe(CleanFiles) == 0} {
        LinePuts "File database cleaning disabled, skipping."
    } elseif {[catch {DbOpenFile FileDb "DupeFiles.db"} ErrorMsg]} {
        LinePuts "Unable to open the file database."
        ErrorLog CleanFiles $ErrorMsg
    } else {
        LinePuts "Cleaning the file database."
        set MaxAge [expr {[clock seconds] - $dupe(CleanFiles) * 86400}]
        FileDb eval {DELETE FROM DupeFiles WHERE TimeStamp < $MaxAge}
        FileDb close
    }

    if {$dupe(CleanFiles) == 0} {
        LinePuts "Directory database cleaning disabled, skipping."
    } elseif {[catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        LinePuts "Unable to open the directory database."
        ErrorLog CleanDirs $ErrorMsg
    } else {
        LinePuts "Cleaning the directory database."
        set MaxAge [expr {[clock seconds] - $dupe(CleanDirs) * 86400}]
        DirDb eval {BEGIN}
        DirDb eval {SELECT DirPath,DirName,rowid FROM DupeDirs WHERE TimeStamp < $MaxAge ORDER BY TimeStamp DESC} values {
            set FullPath [file join $values(DirPath) $values(DirName)]
            if {![file isdirectory [resolve pwd $FullPath]]} {
                DirDb eval {DELETE FROM DupeDirs WHERE rowid=$values(rowid)}
            }
        }
        DirDb eval {COMMIT}
        DirDb close
    }
    iputs "'------------------------------------------------------------------------'"
    return 0
}

proc ::nxTools::Dupe::RebuildDb {} {
    global dupe misc
    iputs ".-\[RebuildLogs\]----------------------------------------------------------."
    if {![llength $dupe(RebuildPaths)]} {
        ErrorReturn "There are no paths defined, check your configuration."
    }
    if {[catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        ErrorLog RebuildDirs $ErrorMsg
        return 1
    }
    if {[catch {DbOpenFile FileDb "DupeFiles.db"} ErrorMsg]} {
        ErrorLog RebuildFiles $ErrorMsg
        DirDb close
        return 1
    }
    DirDb eval {BEGIN; DELETE FROM DupeDirs;}
    FileDb eval {BEGIN; DELETE FROM DupeFiles;}

    foreach RebuildPath $dupe(RebuildPaths) {
        if {[llength $RebuildPath] != 4} {
            ErrorLog DupeRebuild "wrong number of parameters in line: \"$RebuildPath\""; continue
        }
        foreach {VirtualPath RealPath UpdateDirs UpdateFiles} $RebuildPath {break}
        set TrimLength [expr {[string length [file normalize $RealPath]] + 1}]

        ## Process directory lists
        LinePuts "Updating dupe database from: $RealPath"
        GetDirList $RealPath dirlist $dupe(RebuildIgnore)

        foreach ListName "DirList FileList" DefOwner [list $misc(DirOwner) $misc(FileOwner)] {
            if {[set FileMode [string equal "FileList" $ListName]]} {
                if {![IsTrue $UpdateFiles]} {continue}
                set IgnoreList $dupe(IgnoreFiles)
                set MaxAge [expr {$dupe(CleanFiles) * 86400}]
            } else {
                if {![IsTrue $UpdateDirs]} {continue}
                set IgnoreList $dupe(IgnoreDirs)
                set MaxAge 0
            }
            set DefUser [resolve uid [lindex $DefOwner 0]]
            set DefGroup [resolve gid [lindex $DefOwner 1]]

            foreach ListItem $dirlist($ListName) {
                ## Check if the list item is in the ignore list
                if {[ListMatchI $IgnoreList $ListItem]} {continue}

                ## Read date and owner
                if {[catch {file stat $ListItem fstat}]} {continue}
                if {$MaxAge != 0 && ([clock seconds] - $fstat(ctime)) > $MaxAge} {continue}
                catch {vfs read $ListItem} Owner
                if {[set UserName [resolve uid [lindex $Owner 0]]] == ""} {set UserName $DefUser}
                if {[set GroupName [resolve gid [lindex $Owner 1]]] == ""} {set GroupName $DefGroup}

                ## File/directory specific log types
                set BaseName [file tail $ListItem]
                if {$FileMode} {
                    FileDb eval {INSERT INTO DupeFiles (TimeStamp,UserName,GroupName,FileName) VALUES($fstat(ctime),$UserName,$GroupName,$BaseName)}
                } else {
                    set DirPath [file join $VirtualPath [string range [file dirname $ListItem] $TrimLength end]]
                    append DirPath "/"
                    DirDb eval {INSERT INTO DupeDirs (TimeStamp,UserName,GroupName,DirPath,DirName) VALUES($fstat(ctime),$UserName,$GroupName,$DirPath,$BaseName)}
                }
            }
        }
    }
    DirDb eval {COMMIT}
    DirDb close
    FileDb eval {COMMIT}
    FileDb close
    iputs "'------------------------------------------------------------------------'"
    return 0
}

# Other Procedures
######################################################################

proc ::nxTools::Dupe::ApproveCheck {VirtualPath CreateTag} {
    set Approved 0
    if {![catch {DbOpenFile ApproveDb "Approves.db"} ErrorMsg]} {
        ApproveDb function StrEq {string equal -nocase}
        set Release [file tail $VirtualPath]
        ApproveDb eval {SELECT UserName,GroupName,rowid FROM Approves WHERE StrEq(Release,$Release) LIMIT 1} values {set Approved 1}
        if {$Approved && $CreateTag} {
            ApproveRelease $VirtualPath $values(UserName) $values(GroupName)
            ApproveDb eval {DELETE FROM Approves WHERE rowid=$values(rowid)}
        }
        ApproveDb close
    } else {ErrorLog ApproveCheck $ErrorMsg}
    return $Approved
}

proc ::nxTools::Dupe::ApproveRelease {VirtualPath UserName GroupName} {
    global approve
    set RealPath [resolve pwd $VirtualPath]
    if {[file isdirectory $RealPath]} {
        putlog "APPROVE: \"$VirtualPath\" \"$UserName\" \"$GroupName\""
        set TagPath [file join $RealPath [string map [list %(user) $UserName %(group) $GroupName] $approve(DirTag)]]
        CreateTag $TagPath [resolve user $UserName] [resolve group $GroupName] 555
    } else {
        ErrorLog ApproveRelease "invalid vpath \"$VirtualPath\", \"$RealPath\" doesn't exist."
        return 0
    }
    return 1
}

proc ::nxTools::Dupe::ForceCheck {VirtualPath} {
    global force
    set FileExt [file extension $VirtualPath]
    set MatchPath [file dirname $VirtualPath]

    if {![string equal -nocase ".nfo" $FileExt] && ![string equal -nocase ".sfv" $FileExt] && ![ListMatchI $force(Exempts) $MatchPath]} {
        set ReleasePath [resolve pwd [expr {[IsMultiDisk $MatchPath] ? [file dirname $MatchPath] : $MatchPath}]]
        set CheckFile [ListMatch $force(FilePaths) $MatchPath]

        if {$CheckFile && [IsTrue $force(NfoFirst)]} {
            if {![llength [glob -nocomplain -types f -directory $ReleasePath "*.nfo"]]} {
                iputs -noprefix "553-.-\[ForceNFO\]------------------------------------."
                iputs -noprefix "553-| You must upload the NFO first.                |"
                iputs -noprefix "553 '-----------------------------------------------'"
                return 1
            }
        }
        if {$CheckFile && [IsTrue $force(SfvFirst)]} {
            set RealPath [resolve pwd $MatchPath]
            if {![llength [glob -nocomplain -types f -directory $RealPath "*.sfv"]]} {
                iputs -noprefix "553-.-\[ForceSFV\]------------------------------------."
                iputs -noprefix "553-| You must upload the SFV first.                |"
                iputs -noprefix "553 '-----------------------------------------------'"
                return 1
            }
        }
        if {[IsTrue $force(SampleFirst)] && [ListMatch $force(SamplePaths) $MatchPath]} {
            set SampleFiles "sample/{*.avi,*.mpeg,*.mpg,*.vob}"
            if {![llength [glob -nocomplain -types f -directory $ReleasePath $SampleFiles]]} {
                iputs -noprefix "553-.-\[ForceSample\]---------------------------------."
                iputs -noprefix "553-| You must upload the sample first.             |"
                iputs -noprefix "553 '-----------------------------------------------'"
                return 1
            }
        }
    }
    return 0
}

proc ::nxTools::Dupe::PreTimeCheck {VirtualPath} {
    global misc mysql pretime
    if {[ListMatchI $pretime(Ignores) $VirtualPath]} {return 0}
    set Check 0; set Result 0
    foreach PreCheck $pretime(CheckPaths) {
        if {[llength $PreCheck] != 4} {
            ErrorLog PreTimeCheck "wrong number of parameters in line: \"$PreCheck\""; continue
        }
        foreach {CheckPath DenyLate LogInfo LateMins} $PreCheck {break}
        if {[string match $CheckPath $VirtualPath]} {set Check 1; break}
    }
    if {$Check && [MySqlClose]} {
        set ReleaseName [::mysql::escape [file tail $VirtualPath]]
        set TimeStamp [::mysql::sel $mysql(ConnHandle) "SELECT pretime FROM $mysql(TableName) WHERE release='$ReleaseName' LIMIT 1" -flatlist]

        if {![string equal "" $TimeStamp]} {
            if {[set ReleaseAge [expr {[clock seconds] - $TimeStamp}]] > [set LateSecs [expr {$LateMins * 60}]]} {
                if {[IsTrue $DenyLate]} {
                    set ErrCode 553; set LogPrefix "DENYPRE"; set Result 1
                    set ErrMsg "Release not allowed by pre rules, older than [FormatDurationLong $LateSecs]."
                } else {
                    set ErrCode 257; set LogPrefix "WARNPRE"
                    set ErrMsg "Release older than [FormatDurationLong $LateSecs], possible nuke."
                }
                iputs -noprefix "${ErrCode}-.-\[PreCheck\]--------------------------------------------------."
                iputs -noprefix "${ErrCode}-| [format %-59s $ErrMsg] |"
                iputs -noprefix "${ErrCode}-| [format %-59s "Pre'd [FormatDurationLong $ReleaseAge] ago."] |"
                iputs -noprefix "${ErrCode} '-------------------------------------------------------------'"
                if {[IsTrue $LogInfo]} {
                    if {[IsTrue $misc(dZSbotLogging)]} {
                        set LateSecs $LateMins
                        set ReleaseAge [FormatDuration $ReleaseAge]
                        set TimeStamp [clock format $TimeStamp -format "%m/%d/%y %H:%M:%S" -gmt 1]
                    }
                    putlog "${LogPrefix}: \"$VirtualPath\" \"$LateSecs\" \"$ReleaseAge\" \"$TimeStamp\""
                }
            } elseif {[IsTrue $LogInfo]} {
                if {[IsTrue $misc(dZSbotLogging)]} {
                    set ReleaseAge [FormatDuration $ReleaseAge]
                    set TimeStamp [clock format $TimeStamp -format "%m/%d/%y %H:%M:%S" -gmt 1]
                }
                putlog "PRETIME: \"$VirtualPath\" \"$ReleaseAge\" \"$TimeStamp\""
            }
        }
        MySqlClose
    }
    return $Result
}

proc ::nxTools::Dupe::RaceLinks {VirtualPath} {
    global latest
    if {[ListMatch $latest(Exempts) $VirtualPath] || [ListMatchI $latest(Ignores) $VirtualPath]} {
        return 0
    }
    if {[catch {DbOpenFile LinkDb "Links.db"} ErrorMsg]} {
        ErrorLog RaceLinks $ErrorMsg
        return 1
    }
    ## Format and create the link directory
    set TagName [file tail $VirtualPath]
    if {$latest(MaxLength) > 0 && [string length $TagName] > $latest(MaxLength)} {
        set TagName [string trimright [string range $TagName 0 $latest(MaxLength)] "."]
    }
    set TagName [string map [list %(release) $TagName] $latest(RaceTag)]
    set TimeStamp [clock seconds]
    LinkDb eval {INSERT INTO Links (TimeStamp,LinkType,DirName) VALUES($TimeStamp,0,$TagName)}
    set TagName [file join $latest(SymPath) $TagName]
    if {![catch {file mkdir $TagName} ErrorMsg]} {
        catch {vfs chattr $TagName 1 $VirtualPath}
    } else {ErrorLog RaceLinksMkDir $ErrorMsg}

    ## Remove older links
    if {[set LinkCount [LinkDb eval {SELECT count(*) FROM Links WHERE LinkType=0}]] > $latest(RaceLinks)} {
        set LinkCount [expr {$LinkCount - $latest(RaceLinks)}]
        LinkDb eval "SELECT DirName,rowid FROM Links WHERE LinkType=0 ORDER BY TimeStamp ASC LIMIT $LinkCount" values {
            RemoveTag [file join $latest(SymPath) $values(DirName)]
            LinkDb eval {DELETE FROM Links WHERE rowid=$values(rowid)}
        }
    }
    LinkDb close
    return 0
}

# Site Commands
######################################################################

proc ::nxTools::Dupe::SiteApprove {Action Release} {
    global IsSiteBot approve misc flags group user
    if {[catch {DbOpenFile ApproveDb "Approves.db"} ErrorMsg]} {
        ErrorLog SiteApprove $ErrorMsg
        return 1
    }
    ApproveDb function StrEq {string equal -nocase}
    set Release [file tail $Release]
    switch -- $Action {
        {add} {
            iputs ".-\[Approve\]--------------------------------------------------------------."
            if {![regexp "\[$approve(Flags)\]" $flags]} {
                LinePuts "Only siteops may approve releases."
            } elseif {[ApproveDb eval {SELECT count(*) FROM Approves WHERE StrEq(Release,$Release)}]} {
                LinePuts "This release is already approved."
            } else {
                ## If the release already exists in the dupe database, we'll approve that one.
                set Approved 0
                if {![catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
                    DirDb function StrEq {string equal -nocase}
                    DirDb eval {SELECT DirName,DirPath FROM DupeDirs WHERE StrEq(DirName,$Release) ORDER BY TimeStamp DESC LIMIT 1} values {
                        set VirtualPath [file join $values(DirPath) $values(DirName)]
                        set Approved [ApproveRelease $VirtualPath $user $group]
                    }
                    DirDb close
                } else {ErrorLog SiteApprove $ErrorMsg}

                if {$Approved} {
                    LinePuts "Found the release, approved \"$VirtualPath\"."
                } else {
                    set TimeStamp [clock seconds]
                    ApproveDb eval {INSERT INTO Approves (TimeStamp,UserName,GroupName,Release) values($TimeStamp,$user,$group,$Release)}
                    putlog "APPROVEADD: \"$user\" \"$group\" \"$Release\""
                    LinePuts "Added \"$Release\" to the approve list."
                }
            }
            iputs "'------------------------------------------------------------------------'"
        }
        {del} {
            iputs ".-\[Approve\]--------------------------------------------------------------."
            if {![regexp "\[$approve(Flags)\]" $flags]} {
                LinePuts "Only siteops may deleted approved releases."
            } else {
                set Exists 0
                ApproveDb eval {SELECT rowid,* FROM Approves WHERE StrEq(Release,$Release) LIMIT 1} values {set Exists 1}
                if {$Exists} {
                    ApproveDb eval {DELETE FROM Approves WHERE rowid=$values(rowid)}
                    putlog "APPROVEDEL: \"$user\" \"$group\" \"$values(Release)\""
                    LinePuts "Removed \"$values(Release)\" from the approve list."
                } else {
                    LinePuts "Invalid release, use \"SITE APPROVE LIST\" to view approved releases."
                }
            }
            iputs "'------------------------------------------------------------------------'"
        }
        {list} {
            if {!$IsSiteBot} {
                foreach MessageType {Header Body None Footer} {
                    set template($MessageType) [ReadFile [file join $misc(Templates) "Approves.$MessageType"]]
                }
                OutputData $template(Header)
                set Count 0
            }
            ApproveDb eval {SELECT * FROM Approves ORDER BY Release ASC} values {
                set ApproveAge [expr {[clock seconds] - $values(TimeStamp)}]
                if {$IsSiteBot} {
                    iputs "APPROVE|$values(TimeStamp)|$ApproveAge|$values(UserName)|$values(GroupName)|$values(Release)"
                } else {
                    incr Count
                    set ApproveAge [lrange [FormatDuration $ApproveAge] 0 1]
                    set ValueList [list $Count $ApproveAge $values(UserName) $values(GroupName) $values(Release)]
                    OutputData [ParseCookies $template(Body) $ValueList {num age user group release}]
                }
            }
            if {!$IsSiteBot} {
                if {!$Count} {OutputData $template(None)}
                OutputData $template(Footer)
            }
        }
    }
    ApproveDb close
    return 0
}

proc ::nxTools::Dupe::SiteDupe {MaxResults Pattern} {
    global IsSiteBot misc
    if {[catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        ErrorLog SiteDupe $ErrorMsg
        return 1
    }
    if {!$IsSiteBot} {
        foreach MessageType {Header Body None Footer} {
            set template($MessageType) [ReadFile [file join $misc(Templates) "Dupe.$MessageType"]]
        }
        OutputData $template(Header)
    }
    set Pattern [SqlWildToLike [regsub -all {[\s\*]+} "*$Pattern*" "*"]]
    set Count 0
    DirDb eval "SELECT * FROM DupeDirs WHERE DirName LIKE '$Pattern' ESCAPE '\\' ORDER BY TimeStamp DESC LIMIT $MaxResults" values {
        incr Count
        if {$IsSiteBot} {
            iputs "DUPE|$Count|$values(TimeStamp)|$values(UserName)|$values(GroupName)|$values(DirPath)|$values(DirName)"
        } else {
            set ValueList [clock format $values(TimeStamp) -format {{%S} {%M} {%H} {%d} {%m} {%y} {%Y}} -gmt [IsTrue $misc(UtcTime)]]
            lappend ValueList $Count $values(UserName) $values(GroupName) $values(DirName) [file join $values(DirPath) $values(DirName)]
            OutputData [ParseCookies $template(Body) $ValueList {sec min hour day month year2 year4 num user group release path}]
        }
    }
    if {!$IsSiteBot} {
        if {!$Count} {OutputData $template(None)}
        if {$Count == $MaxResults} {
            set Total [DirDb eval "SELECT count(*) FROM DupeDirs WHERE DirName LIKE '$Pattern' ESCAPE '\\'"]
        } else {
            set Total $Count
        }
        OutputData [ParseCookies $template(Footer) [list $Count $Total] {found total}]
    }
    DirDb close
    return 0
}

proc ::nxTools::Dupe::SiteFileDupe {MaxResults Pattern} {
    global IsSiteBot misc
    if {[catch {DbOpenFile FileDb "DupeFiles.db"} ErrorMsg]} {
        ErrorLog SiteFileDupe $ErrorMsg
        return 1
    }
    if {!$IsSiteBot} {
        foreach MessageType {Header Body None Footer} {
            set template($MessageType) [ReadFile [file join $misc(Templates) "FileDupe.$MessageType"]]
        }
        OutputData $template(Header)
    }
    set Pattern [SqlWildToLike [regsub -all {[\s\*]+} "*$Pattern*" "*"]]
    set Count 0
    FileDb eval "SELECT * FROM DupeFiles WHERE FileName LIKE '$Pattern' ESCAPE '\\' ORDER BY TimeStamp DESC LIMIT $MaxResults" values {
        incr Count
        if {$IsSiteBot} {
            iputs "DUPE|$Count|$values(TimeStamp)|$values(UserName)|$values(GroupName)|$values(FileName)"
        } else {
            set ValueList [clock format $values(TimeStamp) -format {{%S} {%M} {%H} {%d} {%m} {%y} {%Y}} -gmt [IsTrue $misc(UtcTime)]]
            lappend ValueList $Count $values(UserName) $values(GroupName) $values(FileName)
            OutputData [ParseCookies $template(Body) $ValueList {sec min hour day month year2 year4 num user group file}]
        }
    }
    if {!$IsSiteBot} {
        if {!$Count} {OutputData $template(None)}
        if {$Count == $MaxResults} {
            set Total [FileDb eval "SELECT count(*) FROM DupeFiles WHERE FileName LIKE '$Pattern' ESCAPE '\\'"]
        } else {
            set Total $Count
        }
        OutputData [ParseCookies $template(Footer) [list $Count $Total] {found total}]
    }
    FileDb close
    return 0
}

proc ::nxTools::Dupe::SiteNew {MaxResults ShowSection} {
    global IsSiteBot misc new
    if {[catch {DbOpenFile DirDb "DupeDirs.db"} ErrorMsg]} {
        ErrorLog SiteNew $ErrorMsg
        return 1
    }
    if {!$IsSiteBot} {
        foreach MessageType {Header Error Body None Footer} {
            set template($MessageType) [ReadFile [file join $misc(Templates) "New.$MessageType"]]
        }
        OutputData $template(Header)
    }
    set SectionList [GetSectionList]
    if {![set ShowAll [string equal "" $ShowSection]]} {
        ## Validate the section name
        set SectionNameList ""; set ValidSection 0
        foreach {SectionName CreditSection StatSection MatchPath} $SectionList {
            if {[string equal -nocase $ShowSection $SectionName]} {
                set ShowSection $SectionName
                set ValidSection 1; break
            }
            lappend SectionNameList $SectionName
        }
        if {!$ValidSection} {
            set SectionNameList [join [lsort -ascii $SectionNameList]]
            OutputData [ParseCookies $template(Error) [list $SectionNameList] {sections}]
            OutputData $template(Footer)
            DirDb close
            return 1
        }
        set MatchPath [SqlWildToLike $MatchPath]
        set WhereClause "WHERE DirPath LIKE '$MatchPath' ESCAPE '\\'"
    } else {set WhereClause ""}

    set Count 0
    DirDb eval "SELECT * FROM DupeDirs $WhereClause ORDER BY TimeStamp DESC LIMIT $MaxResults" values {
        incr Count
        ## Find section name and check the match path
        if {$ShowAll} {
            set SectionName "Default"
            foreach {SectionName CreditSection StatSection MatchPath} $SectionList {
                if {[string match -nocase $MatchPath $values(DirPath)]} {set ShowSection $SectionName; break}
            }
        }
        set ReleaseAge [expr {[clock seconds] - $values(TimeStamp)}]
        if {$IsSiteBot} {
            iputs "NEW|$Count|$ReleaseAge|$values(UserName)|$values(GroupName)|$ShowSection|$values(DirPath)|$values(DirName)"
        } else {
            set ReleaseAge [lrange [FormatDuration $ReleaseAge] 0 1]
            set ValueList [list $Count $ReleaseAge $values(UserName) $values(GroupName) $ShowSection $values(DirName) [file join $values(DirPath) $values(DirName)]]
            OutputData [ParseCookies $template(Body) $ValueList {num age user group section release path}]
        }
    }
    if {!$IsSiteBot} {
        if {!$Count} {OutputData $template(None)}
        OutputData $template(Footer)
    }
    DirDb close
    return 0
}

proc ::nxTools::Dupe::SitePreTime {MaxResults Pattern} {
    global IsSiteBot misc mysql
    if {!$IsSiteBot} {
        foreach MessageType {Header Body BodyInfo BodyNuke None Footer} {
            set template($MessageType) [ReadFile [file join $misc(Templates) "PreTime.$MessageType"]]
        }
        OutputData $template(Header)
    }
    set Pattern [SqlWildToLike [regsub -all {[\s\*]+} "*$Pattern*" "*"]]
    set Count 0
    if {[MySqlClose]} {
        set QueryResults [::mysql::sel $mysql(ConnHandle) "SELECT * FROM $mysql(TableName) WHERE release LIKE '$Pattern' ORDER BY pretime DESC LIMIT $MaxResults" -list]
        set SingleResult [expr {[llength $QueryResults] == 1}]
        set TimeNow [clock seconds]

        foreach QueryLine $QueryResults {
            incr Count
            foreach {PreId PreTime Section Release Files KBytes Disks IsNuked NukeTime NukeReason} $QueryLine {break}
            set ReleaseAge [expr {$TimeNow - $PreTime}]
            if {$IsSiteBot} {
                iputs "PRETIME|$Count|$ReleaseAge|$PreTime|$Section|$Release|$Files|$KBytes|$Disks|$IsNuked|$NukeTime|$NukeReason"
            } else {
                set BodyTemplate [expr {$SingleResult ? ($IsNuked != 0 ? $template(BodyNuke) : $template(BodyInfo)) : $template(Body)}]
                set ReleaseAge [FormatDuration $ReleaseAge]

                ## The pre time should always been in UTC (GMT).
                set ValueList [clock format $PreTime -format {{%S} {%M} {%H} {%d} {%m} {%y} {%Y}} -gmt 1]
                set ValueList [concat $ValueList [clock format $NukeTime -format {{%S} {%M} {%H} {%d} {%m} {%y} {%Y}} -gmt 1]]
                lappend ValueList $ReleaseAge $Count $Section $Release $Files [FormatSize $KBytes] $Disks $NukeReason
                OutputData [ParseCookies $BodyTemplate $ValueList {sec min hour day month year2 year4 nukesec nukemin nukehour nukeday nukemonth nukeyear2 nukeyear4 age num section release files size disks reason}]
            }
        }
        MySqlClose
    }
    if {!$IsSiteBot} {
        if {!$Count} {OutputData $template(None)}
        OutputData $template(Footer)
    }
    return 0
}

proc ::nxTools::Dupe::SiteUndupe {ArgList} {
    global IsSiteBot dupe misc
    if {!$IsSiteBot} {iputs ".-\[Undupe\]---------------------------------------------------------------."}
    if {[string equal -nocase "-d" [lindex $ArgList 0]]} {
        set ColName "DirName"; set DbName "DupeDirs"
        set Pattern [join [lrange $ArgList 1 end]]
    } else {
        set ColName "FileName"; set DbName "DupeFiles"
        set Pattern [join [lrange $ArgList 0 end]]
    }
    if {[regexp {[\*\?]} $Pattern] && [regexp -all {[[:alnum:]]} $Pattern] < $dupe(AlphaNumChars)} {
        if {!$IsSiteBot} {ErrorReturn "There must be at $dupe(AlphaNumChars) least alpha-numeric chars when wildcards are used."}
        return 1
    }
    if {!$IsSiteBot} {LinePuts "Searching for: $Pattern"}
    set Removed 0; set Total 0
    set Pattern [SqlWildToLike $Pattern]

    if {![catch {DbOpenFile DupeDb "${DbName}.db"} ErrorMsg]} {
        set Total [DupeDb eval "SELECT count(*) FROM $DbName"]
        DupeDb eval {BEGIN}
        DupeDb eval "SELECT $ColName,rowid FROM $DbName WHERE $ColName LIKE '$Pattern' ESCAPE '\\' ORDER BY $ColName ASC" values {
            incr Removed
            if {$IsSiteBot} {
                iputs "UNDUPE|$values($ColName)"
            } else {
                LinePuts "Unduped: $values($ColName)"
            }
            DupeDb eval "DELETE FROM $DbName WHERE rowid=$values(rowid)"
        }
        DupeDb eval {COMMIT}
        DupeDb close
    }
    if {!$IsSiteBot} {
        iputs "|------------------------------------------------------------------------|"
        LinePuts "Unduped $Removed of $Total dupe entries."
        iputs "'------------------------------------------------------------------------'"
    }
    return 0
}

proc ::nxTools::Dupe::SiteWipe {VirtualPath} {
    global dupe misc wipe group user
    iputs ".-\[Wipe\]-----------------------------------------------------------------."
    ## Resolving a symlink returns its target path, which could have unwanted
    ## results. To avoid such issues, we'll resolve the parent path instead.
    set ParentPath [resolve pwd [file dirname $VirtualPath]]
    set RealPath [file join $ParentPath [file tail $VirtualPath]]
    if {![file exists $RealPath]} {
        ErrorReturn "The specified file or directory does not exist."
    }

    set MatchPath [string range $VirtualPath 0 [string last "/" $VirtualPath]]
    if {[ListMatch $wipe(NoPaths) $MatchPath]} {
        ErrorReturn "Not allowed to wipe from here."
    }
    GetDirStats $RealPath stats ".ioFTPD*"
    set stats(TotalSize) [expr {wide($stats(TotalSize)) / 1024}]

    set IsDir [file isdirectory $RealPath]
    KickUsers [expr {$IsDir ? "$VirtualPath/*" : $VirtualPath}]
    if {[catch {file delete -force -- $RealPath} ErrorMsg]} {
        ErrorLog SiteWipe $ErrorMsg
        LinePuts "Unable to delete the specified file or directory."
    }
    catch {vfs flush [resolve pwd $ParentPath]}
    LinePuts "Wiped $stats(FileCount) File(s), $stats(DirCount) Directory(s), [FormatSize $stats(TotalSize)]"
    iputs "'------------------------------------------------------------------------'"

    if {$IsDir} {
        RemoveParentLinks $RealPath $VirtualPath
        if {[IsTrue $misc(dZSbotLogging)]} {
            set stats(TotalSize) [expr {wide($stats(TotalSize)) / 1024}]
        }
        putlog "WIPE: \"$VirtualPath\" \"$user\" \"$group\" \"$stats(DirCount)\" \"$stats(FileCount)\" \"$stats(TotalSize)\""
        if {[IsTrue $dupe(CheckDirs)]} {
            UpdateLog "WIPE" $VirtualPath
        }
    } elseif {[IsTrue $dupe(CheckFiles)]} {
        UpdateLog "DELE" $VirtualPath
    }
    return 0
}

# Dupe Main
######################################################################

proc ::nxTools::Dupe::Main {ArgV} {
    global IsSiteBot approve dupe force latest misc pretime group ioerror pwd user
    if {[IsTrue $misc(DebugMode)]} {DebugLog -state [info script]}
    set IsSiteBot [expr {[info exists user] && [string equal $misc(SiteBot) $user]}]

    ## Safe argument handling
    set ArgLength [llength [set ArgList [ArgList $ArgV]]]
    set Action [string tolower [lindex $ArgList 0]]
    set Result 0
    switch -- $Action {
        {dupelog} {
            set VirtualPath [GetPath $pwd [join [lrange $ArgList 2 end]]]
            if {[IsTrue $dupe(CheckDirs)] || [IsTrue $dupe(CheckFiles)]} {
                set Result [UpdateLog [lindex $ArgList 1] $VirtualPath]
            }
        }
        {postmkd} {
            set VirtualPath [GetPath $pwd [join [lrange $ArgList 2 end]]]
            if {[IsTrue $dupe(CheckDirs)]} {
                set Result [UpdateLog [lindex $ArgList 1] $VirtualPath]
            }
            if {$latest(RaceLinks) > 0} {
                set Result [RaceLinks $VirtualPath]
            }
            if {[IsTrue $approve(CheckMkd)]} {ApproveCheck $VirtualPath 1}
        }
        {premkd} {
            set VirtualPath [GetPath $pwd [join [lrange $ArgList 2 end]]]
            if {!([IsTrue $approve(CheckMkd)] && [ApproveCheck $VirtualPath 0])} {
                if {[IsTrue $dupe(CheckDirs)]} {
                    set Result [CheckDirs $VirtualPath]
                }
                if {$Result == 0 && [IsTrue $pretime(CheckMkd)]} {
                    set Result [PreTimeCheck $VirtualPath]
                }
            }
        }
        {prestor} {
            set VirtualPath [GetPath $pwd [join [lrange $ArgList 2 end]]]
            if {[IsTrue $force(NfoFirst)] || [IsTrue $force(SfvFirst)] || [IsTrue $force(SampleFirst)]} {
                set Result [ForceCheck $VirtualPath]
            }
            if {$Result == 0 && [IsTrue $dupe(CheckFiles)]} {
                set Result [CheckFiles $VirtualPath]
            }
        }
        {upload} {
            if {[IsTrue $dupe(CheckFiles)]} {
                foreach {Tmp RealPath CRC VirtualPath} $ArgV {break}
                UpdateLog "UPLD" $VirtualPath
            }
        }
        {uploaderror} {
            if {[IsTrue $dupe(CheckFiles)]} {
                foreach {Tmp RealPath CRC VirtualPath} $ArgV {break}
                UpdateLog "DELE" $VirtualPath
            }
        }
        {clean} {
            set Result [CleanDb]
        }
        {approve} {
            array set params [list add 2 del 2 list 0]
            set SubAction [string tolower [lindex $ArgList 1]]
            if {[info exists params($SubAction)] && $ArgLength > $params($SubAction)} {
                set Result [SiteApprove $SubAction [join [lrange $ArgList 2 end]]]
            } else {
                iputs "Syntax: SITE APPROVE ALL <release>"
                iputs "        SITE APPROVE DEL <release>"
                iputs "        SITE APPROVE LIST"
            }
        }
        {dupe} {
            if {$ArgLength > 1 && [GetOptions [lrange $ArgList 1 end] MaxResults Pattern]} {
                set Result [SiteDupe $MaxResults $Pattern]
            } else {
                iputs "Syntax: SITE DUPE \[-max <limit>\] <release>"
            }
        }
        {fdupe} {
            if {$ArgLength > 1 && [GetOptions [lrange $ArgList 1 end] MaxResults Pattern]} {
                set Result [SiteFileDupe $MaxResults $Pattern]
            } else {
                iputs "Syntax: SITE FDUPE \[-max <limit>\] <filename>"
            }
        }
        {new} {
            if {[GetOptions [lrange $ArgList 1 end] MaxResults SectionName]} {
                set Result [SiteNew $MaxResults $SectionName]
            } else {
                iputs "Syntax: SITE NEW \[-max <limit>\] \[section\]"
            }
        }
        {pretime} {
            if {$ArgLength > 1 && [GetOptions [lrange $ArgList 1 end] MaxResults Pattern]} {
                set Result [SitePreTime $MaxResults $Pattern]
            } else {
                iputs "Syntax: SITE PRETIME \[-max <limit>\] <release>"
            }
        }
        {rebuild} {
            set Result [RebuildDb]
        }
        {undupe} {
            if {$ArgLength > 1} {
                set Result [SiteUndupe [lrange $ArgList 1 end]]
            } else {
                iputs "Syntax: SITE UNDUPE <filename>"
                iputs "        SITE UNDUPE -d <directory>"
            }
        }
        {wipe} {
            if {$ArgLength > 1} {
                set VirtualPath [GetPath $pwd [join [lrange $ArgList 1 end]]]
                set Result [SiteWipe $VirtualPath]
            } else {
                iputs " Usage: SITE WIPE <file/directory>"
            }
        }
        default {
            ErrorLog InvalidArgs "invalid parameter \"[info script] $Action\": check your ioFTPD.ini for errors"
        }
    }
    return [set ioerror $Result]
}

::nxTools::Dupe::Main [expr {[info exists args] ? $args : ""}]