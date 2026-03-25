@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
cd /d C:\Users\CyYu\Programs\DancherLink-qt\build\build-x64-release
ninja app/CMakeFiles/DancherLink.dir/utils/latencymeasurer.cpp.obj
