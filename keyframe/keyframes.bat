@echo off
setlocal EnableExtensions

rem ====================================================================
rem  keyframes.bat - make SCXvid keyframe logs for Aegisub
rem
rem  Output: <video name>_keyframes.log, saved next to each video.
rem
rem  REQUIREMENTS
rem    ffmpeg.exe and SCXvid.exe must be either:
rem      - in your PATH, or
rem      - in the same folder as THIS .bat file
rem
rem  HOW TO USE WITH "SEND TO" (recommended)
rem    1. Put keyframes.bat, ffmpeg.exe and SCXvid.exe in one folder,
rem       e.g. C:\Tools\keyframes
rem    2. Press Win+R, type  shell:sendto  and press Enter.
rem    3. In the folder that opens, create a SHORTCUT to keyframes.bat
rem       (right-click keyframes.bat > Show more options > Create shortcut,
rem       then move the shortcut into the SendTo folder).
rem       Use a shortcut, not a copy of the .bat: a copy in SendTo would
rem       not find ffmpeg/SCXvid sitting in C:\Tools\keyframes.
rem       (If ffmpeg and SCXvid are already in PATH, copying the .bat
rem       itself into SendTo also works.)
rem    4. Right-click a video (or select several) > Show more options
rem       > Send to > keyframes.
rem    5. Wait for "All keyframes complete", then press any key.
rem
rem  OTHER WAYS
rem    - Drag one or more videos onto keyframes.bat
rem    - Command line: keyframes.bat "video1.mkv" "video2.mp4"
rem ====================================================================

set "PATH=%~dp0;%PATH%"

if "%~1"=="" (
    echo Usage: drag a video file onto this script, or run: keyframes.bat "video.mkv"
    pause
    exit /b 1
)

where ffmpeg >nul 2>nul
if errorlevel 1 (
    echo ERROR: ffmpeg not found. Put it in PATH or next to this script.
    pause
    exit /b 1
)

where SCXvid.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: SCXvid.exe not found. Put it in PATH or next to this script.
    pause
    exit /b 1
)

set "failed=0"

:loop
if "%~1"=="" goto done
call :process "%~1"
if errorlevel 1 set "failed=1"
shift
goto loop

:done
echo.
if "%failed%"=="1" (
    echo Finished with errors.
) else (
    echo All keyframes complete.
)
pause
exit /b %failed%


:process
setlocal
if not exist "%~1" (
    echo ERROR: file not found: %~1
    exit /b 1
)

set "log=%~dpn1_keyframes.log"
rem SCXvid is an old ANSI program and may choke on Vietnamese/Chinese filenames,
rem so write to an ASCII temp name first, then move to the final name.
set "tmplog=%TEMP%\scxvid_%RANDOM%%RANDOM%.log"

echo.
echo Making SCXvid keyframes for: %~nx1

ffmpeg -hide_banner -loglevel error -stats -i "%~1" -map 0:v:0 -an -sn -dn -vf scale=640:-2 -pix_fmt yuv420p -fps_mode passthrough -f yuv4mpegpipe - | SCXvid.exe "%tmplog%"

set "size=0"
if exist "%tmplog%" for %%A in ("%tmplog%") do set "size=%%~zA"
if "%size%"=="0" (
    echo ERROR: no keyframe log produced for %~nx1
    if exist "%tmplog%" del "%tmplog%"
    exit /b 1
)

move /y "%tmplog%" "%log%" >nul
if errorlevel 1 (
    echo ERROR: could not write %log%
    exit /b 1
)

echo Done: %log%
exit /b 0
