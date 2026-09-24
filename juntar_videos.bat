@echo off
chcp 65001 >nul
setlocal DisableDelayedExpansion
title Juntar Videos (sem recodificar)

rem ==========================================================================
rem  Junta todos os videos da pasta onde este .bat esta, SEM recodificar
rem  (ffmpeg -c copy), na ordem escolhida:
rem    1 = Nome do arquivo (ordem natural: video2 antes de video10)
rem    2 = Data de gravacao (metadado do video; se nao houver, usa modificacao)
rem    3 = Data de modificacao do arquivo
rem    4 = Data de criacao do arquivo
rem  A ordem pode ser passada como parametro:  juntar_videos.bat 2
rem  Requer ffmpeg e ffprobe no PATH ou na mesma pasta deste .bat.
rem ==========================================================================

cd /d "%~dp0"

set "JV_PREFIXO=JUNTADO_"
set "JV_BAT=%~f0"
set "LISTA=%TEMP%\juntar_videos_lista_%RANDOM%.txt"
set "JV_ORDENADOS=%TEMP%\juntar_videos_ordem_%RANDOM%.txt"

echo.
echo ==============================================================
echo    JUNTAR VIDEOS  -  copia direta de streams (sem renderizar)
echo ==============================================================
echo  Pasta: %CD%
echo.

rem ---- Verifica ffmpeg / ffprobe ----
where ffmpeg >nul 2>&1 || (
    echo [ERRO] ffmpeg nao encontrado. Instale com:  winget install Gyan.FFmpeg
    echo        ou coloque ffmpeg.exe e ffprobe.exe nesta pasta.
    goto :fim
)
where ffprobe >nul 2>&1 || (
    echo [ERRO] ffprobe nao encontrado. Ele vem junto com o ffmpeg.
    goto :fim
)

rem ---- Escolha da ordem ----
set "JV_ORDEM=%~1"
if "%JV_ORDEM%"=="1" goto :ordem_ok
if "%JV_ORDEM%"=="2" goto :ordem_ok
if "%JV_ORDEM%"=="3" goto :ordem_ok
if "%JV_ORDEM%"=="4" goto :ordem_ok
echo  Como ordenar os videos?
echo    [1] Nome do arquivo (ordem natural: video2 antes de video10)
echo    [2] Data de gravacao (metadado interno do video)
echo    [3] Data de modificacao do arquivo
echo    [4] Data de criacao do arquivo
echo.
choice /c 1234 /n /m "  Escolha (1-4): "
set "JV_ORDEM=%ERRORLEVEL%"
:ordem_ok
if "%JV_ORDEM%"=="1" set "ORDEM_DESC=Nome do arquivo (ordem natural)"
if "%JV_ORDEM%"=="2" set "ORDEM_DESC=Data de gravacao (metadado do video)"
if "%JV_ORDEM%"=="3" set "ORDEM_DESC=Data de modificacao do arquivo"
if "%JV_ORDEM%"=="4" set "ORDEM_DESC=Data de criacao do arquivo"
echo.
echo  Ordenando por: %ORDEM_DESC%
if "%JV_ORDEM%"=="2" echo  (lendo metadados dos videos, aguarde...)

rem ---- Gera a lista ordenada (bloco PowerShell no final deste arquivo) ----
if exist "%JV_ORDENADOS%" del "%JV_ORDENADOS%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:JV_BAT,[Text.Encoding]::UTF8); iex $s.Substring($s.LastIndexOf('#PS_INICIO'))"
if not exist "%JV_ORDENADOS%" (
    echo  [ERRO] Nenhum video encontrado nesta pasta.
    goto :fim
)

rem ---- Mostra os videos na ordem e monta a lista do ffmpeg ----
if exist "%LISTA%" del "%LISTA%"
set /a QTD=0
set "PRIMEIRO="
set "CODEC_REF="
set "DIVERGENTE=0"

