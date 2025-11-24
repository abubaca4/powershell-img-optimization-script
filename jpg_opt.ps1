param(
    [Parameter(Position=0)]
    [string]$InputPath,
    
    [Parameter(Position=1)]
    [string]$OutputPath
)

# Настройки
$MozJpegPath = "mozjpeg\cjpeg-static.exe"
$ProcessorCores = (Get-CimInstance Win32_Processor).NumberOfCores

# Проверка версии PowerShell
$PSVersion = $PSVersionTable.PSVersion.Major
$UseParallel = $PSVersion -ge 7

if ($UseParallel) {
    $ThrottleLimit = $ProcessorCores
} else {
    Write-Host "PowerShell версии $PSVersion - параллельная обработка недоступна, используется последовательная обработка"
}

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

# Проверка наличия mozcjpeg
if (-not (Test-Path $MozJpegPath)) {
    Write-Error "mozcjpeg не найден по пути: $MozJpegPath"
    exit 1
}

# Наборы параметров для тестирования
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

Write-Host "НАЧАЛО: $(Get-Date)"
Write-Host "Размер в байтах:"
Write-Host "исх.    сейчас  % от исх.    имя и путь (секунд обработки) параметры"

# Получаем все файлы для обработки
$Files = Get-ChildItem -Path $InputPath -Include *.jpg, *.jpeg, *.png -Recurse -File

# Функция для обработки одного файла
function Optimize-File {
    param($File, $MozJpegPath, $ParameterSets, $OutputPath, $InputPath, $ConfirmReplace)
    
    $StartTime = Get-Date
    $OriginalFile = $File.FullName

    try {
        # Определяем выходное имя файла
        if ($ConfirmReplace) {
            # Если выход в ту же папку
            if ($File.Extension -eq '.png') {
                $OutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti.jpg")
            } else {
                $OutputFile = $File.FullName + ".opti.jpg"
            }
        } else {
            # Если выход в другую папку
            if ($InputPath -ne $OutputPath) {
                $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
            }
            
            if ($File.Extension -eq '.png') {
                $OutputFile = Join-Path $OutputPath ($File.BaseName + ".jpg")
            } else {
                $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
            }
        }
        
        # Создаем папку для выходного файла если нужно
        $OutputDir = Split-Path $OutputFile -Parent
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }
        
        $OriginalSize = $File.Length
        $BestSize = $OriginalSize
        $BestParams = ""
        $BestTempFile = $null
        
        # Перебираем все наборы параметров для этого файла
        foreach ($Params in $ParameterSets) {
            $TempOutput = [System.IO.Path]::GetTempFileName() + ".jpg"
            
            try {
                # Формируем полную командную строку
                $Arguments = "-outfile `"$TempOutput`" $Params `"$OriginalFile`""
                
                $process = Start-Process -FilePath $MozJpegPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
                if ($process.ExitCode -eq 0 -and (Test-Path $TempOutput)) { 
                    $TempSize = (Get-Item $TempOutput).Length
                    
                    # Ищем наименьший размер
                    if ($TempSize -lt $BestSize) {
                        $BestSize = $TempSize
                        $BestParams = $Params
                        
                        # Сохраняем путь к лучшему временному файлу
                        if ($BestTempFile -and (Test-Path $BestTempFile)) {
                            Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
                        }
                        $BestTempFile = $TempOutput
                    } else {
                        # Удаляем временный файл если он не лучший
                        Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    # Удаляем временный файл если конвертация не удалась
                    if (Test-Path $TempOutput) { 
                        Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                    }
                }
            }
            catch {
                # Удаляем временный файл при ошибке
                if (Test-Path $TempOutput) { 
                    Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                }
            }
        }
        
        # Копируем лучший результат в выходной файл
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
            Write-Host "$OriginalSize`t----`tпропущен`t`t$($File.Name)"
            return $null
        }
    }
    catch {
        Write-Host "ОШИБКА: $($File.Name) - $($_.Exception.Message)"
        return $null
    }
}

