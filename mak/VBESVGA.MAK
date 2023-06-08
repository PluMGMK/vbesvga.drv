# File: VBESVGA.MAK - Makefile for VRAM Windows display driver.
# Date: 10/10/89
#
# The assembly of each individual module (and the linking phase) is performed
# using a response file instead of a simple command line. The reason for this
# is that the length of a command line used to invoke masm (and link) would
# be quite long due to a large number of commad line options. Since DOS is
# called to enter the command line, characters may be truncated. (DOS
# truncates input lines at approximately 128 characters.) Response files
# allow breaking down the command lines into manageable lengths so that no
# truncation occurs.
#
# 23 October 1991 - Steve Glickman
# Moved to subdirectory mak of ddk

DDK     = ..
MAK     = $(DDK)\mak            # VRAM driver make directory
SRC     = $(DDK)\src            # VRAM driver source directory
OBJ     = $(DDK)\obj            # VRAM driver objects directory
RES     = $(DDK)\res31          # VRAM driver resources directory
RES96   = $(DDK)\res96
TOOLDIR = $(DDK)\tools          # VRAM driver tools directory
TOOLS   =                       # with backslash, so blanking defaults to path

ASM     = $(TOOLS)masm                          # assembler
RASM    = $(TOOLS)masm -b63 -t -v -z            # assembler for resources
LNK     = $(TOOLS)link4                         # linker
X2B     = $(TOOLS)exe2bin
RC      = $(TOOLS)rc

INC     = -I$(DDK)\inc -I$(SRC)\ -I$(SRC)\inc   # additional include directories

ASMFLAGS = -B63 -v -ML 	                        # assmebler flags
ASMOPTS = -DPALETTES -DHIRES -DPROTECTEDMODE -DDEBUGAUX   # assembler options

NAME = VBESVGA

