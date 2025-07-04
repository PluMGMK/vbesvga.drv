#!/bin/bash
set -e

# Go to where the script resides
unset CDPATH
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

# Usage explanation
echo
echo This script is written to create and package release
echo builds of the three components of this project, i.e.
echo VBESVGA.DRV, VDDVBE.386 and VBEVMDIB.3GR
echo
echo To do so, it requires the following:
echo - A working dosbox in your PATH
echo - The full Win16 DDK directory hierarchy at:
echo   $(pwd)/WIN16DDK
echo - The full Visual C++ 1.5 directory hierarchy at:
echo   $(pwd)/MSVC
echo - A copy of EXE2BIN.EXE at:
echo   $(pwd)/EXE2BIN.EXE
echo

# Check that everything is present...
which dosbox > /dev/null
if [ ! -e EXE2BIN.EXE ]; then
	echo EXE2BIN.EXE not present, cannot continue
	exit 1
fi
if [ ! -d MSVC ]; then
	echo MSVC directory not present, cannot continue
	exit 1
fi
if [ ! -d WIN16DDK ]; then
	echo WIN16DDK directory not present, cannot continue
	exit 1
fi

# Symlink the driver components into the hierarchy and create
# non-debug versions of the makefiles...
rm -rfv WIN16DDK/286/DISPLAY/8PLANE/VBESVGA
ln -sfnv ../../../../../VBESVGA WIN16DDK/286/DISPLAY/8PLANE/VBESVGA
sed 's/-DDEBUGAUX/\#\0/' WIN16DDK/286/DISPLAY/8PLANE/VBESVGA/mak/VBESVGA.MAK > WIN16DDK/286/DISPLAY/8PLANE/VBESVGA/mak/VBESREL.MAK

rm -rfv WIN16DDK/386/VDDVBE
ln -sfnv ../../../VDDVBE WIN16DDK/386/VDDVBE
sed '/^Debug=/d' WIN16DDK/386/VDDVBE/MAKEFILE > WIN16DDK/386/VDDVBE/MAKEREL

rm -rfv WIN16DDK/386/VBEGRAB
ln -sfnv ../../../VBEGRAB WIN16DDK/386/VBEGRAB
sed '/^Debug=/d' WIN16DDK/386/VBEGRAB/MAKEFILE > WIN16DDK/386/VBEGRAB/MAKEREL

# Run DOSBox to do the building - include "pause" after each stage
# to make sure we catch any issues...
cat > BUILDREL.BAT <<EOF
mount c .
c:
PATH C:\\;C:\\WIN16DDK\\286\\TOOLS;C:\\WIN16DDK\\386\\TOOLS
set INCLUDE=C:\\WIN16DDK\\286\\INC;C:\\WIN16DDK\\386\\INCLUDE
call c:\\msvc\\bin\\msvcvars.bat

cd c:\\WIN16DDK\\286\\DISPLAY\\8PLANE\\VBESVGA\\mak
make vbesrel.mak
pause

cd c:\\WIN16DDK\\386\\VDDVBE
nmake -f makerel
pause

cd c:\\WIN16DDK\\386\\VBEGRAB
nmake -f makerel
pause

EOF
dosbox -noautoexec ./BUILDREL.BAT -exit
rm -v BUILDREL.BAT

# Move the built files into one place
mv -v WIN16DDK/286/DISPLAY/8PLANE/VBESVGA/mak/VBESVGA.DRV .
mv -v WIN16DDK/386/VDDVBE/VDDVBE.386 .
mv -v WIN16DDK/386/VBEGRAB/VBEVMDIB.3GR .

# Grab the syms for the release builds too...
mkdir -pv relsyms
mv -v WIN16DDK/286/DISPLAY/8PLANE/VBESVGA/mak/VBESVGA.SYM relsyms
mv -v WIN16DDK/386/VDDVBE/VDDVBE.SYM relsyms
mv -v WIN16DDK/386/VBEGRAB/VBEVMDIB.SYM relsyms

# Build the tools as well
jwasm -bin ../AUXSTACK.ASM
mv -v AUXSTACK.BIN AUXSTACK.COM
jwasm -bin ../VIDMODES.ASM
mv -v VIDMODES.BIN VIDMODES.COM
jwasm -bin ../SETUP.ASM
mv -v SETUP.BIN SETUP.EXE # !

# Zip it all up
zip -u -9 vbesvga-release.zip VBESVGA.DRV VDDVBE.386 VBEVMDIB.3GR AUXSTACK.COM VIDMODES.COM SETUP.EXE

# Make a debug ZIP too (for my own setup)
if [ -x make-debug.sh ]; then
	./make-debug.sh
fi
