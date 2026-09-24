@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
title Juntar Videos (sem recodificar)

rem ==========================================================================
rem  Joins every video in the folder where this .bat lives, WITHOUT
rem  re-encoding (ffmpeg -c copy), in the chosen order:
rem    1 = File name (natural order: video2 before video10)
rem    2 = Recording date (video metadata; falls back to modified date)
rem    3 = File modified date
rem    4 = File created date
rem  The order can be passed as an argument:  join_videos.bat 2
rem  Requires ffmpeg and ffprobe on PATH or next to this .bat.
rem ==========================================================================

cd /d "%~dp0"

set "JV_PREFIX=MERGED_"
set "JV_BAT=%~f0"
set "CONCAT_LIST=%TEMP%\join_videos_list_%RANDOM%.txt"
set "JV_SORTED=%TEMP%\join_videos_sorted_%RANDOM%.txt"

echo.
echo ==============================================================
echo    JUNTAR VIDEOS  -  copia direta de streams (sem renderizar)
echo ==============================================================
echo  Pasta: %CD%
echo.

rem ---- Check ffmpeg / ffprobe ----
where ffmpeg >nul 2>&1 || (
    echo [ERRO] ffmpeg nao encontrado. Instale com:  winget install Gyan.FFmpeg
    echo        ou coloque ffmpeg.exe e ffprobe.exe nesta pasta.
    goto :finish
)
where ffprobe >nul 2>&1 || (
    echo [ERRO] ffprobe nao encontrado. Ele vem junto com o ffmpeg.
    goto :finish
)

rem ---- Choose sort order ----
set "JV_ORDER=%~1"
if "%JV_ORDER%"=="1" goto :order_ok
if "%JV_ORDER%"=="2" goto :order_ok
if "%JV_ORDER%"=="3" goto :order_ok
if "%JV_ORDER%"=="4" goto :order_ok
echo  Como ordenar os videos?
echo    [1] Nome do arquivo (ordem natural: video2 antes de video10)
echo    [2] Data de gravacao (metadado interno do video)
echo    [3] Data de modificacao do arquivo
echo    [4] Data de criacao do arquivo
echo.
choice /c 1234 /n /m "  Escolha (1-4): "
set "JV_ORDER=%ERRORLEVEL%"
:order_ok
if "%JV_ORDER%"=="1" set "ORDER_DESC=Nome do arquivo (ordem natural)"
if "%JV_ORDER%"=="2" set "ORDER_DESC=Data de gravacao (metadado do video)"
if "%JV_ORDER%"=="3" set "ORDER_DESC=Data de modificacao do arquivo"
if "%JV_ORDER%"=="4" set "ORDER_DESC=Data de criacao do arquivo"
echo.
echo  Ordenando por: %ORDER_DESC%
if "%JV_ORDER%"=="2" echo  (lendo metadados dos videos, aguarde...)

rem ---- Build the sorted list (PowerShell block at the end of this file) ----
if exist "%JV_SORTED%" del "%JV_SORTED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:JV_BAT,[Text.Encoding]::UTF8); iex $s.Substring($s.LastIndexOf('#PS_START'))"
if not exist "%JV_SORTED%" (
    echo  [ERRO] Nenhum video encontrado nesta pasta.
    goto :finish
)

rem ---- Show videos in order and build the ffmpeg concat list ----
if exist "%CONCAT_LIST%" del "%CONCAT_LIST%"
set /a COUNT=0
set "FIRST_FILE="
set "CODEC_REF="
set "MISMATCH=0"

echo.
echo  Videos na ordem em que serao juntados:
echo  --------------------------------------------------------------
for /f "usebackq tokens=1,2 delims=|" %%A in ("%JV_SORTED%") do (
    call :process_file "%%A" "%%B"
)

if %COUNT% LSS 2 (
    echo.
    echo  [AVISO] Apenas %COUNT% video encontrado. Nada para juntar.
    goto :finish
)

