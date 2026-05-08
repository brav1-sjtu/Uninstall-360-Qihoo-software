# Remove-360-Software.ps1
# Removes Qihoo/360-family software by using official uninstall registry entries,
# then cleans matching services, startup items, scheduled tasks, shortcuts, and
# leftover folders. Run from the companion .cmd file for easiest use.

[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$Remove360DownloadedApps,
    [switch]$SkipRestorePoint
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$script:Publisher360Regex = '(?i)(qihoo|qihu|360\.cn|360\s*(security|safe|total\s*security|company)|beijing\s+qihoo)'
$script:Product360Regex = '(?i)(360\s*(safe|security|total\s*security|antivirus|browser|secure\s*browser|chrome|zip|compress|desktop|wallpaper|software\s*manager|driver|doc|pdf|speed|guard|enterprise|cleaner)|360safe|360se|360chrome|360browser|360zip|360sd|360desktop|360softmgr|360wallpaper|360totalsecurity|safe360|qhsafe|qihoo|qihu|(^|[^A-Za-z0-9])360([^A-Za-z0-9]|$))'
$script:Path360Regex = '(?i)(\\|/)(360safe|360se|360chrome|360browser|360zip|360sd|360softmgr|360downloads|qihoo|qihu|360desktop|360wallpaper|360totalsecurity|safe360)(\\|/|$)'
$script:DownloadSource360Regex = '(?i)(\\|/)(360downloads|360softmgr|360safe.*softwaremgr|360.*downloads)(\\|/|$)'
$script:FalsePositiveRegex = '(?i)(norton\s*360|symantec|broadcom|autodesk\s*fusion\s*360|fusion\s*360|xbox\s*360|microsoft\s*xbox|insta360|gopro|ricoh\s*theta|garmin|matterport|viewsonic|logitech)'

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[*] $Message"
}

function Write-Good {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-SelfElevated {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        Write-WarnLine 'Cannot find this script path for administrator relaunch.'
        return $false
    }

    $argsLine = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Run"
    if ($Remove360DownloadedApps) {
        $argsLine += ' -Remove360DownloadedApps'
    }
    if ($SkipRestorePoint) {
        $argsLine += ' -SkipRestorePoint'
    }

    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argsLine -Verb RunAs | Out-Null
        return $true
    } catch {
        Write-WarnLine "Administrator relaunch failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-TextMatches360 {
    param([string[]]$Text)

    $joined = ($Text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '
    if ([string]::IsNullOrWhiteSpace($joined)) {
        return $false
    }
    if ($joined -match $script:FalsePositiveRegex) {
        return $false
    }
    return (($joined -match $script:Publisher360Regex) -or ($joined -match $script:Product360Regex) -or ($joined -match $script:Path360Regex))
}

function Get-PropertyString {
    param(
        [object]$Object,
        [string]$Name
    )

    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) {
        return ''
    }
    return [string]$prop.Value
}

function Get-UninstallEntries {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
                $displayName = Get-PropertyString -Object $p -Name 'DisplayName'
                if ([string]::IsNullOrWhiteSpace($displayName)) {
                    return
                }

                [pscustomobject]@{
                    DisplayName          = $displayName
                    DisplayVersion       = Get-PropertyString -Object $p -Name 'DisplayVersion'
                    Publisher            = Get-PropertyString -Object $p -Name 'Publisher'
                    InstallLocation      = Get-PropertyString -Object $p -Name 'InstallLocation'
                    InstallSource        = Get-PropertyString -Object $p -Name 'InstallSource'
                    UninstallString      = Get-PropertyString -Object $p -Name 'UninstallString'
                    QuietUninstallString = Get-PropertyString -Object $p -Name 'QuietUninstallString'
                    RegistryPath         = [string]$_.PSPath
                    KeyName              = [string]$_.PSChildName
                }
            } catch {
                Write-WarnLine "Failed to read uninstall entry $($_.PSPath): $($_.Exception.Message)"
            }
        }
    }
}

