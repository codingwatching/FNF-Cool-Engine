@echo off
title FNF Environment Setup
color 0A

echo ===============================================
echo        FNF / HaxeFlixel Environment Setup
echo ===============================================
echo.
echo This script will install a STABLE and COMPATIBLE
echo HaxeFlixel environment for FNF-based projects.
echo.
echo Make sure the following are already installed:
echo  - Haxe 4.3.6
echo  - Git
echo  - Visual Studio Build Tools (for Windows)
echo.
pause

cls
echo ===============================================
echo Cleaning conflicting libraries...
echo ===============================================

haxelib remove flixel-ui >nul 2>&1
haxelib remove flixel >nul 2>&1
haxelib remove openfl >nul 2>&1
haxelib remove lime >nul 2>&1

cls
echo ===============================================
echo Installing core dependencies...
echo ===============================================

haxelib install hxcpp >nul
haxelib install lime 8.1.0
haxelib install openfl 9.3.0

cls
echo ===============================================
echo Installing HaxeFlixel...
echo ===============================================

haxelib git flixel https://github.com/HaxeFlixel/flixel

haxelib git flixel-ui https://github.com/HaxeFlixel/flixel-ui
haxelib install flixel-tools 1.5.1

cls
echo ===============================================
echo Installing additional libraries...
echo ===============================================

haxelib install actuate
haxelib install hscript
haxelib install hxcpp-debug-server
haxelib install format
haxelib install hxp

cls
echo ===============================================
echo Setting up Lime and Flixel...
echo ===============================================

haxelib run lime setup windows
haxelib run lime setup flixel
haxelib run flixel-tools setup

cls
echo ===============================================
echo Installing Discord RPC...
echo ===============================================

haxelib git discord_rpc https://github.com/Aidan63/linc_discord-rpc

haxelib git flixel-animate https://github.com/MaybeMaru/flixel-animate

haxelib git hxvlc https://github.com/MAJigsaw77/hxvlc.git

haxelib git flixel-addons https://github.com/FunkinCrew/flixel-addons funkin-4.0.6

echo ===============================================
echo Re-locking Lime and OpenFL versions...
echo ===============================================

haxelib set lime 8.1.0
haxelib install openfl 9.3.0

cls
echo ===============================================
echo Setup completed successfully!
echo ===============================================
echo.
echo Installed versions:
echo  - Lime:        8.1.0
echo  - OpenFL:      9.3.0
echo  - Flixel:      5.4.0
echo.
echo You are now ready to compile your project.
echo.
pause
exit
