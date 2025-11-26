param(
    [Parameter(Position=0)]
    [string]$InputPath,
    
    [Parameter(Position=1)]
    [string]$OutputPath
)

# Detect system language
$SystemLanguage = (Get-Culture).TwoLetterISOLanguageName

# Messages in both languages
$Messages = @{
    "PSVersionWarning" = @{
        "ru" = "PowerShell версии {0} - параллельная обработка недоступна, используется последовательная обработка"
        "en" = "PowerShell version {0} - parallel processing unavailable, using sequential processing"
    }
    "InputPathNotSpecified" = @{
        "ru" = "Не указан входной путь"
        "en" = "Input path not specified"
    }
    "InputPathNotFound" = @{
        "ru" = "Входной путь не существует: {0}"
        "en" = "Input path does not exist: {0}"
    }
    "MozJpegNotFound" = @{
        "ru" = "jpegtran не найден по пути: {0}"
        "en" = "jpegtran not found at path: {0}"
    }
    "Start" = @{
        "ru" = "НАЧАЛО: {0}"
        "en" = "START: {0}"
    }
    "SizeHeader" = @{
        "ru" = "Размер в байтах:"
        "en" = "Size in bytes:"
    }
    "SizeRowHeader" = @{
        "ru" = "исх.    сейчас  % от исх.    имя и путь (секунд обработки)"
        "en" = "orig.   current % of orig.   name and path (processing seconds)"
    }
    "NotCompressed" = @{
        "ru" = "не сжался"
        "en" = "not compressed"
    }
    "ErrorProcessing" = @{
        "ru" = "ошибка"
        "en" = "error"
    }
    "ErrorWithDetails" = @{
        "ru" = "ОШИБКА: {0} - {1}"
        "en" = "ERROR: {0} - {1}"
    }
    "ReplacePrompt" = @{
        "ru" = "Заменить оригинальные jpg файлы сжатыми версиями? Нажмите Y для ДА или N для НЕТ и нажмите ENTER"
        "en" = "Replace original jpg files with compressed versions? Press Y for YES or N for NO and press ENTER"
    }
    "DoneReplaced" = @{
        "ru" = "Готово. Оригинальные файлы были заменены."
        "en" = "Done. Original files have been replaced."
    }
    "DoneNotReplaced" = @{
        "ru" = "Готово. Оригинальные и сжатые файлы сохранены. Сжатые файлы имеют суффикс .opti.jpg"
        "en" = "Done. Original and compressed files are saved. Compressed files have suffix .opti.jpg"
    }
    "DoneOutput" = @{
        "ru" = "Готово. Сжатые файлы сохранены в: {0}"
        "en" = "Done. Compressed files are saved in: {0}"
    }
}

# Helper function to get localized message
function Get-LocalizedMessage {
    param([string]$Key, [array]$FormatArgs = @())
    
    $messageTemplate = $Messages[$Key][$SystemLanguage]
    if (-not $messageTemplate) {
        $messageTemplate = $Messages[$Key]["en"] # Fallback to English
    }
    
    if ($FormatArgs.Count -gt 0) {
        return $messageTemplate -f $FormatArgs
    }
    return $messageTemplate
}

# Settings
$MozJpegPath = "mozjpeg\jpegtran-static.exe"
$ProcessorCores = (Get-CimInstance Win32_Processor).NumberOfCores

# Check PowerShell version
$PSVersion = $PSVersionTable.PSVersion.Major
$UseParallel = $PSVersion -ge 7

if ($UseParallel) {
    $ThrottleLimit = $ProcessorCores
} else {
    Write-Host (Get-LocalizedMessage "PSVersionWarning" @($PSVersion))
}

# Check arguments
if (-not $InputPath) {
    Write-Error (Get-LocalizedMessage "InputPathNotSpecified")
    exit 1
}

if (-not (Test-Path $InputPath)) {
    Write-Error (Get-LocalizedMessage "InputPathNotFound" @($InputPath))
    exit 1
}

if (-not $OutputPath) {
    $OutputPath = $InputPath
    $ConfirmReplace = $true
} else {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    $ConfirmReplace = $false
}

# Check if jpegtran exists
if (-not (Test-Path $MozJpegPath)) {
    Write-Error (Get-LocalizedMessage "MozJpegNotFound" @($MozJpegPath))
    exit 1
}

Write-Host (Get-LocalizedMessage "Start" @((Get-Date)))
Write-Host (Get-LocalizedMessage "SizeHeader")
Write-Host (Get-LocalizedMessage "SizeRowHeader")

# Get all files for processing (only JPG and JPEG)
$Files = Get-ChildItem -Path $InputPath -Include *.jpg, *.jpeg -Recurse -File

