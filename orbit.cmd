@echo off
setlocal
set "ORBIT_APP=%~dp0"
if exist "%ORBIT_APP%app\backend\cli.py" set "ORBIT_APP=%ORBIT_APP%app\"
set "ORBIT_EXEC=python"
if exist "%ORBIT_APP%runtime\Scripts\python.exe" set "ORBIT_EXEC=%ORBIT_APP%runtime\Scripts\python.exe"
if defined ORBIT_PYTHON set "ORBIT_EXEC=%ORBIT_PYTHON%"
"%ORBIT_EXEC%" -u "%ORBIT_APP%backend\cli.py" %*
exit /b %errorlevel%