echo.
echo  Videos na ordem em que serao juntados:
echo  --------------------------------------------------------------
for /f "usebackq tokens=1,2 delims=|" %%A in ("%JV_ORDENADOS%") do (
    call :processar "%%A" "%%B"
)

if %QTD% LSS 2 (
    echo.
    echo  [AVISO] Apenas %QTD% video encontrado. Nada para juntar.
    goto :fim
)

if "%DIVERGENTE%"=="1" (
    echo.
    echo  [AVISO] Os videos possuem codecs/resolucoes diferentes.
    echo          A juncao sem recodificar pode falhar ou gerar um arquivo
    echo          com problemas de reproducao.
)

echo.
choice /c SN /m "  A ordem acima esta correta? Continuar"
if errorlevel 2 (
    echo  Cancelado. Rode novamente e escolha outra forma de ordenar.
    goto :fim
)

rem ---- Nome do arquivo de saida ----
for %%A in ("%PRIMEIRO%") do set "EXT=%%~xA"
for /f %%D in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "DATAHORA=%%D"
set "SAIDA=%JV_PREFIXO%%DATAHORA%%EXT%"

echo.
echo  --------------------------------------------------------------
echo  Total de videos : %QTD%
echo  Ordem           : %ORDEM_DESC%
echo  Arquivo de saida: %SAIDA%
echo  Modo            : copia de streams (-c copy), sem recodificar
echo  --------------------------------------------------------------
echo.
echo  Juntando... (progresso abaixo)
echo.

set "INICIO=%TIME%"
ffmpeg -hide_banner -loglevel warning -stats -f concat -safe 0 -i "%LISTA%" -map 0 -c copy -avoid_negative_ts make_zero "%SAIDA%"
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo  [ERRO] O ffmpeg terminou com erro ^(codigo %RC%^).
    echo         Tentando novamente apenas com video e audio principais...
    if exist "%SAIDA%" del "%SAIDA%"
    ffmpeg -hide_banner -loglevel warning -stats -f concat -safe 0 -i "%LISTA%" -map 0:v:0 -map 0:a:0? -c copy -avoid_negative_ts make_zero "%SAIDA%"
)
if not "%RC%"=="0" set "RC=%ERRORLEVEL%"
set "FIM=%TIME%"
if not "%RC%"=="0" (
    echo  [ERRO] Nao foi possivel juntar os videos sem recodificar.
    goto :fim
)

echo ==============================================================
echo  CONCLUIDO!
echo  Inicio : %INICIO%
echo  Fim    : %FIM%
for %%S in ("%SAIDA%") do call :tamanho_mb "%%~zS"
echo  Tamanho: %MB% MB
set "DUR=?"
for /f "delims=" %%T in ('ffprobe -v error -show_entries format^=duration -sexagesimal -of default^=nw^=1:nk^=1 "%SAIDA%"') do set "DUR=%%T"
echo  Duracao: %DUR%
echo  Arquivo: %CD%\%SAIDA%
echo ==============================================================
goto :fim


rem ==========================================================================
:processar
set "ARQ=%~1"
set "CHAVE=%~2"
set /a QTD+=1
if not defined PRIMEIRO set "PRIMEIRO=%ARQ%"

for %%A in ("%ARQ%") do (
    set "BYTES=%%~zA"
    set "CAMINHO=%%~fA"
)

set "INFO="
set "DUR=?"
for /f "delims=" %%I in ('ffprobe -v error -select_streams v:0 -show_entries stream^=codec_name^,width^,height -of csv^=p^=0:s^=x "%ARQ%" 2^>nul') do set "INFO=%%I"
for /f "delims=" %%T in ('ffprobe -v error -show_entries format^=duration -sexagesimal -of default^=nw^=1:nk^=1 "%ARQ%" 2^>nul') do set "DUR=%%T"
if not defined CODEC_REF set "CODEC_REF=%INFO%"
if not "%INFO%"=="%CODEC_REF%" set "DIVERGENTE=1"

call :tamanho_mb "%BYTES%"
echo  [%QTD%] %ARQ%
echo       %CHAVE%  ^|  %MB% MB  ^|  Duracao: %DUR%  ^|  Video: %INFO%

