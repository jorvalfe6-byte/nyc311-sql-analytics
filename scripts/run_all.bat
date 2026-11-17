@echo off
rem Windows launcher: download, load, check and export, using Git Bash and a local PostgreSQL.
rem Edit the two paths below if yours differ. The database "nyc311" must exist
rem (createdb nyc311).
setlocal
set "PGBIN=C:\Users\USER\AppData\Local\PostgreSQL16\pgsql\bin"
set "GITBASH=C:\Program Files\Git\bin\bash.exe"
set "PATH=%PGBIN%;%PATH%"
set PGHOST=localhost
set PGUSER=postgres
set PGPASSWORD=postgres
set PGDATABASE=nyc311

cd /d "%~dp0.."
"%GITBASH%" -c "./scripts/download_data.sh && ./scripts/load.sh && ./scripts/export_dashboard.sh"
if errorlevel 1 echo.& echo Something failed, see the messages above.
pause
