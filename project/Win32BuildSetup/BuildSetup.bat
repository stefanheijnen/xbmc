@ECHO OFF
SETLOCAL ENABLEDELAYEDEXPANSION
REM setup all paths
SET cur_dir=%CD%
SET base_dir=%cur_dir%\..\..
SET builddeps_dir=%cur_dir%\..\..\project\BuildDependencies
SET bin_dir=%builddeps_dir%\bin
SET msys_dir=%builddeps_dir%\msys64
IF NOT EXIST %msys_dir% (SET msys_dir=%builddeps_dir%\msys32)
SET awk_exe=%msys_dir%\usr\bin\awk.exe
SET sed_exe=%msys_dir%\usr\bin\sed.exe

REM read the version values from version.txt
FOR /f %%i IN ('%awk_exe% "/APP_NAME/ {print $2}" %base_dir%\version.txt') DO SET APP_NAME=%%i
FOR /f %%i IN ('%awk_exe% "/COMPANY_NAME/ {print $2}" %base_dir%\version.txt') DO SET COMPANY_NAME=%%i
FOR /f %%i IN ('%awk_exe% "/WEBSITE/ {print $2}" %base_dir%\version.txt') DO SET WEBSITE=%%i
FOR /f %%i IN ('%awk_exe% "/VERSION_MAJOR/ {print $2}" %base_dir%\version.txt') DO SET MAJOR=%%i
FOR /f %%i IN ('%awk_exe% "/VERSION_MINOR/ {print $2}" %base_dir%\version.txt') DO SET MINOR=%%i
FOR /f %%i IN ('%awk_exe% "/VERSION_TAG/ {print $2}" %base_dir%\version.txt') DO SET TAG=%%i
FOR /f %%i IN ('%awk_exe% "/ADDON_API/ {print $2}" %base_dir%\version.txt') DO SET VERSION_NUMBER=%%i.0

SET APP_VERSION=%MAJOR%.%MINOR%
IF NOT [%TAG%] == [] (
  SET APP_VERSION=%APP_VERSION%-%TAG%
)

rem ----Usage----
rem BuildSetup [clean|noclean]
rem clean to force a full rebuild
rem noclean to force a build without clean
rem noprompt to avoid all prompts
rem nomingwlibs to skip building all libs built with mingw
rem cmake to build with cmake instead of VS solution
CLS
COLOR 1B
TITLE %APP_NAME% for Windows Build Script
rem ----PURPOSE----
rem - Create a working application build with a single click
rem -------------------------------------------------------------
rem Config
rem If you get an error that Visual studio was not found, SET your path for VSNET main executable.
rem -------------------------------------------------------------
rem  CONFIG START
SET buildmode=ask
SET promptlevel=prompt
SET buildmingwlibs=true
SET buildbinaryaddons=true
SET exitcode=0
SET useshell=rxvt
SET cmake=0
SET BRANCH=na
FOR %%b in (%1, %2, %3, %4, %5, %6) DO (
  IF %%b==clean SET buildmode=clean
  IF %%b==noclean SET buildmode=noclean
  IF %%b==noprompt SET promptlevel=noprompt
  IF %%b==nomingwlibs SET buildmingwlibs=false
  IF %%b==nobinaryaddons SET buildbinaryaddons=false
  IF %%b==sh SET useshell=sh
  IF %%b==cmake SET cmake=1
)