# Function to process a single file
function Optimize-File {
    param($File, $MozJpegPath, $OutputPath, $InputPath, $ConfirmReplace)
    
    $StartTime = Get-Date
    $OriginalFile = $File.FullName

    try {
        # Determine output filename
        if ($ConfirmReplace) {
            # If output to the same folder
            $OutputFile = $File.FullName + ".opti.jpg"
        } else {
            # If output to a different folder
            if ($InputPath -ne $OutputPath) {
                $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
            }
            $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
        }
        
        # Create folder for output file if needed
        $OutputDir = Split-Path $OutputFile -Parent
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        $OriginalSize = $File.Length
        
        # Build and execute jpegtran command using direct call
        $arguments = '-outfile', "`"$OutputFile`"", '-copy', 'none', '-optimize', "`"$OriginalFile`""
        & $MozJpegPath $arguments 2>$null
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputFile)) { 
            $NewSize = (Get-Item $OutputFile).Length
            
            $EndTime = Get-Date
            $TimeSpent = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
            
            if ($NewSize -lt $OriginalSize) {
                $Percent = [math]::Round(($NewSize / $OriginalSize) * 100, 2)
                Write-Host "$OriginalSize`t$NewSize`t$Percent`t`t$($File.Name) ($TimeSpent)"
                return @{
                    OriginalFile = $OriginalFile
                    OutputFile = $OutputFile
                    OriginalSize = $OriginalSize
                    CompressedSize = $NewSize
                }
            } else {
                # If file wasn't compressed, delete output file
                Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
                Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessage "NotCompressed")`t`t$($File.Name)"
                return $null
            }
        } else {
            Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessage "ErrorProcessing")`t`t$($File.Name)"
            return $null
        }
    }
    catch {
        Write-Host (Get-LocalizedMessage "ErrorWithDetails" @($File.Name, $_.Exception.Message))
        return $null
    }
}

# Process files based on PowerShell version
if ($UseParallel) {
    # PowerShell 7+ - use parallel processing (System.Diagnostics.Process remains)
    $Results = $Files | ForEach-Object -Parallel {
        # Define localized message function inside parallel block to avoid scope issues
        function Get-LocalizedMessageParallel {
            param([string]$Key, [array]$FormatArgs = @())
            
            $Messages = $using:Messages
            $SystemLanguage = $using:SystemLanguage
            
            $messageTemplate = $Messages[$Key][$SystemLanguage]
            if (-not $messageTemplate) {
                $messageTemplate = $Messages[$Key]["en"] # Fallback to English
            }
            
            if ($FormatArgs.Count -gt 0) {
                return $messageTemplate -f $FormatArgs
            }
            return $messageTemplate
        }
        
        function Optimize-File {
            param($File, $MozJpegPath, $OutputPath, $InputPath, $ConfirmReplace)
            
            $StartTime = Get-Date
            $OriginalFile = $File.FullName

            try {
                # Determine output filename
                if ($ConfirmReplace) {
                    # If output to the same folder
                    $OutputFile = $File.FullName + ".opti.jpg"
                } else {
                    # If output to a different folder
                    if ($InputPath -ne $OutputPath) {
                        $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
                    }
                    $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
                }
                
                # Create folder for output file if needed
                $OutputDir = Split-Path $OutputFile -Parent
                if (-not (Test-Path $OutputDir)) {
                    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                }
                
                $OriginalSize = $File.Length
                
                # Build jpegtran command using System.Diagnostics.Process
                $processInfo = New-Object System.Diagnostics.ProcessStartInfo
                $processInfo.FileName = $MozJpegPath
                $processInfo.Arguments = "-outfile `"$OutputFile`" -copy none -optimize `"$OriginalFile`""
                $processInfo.RedirectStandardOutput = $true
                $processInfo.RedirectStandardError = $true
                $processInfo.UseShellExecute = $false
                $processInfo.CreateNoWindow = $true
                
                $process = New-Object System.Diagnostics.Process
                $process.StartInfo = $processInfo
                $process.Start() | Out-Null
                $process.WaitForExit()
                
                if ($process.ExitCode -eq 0 -and (Test-Path $OutputFile)) { 
                    $NewSize = (Get-Item $OutputFile).Length
                    
                    $EndTime = Get-Date
                    $TimeSpent = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
                    
                    if ($NewSize -lt $OriginalSize) {
                        $Percent = [math]::Round(($NewSize / $OriginalSize) * 100, 2)
                        Write-Host "$OriginalSize`t$NewSize`t$Percent`t`t$($File.Name) ($TimeSpent)"
                        return @{
                            OriginalFile = $OriginalFile
                            OutputFile = $OutputFile
                            OriginalSize = $OriginalSize
                            CompressedSize = $NewSize
                        }
                    } else {
                        # If file wasn't compressed, delete output file
                        Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
                        Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessageParallel "NotCompressed")`t`t$($File.Name)"
                        return $null
                    }
                } else {
                    Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessageParallel "ErrorProcessing")`t`t$($File.Name)"
                    return $null
                }
            }
            catch {
                Write-Host (Get-LocalizedMessageParallel "ErrorWithDetails" @($File.Name, $_.Exception.Message))
                return $null
            }
        }
        
        # Call function for current file
        $result = Optimize-File -File $_ -MozJpegPath $using:MozJpegPath -OutputPath $using:OutputPath -InputPath $using:InputPath -ConfirmReplace $using:ConfirmReplace
        return $result
    } -ThrottleLimit $ThrottleLimit
} else {
    # PowerShell 5 and below - use sequential processing with direct call
    $Results = $Files | ForEach-Object {
        Optimize-File -File $_ -MozJpegPath $MozJpegPath -OutputPath $OutputPath -InputPath $InputPath -ConfirmReplace $ConfirmReplace
    }
}

Write-Host "END: $(Get-Date)"

# Prompt to replace originals if needed
if ($ConfirmReplace -and $Results -ne $null) {
    $Response = Read-Host (Get-LocalizedMessage "ReplacePrompt")
    if ($Response -eq 'Y' -or $Response -eq 'y') {
        foreach ($Result in $Results) {
            if ($Result -ne $null) {
                # Replace original JPG file
                Move-Item $Result.OutputFile $Result.OriginalFile -Force
            }
        }
        Write-Host (Get-LocalizedMessage "DoneReplaced")
    } else {
        Write-Host (Get-LocalizedMessage "DoneNotReplaced")
    }
} else {
    Write-Host (Get-LocalizedMessage "DoneOutput" @($OutputPath))
}