if "%MISMATCH%"=="1" (
    echo.
    echo  [AVISO] Os videos possuem codecs/resolucoes diferentes.
    echo          A juncao sem recodificar pode falhar ou gerar um arquivo
    echo          com problemas de reproducao.
)

echo.
choice /c SN /m "  A ordem acima esta correta? Continuar"
if errorlevel 2 (
    echo  Cancelado. Rode novamente e escolha outra forma de ordenar.
    goto :finish
)

rem ---- Output file name ----
for %%A in ("%FIRST_FILE%") do set "EXT=%%~xA"
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TIMESTAMP=%%D"
set "OUTPUT=%JV_PREFIX%%TIMESTAMP%%EXT%"

echo.
echo  --------------------------------------------------------------
echo  Total de videos : %COUNT%
echo  Ordem           : %ORDER_DESC%
echo  Arquivo de saida: %OUTPUT%
echo  Modo            : copia de streams (-c copy), sem recodificar
echo  --------------------------------------------------------------
echo.
echo  Juntando... (progresso abaixo)
echo.

set "START_TIME=%TIME%"
rem Copy only the main video stream, audio and subtitles. Skips cover thumbnails
rem (the concat demuxer drops the attached_pic flag, so 0:V would keep them) and
rem camera data tracks (e.g. DJI djmd/dbgi telemetry), which ffmpeg cannot join.
ffmpeg -hide_banner -loglevel error -stats -f concat -safe 0 -i "%CONCAT_LIST%" -map 0:v:0 -map 0:a? -map 0:s? -ignore_unknown -c copy -avoid_negative_ts make_zero "%OUTPUT%"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo  [AVISO] O ffmpeg terminou com erro ^(codigo %RC%^).
    echo          Tentando novamente apenas com video e audio principais...
    if exist "%OUTPUT%" del "%OUTPUT%"
    ffmpeg -hide_banner -loglevel error -stats -f concat -safe 0 -i "%CONCAT_LIST%" -map 0:v:0 -map 0:a:0? -c copy -avoid_negative_ts make_zero "%OUTPUT%"
)
if not "%RC%"=="0" set "RC=%ERRORLEVEL%"
set "END_TIME=%TIME%"
if not "%RC%"=="0" (
    echo  [ERRO] Nao foi possivel juntar os videos sem recodificar.
    goto :finish
)

echo ==============================================================
echo  CONCLUIDO!
echo  Inicio : %START_TIME%
echo  Fim    : %END_TIME%
for %%S in ("%OUTPUT%") do call :size_mb "%%~zS"
echo  Tamanho: %MB% MB
set "DURATION=?"
for /f "delims=" %%T in ('ffprobe -v error -show_entries format^=duration -sexagesimal -of default^=nw^=1:nk^=1 "%OUTPUT%"') do set "DURATION=%%T"
echo  Duracao: %DURATION%
echo  Arquivo: %CD%\%OUTPUT%
echo ==============================================================
goto :finish


rem ==========================================================================
:process_file
set "FILE_NAME=%~1"
set "SORT_KEY=%~2"
set /a COUNT+=1
if not defined FIRST_FILE set "FIRST_FILE=%FILE_NAME%"

for %%A in ("%FILE_NAME%") do (
    set "BYTES=%%~zA"
    set "FULL_PATH=%%~fA"
)

set "VIDEO_INFO="
set "DURATION=?"
for /f "delims=" %%I in ('ffprobe -v error -select_streams v:0 -show_entries stream^=codec_name^,width^,height -of csv^=p^=0:s^=x "%FILE_NAME%" 2^>nul') do set "VIDEO_INFO=%%I"
for /f "delims=" %%T in ('ffprobe -v error -show_entries format^=duration -sexagesimal -of default^=nw^=1:nk^=1 "%FILE_NAME%" 2^>nul') do set "DURATION=%%T"
if not defined CODEC_REF set "CODEC_REF=%VIDEO_INFO%"
if not "%VIDEO_INFO%"=="%CODEC_REF%" set "MISMATCH=1"

call :size_mb "%BYTES%"
echo  [%COUNT%] %FILE_NAME%
echo       %SORT_KEY%  ^|  %MB% MB  ^|  Duracao: %DURATION%  ^|  Video: %VIDEO_INFO%