SET buildconfig=Release
set WORKSPACE=%CD%\..\..


  REM look for MSBuild.exe delivered with Visual Studio 2015
  FOR /F "tokens=2,* delims= " %%A IN ('REG QUERY HKLM\SOFTWARE\Microsoft\MSBuild\ToolsVersions\14.0 /v MSBuildToolsRoot') DO SET MSBUILDROOT=%%B
  SET NET="%MSBUILDROOT%14.0\bin\MSBuild.exe"

  IF EXIST "!NET!" (
    set msbuildemitsolution=1
    set OPTS_EXE="..\VS2010Express\XBMC for Windows.sln" /t:Build /p:Configuration="%buildconfig%" /property:VCTargetsPath="%MSBUILDROOT%Microsoft.Cpp\v4.0\V140" /m
    set CLEAN_EXE="..\VS2010Express\XBMC for Windows.sln" /t:Clean /p:Configuration="%buildconfig%" /property:VCTargetsPath="%MSBUILDROOT%Microsoft.Cpp\v4.0\V140"
  )

  IF NOT EXIST %NET% (
    set DIETEXT=MSBuild was not found.
    goto DIE
  )
  
  set EXE= "..\VS2010Express\XBMC\%buildconfig%\%APP_NAME%.exe"
  set PDB= "..\VS2010Express\XBMC\%buildconfig%\%APP_NAME%.pdb"
  set D3D= "..\VS2010Express\XBMC\%buildconfig%\D3DCompile*.DLL"
  
  :: sets the BRANCH env var
  call getbranch.bat

  rem  CONFIG END
  rem -------------------------------------------------------------
  goto EXE_COMPILE

:EXE_COMPILE
  IF EXIST buildlog.html del buildlog.html /q
  IF NOT %buildmode%==ask goto COMPILE_MINGW
  IF %promptlevel%==noprompt goto COMPILE_MINGW
  rem ---------------------------------------------
  rem  check for existing exe
  rem ---------------------------------------------
  set buildmode=clean
  
  IF NOT EXIST %EXE% goto COMPILE_MINGW
  
  ECHO ------------------------------------------------------------
  ECHO Found a previous Compiled WIN32 EXE!
  ECHO [1] a NEW EXE will be compiled for the BUILD_WIN32
  ECHO [2] existing EXE will be updated (quick mode compile) for the BUILD_WIN32
  ECHO ------------------------------------------------------------
  set /P APP_COMPILE_ANSWER=Compile a new EXE? [1/2]:
  if /I %APP_COMPILE_ANSWER% EQU 1 set buildmode=clean
  if /I %APP_COMPILE_ANSWER% EQU 2 set buildmode=noclean

  goto COMPILE_MINGW
  

:COMPILE_MINGW
  ECHO Buildmode = %buildmode%
  IF %buildmingwlibs%==true (
    ECHO Compiling mingw libs
    ECHO bla>noprompt
    IF EXIST errormingw del errormingw > NUL
    IF %buildmode%==clean (
      ECHO bla>makeclean
    )
    rem only use sh to please jenkins
    IF %useshell%==sh (
      call ..\..\tools\buildsteps\win32\make-mingwlibs.bat sh noprompt %buildmode%
    ) ELSE (
      call ..\..\tools\buildsteps\win32\make-mingwlibs.bat noprompt %buildmode%
    )
    IF EXIST errormingw (
      set DIETEXT="failed to build mingw libs"
      goto DIE
    )
  )
  IF %cmake%==1 goto COMPILE_CMAKE_EXE
  IF %buildmode%==clean goto COMPILE_EXE
  goto COMPILE_NO_CLEAN_EXE
  
  
:COMPILE_EXE
  ECHO Wait while preparing the build.
  ECHO ------------------------------------------------------------
  ECHO Cleaning Solution...
  %NET% %CLEAN_EXE%
  ECHO Compiling %APP_NAME% branch %BRANCH%...
  %NET% %OPTS_EXE%
  IF %errorlevel%==1 (
    set DIETEXT="%APP_NAME%.EXE failed to build!  See %CD%\..\vs2010express\XBMC\%buildconfig%\objs\XBMC.log"
    IF %promptlevel%==noprompt (
      type "%CD%\..\vs2010express\XBMC\%buildconfig%\objs\XBMC.log"
    )
    goto DIE
  )
  ECHO Done!
  ECHO ------------------------------------------------------------
  set buildmode=clean
  GOTO MAKE_BUILD_EXE
  
