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
        "ru" = "mozcjpeg не найден по пути: {0}"
        "en" = "mozcjpeg not found at path: {0}"
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
        "ru" = "исх.    сейчас  % от исх.    имя и путь (секунд обработки) параметры"
        "en" = "orig.   current % of orig.   name and path (processing seconds) parameters"
    }
    "Skipped" = @{
        "ru" = "пропущен"
        "en" = "skipped"
    }
    "Error" = @{
        "ru" = "ОШИБКА: {0} - {1}"
        "en" = "ERROR: {0} - {1}"
    }
    "ReplacePrompt" = @{
        "ru" = "Заменить оригинальные файлы изображений сжатыми версиями? Нажмите Y для ДА или N для НЕТ и нажмите ENTER"
        "en" = "Replace original image files with compressed versions? Press Y for YES or N for NO and press ENTER"
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
$MozJpegPath = "mozjpeg\cjpeg-static.exe"
$ProcessorCores = (Get-CimInstance Win32_Processor).NumberOfCores

# Check PowerShell version
$PSVersion = $PSVersionTable.PSVersion.Major
$UseParallel = $PSVersion -ge 7

if ($UseParallel) {
    $ThrottleLimit = $ProcessorCores
} else {
    Write-Host (Get-LocalizedMessage "PSVersionWarning" -FormatArgs $PSVersion)
}

# Check arguments
if (-not $InputPath) {
    Write-Error (Get-LocalizedMessage "InputPathNotSpecified")
    exit 1
}

if (-not (Test-Path $InputPath)) {
    Write-Error (Get-LocalizedMessage "InputPathNotFound" -FormatArgs $InputPath)
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

# Check if mozcjpeg is available
if (-not (Test-Path $MozJpegPath)) {
    Write-Error (Get-LocalizedMessage "MozJpegNotFound" -FormatArgs $MozJpegPath)
    exit 1
}

# Parameter sets for testing
$ParameterSets = @(
    "-dct float -quant-table 1 -nojfif -dc-scan-opt 2",
    "-dct float -quant-table 2 -nojfif -dc-scan-opt 2",
    "-dct float -quant-table 3 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ms-ssim -nojfif -dc-scan-opt 2",
    "-dct float -tune-ms-ssim -quant-table 3 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -quant-table 0 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -quant-table 1 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -quant-table 2 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -quant-table 3 -nojfif -dc-scan-opt 1",
    "-dct float -tune-ssim -quant-table 3 -nojfif -dc-scan-opt 2",
    "-dct float -tune-ssim -quant-table 4 -nojfif -dc-scan-opt 2",
    "-quant-table 2 -nojfif -dc-scan-opt 1",
    "-quant-table 2 -nojfif -dc-scan-opt 2",
    "-tune-ssim -nojfif -dc-scan-opt 2",
    "-tune-ssim -quant-table 1 -nojfif -dc-scan-opt 2",
    "-tune-ssim -quant-table 2 -nojfif",
    "-tune-ssim -quant-table 2 -nojfif -dc-scan-opt 0",
    "-tune-ssim -quant-table 2 -nojfif -dc-scan-opt 2",
    "-tune-ssim -quant-table 3 -nojfif -dc-scan-opt 1",
    "-tune-ssim -quant-table 3 -nojfif -dc-scan-opt 2"
)

# Define image extensions to convert to JPG
$ConvertToJpgExtensions = @('.png', '.ppm', '.pnm', '.pgm', '.pbm', '.bmp', '.dib', '.tga', '.icb', '.vda', '.vst', '.rle')

# Define all image extensions to process (including JPG formats)
$AllImageExtensions = $ConvertToJpgExtensions + @('.jpg', '.jpeg')

# Create include patterns for Get-ChildItem
$IncludePatterns = $AllImageExtensions | ForEach-Object { "*$_" }

Write-Host (Get-LocalizedMessage "Start" -FormatArgs (Get-Date))
Write-Host (Get-LocalizedMessage "SizeHeader")
Write-Host (Get-LocalizedMessage "SizeRowHeader")

# Get all files for processing using the variable
$Files = Get-ChildItem -Path $InputPath -Include $IncludePatterns -Recurse -File

# Function to process a single file
function Optimize-File {
    param($File, $MozJpegPath, $ParameterSets, $OutputPath, $InputPath, $ConfirmReplace, $ConvertToJpgExtensions)

    $StartTime = Get-Date
    $OriginalFile = $File.FullName

    try {
        # Determine output filename
        if ($ConfirmReplace) {
            # If output to the same folder
            if ($ConvertToJpgExtensions -contains $File.Extension.ToLower()) {
                $OutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti.jpg")
            } else {
                $OutputFile = $File.FullName + ".opti.jpg"
            }
        } else {
            # If output to a different folder
            if ($InputPath -ne $OutputPath) {
                $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
            }
            
            if ($ConvertToJpgExtensions -contains $File.Extension.ToLower()) {
                $OutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti.jpg")
            } else {
                $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
            }
        }
        
        # Create folder for output file if needed
        $OutputDir = Split-Path $OutputFile -Parent
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        $OriginalSize = $File.Length
        $BestSize = $OriginalSize
        $BestParams = ""
        $BestTempFile = $null
        
        # Iterate through all parameter sets for this file
        foreach ($Params in $ParameterSets) {
            $TempOutput = [System.IO.Path]::GetTempFileName() + ".jpg"
            
            try {
                # Build full command line and execute directly
                & $MozJpegPath -outfile $TempOutput $Params.Split(' ') $OriginalFile 2>$null 1>$null
                
                if ($LASTEXITCODE -eq 0 -and (Test-Path $TempOutput)) { 
                    $TempSize = (Get-Item $TempOutput).Length
                    
                    # Find smallest size
                    if ($TempSize -lt $BestSize) {
                        $BestSize = $TempSize
                        $BestParams = $Params
                        
                        # Save path to best temp file
                        if ($BestTempFile -and (Test-Path $BestTempFile)) {
                            Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
                        }
                        $BestTempFile = $TempOutput
                    } else {
                        # Delete temp file if it's not the best
                        Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    # Delete temp file if conversion failed
                    if (Test-Path $TempOutput) { 
                        Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                    }
                }
            }
            catch {
                # Delete temp file on error
                if (Test-Path $TempOutput) { 
                    Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                }
            }
        }
        
        # Copy best result to output file
        if ($BestTempFile -and (Test-Path $BestTempFile)) {
            Copy-Item $BestTempFile $OutputFile -Force
            Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
        }
        
        $EndTime = Get-Date
        $TimeSpent = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
        
        if ($BestParams -ne "") {
            $Percent = [math]::Round(($BestSize / $OriginalSize) * 100, 2)
            Write-Host "$OriginalSize`t$BestSize`t$Percent`t`t$($File.Name) ($TimeSpent) $BestParams"
            return @{
                OriginalFile = $OriginalFile
                OutputFile = $OutputFile
                OriginalSize = $OriginalSize
                CompressedSize = $BestSize
            }
        } else {
            Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessage "Skipped")`t`t$($File.Name)"
            return $null
        }
    }
    catch {
        Write-Host (Get-LocalizedMessage "Error" -FormatArgs $File.Name, $_.Exception.Message)
        return $null
    }
}

# Process files depending on PowerShell version
if ($UseParallel) {
    # PowerShell 7+ - use parallel processing with System.Diagnostics.Process
    $Results = $Files | ForEach-Object -Parallel {
        # Recreate localization function inside parallel block
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
            param($File, $MozJpegPath, $ParameterSets, $OutputPath, $InputPath, $ConfirmReplace, $ConvertToJpgExtensions)
            
            $StartTime = Get-Date
            $OriginalFile = $File.FullName

            try {
                # Determine output filename
                if ($ConfirmReplace) {
                    # If output to the same folder
                    if ($ConvertToJpgExtensions -contains $File.Extension.ToLower()) {
                        $OutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti.jpg")
                    } else {
                        $OutputFile = $File.FullName + ".opti.jpg"
                    }
                } else {
                    # If output to a different folder
                    if ($InputPath -ne $OutputPath) {
                        $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
                    }
                    
                    if ($ConvertToJpgExtensions -contains $File.Extension.ToLower()) {
                        $OutputFile = Join-Path $OutputPath ($File.BaseName + ".jpg")
                    } else {
                        $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
                    }
                }
                
                # Create folder for output file if needed
                $OutputDir = Split-Path $OutputFile -Parent
                if (-not (Test-Path $OutputDir)) {
                    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                }
                
                $OriginalSize = $File.Length
                $BestSize = $OriginalSize
                $BestParams = ""
                $BestTempFile = $null
                
                # Iterate through all parameter sets for this file
                foreach ($Params in $ParameterSets) {
                    $TempOutput = [System.IO.Path]::GetTempFileName() + ".jpg"
                    
                    try {
                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo.FileName = $MozJpegPath
                        $process.StartInfo.Arguments = "-outfile `"$TempOutput`" $Params `"$OriginalFile`""
                        $process.StartInfo.UseShellExecute = $false
                        $process.StartInfo.CreateNoWindow = $true
                        $process.StartInfo.RedirectStandardOutput = $true
                        $process.StartInfo.RedirectStandardError = $true
                        $process.Start() | Out-Null
                        $process.WaitForExit()
                        
                        if ($process.ExitCode -eq 0 -and (Test-Path $TempOutput)) { 
                            $TempSize = (Get-Item $TempOutput).Length
                            
                            # Find smallest size
                            if ($TempSize -lt $BestSize) {
                                $BestSize = $TempSize
                                $BestParams = $Params
                                
                                # Save path to best temp file
                                if ($BestTempFile -and (Test-Path $BestTempFile)) {
                                    Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
                                }
                                $BestTempFile = $TempOutput
                            } else {
                                # Delete temp file if it's not the best
                                Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue
                            }
                        } else {
                            # Delete temp file if conversion failed
                            if (Test-Path $TempOutput) { 
                                Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                            }
                        }
                    }
                    catch {
                        # Delete temp file on error
                        if (Test-Path $TempOutput) { 
                            Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                        }
                    }
                }
                
                # Copy best result to output file
                if ($BestTempFile -and (Test-Path $BestTempFile)) {
                    Copy-Item $BestTempFile $OutputFile -Force
                    Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
                }
                
                $EndTime = Get-Date
                $TimeSpent = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
                
                if ($BestParams -ne "") {
                    $Percent = [math]::Round(($BestSize / $OriginalSize) * 100, 2)
                    Write-Host "$OriginalSize`t$BestSize`t$Percent`t`t$($File.Name) ($TimeSpent) $BestParams"
                    return @{
                        OriginalFile = $OriginalFile
                        OutputFile = $OutputFile
                        OriginalSize = $OriginalSize
                        CompressedSize = $BestSize
                    }
                } else {
                    Write-Host "$OriginalSize`t----`t$(Get-LocalizedMessageParallel "Skipped")`t`t$($File.Name)"
                    return $null
                }
            }
            catch {
                Write-Host (Get-LocalizedMessageParallel "Error" -FormatArgs $File.Name, $_.Exception.Message)
                return $null
            }
        }
        
        # Call function for current file
        $result = Optimize-File -File $_ -MozJpegPath $using:MozJpegPath -ParameterSets $using:ParameterSets -OutputPath $using:OutputPath -InputPath $using:InputPath -ConfirmReplace $using:ConfirmReplace -ConvertToJpgExtensions $using:ConvertToJpgExtensions
        return $result
    } -ThrottleLimit $ThrottleLimit
} else {
    # PowerShell 5 and below - use sequential processing with direct exe call
    $Results = $Files | ForEach-Object {
        Optimize-File -File $_ -MozJpegPath $MozJpegPath -ParameterSets $ParameterSets -OutputPath $OutputPath -InputPath $InputPath -ConfirmReplace $ConfirmReplace -ConvertToJpgExtensions $ConvertToJpgExtensions
    }
}

Write-Host "END: $(Get-Date)"

# Prompt to replace originals if needed
if ($ConfirmReplace -and $Results -ne $null) {
    $Response = Read-Host (Get-LocalizedMessage "ReplacePrompt")
    if ($Response -eq 'Y' -or $Response -eq 'y') {
        foreach ($Result in $Results) {
            if ($Result -ne $null) {
                $OriginalExt = [System.IO.Path]::GetExtension($Result.OriginalFile).ToLower()
                if ($ConvertToJpgExtensions -contains $OriginalExt) {
                    # For non-JPG formats: delete original and rename JPG
                    Remove-Item $Result.OriginalFile -Force -ErrorAction SilentlyContinue
                    $NewName = $Result.OriginalFile -replace '\.[^\.]+$', '.jpg'
                    Move-Item $Result.OutputFile $NewName -Force
                } else {
                    # For JPG files: replace original
                    Move-Item $Result.OutputFile $Result.OriginalFile -Force
                }
            }
        }
        Write-Host (Get-LocalizedMessage "DoneReplaced")
    } else {
        Write-Host (Get-LocalizedMessage "DoneNotReplaced")
    }
} else {
    Write-Host (Get-LocalizedMessage "DoneOutput" -FormatArgs $OutputPath)
}