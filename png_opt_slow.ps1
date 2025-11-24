param(
    [Parameter(Position=0)]
    [string]$InputPath,
    
    [Parameter(Position=1)]
    [string]$OutputPath
)

# Настройки
$OxipngPath = "oxipng\oxipng.exe"

# Проверка аргументов
if (-not $InputPath) {
    Write-Error "Не указан входной путь"
    exit 1
}

if (-not (Test-Path $InputPath)) {
    Write-Error "Входной путь не существует: $InputPath"
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

# Проверка наличия oxipng
if (-not (Test-Path $OxipngPath)) {
    Write-Error "oxipng не найден по пути: $OxipngPath"
    exit 1
}

Write-Host "НАЧАЛО: $(Get-Date)"
Write-Host "Размер в байтах:"
Write-Host "исх.    сейчас  % от исх.    имя и путь (секунд обработки)"

# Получаем все файлы для обработки (только PNG и APNG)
$Files = Get-ChildItem -Path $InputPath -Include *.png, *.apng -Recurse -File

# Функция для обработки одного файла
function Optimize-File {
    param($File, $OxipngPath, $OutputPath, $InputPath, $ConfirmReplace)
    
    $StartTime = Get-Date
    $OriginalFile = $File.FullName

    try {
        # Определяем выходное имя файла
        if ($ConfirmReplace) {
            # Если выход в ту же папку
            $OutputFile = $File.FullName + ".opti" + $File.Extension
        } else {
            # Если выход в другую папку
            $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti" + $File.Extension)
        }
        
        # Создаем папку для выходного файла если нужно
        $OutputDir = Split-Path $OutputFile -Parent
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        $OriginalSize = $File.Length
        
        # Формируем команду oxipng
        $Arguments = "-o max --strip safe -Z -q --out `"$OutputFile`" `"$OriginalFile`""
        
        $process = Start-Process -FilePath $OxipngPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
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
                # Если файл не сжался, удаляем выходной файл
                Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue
                Write-Host "$OriginalSize`t----`tне сжался`t`t$($File.Name)"
                return $null
            }
        } else {
            Write-Host "$OriginalSize`t----`tошибка`t`t$($File.Name)"
            return $null
        }
    }
    catch {
        Write-Host "ОШИБКА: $($File.Name) - $($_.Exception.Message)"
        return $null
    }
}

# Обрабатываем файлы последовательно
$Results = $Files | ForEach-Object {
    Optimize-File -File $_ -OxipngPath $OxipngPath -OutputPath $OutputPath -InputPath $InputPath -ConfirmReplace $ConfirmReplace
}

Write-Host "КОНЕЦ: $(Get-Date)"

# Запрос на замену оригиналов если нужно
if ($ConfirmReplace -and $Results -ne $null) {
    $Response = Read-Host "Заменить оригинальные PNG/APNG файлы сжатыми версиями? Нажмите Y для ДА или N для НЕТ и нажмите ENTER"
    if ($Response -eq 'Y' -or $Response -eq 'y') {
        foreach ($Result in $Results) {
            if ($Result -ne $null) {
                # Заменяем оригинал PNG/APNG файла
                Move-Item $Result.OutputFile $Result.OriginalFile -Force
            }
        }
        Write-Host "Готово. Оригинальные файлы были заменены."
    } else {
        Write-Host "Готово. Оригинальные и сжатые файлы сохранены. Сжатые файлы имеют суффикс .opti"
    }
} else {
    Write-Host "Готово. Сжатые файлы сохранены в: $OutputPath"
}