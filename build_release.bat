@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
cd /d C:\Users\CyYu\Programs\DancherLink-qt
scripts\build-arch.bat Release x64