function Get-Entry360Reason {
    param([pscustomobject]$Entry)

    $text = @(
        $Entry.DisplayName,
        $Entry.Publisher,
        $Entry.InstallLocation,
        $Entry.InstallSource,
        $Entry.UninstallString,
        $Entry.QuietUninstallString
    )
    $joined = ($text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' '

    if ($joined -match $script:FalsePositiveRegex) {
        return $null
    }
    if ($Entry.Publisher -match $script:Publisher360Regex) {
        return '360/Qihoo publisher'
    }
    if ($Entry.DisplayName -match $script:Product360Regex) {
        return '360-family product name'
    }
    if ($joined -match $script:Path360Regex) {
        return '360-family install path'
    }

    return $null
}

function Test-EntryFrom360DownloadSource {
    param([pscustomobject]$Entry)

    $text = @($Entry.InstallSource, $Entry.InstallLocation, $Entry.UninstallString, $Entry.QuietUninstallString) -join ' '
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $false
    }
    if ($text -match $script:FalsePositiveRegex) {
        return $false
    }
    return ($text -match $script:DownloadSource360Regex)
}

function Add-Reason {
    param(
        [pscustomobject]$Entry,
        [string]$Reason
    )

    $copy = $Entry | Select-Object *
    $copy | Add-Member -NotePropertyName Remove360Reason -NotePropertyValue $Reason -Force
    return $copy
}

function Split-CommandLine {
    param([string]$CommandLine)

    $s = $CommandLine.Trim()
    if ([string]::IsNullOrWhiteSpace($s)) {
        return $null
    }

    if ($s.StartsWith('"')) {
        $end = $s.IndexOf('"', 1)
        while ($end -gt 0 -and $s[$end - 1] -eq '\') {
            $end = $s.IndexOf('"', $end + 1)
        }
        if ($end -gt 0) {
            return [pscustomobject]@{
                FilePath  = $s.Substring(1, $end - 1)
                Arguments = $s.Substring($end + 1).Trim()
            }
        }
    }

    if ($s -match '^(?i)(msiexec(?:\.exe)?)\s+(.*)$') {
        return [pscustomobject]@{ FilePath = $Matches[1]; Arguments = $Matches[2] }
    }

    if ($s -match '^(?i)(rundll32(?:\.exe)?)\s+(.*)$') {
        return [pscustomobject]@{ FilePath = $Matches[1]; Arguments = $Matches[2] }
    }

    if ($s -match '^(.*?\.exe)(\s+.*)?$') {
        return [pscustomobject]@{
            FilePath  = $Matches[1].Trim()
            Arguments = ([string]$Matches[2]).Trim()
        }
    }

    return [pscustomobject]@{
        FilePath  = 'cmd.exe'
        Arguments = "/c $s"
    }
}

