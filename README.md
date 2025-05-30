# vbesvga.drv and vddvbe.386
Modern Generic SVGA driver for Windows 3.1

This is a rewrite of the Windows 3.1 SVGA driver, designed to support **ALL** available 8-bit, 16-bit, 24-bit or 32-bit graphic modes on any system providing the [VESA BIOS Extensions](https://en.wikipedia.org/wiki/VESA_BIOS_Extensions) (hence the `VBE` in the name). It is based on the Video 7 SVGA driver included in the [Win16 Driver Development Kit](http://www.win3x.org/win3board/viewtopic.php?t=2776), with most of the hardware-specific code gutted out, and with support added for multi-byte pixels.

## Why on Earth did I make such a thing?

* To demonstrate that it's possible to run Windows 3.1 in True-Colour Full HD
* Because my AMD Radeon RX 5500 XT doesn't support 256-colour modes, rendering the old [VESA Patch](http://www.win3x.org/win3board/viewtopic.php?t=5408&hilit=svga) useless for me
* To help out any fellow enthusiasts who like running old software on new hardware!

## Limitations in Windows programs / components

### Program Manager icons

When using high-colour modes, Program Manager may complain that there is not enough memory to convert all the icons. There is nothing I can do about this, as it is a limitation of Program Manager itself, as described [in this VOGONS post](https://www.vogons.org/viewtopic.php?t=48203). It tries to stuff all the 32*32 icon bitmaps for each program group into a single 64k segment, so the max icons you can have per group is floor(65535 / (32 * 32 * (Total bit depth / 8))). That's 31 for 16-bit modes, 21 for 24-bit modes (not accessible with `Allow3ByteMode=0`) and 15 for 32-bit modes. (This limitation doesn't come into play for 8-bit modes, because there is a hard limit of 50 icons anyway, regardless of bitmap sizes.)

### Zoom-in in Paintbrush

The zoomed-in editing mode in Paintbrush breaks in high-colour mode if the viewport is wider than about 800 pixels (100 zoomed-in pixels). You can work around this issue by reducing the size of the window while working in this mode. The reason is that this driver doesn't implement `StretchBlt`, and so GDI falls back to its internal implementation, which limits the intermediate DIB size to (again) a 64k segment (more details [here](https://github.com/PluMGMK/vbesvga.drv/issues/77#issuecomment-2913480799)). Because it uses a DIB, the outcome is the same regardless of whether you use a 16-bit, 24-bit or 32-bit video mode.

## Screenshots

### Using standard Program Manager shell

![True-Colour Full HD screenshot of Windows 3.1 desktop showing colour settings (on "Plasma Power Saver"), Program Manager, a 50-row MS-DOS prompt, Solitaire and Minesweeper](./Screenshots/VBESVGA.BMP.png)

This True-Colour Full HD screenshot, with large fonts, gives you some idea of what's working so far. The colour settings dialogue shows that pretty much the entire Windows GUI renders correctly, and the Program Manager shows icons working well too. The windowed 50-row DOS prompt demonstrates that I am running this on MS-DOS 6.20, and that I'm using a real AMD graphics card with [vendor string](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `(C) 1988-2018, Advanced Micro Devices, Inc.` and [product name](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `NAVI14`. Minesweeper and Solitaire both look OK, and the game underway indicates that the latter is eminently playable.

See the Issues page for more details of what is _not_ working at the moment...

### Using **third-party** [Calmira XP](https://winworldpc.com/product/calmira/4x) shell

![True-Colour Full HD screenshot of Calmira XP shell showing colour settings (on "Bordeaux"), Character Map, Advanced Task Manager, Calmira Explorer, an MS-DOS prompt, GVim and Minesweeper](./Screenshots/VBESVGA2.BMP.png)

This screenshot showcases the True Colour rendering capability, in the Windows-XP-derived icons used by the Calmira XP shell. The [Advanced Task Manager](https://winworldpc.com/product/advanced-task-manage/1x) instance again confirms that we're on DOS 6.20 and Windows 3.10. It also says we're on a 486, which of course isn't true, but that's just the newest CPU that Windows 3.1 knows about! The 25-row DOS prompt shows the output of `VIDMODES.COM` (see below), confirming again that I'm using a real AMD graphics card with [vendor string](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `(C) 1988-2018, Advanced Micro Devices, Inc.` and [product name](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `NAVI14` (reported a bit more legibly this time!).

## Building

Thanks to @lss4 for [pointing out some omissions](https://github.com/PluMGMK/vbesvga.drv/issues/19) in the setup process!

Note that the only step below which requires Windows is the initial installation of Visual C++ - the build process itself is purely DOS-based and can be automated using a batch file (or a Dosbox configuration file on a modern system!).

### `vbesvga.drv` (needed in both Standard and 386 Enhanced Mode)

* Install both the [Win16 DDK](http://www.win3x.org/win3board/viewtopic.php?t=2776) and [a contemporary version of Visual C++](http://www.win3x.org/win3board/viewtopic.php?t=1375)
* Obtain a copy of `EXE2BIN.EXE` (e.g. from FreeDOS, or from the Open Watcom compiler) and place it somewhere in your `PATH`
* Place the `VBESVGA` folder from this repository in the DDK hierarchy, at `286/DISPLAY/8PLANE/VBESVGA`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `286\TOOLS` from the DDK is in your `PATH` and `286\INC` is in your `INCLUDE` variable
* Go to the `VBESVGA\mak` folder and run `make vbesvga.mak`; this should create the file `VBESVGA.DRV` which can be loaded by Windows

### `vddvbe.386` (needed only in 386 Enhanced Mode)

* Place the `VDDVBE` folder from this repository in the DDK hierarchy, at `386/VDDVBE`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `386\TOOLS` from the DDK is in your `PATH`
* Go to the `VDDVBE` folder and run `nmake`; this should create the file `VDDVBE.386` which can be loaded by Windows

### Tip for using the DDK on a modern system

To make the debugger `WDEB386` work, you need to change some bytes:

* At position `63D8`, you need to change `0F 24 F0` to `66 33 C0`
* At position `63DF`, you need to change `0F 24 F8` to `66 33 C0`

This removes references to the [`TR6` and `TR7` registers](https://en.wikipedia.org/wiki/Test_register), which crash the system since they only existed on the 386, 486 and a few other less-well-known chips!

## Usage

The following changes are needed to your `C:\WINDOWS\SYSTEM.INI` file:

* In the `[boot]` section, change the `display.drv=` line to point to `vbesvga.drv`. You should specify the full path, or else copy the file to `C:\WINDOWS\SYSTEM`. (Note that if the path is too long, it can cause the CodeView debugger to crash on startup!)
* In the `[386Enh]` section, change the `display=` line to point to `vddvbe.386`. Again, you should specify the full path, or else copy the file to `C:\WINDOWS\SYSTEM`.
* If needed, create a `[VBESVGA.DRV]` section to configure the driver, as detailed [below](#configuration-parameters).

## Configuration parameters

This table lists the parameters you can specify in the `[VBESVGA.DRV]` section of `SYSTEM.INI`.

|Parameter |Valid values |Meaning |Default value |
--- | --- | --- | ---
|`Width` | 320 - 65535 | Width in pixels of the desired video mode | Your monitor's preferred width, or **1024** if no EDID |
|`Height` | 200 - 65535 | Height in scanlines of the desired video mode | Your monitor's preferred height, or **768** if no EDID |
|`Depth` | 8 - 24 | Significant bits per pixel of the desired video mode ("significant" means that padding bits are excluded, so for example if you choose 24, both 24-bit and 32-bit modes will qualify) | 24 |
|`fontsize` | `small` or `large` | Choose whether to use 96dpi or 120dpi fonts | `small` |
|`dacdepth` | 6, 8 or `auto` | Significant bits to use per colour in 256-colour modes; `auto` means 8 if the BIOS advertises that 8 is supported, 6 otherwise; if 8 is specified then the driver attempts to use 8 regardless of what the BIOS says! | `auto` |
|`SwapBuffersInterval` | 0 - 55 | Time in milliseconds between buffer swaps if [double-buffering](#linear-modes-and-double-buffering) is enabled; specifying a value of 0 **disables** double-buffering | 16 |
|`PreferBankedModes` | 0 or 1 | If set to 1, then the driver searches for bank-switching modes **before** searching for linear modes; may be useful for debugging | 0 |
|`Allow3ByteMode` | 0 or 1 | Allow using modes with a *total* depth of 24 bits; disable this to prefer 32-bit modes which give the same colour depth but use more RAM | 1 |

### Example configuration

Note that in many cases, the driver should now work out of the box, without any extra configuration, since it detects your monitor's preferred resolution and mostly uses sane defaults.

```
[VBESVGA.DRV]
Width=1440
Height=900
Depth=15
SwapBuffersInterval=15
fontsize=large
```

## Linear Modes and Double Buffering

The VBE modes used by this driver involve a framebuffer larger than can be addressed by a single segment (65536 bytes). VBE provides two strategies for dealing with this: bank-switching and using linear framebuffers. Bank-switching involves mapping only one segment at a time into physical memory, usually at address `A0000h`, whereas a linear framebuffer gets fully mapped somewhere in extended memory (i.e. beyond the 1-MiB boundary). This driver prefers to use linear modes when available, but unfortunately, due to a bug in `DOSX.EXE`, this is not possible when running Windows in Standard Mode while using `EMM386`. To ensure the driver can use linear framebuffers, you will need to run Windows in 386 Enhanced Mode, or else disable `EMM386`.

When using a linear framebuffer, on a 386 or newer, the driver also attempts to use [Double Buffering](https://wiki.osdev.org/Double_Buffering), which improves performance by ensuring that GDI operations never have to touch video RAM directly. However, it involves allocating two copies of the framebuffer in system RAM, which is quite expensive (especially given that Windows 3.1 usually can't take advantage of more than a quarter of a GiB). If it can't allocate this much RAM, it falls back to direct VRAM access.

Basically, if you're using 386 Enhanced Mode (or Standard Mode without `EMM386`), with a modern graphics card and a decent amount of system RAM, then the driver will probably enable Double Buffering. In that case, you can adjust how often the screen is redrawn using the `SwapBuffersInterval=` setting in `SYSTEM.INI`!

The default is 16 ms, which means that the screen is redrawn just over sixty times a second. Unfortunately I haven't found a way to synchronize it to your monitor's blanking interval, meaning that "sixty times a second" and "60fps" won't necessarily line up as well as one might hope (see discussion [here](https://github.com/PluMGMK/vbesvga.drv/issues/55)). Shorter intervals lead to smoother drawing - as long as your CPU can keep up!

If you suspect there are problems with Double Buffering, you can force-disable it by setting `SwapBuffersInterval=0`. This can **significantly** degrade performance for certain operations on large screens, but may be useful for debugging...

## Mode selection

When Windows boots, the driver queries the BIOS for available modes, and automatically selects the first one which fulfills the following criteria:

* Supported by the current hardware according to the BIOS
* Graphics mode (not text)
* Colour mode (not black & white)
* Resolution matches what was specified in `SYSTEM.INI`
* Total bit depth (i.e. red+green+blue+padding) is exactly 1, 2, 3 (unless `Allow3ByteMode=0`) or 4 bytes
* Either packed-pixel or direct-colour framebuffer
* Significant bit depth (i.e. red+green+blue but without padding) matches what was specified in `SYSTEM.INI`

The driver searches for linear modes first, and if it can't find any (or the system can't support them), it goes back and looks for bank-switching modes. If it can't find any mode matching the above criteria, it will switch the display back to text mode, print an error message and return to DOS.

Note that this automatic search is currently the only way the driver selects modes: you cannot give it a specific VESA mode number to use.

### Having trouble finding compatible modes?

If you know what resolution your monitor and card support, then set the `Width` and `Height` accordingly (or allow them to be autodetected), and the driver will either boot successfully or give you a list of `Depth` values to try (if the default isn't supported).

If you're not sure which resolution to try, the `VIDMODES.COM` tool included in the releases can list the available modes on your system to give some idea. Example output running under DOSBox-X 2024.07.01:
```
Your card: 
DOSBox Development Team DOSBox - The DOS Emulator 2

Available modes:
0100: 640*400*8 Packed-pixel
0101: 640*480*8 Packed-pixel
0102: 800*600*4 EGA-type (NG for VBESVGA.DRV)
0103: 800*600*8 Packed-pixel
0104: 1024*768*4 EGA-type (NG for VBESVGA.DRV)
0105: 1024*768*8 Packed-pixel
0106: 1280*1024*4 EGA-type (NG for VBESVGA.DRV)
0107: 1280*1024*8 Packed-pixel
8101: 640*480*8 Packed-pixel
0114: 800*600*16 Direct-colour, 16S/16T
C116: 1024*768*15 Direct-colour, 15S/16T
023E: 1280*720*8 Packed-pixel
8106: 1280*1024*4 EGA-type (NG for VBESVGA.DRV)
0206: 1280*960*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0206: 1280*960*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
4153: 320*200*8 Packed-pixel
0100: 640*400*8 Packed-pixel
0190: 320*240*32 Direct-colour, 24S/32T
0242: 1920*1080*4 EGA-type (NG for VBESVGA.DRV)
0242: 1920*1080*4 EGA-type (NG for VBESVGA.DRV)
0242: 1920*1080*4 EGA-type (NG for VBESVGA.DRV)
0232: 1400*1050*16 Direct-colour, 16S/16T
0232: 1400*1050*16 Direct-colour, 16S/16T
0236: 1440*900*15 Direct-colour, 15S/16T
0231: 1400*1050*15 Direct-colour, 15S/16T
0213: 640*400*32 Direct-colour, 24S/32T
0110: 640*480*15 Direct-colour, 15S/16T
```
Another example can be seen in the screenshot above, running on real hardware.

You can see that it lists all detected colour graphics modes, showing their resolutions in typical `Width*Height*NominalBitDepth` form. It then indicates the memory model for each one - only *packed-pixel* and *direct-colour* modes are usable with `VBESVGA.DRV`, so all others say "NG" (no good).

Direct-colour modes may have padding bits in each pixel, so the bit depths for these modes are listed with and without padding. The "S" number is what I call the *significant depth*, which excludes padding bits, and the "T" number is the *total depth*, which is the physical size of a pixel in memory. The driver searches for modes whose significant depths match what is specified in `SYSTEM.INI` (or 24 by default), but also makes sure the total depth is divisible by eight. If it is not divisible by eight, then pixels are not byte-aligned, and so those modes are also "NG" as seen above.

## Windows 3.1 refusing to boot with your GPU?

Windows may get stuck on the logo when you try to boot it with certain graphics card option ROMs. This happens regardless of whether or not you try to use this driver. It may be caused by a stack overflow in the logo code in `WIN.COM` when it tries to do an `int 10h` call. Another manifestation of this, which I have personally experienced, is that Windows boots successfully, but then gets caught in a loop if you try to start a DOS prompt in Standard Mode.

To work around this issue, you can try using the `AUXSTACK.COM` TSR, included in newer releases. Simply run `AUXSTACK.COM` before starting Windows, and it will allocate 1 kiB of Conventional Memory to use as an auxiliary stack and prevent the overflow from occurring. I've only tested it in the specific case I mentioned above (failure to start a DOS prompt in Standard Mode) but hopefully it will also work for other cases...