:COMPILE_NO_CLEAN_EXE
  ECHO Wait while preparing the build.
  ECHO ------------------------------------------------------------
  ECHO Compiling %APP_NAME% branch %BRANCH%...
  %NET% %OPTS_EXE%
  IF %errorlevel%==1 (
    set DIETEXT="%APP_NAME%.EXE failed to build!  See %CD%\..\vs2010express\XBMC\%buildconfig%\objs\XBMC.log"
    IF %promptlevel%==noprompt (
      type "%CD%\..\vs2010express\XBMC\%buildconfig%\objs\XBMC.log"
    )
    goto DIE
  )
  ECHO Done!
  ECHO ------------------------------------------------------------
  GOTO MAKE_BUILD_EXE


:COMPILE_CMAKE_EXE
  ECHO Wait while preparing the build.
  ECHO ------------------------------------------------------------
  ECHO Compiling %APP_NAME% branch %BRANCH%...

  IF %buildmode%==clean (
    RMDIR /S /Q %WORKSPACE%\kodi-build
  )
  MKDIR %WORKSPACE%\kodi-build
  PUSHD %WORKSPACE%\kodi-build

  cmake.exe -G "Visual Studio 14" %WORKSPACE%\project\cmake
  IF %errorlevel%==1 (
    set DIETEXT="%APP_NAME%.EXE failed to build!"
    goto DIE
  )

  cmake.exe --build . --config "%buildconfig%"
  IF %errorlevel%==1 (
    set DIETEXT="%APP_NAME%.EXE failed to build!"
    goto DIE
  )

  set EXE="%WORKSPACE%\kodi-build\%buildconfig%\%APP_NAME%.exe"
  set PDB="%WORKSPACE%\kodi-build\%buildconfig%\%APP_NAME%.pdb"
  set D3D="%WORKSPACE%\kodi-build\D3DCompile*.DLL"

  POPD
  ECHO Done!
  ECHO ------------------------------------------------------------
  GOTO MAKE_BUILD_EXE