function Invoke-UninstallEntry {
    param([pscustomobject]$Entry)

    $cmd = $Entry.QuietUninstallString
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        $cmd = $Entry.UninstallString
    }

    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Write-WarnLine "No uninstall command found for: $($Entry.DisplayName)"
        return
    }

    Write-Info "Uninstalling: $($Entry.DisplayName) [$($Entry.Remove360Reason)]"

    try {
        if ($cmd -match '(?i)msiexec(?:\.exe)?' -and $cmd -match '\{[0-9A-Fa-f-]{36}\}') {
            $guid = $Matches[0]
            $args = "/x $guid /qn /norestart"
            Write-Info "Running: msiexec.exe $args"
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -Wait -PassThru
            Write-Info "Exit code: $($p.ExitCode)"
            return
        }

        $parts = Split-CommandLine -CommandLine $cmd
        if ($null -eq $parts) {
            Write-WarnLine "Cannot parse uninstall command for: $($Entry.DisplayName)"
            return
        }

        if ($parts.FilePath -match '(?i)\.msi$') {
            $msiArgs = "/x `"$($parts.FilePath)`" /qn /norestart"
            Write-Info "Running: msiexec.exe $msiArgs"
            $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru
            Write-Info "Exit code: $($p.ExitCode)"
            return
        }

        Write-Info "Running: $($parts.FilePath) $($parts.Arguments)"
        if ([string]::IsNullOrWhiteSpace($parts.Arguments)) {
            $p = Start-Process -FilePath $parts.FilePath -Wait -PassThru
        } else {
            $p = Start-Process -FilePath $parts.FilePath -ArgumentList $parts.Arguments -Wait -PassThru
        }
        Write-Info "Exit code: $($p.ExitCode)"
    } catch {
        Write-WarnLine "Uninstall failed for $($Entry.DisplayName): $($_.Exception.Message)"
    }
}

function Stop-360Processes {
    Write-Step 'Closing 360-family processes'

    $candidates = @()
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        $path = ''
        try {
            $path = [string]$p.Path
        } catch {
            $path = ''
        }

        if (($p.ProcessName -match '(?i)^(360|qihoo|qihu|360safe|360sd|360tray|360rp|360rps|360se|360chrome|360browser|360zip|360desktop|360bdoctor|360doctor|360net|360speed|qhactive|zhudongfangyu|liveupd|dumpuper)') -or ($path -match $script:Path360Regex)) {
            $candidates += $p
        }
    }

    $candidates = $candidates | Sort-Object Id -Unique
    if (($candidates | Measure-Object).Count -eq 0) {
        Write-Good 'No running 360-family processes found.'
        return
    }

    foreach ($p in $candidates) {
        try {
            Write-Info "Stopping process: $($p.ProcessName) ($($p.Id))"
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
        } catch {
            Write-WarnLine "Could not stop process $($p.ProcessName): $($_.Exception.Message)"
        }
    }
}

function Get-360Services {
    $services = @()
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
        } else {
            $services = @(Get-WmiObject Win32_Service -ErrorAction SilentlyContinue)
        }
    } catch {
        Write-WarnLine "Could not enumerate services: $($_.Exception.Message)"
        return @()
    }

    return @($services | Where-Object {
        $text = @($_.Name, $_.DisplayName, $_.PathName, $_.Description) -join ' '
        Test-TextMatches360 -Text @($text)
    })
}

function Stop-360Services {
    Write-Step 'Stopping 360-family services'
    $services = @(Get-360Services)
    if (($services | Measure-Object).Count -eq 0) {
        Write-Good 'No 360-family services found.'
        return
    }

    foreach ($svc in $services) {
        try {
            Write-Info "Stopping service: $($svc.Name) - $($svc.DisplayName)"
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        } catch {
            Write-WarnLine "Could not stop service $($svc.Name): $($_.Exception.Message)"
        }
    }
}

function Remove-Leftover360Services {
    Write-Step 'Removing leftover 360-family services'
    $services = @(Get-360Services)
    if (($services | Measure-Object).Count -eq 0) {
        Write-Good 'No leftover 360-family services found.'
        return
    }

    foreach ($svc in $services) {
        try {
            Write-Info "Deleting service: $($svc.Name)"
            & sc.exe delete $svc.Name | Out-Host
        } catch {
            Write-WarnLine "Could not delete service $($svc.Name): $($_.Exception.Message)"
        }
    }
}

function Remove-360ScheduledTasks {
    Write-Step 'Removing 360-family scheduled tasks'

    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        Write-WarnLine 'Get-ScheduledTask is unavailable on this Windows version. Skipping scheduled task cleanup.'
        return
    }

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $text = @($_.TaskName, $_.TaskPath, $_.Description) -join ' '
            Test-TextMatches360 -Text @($text)
        })
        if (($tasks | Measure-Object).Count -eq 0) {
            Write-Good 'No matching scheduled tasks found.'
            return
        }

        foreach ($task in $tasks) {
            try {
                Write-Info "Removing task: $($task.TaskPath)$($task.TaskName)"
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            } catch {
                Write-WarnLine "Could not remove task $($task.TaskName): $($_.Exception.Message)"
            }
        }
    } catch {
        Write-WarnLine "Scheduled task cleanup failed: $($_.Exception.Message)"
    }
}

function Remove-360StartupEntries {
    Write-Step 'Removing 360-family startup registry entries'

    $runKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )

    foreach ($key in $runKeys) {
        if (-not (Test-Path -LiteralPath $key)) {
            continue
        }

        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($prop in $item.PSObject.Properties) {
                if ($prop.Name -match '^PS') {
                    continue
                }

                $text = @($prop.Name, [string]$prop.Value) -join ' '
                if (Test-TextMatches360 -Text @($text)) {
                    Write-Info "Removing startup value: $key -> $($prop.Name)"
                    Remove-ItemProperty -LiteralPath $key -Name $prop.Name -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-WarnLine "Could not inspect startup key ${key}: $($_.Exception.Message)"
        }
    }
}

function Get-ShortcutRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    $known = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('Programs'),
        [Environment]::GetFolderPath('CommonPrograms'),
        [Environment]::GetFolderPath('Startup'),
        [Environment]::GetFolderPath('CommonStartup')
    )

    foreach ($root in $known) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and (Test-Path -LiteralPath $root)) {
            $roots.Add($root) | Out-Null
        }
    }

    return @($roots | Sort-Object -Unique)
}

function Remove-360Shortcuts {
    Write-Step 'Removing 360-family shortcuts'

    foreach ($root in Get-ShortcutRoots) {
        try {
            Get-ChildItem -LiteralPath $root -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-TextMatches360 -Text @($_.Name, $_.FullName)) {
                    Write-Info "Removing shortcut: $($_.FullName)"
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-WarnLine "Could not clean shortcuts in ${root}: $($_.Exception.Message)"
        }
    }
}

function Test-Safe360Path {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $false
    }

    $trimmed = $full.TrimEnd('\', '/')
    if ($trimmed.Length -lt 8) {
        return $false
    }
    if ($trimmed -match '^[A-Za-z]:$') {
        return $false
    }
    if ($trimmed -match $script:FalsePositiveRegex) {
        return $false
    }

    $leaf = Split-Path -Path $trimmed -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        return $false
    }

    if ($leaf -match '(?i)^(360|360safe|360se|360chrome|360browser|360zip|360sd|360softmgr|360downloads|qihoo|qihu|360desktop|360wallpaper|360totalsecurity|safe360)') {
        return $true
    }
    if ($trimmed -match $script:Path360Regex) {
        return $true
    }

    return $false
}

function Remove-Safe360Item {
    param([string]$Path)

    try {
        $resolved = @(Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
        foreach ($r in $resolved) {
            $full = $r.ProviderPath
            if (-not (Test-Safe360Path -Path $full)) {
                Write-WarnLine "Skipped unsafe cleanup path: $full"
                continue
            }

            Write-Info "Removing leftover: $full"
            Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Continue
        }
    } catch {
        Write-WarnLine "Could not remove ${Path}: $($_.Exception.Message)"
    }
}

function Get-360LeftoverPaths {
    $baseDirs = New-Object System.Collections.Generic.List[string]
    $names = @(
        '360',
        '360Safe',
        '360SE',
        '360SE6',
        '360Chrome',
        '360Browser',
        '360zip',
        '360sd',
        '360SoftMgr',
        '360Downloads',
        '360Desktop',
        '360Wallpaper',
        '360TotalSecurity',
        'Qihoo',
        'Qihu',
        'Safe360'
    )

    $knownBases = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        $env:APPDATA,
        (Join-Path $env:SystemDrive 'ProgramData')
    )

    foreach ($base in $knownBases) {
        if (-not [string]::IsNullOrWhiteSpace($base) -and (Test-Path -LiteralPath $base)) {
            $baseDirs.Add($base) | Out-Null
        }
    }

    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $profile = $_.FullName
            $profileBases = @(
                (Join-Path $profile 'AppData\Local'),
                (Join-Path $profile 'AppData\Roaming'),
                (Join-Path $profile 'Downloads'),
                (Join-Path $profile 'Documents'),
                (Join-Path $profile 'Desktop')
            )
            foreach ($base in $profileBases) {
                if (Test-Path -LiteralPath $base) {
                    $baseDirs.Add($base) | Out-Null
                }
            }
        }
    }

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -eq [System.IO.DriveType]::Fixed -and $drive.IsReady) {
            foreach ($name in $names) {
                $candidate = Join-Path $drive.RootDirectory.FullName $name
                if (Test-Path -LiteralPath $candidate) {
                    $candidate
                }
            }
        }
    }

    foreach ($base in ($baseDirs | Sort-Object -Unique)) {
        foreach ($name in $names) {
            $candidate = Join-Path $base $name
            if (Test-Path -LiteralPath $candidate) {
                $candidate
            }
        }

        try {
            Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | Where-Object {
                Test-Safe360Path -Path $_.FullName
            } | ForEach-Object {
                $_.FullName
            }
        } catch {
            Write-WarnLine "Could not enumerate leftover base ${base}: $($_.Exception.Message)"
        }
    }
}

function Remove-360Leftovers {
    Write-Step 'Removing leftover 360-family files and folders'

    $paths = @(Get-360LeftoverPaths | Sort-Object -Unique)
    if (($paths | Measure-Object).Count -eq 0) {
        Write-Good 'No leftover folders found.'
        return
    }

    foreach ($path in $paths) {
        Remove-Safe360Item -Path $path
    }
}

function Write-TargetList {
    param([pscustomobject[]]$Targets)

    if (($Targets | Measure-Object).Count -eq 0) {
        Write-Good 'No installed 360-family products were found.'
        return
    }

    Write-Info 'Targets:'
    foreach ($target in $Targets) {
        $version = ''
        if (-not [string]::IsNullOrWhiteSpace($target.DisplayVersion)) {
            $version = " $($target.DisplayVersion)"
        }
        Write-Host "  - $($target.DisplayName)$version [$($target.Remove360Reason)]"
    }
}

if (-not (Test-IsAdmin)) {
    Write-WarnLine 'Administrator permission is required.'
    if (Start-SelfElevated) {
        exit 0
    }
    exit 1
}

if (-not $Run) {
    Write-Host ''
    Write-WarnLine 'This script will uninstall Qihoo/360-family software and remove matching leftovers.'
    Write-WarnLine 'Type RUN and press Enter to continue.'
    $answer = Read-Host 'Confirm'
    if ($answer -ne 'RUN') {
        Write-Info 'Cancelled.'
        exit 0
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) {
    $desktop = $env:TEMP
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $desktop "Remove360_Log_$stamp.txt"
$transcriptStarted = $false
try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
    $transcriptStarted = $true
} catch {
    Write-WarnLine "Could not start log transcript: $($_.Exception.Message)"
}

Write-Step 'Remove 360 software'
Write-Info "Log file: $logPath"

if (-not $SkipRestorePoint) {
    Write-Step 'Creating a system restore point'
    try {
        Checkpoint-Computer -Description 'Before Remove360 cleanup' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Good 'Restore point created.'
    } catch {
        Write-WarnLine "Restore point was not created. This is common if System Protection is disabled: $($_.Exception.Message)"
    }
}

Write-Step 'Scanning installed programs'
$entries = @(Get-UninstallEntries)
$targets = New-Object System.Collections.Generic.List[object]
$downloadedTargets = New-Object System.Collections.Generic.List[object]

foreach ($entry in $entries) {
    $reason = Get-Entry360Reason -Entry $entry
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
        $targets.Add((Add-Reason -Entry $entry -Reason $reason)) | Out-Null
        continue
    }

    if (Test-EntryFrom360DownloadSource -Entry $entry) {
        $downloadedTargets.Add((Add-Reason -Entry $entry -Reason 'install source points to a 360 download/cache path')) | Out-Null
    }
}

$targets = @($targets | Sort-Object DisplayName, RegistryPath -Unique)
$downloadedTargets = @($downloadedTargets | Sort-Object DisplayName, RegistryPath -Unique)

Write-TargetList -Targets $targets

if (($downloadedTargets | Measure-Object).Count -gt 0) {
    Write-Step 'Programs that appear to come from 360 download/cache paths'
    foreach ($target in $downloadedTargets) {
        Write-Host "  - $($target.DisplayName) [$($target.Remove360Reason)]"
    }
    if ($Remove360DownloadedApps) {
        Write-WarnLine 'The Remove360DownloadedApps option is enabled. These will also be uninstalled.'
        $targets = @($targets + $downloadedTargets | Sort-Object DisplayName, RegistryPath -Unique)
    } else {
        Write-WarnLine 'These third-party-looking programs are only listed in the log, not uninstalled automatically.'
    }
}

Stop-360Processes
Stop-360Services

if (($targets | Measure-Object).Count -gt 0) {
    Write-Step 'Running uninstallers'
    foreach ($target in $targets) {
        Invoke-UninstallEntry -Entry $target
    }
}

Remove-360ScheduledTasks
Remove-360StartupEntries
Remove-Leftover360Services
Remove-360Shortcuts
Remove-360Leftovers

Write-Step 'Done'
Write-Good 'Finished. Restart Windows after this script completes.'
Write-Info "Log file: $logPath"

if ($transcriptStarted) {
    try {
        Stop-Transcript | Out-Null
    } catch {
    }
}
