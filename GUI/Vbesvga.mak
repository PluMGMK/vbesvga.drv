#
# Borland C++ IDE generated makefile
# Generated 11/27/25 at 11:52:36 AM 
#
.AUTODEPEND


#
# Borland C++ tools
#
IMPLIB  = Implib
BCC     = Bcc +BccW16.cfg 
TLINK   = TLink
TLIB    = TLib
BRC     = Brc
TASM    = Tasm
#
# IDE macros
#


#
# Options
#
IDE_LinkFLAGS =  -LC:\BC5\LIB
IDE_ResFLAGS = 
LinkerLocalOptsAtW16_vbesvgadexe =  -Twe -C -c
ResLocalOptsAtW16_vbesvgadexe = 
BLocalOptsAtW16_vbesvgadexe = 
CompInheritOptsAt_vbesvgadexe = -I.\;C:\BC5\INCLUDE -DSTRICT;_OWLPCH;
LinkerInheritOptsAt_vbesvgadexe = -x
LinkerOptsAt_vbesvgadexe = $(LinkerLocalOptsAtW16_vbesvgadexe)
ResOptsAt_vbesvgadexe = $(ResLocalOptsAtW16_vbesvgadexe)
BOptsAt_vbesvgadexe = $(BLocalOptsAtW16_vbesvgadexe)

#
# Dependency List
#
Dep_Vbesvga = \
   vbesvga.exe

Vbesvga : BccW16.cfg $(Dep_Vbesvga)
  echo MakeNode

Dep_vbesvgadexe = \
   vbsvgapp.obj\
   vbsvgdlc.obj\
   vbsvgapp.res\
   vbsvgapp.def

vbesvga.exe : $(Dep_vbesvgadexe)
  $(TLINK)   @&&|
 /v $(IDE_LinkFLAGS) $(LinkerOptsAt_vbesvgadexe) $(LinkerInheritOptsAt_vbesvgadexe) +
C:\BC5\LIB\c0wl.obj+
vbsvgapp.obj+
vbsvgdlc.obj
$<,$*
C:\BC5\LIB\owlwl.lib+
C:\BC5\LIB\bidsl.lib+
C:\BC5\LIB\import.lib+
C:\BC5\LIB\mathwl.lib+
C:\BC5\LIB\cwl.lib
vbsvgapp.def
vbsvgapp.res

|
Dep_vbsvgappdobj = \
   vbsvgapp.h\
   vbsvgapp.cpp

vbsvgapp.obj : $(Dep_vbsvgappdobj)
  $(BCC)   -c @&&|
 $(CompOptsAt_vbesvgadexe) $(CompInheritOptsAt_vbesvgadexe) -o$@ vbsvgapp.cpp
|

Dep_vbsvgdlcdobj = \
   vbsvgdlc.h\
   vbsvgdlc.cpp

vbsvgdlc.obj : $(Dep_vbsvgdlcdobj)
  $(BCC)   -c @&&|
 $(CompOptsAt_vbesvgadexe) $(CompInheritOptsAt_vbesvgadexe) -o$@ vbsvgdlc.cpp
|

Dep_vbsvgappdres = \
   vbsvgapp.rh\
   vbsvgapp.rc

vbsvgapp.res : $(Dep_vbsvgappdres)
  $(BRC) -R @&&|
 $(IDE_ResFLAGS) $(ROptsAt_vbesvgadexe) $(CompInheritOptsAt_vbesvgadexe)  -FO$@ vbsvgapp.rc
|
# Compiler configuration file
BccW16.cfg : 
   Copy &&|
-w
-R
-v
-vi
-H
-H=Vbesvga.csm
-1-
-Fc-
-ml
-WS
-H"owl\pch.h"
| $@