$(OBJ)\v31.obj:         $(SRC)\v31.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bblt.obj:        $(SRC)\bblt.asm         \
			$(SRC)\ropdefs.blt      \
			$(SRC)\roptable.blt     \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\blt216.obj:      $(SRC)\blt216.asm       \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\blt11.obj:       $(SRC)\blt11.asm                \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\blt18.obj:       $(SRC)\blt18.asm                \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\blt81.obj:       $(SRC)\blt81.asm                \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\blt88.obj:       $(SRC)\blt88.asm                \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bltstos.obj:     $(SRC)\bltstos.asm      \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bltpat.obj:      $(SRC)\bltpat.asm       \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\vgautil.obj:     $(SRC)\vgautil.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bltutil.obj:     $(SRC)\bltutil.asm      \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\compblt.obj:     $(SRC)\compblt.asm      \
			$(SRC)\inc\genconst.inc \
			$(SRC)\inc\bblt.inc     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bmc_eti.obj:     $(SRC)\bmc_eti.asm      \
			$(SRC)\bmc_main.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bmc_ite.obj:     $(SRC)\bmc_ite.asm      \
			$(SRC)\bmc_main.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bmc_main.obj:    $(SRC)\bmc_main.asm     \
			$(SRC)\bmc_main.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\buildstr.obj:    $(SRC)\buildstr.asm     \
			$(SRC)\inc\strblt.inc   \
			$(SRC)\inc\fontseg.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\charwdth.obj:    $(SRC)\charwdth.asm     \
			$(SRC)\inc\fontseg.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\chkstk.obj:      $(SRC)\chkstk.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\colorinf.obj:    $(SRC)\colorinf.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\control.obj:     $(SRC)\control.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\cursor.obj:      $(SRC)\cursor.asm $(SRC)\inc\cursor.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\swcurs.obj:      $(SRC)\swcurs.asm $(SRC)\inc\cursor.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\hwcurs.obj:      $(SRC)\hwcurs.asm $(SRC)\inc\cursor.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\dibsel.obj:      $(SRC)\dibsel.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\disable.obj:     $(SRC)\disable.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\discreen.obj:    $(SRC)\discreen.asm     \
			$(SRC)\inc\display.inc  \
			$(SRC)\inc\rlecom.inc   \
			$(SRC)\inc\rledat.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\dither.obj:      $(SRC)\dither.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\dithers.obj:     $(SRC)\dithers.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\egainit.obj:     $(SRC)\egainit.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\enable.obj:      $(SRC)\enable.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\enum.obj:                $(SRC)\enum.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\fb.obj:          $(SRC)\fb.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\getrle.obj:      $(SRC)\getrle.asm       \
			$(SRC)\inc\rledat.inc   \
			$(SRC)\bmc_main.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\inquire.obj:     $(SRC)\inquire.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\int10.obj:       $(SRC)\int10.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\pixel.obj:       $(SRC)\pixel.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\output.obj:      $(SRC)\output.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\polyline.obj:    $(SRC)\clip.asm         \
			$(SRC)\polybitm.asm     \
			$(SRC)\polyline.asm     \
			$(SRC)\polystyl.asm     \
			$(SRC)\inc\lines.inc    \
			$(SRC)\inc\polyline.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\rgb2ipc.obj:     $(SRC)\rgb2ipc.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\rld.obj:         $(SRC)\rld.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\rlecom.obj:      $(SRC)\rlecom.asm       \
			$(SRC)\inc\rledat.inc   \
			$(SRC)\bmc_main.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\rledat.obj:      $(SRC)\rledat.asm       \
			$(SRC)\inc\getrle.inc   \
			$(SRC)\inc\rlecom.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\robject.obj:     $(SRC)\robject.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\scanline.obj:    $(SRC)\scanline.asm     \
			$(SRC)\inc\scanmono.inc \
			$(SRC)\inc\scancolo.inc \
			$(SRC)\inc\pattern.inc  \
			$(SRC)\inc\sl216.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\scanlr.obj:      $(SRC)\scanlr.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\setmode.obj:     $(SRC)\setmode.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\smartpro.obj:    $(SRC)\smartpro.asm     \
			$(SRC)\inc\strblt.inc   \
			$(SRC)\inc\fontseg.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\sswitch.obj:     $(SRC)\sswitch.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\strblt.obj:      $(SRC)\strblt.asm       \
			$(SRC)\inc\strblt.inc   \
			$(SRC)\inc\fontseg.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\stretch.obj:     $(SRC)\stretch.asm      \
			$(SRC)\inc\display.inc  \
			$(SRC)\inc\cursor.inc   \
			$(SRC)\macros.mac       \
			$(SRC)\njumps.mac       \
			$(SRC)\devconst.blt     \
			$(SRC)\bitblt.var
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\trn_pal.obj:     $(SRC)\trn_pal.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\vgastate.obj:    $(SRC)\vgastate.asm     \
			$(SRC)\inc\bank.inc
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\vesafns.obj:     $(SRC)\vesafns.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\vesafns      > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\vgavram.obj:     $(SRC)\vga.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\vga      > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\3xswitch.obj:    $(SRC)\3xswitch.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak

$(OBJ)\bs216.obj:       $(SRC)\bs216.asm
			echo $(ASMFLAGS) $(INC) $(SRC)\$* > vrammak
			echo $(ASMOPTS) $(OBJ)\$*.obj; >> vrammak
			$(ASM) < vrammak


$(RES)\config.bin:      $(RES)\$*.asm
	cd $(RES)
	$(RASM) $*;
	$(LNK) $*;
	del $*.obj
	$(X2B) $*
	del $*.exe
	cd $(MAK)

$(RES)\colortab.bin:    $(RES)\$*.asm
	cd $(RES)
	$(RASM) $*;
	$(LNK) $*;
	del $*.obj
	$(X2B) $*
	del $*.exe
	cd $(MAK)

$(RES)\fonts.bin:       $(RES)\$*.asm
	cd $(RES)
	$(RASM) $*;
	$(LNK) $*;
	del $*.obj
	$(X2B) $*
	del $*.exe
	cd $(MAK)