rem Append to the ffmpeg concat list (single quotes escaped as '\'')
set "LINE=%FULL_PATH:'='\''%"
>>"%CONCAT_LIST%" echo file '%LINE%'
goto :eof


rem ==========================================================================
:size_mb
rem Converts bytes to MB with 1 decimal place (avoids 32-bit overflow in set /a)
set "B=%~1"
set "MB=0"
if not defined B goto :eof
set "B=000000%B%"
set "MB=%B:~0,-6%,%B:~-6,1%"
for /f "tokens=* delims=0" %%Z in ("%MB%") do set "MB=%%Z"
if "%MB:~0,1%"=="," set "MB=0%MB%"
goto :eof


rem ==========================================================================
:finish
if exist "%CONCAT_LIST%" del "%CONCAT_LIST%" >nul 2>&1
if exist "%JV_SORTED%" del "%JV_SORTED%" >nul 2>&1
echo.
pause
endlocal
exit /b


rem ==========================================================================
rem  PowerShell block: lists the folder's videos and sorts them by JV_ORDER.
rem  Writes "name|sort key description" lines to JV_SORTED (UTF-8).
rem  (Never executed by cmd, only read by the PowerShell call above.)
rem ==========================================================================
#PS_START
$extensions = '.mp4','.mkv','.mov','.m4v','.avi','.ts','.mts','.m2ts','.wmv','.flv','.webm','.3gp','.mpg','.mpeg'
$files = Get-ChildItem -LiteralPath . -File | Where-Object {
    # Skip previous outputs of this script (JUNTADO_ is the legacy prefix)
    ($extensions -contains $_.Extension.ToLower()) -and
    -not $_.Name.StartsWith($env:JV_PREFIX, 'OrdinalIgnoreCase') -and
    -not $_.Name.StartsWith('JUNTADO_', 'OrdinalIgnoreCase')
}
if (-not $files) { return }

$dateFormat = 'dd"/"MM"/"yyyy HH:mm:ss'
$items = foreach ($file in $files) {
    switch ($env:JV_ORDER) {
        '1' {
            $key  = [regex]::Replace($file.Name.ToLower(), '\d+', { param($m) $m.Value.PadLeft(20, '0') })
            $desc = 'Nome'
        }
        '2' {
            $tags = @{}
            $probe = & ffprobe -v error -show_entries 'format_tags=com.apple.quicktime.creationdate,creation_time,date' -of 'default=nw=1' $file.FullName 2>$null
            foreach ($line in $probe) { if ($line -match '^TAG:([^=]+)=(.+)$') { $tags[$matches[1].ToLower()] = $matches[2].Trim() } }
            $date = $null
            foreach ($tag in 'com.apple.quicktime.creationdate', 'creation_time', 'date') {
                $parsed = [datetime]::MinValue
                if ($tags[$tag] -and [datetime]::TryParse($tags[$tag], [ref]$parsed) -and $parsed.Year -ge 1980) { $date = $parsed; break }
            }
            if ($date) { $desc = 'Gravado: ' + $date.ToString($dateFormat) }
            else       { $date = $file.LastWriteTime; $desc = 'Sem metadado, modificado: ' + $date.ToString($dateFormat) }
            $key = $date.ToString('yyyyMMddHHmmssfff')
        }
        '3' {
            $key  = $file.LastWriteTime.ToString('yyyyMMddHHmmssfff')
            $desc = 'Modificado: ' + $file.LastWriteTime.ToString($dateFormat)
        }
        default {
            $key  = $file.CreationTime.ToString('yyyyMMddHHmmssfff')
            $desc = 'Criado: ' + $file.CreationTime.ToString($dateFormat)
        }
    }
    [pscustomobject]@{ Key = $key; Name = $file.Name; Desc = $desc }
}

$lines = $items | Sort-Object Key, Name | ForEach-Object { $_.Name + '|' + $_.Desc }
[IO.File]::WriteAllLines($env:JV_SORTED, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