:MAKE_BUILD_EXE
  ECHO Copying files...
  IF EXIST BUILD_WIN32 rmdir BUILD_WIN32 /S /Q
  rem Add files to exclude.txt that should not be included in the installer
  
  Echo Thumbs.db>>exclude.txt
  Echo Desktop.ini>>exclude.txt
  Echo dsstdfx.bin>>exclude.txt
  Echo exclude.txt>>exclude.txt
  Echo xbmc.log>>exclude.txt
  Echo xbmc.old.log>>exclude.txt
  Echo kodi.log>>exclude.txt
  Echo kodi.old.log>>exclude.txt
  rem Exclude userdata files
  Echo userdata\advancedsettings.xml>>exclude.txt
  Echo userdata\guisettings.xml>>exclude.txt
  Echo userdata\mediasources.xml>>exclude.txt
  Echo userdata\ModeLines_template.xml>>exclude.txt
  Echo userdata\passwords.xml>>exclude.txt
  Echo userdata\profiles.xml>>exclude.txt
  Echo userdata\sources.xml>>exclude.txt
  Echo userdata\upnpserver.xml>>exclude.txt
  rem Exclude userdata folders
  Echo userdata\addon_data\>>exclude.txt
  Echo userdata\cache\>>exclude.txt
  Echo userdata\database\>>exclude.txt
  Echo userdata\playlists\>>exclude.txt
  Echo userdata\thumbnails\>>exclude.txt
  rem Exclude skins as they're copied by their own script
  Echo addons\skin.estuary\>>exclude.txt
  Echo addons\skin.estouchy\>>exclude.txt

  rem Exclude dlls from system to avoid duplicates
  Echo .dll>>exclude_dll.txt
  
  md BUILD_WIN32\application

  xcopy %EXE% BUILD_WIN32\application > NUL
  xcopy %D3D% BUILD_WIN32\application > NUL
  xcopy ..\..\userdata BUILD_WIN32\application\userdata /E /Q /I /Y /EXCLUDE:exclude.txt > NUL
  copy ..\..\copying.txt BUILD_WIN32\application > NUL
  copy ..\..\LICENSE.GPL BUILD_WIN32\application > NUL
  copy ..\..\known_issues.txt BUILD_WIN32\application > NUL
  xcopy dependencies\*.* BUILD_WIN32\application /Q /I /Y /EXCLUDE:exclude.txt  > NUL

  xcopy ..\..\addons BUILD_WIN32\application\addons /E /Q /I /Y /EXCLUDE:exclude.txt > NUL
  xcopy ..\..\system\*.dll BUILD_WIN32\application /E /Q /I /Y /EXCLUDE:exclude.txt > NUL
  xcopy ..\..\system BUILD_WIN32\application\system /E /Q /I /Y /EXCLUDE:exclude.txt+exclude_dll.txt  > NUL
  xcopy ..\..\media BUILD_WIN32\application\media /E /Q /I /Y /EXCLUDE:exclude.txt  > NUL

  REM create AppxManifest.xml
  "%sed_exe%" -e s/@APP_NAME@/%APP_NAME%/g -e s/@COMPANY_NAME@/%COMPANY_NAME%/g -e s/@APP_VERSION@/%APP_VERSION%/g -e s/@VERSION_NUMBER@/%VERSION_NUMBER%/g "AppxManifest.xml.in" > "BUILD_WIN32\application\AppxManifest.xml"

  SET build_path=%CD%
  IF %buildbinaryaddons%==true (
    ECHO ------------------------------------------------------------
    ECHO Building addons...
    cd ..\..\tools\buildsteps\win32
    IF %buildmode%==clean (
      call make-addons.bat clean
    )
    call make-addons.bat
    IF %errorlevel%==1 (
      set DIETEXT="failed to build addons"
      cd %build_path%
      goto DIE
    )

    cd %build_path%
    IF EXIST error.log del error.log > NUL
  )

  ECHO ------------------------------------------------------------
  ECHO Building Estuary Skin...
  cd ..\..\addons\skin.estuary
  call build.bat > NUL
  cd %build_path%

  ECHO Building Estouchy Skin...
  cd ..\..\addons\skin.estouchy
  call build.bat > NUL
  cd %build_path%
  
  rem restore color and title, some scripts mess these up
  COLOR 1B
  TITLE %APP_NAME% for Windows Build Script

  IF EXIST exclude.txt del exclude.txt  > NUL
  del /s /q /f BUILD_WIN32\application\*.so  > NUL
  del /s /q /f BUILD_WIN32\application\*.h  > NUL
  del /s /q /f BUILD_WIN32\application\*.cpp  > NUL
  del /s /q /f BUILD_WIN32\application\*.exp  > NUL
  del /s /q /f BUILD_WIN32\application\*.lib  > NUL
  
  ECHO ------------------------------------------------------------
  ECHO Build Succeeded!
  GOTO NSIS_EXE