$(RES96)\config.bin:    $(RES96)\$*.asm
	cd $(RES96)
	$(RASM) $*;
	$(LNK) $*;
	del $*.obj
	$(X2B) $*
	del $*.exe
	cd $(MAK)

$(RES96)\fonts.bin:     $(RES96)\$*.asm
	cd $(RES96)
	$(RASM) $*;
	$(LNK) $*;
	del $*.obj
	$(X2B) $*
	del $*.exe
	cd $(MAK)

$(RES)\drv256.res:      $(RES)\drv256.rc        \
		$(RES)\config.bin       \
		$(RES)\colortab.bin     \
		$(RES)\fonts.bin        \
		$(RES)\combo.bmp        \
		$(RES)\down.bmp         \
		$(RES)\downd.bmp        \
		$(RES)\downi.bmp        \
		$(RES)\left.bmp         \
		$(RES)\leftd.bmp        \
		$(RES)\lefti.bmp        \
		$(RES)\max.bmp          \
		$(RES)\maxd.bmp         \
		$(RES)\min.bmp          \
		$(RES)\mind.bmp         \
		$(RES)\mnarrow.bmp      \
		$(RES)\obtncorn.bmp     \
		$(RES)\obtsize.bmp      \
		$(RES)\obutton.bmp      \
		$(RES)\ocheck.bmp       \
		$(RES)\oclose.bmp       \
		$(RES)\odown.bmp        \
		$(RES)\oleft.bmp        \
		$(RES)\ored.bmp         \
		$(RES)\orest.bmp        \
		$(RES)\oright.bmp       \
		$(RES)\osize.bmp        \
		$(RES)\oup.bmp          \
		$(RES)\ozoom.bmp        \
		$(RES)\restore.bmp      \
		$(RES)\restored.bmp     \
		$(RES)\right.bmp        \
		$(RES)\rightd.bmp       \
		$(RES)\righti.bmp       \
		$(RES)\sysmenu.bmp      \
		$(RES)\up.bmp           \
		$(RES)\upd.bmp          \
		$(RES)\upi.bmp          \
		$(RES)\cross.cur        \
		$(RES)\ibeam.cur        \
		$(RES)\icon.cur         \
		$(RES)\normal.cur       \
		$(RES)\size.cur         \
		$(RES)\sizenesw.cur     \
		$(RES)\sizens.cur       \
		$(RES)\sizenwse.cur     \
		$(RES)\sizewe.cur       \
		$(RES)\up.cur           \
		$(RES)\wait.cur         \
		$(RES)\bang.ico         \
		$(RES)\hand.ico         \
		$(RES)\note.ico         \
		$(RES)\ques.ico         \
		$(RES)\sample.ico       \
		$(RES)\96dpi.h          \
		$(RES96)\config.bin     \
		$(RES96)\fonts.bin      \
		$(RES96)\orest.bmp      \
		$(RES96)\ored.bmp       \
		$(RES96)\ozoom.bmp      \
		$(RES96)\oright.bmp     \
		$(RES96)\oleft.bmp      \
		$(RES96)\oup.bmp        \
		$(RES96)\odown.bmp      \
		$(RES96)\oclose.bmp     \
		$(RES96)\restore.bmp    \
		$(RES96)\restored.bmp   \
		$(RES96)\min.bmp        \
		$(RES96)\mind.bmp       \
		$(RES96)\max.bmp        \
		$(RES96)\maxd.bmp       \
		$(RES96)\right.bmp      \
		$(RES96)\rightd.bmp     \
		$(RES96)\left.bmp       \
		$(RES96)\leftd.bmp      \
		$(RES96)\up.bmp         \
		$(RES96)\upd.bmp        \
		$(RES96)\down.bmp       \
		$(RES96)\downd.bmp      \
		$(RES96)\sysmenu.bmp    \
		$(RES96)\ocheck.bmp     \
		$(RES96)\obtsize.bmp    \
		$(RES96)\osize.bmp      \
		$(RES96)\obutton.bmp    \
		$(RES96)\obtncorn.bmp   \
		$(RES96)\combo.bmp      \
		$(RES96)\mnarrow.bmp    \
		$(RES96)\upi.bmp        \
		$(RES96)\downi.bmp      \
		$(RES96)\lefti.bmp      \
		$(RES96)\righti.bmp     \
