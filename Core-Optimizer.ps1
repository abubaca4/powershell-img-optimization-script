param(
    [Parameter(Mandatory=$true, Position=0)][string]$InputPath,
    [Parameter(Position=1)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$ToolPath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentSets,
    [Parameter(Mandatory=$true)][string[]]$Extensions,
    [string]$OutputExtension,
    [string]$ValidatorPath,
    [string]$ValidatorArgs,
    [int]$ThrottleLimit = 0,
    [switch]$AsciiTempMode
)

# --- 1. Localization ---
$SystemLanguage = (Get-Culture).TwoLetterISOLanguageName
$Messages = @{
    "Start" = @{ "ru" = "НАЧАЛО: {0}"; "en" = "START: {0}" }
    "SizeHeader" = @{ "ru" = "Размер в байтах:"; "en" = "Size in bytes:" }
    "SizeRowHeader" = @{ "ru" = "исх.    сейчас  % от исх.    имя и пути (секунд обработки)"; "en" = "orig.   current % of orig.   name and path (processing seconds)" }
    "NotCompressed" = @{ "ru" = "не сжался"; "en" = "not compressed" }
    "ErrorProcessing" = @{ "ru" = "ошибка"; "en" = "error" }
    "ValidationFailed" = @{ "ru" = "ошибка валидации"; "en" = "validation failed" }
    "Skipped" = @{ "ru" = "пропущен"; "en" = "skipped" }
    "NoFilesCompressed" = @{ "ru" = "Оптимизация не выполнена: ни один файл не был сжат."; "en" = "Optimization not performed: no files were compressed." }
    "End" = @{ "ru" = "КОНЕЦ: {0}"; "en" = "END: {0}" }
    "ReplacePrompt" = @{ "ru" = "Заменить оригинальные файлы? (Y/N)"; "en" = "Replace original files? (Y/N)" }
    "DoneReplaced" = @{ "ru" = "Готово. Оригиналы заменены."; "en" = "Done. Originals replaced." }
    "DoneSaved" = @{ "ru" = "Готово. Сохранено в {0}"; "en" = "Done. Saved to {0}" }
}

function Get-Msg {
    param($Key, $FmtArgs)
    $t = $Messages[$Key][$SystemLanguage]
    if (-not $t) { $t = $Messages[$Key]["en"] }
    if ($FmtArgs) { return $t -f $FmtArgs }
    return $t
}

# --- 2. Input validation ---
if (-not $InputPath) { Write-Error "Input Path Missing"; exit 1 }
if (-not (Test-Path -LiteralPath $InputPath)) { Write-Error "Input Path not found: $InputPath"; exit 1 }

if (-not $OutputPath) {
    $OutputPath = $InputPath
    $ConfirmReplace = $true
} else {
    if (-not (Test-Path -LiteralPath $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
    $ConfirmReplace = $false
}

if (-not (Test-Path -LiteralPath $ToolPath)) { Write-Error "Tool not found: $ToolPath"; exit 1 }

# --- 3. Collecting files ---
Write-Host (Get-Msg "Start" (Get-Date))
Write-Host (Get-Msg "SizeHeader")
Write-Host (Get-Msg "SizeRowHeader")

$Files = Get-ChildItem -LiteralPath $InputPath -Include $Extensions -Recurse -File

# --- 4. Parallel processing ---
if ($ThrottleLimit -le 0) {
    $ProcessorCores = (Get-CimInstance Win32_Processor).NumberOfCores
    $ThrottleLimit = if ($ProcessorCores) { [math]::Max(1, $ProcessorCores) } else { 2 }
}

# Create temporary directory for AsciiTempMode
$AsciiTempDir = $null
if ($AsciiTempMode) {
    $AsciiTempDir = Join-Path $env:TEMP "imgopt_ascii_temp"
    if (-not (Test-Path -LiteralPath $AsciiTempDir)) {
        New-Item -ItemType Directory -Path $AsciiTempDir -Force | Out-Null
    }
}

$Results = $Files | ForEach-Object -Parallel {
    $File = $_
    $ToolPath = $using:ToolPath
    $ArgSets = $using:ArgumentSets
    $OutDirRoot = $using:OutputPath
    $InDirRoot = $using:InputPath
    $ReplaceMode = $using:ConfirmReplace
    $OutExt = $using:OutputExtension
    $ValPath = $using:ValidatorPath
    $ValArgs = $using:ValidatorArgs
    $AsciiTempMode = $using:AsciiTempMode
    $AsciiTempDir = $using:AsciiTempDir

    # Replicate localization function inside the thread
    $Messages = $using:Messages
    $Lang = $using:SystemLanguage
    function Get-MsgPar {
        param($Key, $FmtArgs)
        $t = $Messages[$Key][$Lang]
        if (-not $t) { $t = $Messages[$Key]["en"] }
        if ($FmtArgs) { return $t -f $FmtArgs }
        return $t
    }

    function Run-ProcessSafe {
        param($Exe, $Arguments)

        $pInfo = New-Object System.Diagnostics.ProcessStartInfo
        $pInfo.FileName = $Exe
        $pInfo.Arguments = $Arguments
        $pInfo.UseShellExecute = $false
        $pInfo.CreateNoWindow = $true
        $pInfo.RedirectStandardOutput = $true
        $pInfo.RedirectStandardError = $true

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pInfo

        try {
            $p.Start() | Out-Null
            $stdOutTask = $p.StandardOutput.ReadToEndAsync()
            $stdErrTask = $p.StandardError.ReadToEndAsync()
            $p.WaitForExit()
            $null = $stdOutTask.Result
            $null = $stdErrTask.Result
            return $p.ExitCode
        }
        finally {
            if ($p) { $p.Dispose() }
        }
    }

    $StartTime = Get-Date
    $OriginalSize = $File.Length

    # Paths
    $NewName = $File.Name
    if ($OutExt) { $NewName = $File.BaseName + $OutExt }

    if ($ReplaceMode) {
        $FinalOutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti" + [System.IO.Path]::GetExtension($NewName))
    } else {
        $RelPath = $File.DirectoryName.Substring($InDirRoot.Length).TrimStart('\', '/')
        $TargetDir = Join-Path $OutDirRoot $RelPath
        if (-not (Test-Path -LiteralPath $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
        $FinalOutputFile = Join-Path $TargetDir $NewName
    }

    $BestTempFile = $null
    $BestSize = $OriginalSize + 1
    $BestParams = ""

    # Handle AsciiTempMode
    $AsciiTempInputFile = $null
    $SourceFile = $File.FullName

    try {
        if ($AsciiTempMode) {
            $tempFileName = [System.IO.Path]::GetRandomFileName()
            $ext = $File.Extension
            $AsciiTempInputFile = Join-Path $AsciiTempDir ($tempFileName + $ext)

            Copy-Item -LiteralPath $File.FullName -Destination $AsciiTempInputFile -Force
            $SourceFile = $AsciiTempInputFile
        }

        foreach ($ArgsTemplate in $ArgSets) {
            $TempFile = [System.IO.Path]::GetTempFileName()
            if ($OutExt) { $TempFile += $OutExt }

            $CurrentArgs = $ArgsTemplate.Replace("{src}", "`"$SourceFile`"").Replace("{dest}", "`"$TempFile`"")
            $ExitCode = Run-ProcessSafe -Exe $ToolPath -Arguments $CurrentArgs

            if ($ExitCode -eq 0 -and (Test-Path -LiteralPath $TempFile) -and (Get-Item -LiteralPath $TempFile).Length -gt 0) {
                $CurSize = (Get-Item -LiteralPath $TempFile).Length

                $ValidationPassed = $true
                if ($ValPath) {
                    $vArgs = $ValArgs.Replace("{src}", "`"$SourceFile`"").Replace("{dest}", "`"$TempFile`"")
                    $vExit = Run-ProcessSafe -Exe $ValPath -Arguments $vArgs
                    if ($vExit -ne 0) { $ValidationPassed = $false }
                }

                if ($ValidationPassed -and $CurSize -lt $BestSize) {
                    $BestSize = $CurSize
                    $BestParams = $ArgsTemplate
                    if ($BestTempFile -and (Test-Path -LiteralPath $BestTempFile)) { Remove-Item -LiteralPath $BestTempFile -ErrorAction SilentlyContinue }
                    $BestTempFile = $TempFile
                } else {
                    Remove-Item -LiteralPath $TempFile -ErrorAction SilentlyContinue
                }
            } else {
                Remove-Item -LiteralPath $TempFile -ErrorAction SilentlyContinue
            }
        }

        $TimeSpent = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)

        if ($BestTempFile -and $BestSize -lt $OriginalSize) {
            Copy-Item -LiteralPath $BestTempFile -Destination $FinalOutputFile -Force
            Remove-Item -LiteralPath $BestTempFile -ErrorAction SilentlyContinue

            $Percent = [math]::Round(($BestSize / $OriginalSize) * 100, 2)
            $ParamInfo = if ($ArgSets.Count -gt 1) { " [Params: $BestParams]" } else { "" }
            Write-Host "$OriginalSize`t$BestSize`t$Percent`t`t$($File.Name) ($TimeSpent)$ParamInfo"
            return @{ Original = $File.FullName; Optimized = $FinalOutputFile; Success = $true }
        } else {
            if ($BestTempFile) { Remove-Item -LiteralPath $BestTempFile -ErrorAction SilentlyContinue }
            Write-Host "$OriginalSize`t----`t$(Get-MsgPar 'NotCompressed')`t`t$($File.Name)"
            return $null
        }
    }
    catch {
        Write-Host "$OriginalSize`t----`t$(Get-MsgPar 'ErrorProcessing')`t`t$($File.Name) ($($_.Exception.Message))"
        return $null
    }
    finally {
        if ($AsciiTempMode -and $AsciiTempInputFile -and (Test-Path -LiteralPath $AsciiTempInputFile)) {
            Remove-Item -LiteralPath $AsciiTempInputFile -ErrorAction SilentlyContinue
        }
    }

} -ThrottleLimit $ThrottleLimit

Write-Host (Get-Msg "End" (Get-Date))

# --- 5. Replacement ---
if ($ConfirmReplace -and $Results) {
    $SuccessfulResults = $Results | Where-Object { $_ -and $_.Success }

    if ($SuccessfulResults.Count -gt 0) {
        $R = Read-Host (Get-Msg "ReplacePrompt")
        if ($R -eq 'Y' -or $R -eq 'y') {
            foreach ($Res in $SuccessfulResults) {
                if ($Res.Success) {
                    $OriginalFile = $Res.Original
                    $OptimizedFile = $Res.Optimized

                    $FinalExt = [System.IO.Path]::GetExtension($OptimizedFile).Replace(".opti", "")
                    $FinalPath = [System.IO.Path]::ChangeExtension($OriginalFile, $FinalExt)

                    if ($OriginalFile -eq $FinalPath) {
                        Move-Item -LiteralPath $OptimizedFile -Destination $OriginalFile -Force
                    } else {
                        if (Test-Path -LiteralPath $OriginalFile) { Remove-Item -LiteralPath $OriginalFile -Force }
                        Move-Item -LiteralPath $OptimizedFile -Destination $FinalPath -Force
                    }
                }
            }
            Write-Host (Get-Msg "DoneReplaced")
        } else {
            Write-Host (Get-Msg "DoneSaved" $OutputPath)
        }
    } else {
        Write-Host (Get-Msg "NoFilesCompressed")
    }
} else {
    Write-Host (Get-Msg "DoneSaved" $OutputPath)
}

if ($AsciiTempMode -and $AsciiTempDir -and (Test-Path -LiteralPath $AsciiTempDir)) {
    Remove-Item -LiteralPath $AsciiTempDir -Recurse -Force -ErrorAction SilentlyContinue
}