:NSIS_EXE
  ECHO ------------------------------------------------------------
  ECHO Generating installer includes...
  call genNsisIncludes.bat
  ECHO ------------------------------------------------------------
  call getdeploydependencies.bat
  CALL extract_git_rev.bat > NUL
  SET APP_SETUPFILE=%APP_NAME%Setup-%GIT_REV%-%BRANCH%.exe
  SET APP_PDBFILE=%APP_NAME%Setup-%GIT_REV%-%BRANCH%.pdb
  ECHO Creating installer %APP_SETUPFILE%...
  IF EXIST %APP_SETUPFILE% del %APP_SETUPFILE% > NUL
  rem get path to makensis.exe from registry, first try tab delim
  FOR /F "tokens=2* delims=  " %%A IN ('REG QUERY "HKLM\Software\NSIS" /ve') DO SET NSISExePath=%%B

  IF NOT EXIST "%NSISExePath%" (
    rem try with space delim instead of tab
    FOR /F "tokens=2* delims= " %%A IN ('REG QUERY "HKLM\Software\NSIS" /ve') DO SET NSISExePath=%%B
  )
      
  IF NOT EXIST "%NSISExePath%" (
    rem fails on localized windows (Default) becomes (Par D�faut)
    FOR /F "tokens=3* delims=  " %%A IN ('REG QUERY "HKLM\Software\NSIS" /ve') DO SET NSISExePath=%%B
  )

  IF NOT EXIST "%NSISExePath%" (
    FOR /F "tokens=3* delims= " %%A IN ('REG QUERY "HKLM\Software\NSIS" /ve') DO SET NSISExePath=%%B
  )
  
  rem proper x64 registry checks
  IF NOT EXIST "%NSISExePath%" (
    ECHO using x64 registry entries
    FOR /F "tokens=2* delims=  " %%A IN ('REG QUERY "HKLM\Software\Wow6432Node\NSIS" /ve') DO SET NSISExePath=%%B
  )
  IF NOT EXIST "%NSISExePath%" (
    rem try with space delim instead of tab
    FOR /F "tokens=2* delims= " %%A IN ('REG QUERY "HKLM\Software\Wow6432Node\NSIS" /ve') DO SET NSISExePath=%%B
  )
  IF NOT EXIST "%NSISExePath%" (
    rem on win 7 x64, the previous fails
    FOR /F "tokens=3* delims=  " %%A IN ('REG QUERY "HKLM\Software\Wow6432Node\NSIS" /ve') DO SET NSISExePath=%%B
  )
  IF NOT EXIST "%NSISExePath%" (
    rem try with space delim instead of tab
    FOR /F "tokens=3* delims= " %%A IN ('REG QUERY "HKLM\Software\Wow6432Node\NSIS" /ve') DO SET NSISExePath=%%B
  )

  SET NSISExe=%NSISExePath%\makensis.exe
  "%NSISExe%" /V1 /X"SetCompressor /FINAL lzma" /Dapp_root="%CD%\BUILD_WIN32" /DAPP_NAME="%APP_NAME%" /DVERSION_NUMBER="%VERSION_NUMBER%" /DCOMPANY_NAME="%COMPANY_NAME%" /DWEBSITE="%WEBSITE%" /Dapp_revision="%GIT_REV%" /Dapp_target="%target%" /Dapp_branch="%BRANCH%" "genNsisInstaller.nsi"
  IF NOT EXIST "%APP_SETUPFILE%" (
    set DIETEXT=Failed to create %APP_SETUPFILE%. NSIS installed?
    goto DIE
  )
  copy %PDB% %APP_PDBFILE% > nul
  ECHO ------------------------------------------------------------
  ECHO Done!
  ECHO Setup is located at %CD%\%APP_SETUPFILE%
  ECHO ------------------------------------------------------------
  GOTO VIEWLOG_EXE
  
:DIE
  ECHO ------------------------------------------------------------
  ECHO !-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-
  ECHO    ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR ERROR
  ECHO !-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-!-
  set DIETEXT=ERROR: %DIETEXT%
  echo %DIETEXT%
  SET exitcode=1
  ECHO ------------------------------------------------------------
  GOTO END

:VIEWLOG_EXE
  SET log="%CD%\..\vs2010express\XBMC\%buildconfig%\objs\XBMC.log"
  IF NOT EXIST %log% goto END
  
  copy %log% ./buildlog.html > NUL

  IF %promptlevel%==noprompt (
    goto END
  )

  set /P APP_BUILD_ANSWER=View the build log in your HTML browser? [y/n]
  if /I %APP_BUILD_ANSWER% NEQ y goto END
  
  SET log="%CD%\..\vs2010express\XBMC\%buildconfig%\objs\" XBMC.log
  
  start /D%log%
  goto END

:END
  IF %promptlevel% NEQ noprompt (
    ECHO Press any key to exit...
    pause > NUL
  )
  EXIT /B %exitcode%