###             $(RES)\ver.h            \
		$(RES)\vbesvga.rcv
	cd $(RES)
	$(RC) $(RCFLAGS) -r drv256.rc drv256.res
	cd $(MAK)

$(NAME).drv:    $(OBJ)\v31.obj          \
		$(OBJ)\bblt.obj         \
		$(OBJ)\blt216.obj       \
		$(OBJ)\blt11.obj        \
		$(OBJ)\blt18.obj        \
		$(OBJ)\blt81.obj        \
		$(OBJ)\blt88.obj        \
		$(OBJ)\bltstos.obj      \
		$(OBJ)\bltpat.obj       \
		$(OBJ)\vgautil.obj      \
		$(OBJ)\bltutil.obj      \
		$(OBJ)\compblt.obj      \
		$(OBJ)\bmc_eti.obj      \
		$(OBJ)\bmc_ite.obj      \
		$(OBJ)\bmc_main.obj     \
		$(OBJ)\buildstr.obj     \
		$(OBJ)\charwdth.obj     \
		$(OBJ)\chkstk.obj       \
		$(OBJ)\colorinf.obj     \
		$(OBJ)\control.obj      \
		$(OBJ)\cursor.obj       \
		$(OBJ)\swcurs.obj       \
		$(OBJ)\hwcurs.obj       \
		$(OBJ)\dibsel.obj       \
		$(OBJ)\disable.obj      \
		$(OBJ)\discreen.obj     \
		$(OBJ)\dither.obj       \
		$(OBJ)\dithers.obj      \
		$(OBJ)\egainit.obj      \
		$(OBJ)\enable.obj       \
		$(OBJ)\enum.obj         \
		$(OBJ)\fb.obj           \
		$(OBJ)\getrle.obj       \
		$(OBJ)\inquire.obj      \
		$(OBJ)\int10.obj        \
		$(OBJ)\pixel.obj        \
		$(OBJ)\output.obj       \
		$(OBJ)\polyline.obj     \
		$(OBJ)\rgb2ipc.obj      \
		$(OBJ)\rld.obj          \
		$(OBJ)\rlecom.obj       \
		$(OBJ)\rledat.obj       \
		$(OBJ)\robject.obj      \
		$(OBJ)\scanline.obj     \
		$(OBJ)\scanlr.obj       \
		$(OBJ)\setmode.obj      \
		$(OBJ)\smartpro.obj     \
		$(OBJ)\sswitch.obj      \
		$(OBJ)\strblt.obj       \
		$(OBJ)\stretch.obj      \
		$(OBJ)\trn_pal.obj      \
		$(OBJ)\vesafns.obj      \
		$(OBJ)\vgastate.obj     \
		$(OBJ)\vgavram.obj      \
		$(OBJ)\3xswitch.obj     \
		$(OBJ)\bs216.obj        \
		$(MAK)\vbesvga.def      \
		$(RES)\drv256.res
	copy vbesvga.def $(OBJ)
	copy lnkcmd31 $(OBJ)
	cd $(OBJ)
	del display.drv
	del display.map
	$(LNK) @lnkcmd31
	del vbesvga.def
	del lnkcmd31
	copy display.map $(MAK)
	copy display.drv $(MAK)
	del display.map
	del display.drv
	cd $(MAK)
	$(RC) $(RES)\drv256.res display.drv
	$(TOOLS)mapsym display
	if exist $(NAME).drv erase $(NAME).drv
	if exist $(NAME).map erase $(NAME).map
	if exist $(NAME).sym erase $(NAME).sym
	ren display.drv $(NAME).drv
	ren display.map $(NAME).map
	ren display.sym $(NAME).sym
