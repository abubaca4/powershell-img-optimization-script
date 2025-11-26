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
    "InputPathNotSpecified" = @{
        "ru" = "Не указан входной путь"
        "en" = "Input path not specified"
    }
    "InputPathNotFound" = @{
        "ru" = "Входной путь не существует: {0}"
        "en" = "Input path does not exist: {0}"
    }
    "OxipngNotFound" = @{
        "ru" = "oxipng не найден по пути: {0}"
        "en" = "oxipng not found at path: {0}"
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
    "ErrorDetailed" = @{
        "ru" = "ОШИБКА: {0} - {1}"
        "en" = "ERROR: {0} - {1}"
    }
    "End" = @{
        "ru" = "КОНЕЦ: {0}"
        "en" = "END: {0}"
    }
    "ReplacePrompt" = @{
        "ru" = "Заменить оригинальные PNG/APNG файлы сжатыми версиями? Нажмите Y для ДА или N для НЕТ и нажмите ENTER"
        "en" = "Replace original PNG/APNG files with compressed versions? Press Y for YES or N for NO and press ENTER"
    }
    "DoneReplaced" = @{
        "ru" = "Готово. Оригинальные файлы были заменены."
        "en" = "Done. Original files have been replaced."
    }
    "DoneNotReplaced" = @{
        "ru" = "Готово. Оригинальные и сжатые файлы сохранены. Сжатые файлы имеют суффикс .opti"
        "en" = "Done. Original and compressed files are saved. Compressed files have suffix .opti"
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
$OxipngPath = "oxipng\oxipng.exe"

# Check arguments
if (-not $InputPath) {
    Write-Error (Get-LocalizedMessage "InputPathNotSpecified")
    exit 1
}

if (-not (Test-Path $InputPath)) {
    Write-Error (Get-LocalizedMessage "InputPathNotFound" $InputPath)
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

# Check if oxipng exists
if (-not (Test-Path $OxipngPath)) {
    Write-Error (Get-LocalizedMessage "OxipngNotFound" $OxipngPath)
    exit 1
}

Write-Host (Get-LocalizedMessage "Start" (Get-Date))
Write-Host (Get-LocalizedMessage "SizeHeader")
Write-Host (Get-LocalizedMessage "SizeRowHeader")

# Get all files for processing (only PNG and APNG)
$Files = Get-ChildItem -Path $InputPath -Include *.png, *.apng -Recurse -File

# Function to process a single file
function Optimize-File {
    param($File, $OxipngPath, $OutputPath, $InputPath, $ConfirmReplace)
    
    $StartTime = Get-Date
    $OriginalFile = $File.FullName

    try {
        # Determine output filename
        if ($ConfirmReplace) {
            # If output to the same folder
            $OutputFile = $File.FullName + ".opti" + $File.Extension
        } else {
            # If output to a different folder
            $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti" + $File.Extension)
        }
        
        # Create folder for output file if needed
        $OutputDir = Split-Path $OutputFile -Parent
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        $OriginalSize = $File.Length
        
        # Build oxipng command arguments
        $Arguments = "-o max --strip safe -Z --fast -q --out `"$OutputFile`" `"$OriginalFile`""
        
        # Directly call oxipng using &
        & $OxipngPath -o max --strip safe -q --out $OutputFile $OriginalFile
        
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
        Write-Host (Get-LocalizedMessage "ErrorDetailed" $File.Name $_.Exception.Message)
        return $null
    }
}

# Process files sequentially
$Results = $Files | ForEach-Object {
    Optimize-File -File $_ -OxipngPath $OxipngPath -OutputPath $OutputPath -InputPath $InputPath -ConfirmReplace $ConfirmReplace
}

Write-Host (Get-LocalizedMessage "End" (Get-Date))

# Prompt for replacing originals if needed
if ($ConfirmReplace -and $Results -ne $null) {
    $Response = Read-Host (Get-LocalizedMessage "ReplacePrompt")
    if ($Response -eq 'Y' -or $Response -eq 'y') {
        foreach ($Result in $Results) {
            if ($Result -ne $null) {
                # Replace original PNG/APNG file
                Move-Item $Result.OutputFile $Result.OriginalFile -Force
            }
        }
        Write-Host (Get-LocalizedMessage "DoneReplaced")
    } else {
        Write-Host (Get-LocalizedMessage "DoneNotReplaced")
    }
} else {
    Write-Host (Get-LocalizedMessage "DoneOutput" $OutputPath)
}