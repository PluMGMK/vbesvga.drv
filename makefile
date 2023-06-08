v7vga:  src

# Build modes. OFFICIAL is set only by the official builder
#              FINAL is set only for the final ship version.
!ifdef OFFICIAL
RCOFF=-DOFFICIAL
!endif
!ifdef FINAL
RCFINAL=-DFINAL
!endif



src:
        cd mak
        make RCFLAGS="$(RCOFF) $(RCFINAL)" v731vga.mak
        cd ..
