#   Window's Sample Display Drivers.
#
#   High resolution resources
#   96 DPI

config.bin:    config.obj
    link config ,config;
    exe2bin config
    erase config.exe

config.obj:	config.asm
    masm -T config;

colortab.bin:  colortab.obj
    link colortab ,colortab;
    exe2bin colortab
    erase colortab.exe

colortab.obj:  colortab.asm
    masm -T colortab;

fonts.bin:	fonts.obj
    link fonts;
    exe2bin fonts
    erase fonts.exe

fonts.obj:	fonts.asm
    masm -T fonts;