# Обрабатываем файлы в зависимости от версии PowerShell
if ($UseParallel) {
    # PowerShell 7+ - используем параллельную обработку
    $Results = $Files | ForEach-Object -Parallel {
        function Optimize-File {
            param($File, $MozJpegPath, $ParameterSets, $OutputPath, $InputPath, $ConfirmReplace)
            
            $StartTime = Get-Date
            $OriginalFile = $File.FullName

            try {
                # Определяем выходное имя файла
                if ($ConfirmReplace) {
                    # Если выход в ту же папку
                    if ($File.Extension -eq '.png') {
                        $OutputFile = Join-Path $File.DirectoryName ($File.BaseName + ".opti.jpg")
                    } else {
                        $OutputFile = $File.FullName + ".opti.jpg"
                    }
                } else {
                    # Если выход в другую папку
                    if ($InputPath -ne $OutputPath) {
                        $RelativePath = $File.FullName.Substring($InputPath.Length).TrimStart('\', '/')
                    }
                    
                    if ($File.Extension -eq '.png') {
                        $OutputFile = Join-Path $OutputPath ($File.BaseName + ".jpg")
                    } else {
                        $OutputFile = Join-Path $OutputPath ($File.BaseName + ".opti.jpg")
                    }
                }
                
                # Создаем папку для выходного файла если нужно
                $OutputDir = Split-Path $OutputFile -Parent
                if (-not (Test-Path $OutputDir)) {
                    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
                }
                
                $OriginalSize = $File.Length
                $BestSize = $OriginalSize
                $BestParams = ""
                $BestTempFile = $null
                
                # Перебираем все наборы параметров для этого файла
                foreach ($Params in $ParameterSets) {
                    $TempOutput = [System.IO.Path]::GetTempFileName() + ".jpg"
                    
                    try {
                        # Формируем полную командную строку
                        $Arguments = "-outfile `"$TempOutput`" $Params `"$OriginalFile`""
                        
                        $process = Start-Process -FilePath $MozJpegPath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
                        if ($process.ExitCode -eq 0 -and (Test-Path $TempOutput)) { 
                            $TempSize = (Get-Item $TempOutput).Length
                            
                            # Ищем наименьший размер
                            if ($TempSize -lt $BestSize) {
                                $BestSize = $TempSize
                                $BestParams = $Params
                                
                                # Сохраняем путь к лучшему временному файлу
                                if ($BestTempFile -and (Test-Path $BestTempFile)) {
                                    Remove-Item $BestTempFile -Force -ErrorAction SilentlyContinue
                                }
                                $BestTempFile = $TempOutput
                            } else {
                                # Удаляем временный файл если он не лучший
                                Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue
                            }
                        } else {
                            # Удаляем временный файл если конвертация не удалась
                            if (Test-Path $TempOutput) { 
                                Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                            }
                        }
                    }
                    catch {
                        # Удаляем временный файл при ошибке
                        if (Test-Path $TempOutput) { 
                            Remove-Item $TempOutput -Force -ErrorAction SilentlyContinue 
                        }
                    }
                }
                
                # Копируем лучший результат в выходной файл
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
                    Write-Host "$OriginalSize`t----`tпропущен`t`t$($File.Name)"
                    return $null
                }
            }
            catch {
                Write-Host "ОШИБКА: $($File.Name) - $($_.Exception.Message)"
                return $null
            }
        }
        
        # Вызываем функцию для текущего файла
        $result = Optimize-File -File $_ -MozJpegPath $using:MozJpegPath -ParameterSets $using:ParameterSets -OutputPath $using:OutputPath -InputPath $using:InputPath -ConfirmReplace $using:ConfirmReplace
        return $result
    } -ThrottleLimit $ThrottleLimit
} else {
    # PowerShell 5 и ниже - используем последовательную обработку
    $Results = $Files | ForEach-Object {
        Optimize-File -File $_ -MozJpegPath $MozJpegPath -ParameterSets $ParameterSets -OutputPath $OutputPath -InputPath $InputPath -ConfirmReplace $ConfirmReplace
    }
}

Write-Host "КОНЕЦ: $(Get-Date)"

# Запрос на замену оригиналов если нужно
if ($ConfirmReplace -and $Results -ne $null) {
    $Response = Read-Host "Заменить оригинальные jpg или png файлы сжатыми версиями? Нажмите Y для ДА или N для НЕТ и нажмите ENTER"
    if ($Response -eq 'Y' -or $Response -eq 'y') {
        foreach ($Result in $Results) {
            if ($Result -ne $null) {
                $OriginalExt = [System.IO.Path]::GetExtension($Result.OriginalFile)
                if ($OriginalExt -eq '.png') {
                    # Для PNG удаляем оригинал и переименовываем JPG
                    Remove-Item $Result.OriginalFile -Force -ErrorAction SilentlyContinue
                    $NewName = $Result.OriginalFile -replace '\.png$', '.jpg'
                    Move-Item $Result.OutputFile $NewName -Force
                } else {
                    # Для JPG заменяем оригинал
                    Move-Item $Result.OutputFile $Result.OriginalFile -Force
                }
            }
        }
        Write-Host "Готово. Оригинальные файлы были заменены."
    } else {
        Write-Host "Готово. Оригинальные и сжатые файлы сохранены. Сжатые файлы имеют суффикс .opti.jpg"
    }
} else {
    Write-Host "Готово. Сжатые файлы сохранены в: $OutputPath"
}