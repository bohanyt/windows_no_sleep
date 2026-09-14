#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Wns {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

function Get-NormalizedText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return (($Text -replace "`r`n", "`n").Trim())
}

function Get-WnsFileTextOrPlaceholder {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        return (Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    }
    return '<missing>'
}

function Wait-WnsLogPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$TimeoutSeconds = 20
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $Path) {
            $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
            if ($null -ne $text -and $text -match $Pattern) {
                return $true
            }
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Wait-WnsPowerRequestGone {
    param(
        [Parameter(Mandatory = $true)][string]$ReasonFragment,
        [int]$TimeoutSeconds = 10
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $result = Invoke-WnsPowerCfgRequests
        if (-not $result.Available) {
            return $true
        }
        if ($result.Output -notmatch [Regex]::Escape($ReasonFragment)) {
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return $false
}

function Invoke-WnsPowerCfgRequests {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powercfg.exe'
    $psi.Arguments = '/requests'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            Available = $false
            Output = $stdout
            Error = $stderr
            ExitCode = $exitCode
        }
    }

    return [pscustomobject]@{
        Available = $true
        Output = $stdout
        Error = $stderr
        ExitCode = 0
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$appPath = Join-Path $repoRoot 'WindowsNoSleep.ps1'
$powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tempLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ('WindowsNoSleep.E2E.' + [Guid]::NewGuid().ToString('N'))
$runtimeDir = Join-Path $tempLocalAppData 'WindowsNoSleep'
$logPath = Join-Path $runtimeDir 'events.log'
$stdoutPath = Join-Path $tempLocalAppData 'app.stdout.txt'
$stderrPath = Join-Path $tempLocalAppData 'app.stderr.txt'
$secondStdoutPath = Join-Path $tempLocalAppData 'second.stdout.txt'
$secondStderrPath = Join-Path $tempLocalAppData 'second.stderr.txt'
$reasonFragment = 'Windows No Sleep is keeping this computer available for its running workloads.'
$originalLocalAppData = $env:LOCALAPPDATA
$appProcess = $null
$secondProcess = $null

try {
    New-Item -ItemType Directory -Path $tempLocalAppData -Force | Out-Null
    $env:LOCALAPPDATA = $tempLocalAppData

    Write-Host 'Capturing active power-plan state before app launch...'
    $activeSchemeBefore = Get-NormalizedText ((& powercfg.exe /getactivescheme 2>&1 | Out-String))
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /getactivescheme failed before test: $activeSchemeBefore"
    }
    $powerQueryBefore = Get-NormalizedText ((& powercfg.exe /query 2>&1 | Out-String))
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg /query failed before test.'
    }

    Write-Host 'Launching full tray app with default protection...'
    $arguments = @(
        '-NoProfile',
        '-STA',
        '-File', ('"{0}"' -f $appPath)
    )
    $appProcess = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru

    $protected = Wait-WnsLogPattern -Path $logPath -Pattern 'State -> PROTECTED:' -TimeoutSeconds 20
    if (-not $protected) {
        $logText = Get-WnsFileTextOrPlaceholder -Path $logPath
        $stdoutText = Get-WnsFileTextOrPlaceholder -Path $stdoutPath
        $stderrText = Get-WnsFileTextOrPlaceholder -Path $stderrPath
        $processState = if ($appProcess.HasExited) { "exited code=$($appProcess.ExitCode)" } else { 'still running' }
        throw "App did not reach PROTECTED on hosted Windows within timeout. Process=$processState`r`nLOG:`r`n$logText`r`nSTDOUT:`r`n$stdoutText`r`nSTDERR:`r`n$stderrText"
    }
    Assert-Wns (-not $appProcess.HasExited) 'Primary tray process exited after reporting PROTECTED.'

    Write-Host 'Checking live OS power-request visibility when powercfg permits it...'
    $requestDuring = Invoke-WnsPowerCfgRequests
    if ($requestDuring.Available) {
        $reasonVisible = ($requestDuring.Output -match [Regex]::Escape($reasonFragment))
        $powershellVisible = ($requestDuring.Output -match '(?im)^\s*\[PROCESS\].*powershell\.exe')
        Assert-Wns ($reasonVisible -or $powershellVisible) 'powercfg /requests did not expose the live WindowsNoSleep process request.'
    }
    else {
        Write-Warning ("powercfg /requests observer unavailable (exit {0}); API success is still covered by the PROTECTED state. {1}" -f $requestDuring.ExitCode, $requestDuring.Error.Trim())
    }

    Write-Host 'Checking single-instance behavior...'
    $secondProcess = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -RedirectStandardOutput $secondStdoutPath -RedirectStandardError $secondStderrPath -PassThru
    Assert-Wns ($secondProcess.WaitForExit(7000)) 'Second launch did not exit after signaling the existing instance.'
    if ($secondProcess.ExitCode -ne 0) {
        throw "Second launch returned exit code $($secondProcess.ExitCode). STDERR: $(Get-WnsFileTextOrPlaceholder -Path $secondStderrPath)"
    }
    Start-Sleep -Milliseconds 750
    Assert-Wns (-not $appProcess.HasExited) 'Primary instance died after second-instance signaling.'

    Write-Host 'Forcing the test process down to prove handle-scoped cleanup after an unclean exit...'
    Stop-Process -Id $appProcess.Id -Force -ErrorAction Stop
    [void]$appProcess.WaitForExit(7000)
    Start-Sleep -Milliseconds 500

    if ($requestDuring.Available) {
        Assert-Wns (Wait-WnsPowerRequestGone -ReasonFragment $reasonFragment -TimeoutSeconds 10) 'Power request reason remained after the owning process was killed.'
    }

    Write-Host 'Proving this implementation phase did not mutate the active power plan...'
    $activeSchemeAfter = Get-NormalizedText ((& powercfg.exe /getactivescheme 2>&1 | Out-String))
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg /getactivescheme failed after test.'
    }
    $powerQueryAfter = Get-NormalizedText ((& powercfg.exe /query 2>&1 | Out-String))
    if ($LASTEXITCODE -ne 0) {
        throw 'powercfg /query failed after test.'
    }

    Assert-Wns ($activeSchemeAfter -eq $activeSchemeBefore) 'Active power scheme changed during the hosted E2E test.'
    Assert-Wns ($powerQueryAfter -eq $powerQueryBefore) 'Power-plan values changed during the hosted E2E test.'

    $recoveryPath = Join-Path $runtimeDir 'recovery.json'
    Assert-Wns (-not (Test-Path -LiteralPath $recoveryPath)) 'Current non-mutating phase unexpectedly wrote a recovery transaction.'

    Write-Host 'HOSTED_WINDOWS_E2E passed: launch, protection, singleton, process-scoped cleanup, and no power-plan mutation.'
}
finally {
    if ($null -ne $secondProcess) {
        try {
            if (-not $secondProcess.HasExited) {
                Stop-Process -Id $secondProcess.Id -Force -ErrorAction SilentlyContinue
            }
            $secondProcess.Dispose()
        }
        catch {}
    }

    if ($null -ne $appProcess) {
        try {
            if (-not $appProcess.HasExited) {
                Stop-Process -Id $appProcess.Id -Force -ErrorAction SilentlyContinue
                [void]$appProcess.WaitForExit(5000)
            }
            $appProcess.Dispose()
        }
        catch {}
    }

    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Item -LiteralPath $tempLocalAppData -Recurse -Force -ErrorAction SilentlyContinue
}
