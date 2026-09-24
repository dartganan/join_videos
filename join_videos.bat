@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
title Join Videos (no re-encoding)

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
echo    JOIN VIDEOS  -  direct stream copy (no re-encoding)
echo ==============================================================
echo  Folder: %CD%
echo.

rem ---- Check ffmpeg / ffprobe ----
where ffmpeg >nul 2>&1 || (
    echo [ERROR] ffmpeg not found. Install it with:  winget install Gyan.FFmpeg
    echo         or place ffmpeg.exe and ffprobe.exe in this folder.
    goto :finish
)
where ffprobe >nul 2>&1 || (
    echo [ERROR] ffprobe not found. It ships together with ffmpeg.
    goto :finish
)

rem ---- Choose sort order ----
set "JV_ORDER=%~1"
if "%JV_ORDER%"=="1" goto :order_ok
if "%JV_ORDER%"=="2" goto :order_ok
if "%JV_ORDER%"=="3" goto :order_ok
if "%JV_ORDER%"=="4" goto :order_ok
echo  How should the videos be sorted?
echo    [1] File name (natural order: video2 before video10)
echo    [2] Recording date (video's internal metadata)
echo    [3] File modified date
echo    [4] File created date
echo.
choice /c 1234 /n /m "  Choose (1-4): "
set "JV_ORDER=%ERRORLEVEL%"
:order_ok
if "%JV_ORDER%"=="1" set "ORDER_DESC=File name (natural order)"
if "%JV_ORDER%"=="2" set "ORDER_DESC=Recording date (video metadata)"
if "%JV_ORDER%"=="3" set "ORDER_DESC=File modified date"
if "%JV_ORDER%"=="4" set "ORDER_DESC=File created date"
echo.
echo  Sorting by: %ORDER_DESC%
if "%JV_ORDER%"=="2" echo  (reading video metadata, please wait...)

rem ---- Build the sorted list (PowerShell block at the end of this file) ----
if exist "%JV_SORTED%" del "%JV_SORTED%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:JV_BAT,[Text.Encoding]::UTF8); iex $s.Substring($s.LastIndexOf('#PS_START'))"
if not exist "%JV_SORTED%" (
    echo  [ERROR] No videos found in this folder.
    goto :finish
)

rem ---- Show videos in order and build the ffmpeg concat list ----
if exist "%CONCAT_LIST%" del "%CONCAT_LIST%"
set /a COUNT=0
set "FIRST_FILE="
set "CODEC_REF="
set "MISMATCH=0"

echo.
echo  Videos in the order they will be joined:
echo  --------------------------------------------------------------
for /f "usebackq tokens=1,2 delims=|" %%A in ("%JV_SORTED%") do (
    call :process_file "%%A" "%%B"
)

if %COUNT% LSS 2 (
    echo.
    echo  [WARNING] Only %COUNT% video found. Nothing to join.
    goto :finish
)

if "%MISMATCH%"=="1" (
    echo.
    echo  [WARNING] The videos have different codecs/resolutions.
    echo            Joining without re-encoding may fail or produce a file
    echo            with playback issues.
)

echo.
choice /c YN /m "  Is the order above correct? Continue"
if errorlevel 2 (
    echo  Cancelled. Run again and choose a different sort order.
    goto :finish
)

rem ---- Output file name ----
for %%A in ("%FIRST_FILE%") do set "EXT=%%~xA"
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TIMESTAMP=%%D"
set "OUTPUT=%JV_PREFIX%%TIMESTAMP%%EXT%"

echo.
echo  --------------------------------------------------------------
echo  Total videos : %COUNT%
echo  Sort order   : %ORDER_DESC%
echo  Output file  : %OUTPUT%
echo  Mode         : stream copy (-c copy), no re-encoding
echo  --------------------------------------------------------------
echo.
echo  Joining... (progress below)
echo.

set "START_TIME=%TIME%"
rem Copy only the main video stream, audio and subtitles. Skips cover thumbnails
rem (the concat demuxer drops the attached_pic flag, so 0:V would keep them) and
rem camera data tracks (e.g. DJI djmd/dbgi telemetry), which ffmpeg cannot join.
ffmpeg -hide_banner -loglevel error -stats -f concat -safe 0 -i "%CONCAT_LIST%" -map 0:v:0 -map 0:a? -map 0:s? -ignore_unknown -c copy -avoid_negative_ts make_zero "%OUTPUT%"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo  [WARNING] ffmpeg exited with an error ^(code %RC%^).
    echo            Retrying with just the main video and audio tracks...
    if exist "%OUTPUT%" del "%OUTPUT%"
    ffmpeg -hide_banner -loglevel error -stats -f concat -safe 0 -i "%CONCAT_LIST%" -map 0:v:0 -map 0:a:0? -c copy -avoid_negative_ts make_zero "%OUTPUT%"
)
if not "%RC%"=="0" set "RC=%ERRORLEVEL%"
set "END_TIME=%TIME%"
if not "%RC%"=="0" (
    echo  [ERROR] Could not join the videos without re-encoding.
    goto :finish
)

echo ==============================================================
echo  DONE!
echo  Started : %START_TIME%
echo  Finished: %END_TIME%
for %%S in ("%OUTPUT%") do call :size_mb "%%~zS"
echo  Size    : %MB% MB
set "DURATION=?"
for /f "delims=" %%T in ('ffprobe -v error -show_entries format^=duration -sexagesimal -of default^=nw^=1:nk^=1 "%OUTPUT%"') do set "DURATION=%%T"
echo  Duration: %DURATION%
echo  File    : %CD%\%OUTPUT%
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
echo       %SORT_KEY%  ^|  %MB% MB  ^|  Duration: %DURATION%  ^|  Video: %VIDEO_INFO%

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
            $desc = 'Name'
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
            if ($date) { $desc = 'Recorded: ' + $date.ToString($dateFormat) }
            else       { $date = $file.LastWriteTime; $desc = 'No metadata, modified: ' + $date.ToString($dateFormat) }
            $key = $date.ToString('yyyyMMddHHmmssfff')
        }
        '3' {
            $key  = $file.LastWriteTime.ToString('yyyyMMddHHmmssfff')
            $desc = 'Modified: ' + $file.LastWriteTime.ToString($dateFormat)
        }
        default {
            $key  = $file.CreationTime.ToString('yyyyMMddHHmmssfff')
            $desc = 'Created: ' + $file.CreationTime.ToString($dateFormat)
        }
    }
    [pscustomobject]@{ Key = $key; Name = $file.Name; Desc = $desc }
}

$lines = $items | Sort-Object Key, Name | ForEach-Object { $_.Name + '|' + $_.Desc }
[IO.File]::WriteAllLines($env:JV_SORTED, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