rem Escreve na lista do ffmpeg (aspas simples escapadas como '\'')
set "LINHA=%CAMINHO:'='\''%"
>>"%LISTA%" echo file '%LINHA%'
goto :eof


rem ==========================================================================
:tamanho_mb
rem Converte bytes em MB com 1 casa decimal (evita estouro de 32 bits do set /a)
set "B=%~1"
set "MB=0"
if not defined B goto :eof
set "B=000000%B%"
set "MB=%B:~0,-6%,%B:~-6,1%"
for /f "tokens=* delims=0" %%Z in ("%MB%") do set "MB=%%Z"
if "%MB:~0,1%"=="," set "MB=0%MB%"
goto :eof


rem ==========================================================================
:fim
if exist "%LISTA%" del "%LISTA%" >nul 2>&1
if exist "%JV_ORDENADOS%" del "%JV_ORDENADOS%" >nul 2>&1
echo.
pause
endlocal
exit /b


rem ==========================================================================
rem  Bloco PowerShell: lista os videos da pasta e ordena conforme JV_ORDEM.
rem  Gera linhas "nome|descricao da chave" em JV_ORDENADOS (UTF-8).
rem  (Nunca executado pelo cmd, apenas lido pelo PowerShell acima.)
rem ==========================================================================
#PS_INICIO
$exts = '.mp4','.mkv','.mov','.m4v','.avi','.ts','.mts','.m2ts','.wmv','.flv','.webm','.3gp','.mpg','.mpeg'
$arqs = Get-ChildItem -LiteralPath . -File | Where-Object {
    ($exts -contains $_.Extension.ToLower()) -and -not $_.Name.StartsWith($env:JV_PREFIXO, 'OrdinalIgnoreCase')
}
if (-not $arqs) { return }

$fmt = 'dd"/"MM"/"yyyy HH:mm:ss'
$itens = foreach ($a in $arqs) {
    switch ($env:JV_ORDEM) {
        '1' {
            $chave = [regex]::Replace($a.Name.ToLower(), '\d+', { param($m) $m.Value.PadLeft(20, '0') })
            $desc  = 'Nome'
        }
        '2' {
            $tags = @{}
            $saida = & ffprobe -v error -show_entries 'format_tags=com.apple.quicktime.creationdate,creation_time,date' -of 'default=nw=1' $a.FullName 2>$null
            foreach ($l in $saida) { if ($l -match '^TAG:([^=]+)=(.+)$') { $tags[$matches[1].ToLower()] = $matches[2].Trim() } }
            $dt = $null
            foreach ($k in 'com.apple.quicktime.creationdate', 'creation_time', 'date') {
                $p = [datetime]::MinValue
                if ($tags[$k] -and [datetime]::TryParse($tags[$k], [ref]$p) -and $p.Year -ge 1980) { $dt = $p; break }
            }
            if ($dt) { $desc = 'Gravado: ' + $dt.ToString($fmt) }
            else     { $dt = $a.LastWriteTime; $desc = 'Sem metadado, modificado: ' + $dt.ToString($fmt) }
            $chave = $dt.ToString('yyyyMMddHHmmssfff')
        }
        '3' {
            $chave = $a.LastWriteTime.ToString('yyyyMMddHHmmssfff')
            $desc  = 'Modificado: ' + $a.LastWriteTime.ToString($fmt)
        }
        default {
            $chave = $a.CreationTime.ToString('yyyyMMddHHmmssfff')
            $desc  = 'Criado: ' + $a.CreationTime.ToString($fmt)
        }
    }
    [pscustomobject]@{ Chave = $chave; Nome = $a.Name; Desc = $desc }
}

$linhas = $itens | Sort-Object Chave, Nome | ForEach-Object { $_.Nome + '|' + $_.Desc }
[IO.File]::WriteAllLines($env:JV_ORDENADOS, [string[]]$linhas, (New-Object Text.UTF8Encoding($false)))
