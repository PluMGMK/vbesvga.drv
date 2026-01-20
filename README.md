# vbesvga.drv and vddvbe.386
Modern Generic SVGA driver for Windows 3.1 (with decent Windows 9x support)

This is a rewrite of the Windows 3.1 SVGA driver, designed to support **ALL** available 8-bit, 16-bit, 24-bit or 32-bit graphic modes on any system providing the [VESA BIOS Extensions](https://en.wikipedia.org/wiki/VESA_BIOS_Extensions) (hence the `VBE` in the name). It is based on the Video 7 SVGA driver included in the [Win16 Driver Development Kit](http://www.win3x.org/win3board/viewtopic.php?t=2776), with most of the hardware-specific code gutted out, and with support added for multi-byte pixels.

## Issue Templates

Issue templates were added to this repository in November 2025. **Please use them when reporting bugs!** By "use them", I mean "fill out the answers to the questions _in the given format_", **not** "select them and replace the content with your own freeform text". The questions are there for a reason, and if you don't provide all the information then I won't be able to figure out what's going on on your system. I know most of the currently-open issues don't follow these formats, but that's only because they predate the creation of the templates. The templates were written based on my experience of debugging all the previous issues, and reflect questions that I would otherwise need to ask anyway.

## Why on Earth did I make such a thing?

* To demonstrate that it's possible to run Windows 3.1 in True-Colour Full HD
* Because my AMD Radeon RX 5500 XT doesn't support 256-colour modes, rendering the old [VESA Patch](http://www.win3x.org/win3board/viewtopic.php?t=5408&hilit=svga) useless for me
* To help out any fellow enthusiasts who like running old software on new hardware!

## Screenshots

### Using standard Program Manager shell

![True-Colour Full HD screenshot of Windows 3.1 desktop, with a photographic wallpaper, showing colour settings (on "Plasma Power Saver"), Program Manager, an Internet Explorer 4.0 window (showing the "VESA BIOS Extensions" page on Gopherpedia), a 50-row MS-DOS prompt (showing VIDMODES.COM output), Solitaire and Minesweeper](./Screenshots/VBESVGA.BMP.png)

This True-Colour Full HD screenshot, with large fonts, shows the staples of the Windows 3.1 GUI and the iconic games Minesweeper and Solitaire. The windowed 50-row DOS prompt demonstrates that I am running this on MS-DOS 6.20, and (via the output of `VIDMODES.COM`; see below) that I'm using a real AMD graphics card with [vendor string](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `(C) 1988-2018, Advanced Micro Devices, Inc.` and [product name](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `NAVI14`. The wallpaper (a photo I took [here](https://www.buildingsofireland.ie/buildings-search/building/20907021/annahala-east-cork)) nicely demonstrates the True Colour rendering capability.

I also decided to include an IE4 window with a [topical Wikipedia page](https://en.wikipedia.org/wiki/VESA_BIOS_Extensions) (via [Gopherpedia](https://muffinlabs.com/posts/2013/06/14/gopherpedia---the-free-encyclopedia-via-gopher/)!) now that I've figured out how to get my network connection running thanks to a [tutorial posted on VOGONS in 2025](https://www.vogons.org/viewtopic.php?t=105947)!

### Using **third-party** [Calmira XP](https://winworldpc.com/product/calmira/4x) shell

![True-Colour Full HD screenshot of Calmira XP shell, with a photographic wallpaper, showing colour settings (on "Bordeaux"), Character Map, Advanced Task Manager, two MS-DOS prompts (one showing the main menu of Rayman, the other showing VIDMODES.COM output), and Calmira Explorer](./Screenshots/VBESVGA2.BMP.png)

This screenshot again showcases the True Colour rendering capability, in the wallpaper and in the Windows-XP-derived icons used by the Calmira XP shell. The [Advanced Task Manager](https://winworldpc.com/product/advanced-task-manage/1x) instance again confirms that we're on DOS 6.20 and Windows 3.10. It also says we're on a 486, which of course isn't true, but that's just the newest CPU that Windows 3.1 knows about! The 25-row DOS prompt again shows (part of) the output of `VIDMODES.COM`, confirming again that I'm using a real AMD graphics card. And what's that in the other DOS prompt? That's right, it's _Rayman_ (1995)! Thanks to the new 256-colour-capable grabber (see [below](#graphical-mode-sessions)), _Rayman_ can now be played in a window - it's a bit choppy, but it works!

### On Windows 98

![True-Colour Full HD screenshot of Windows 98 Active Desktop, with the Channel Bar, a 50-row DOS prompt (showing VIDMODES.COM output), a Display Properties dialog (showing only the current setting of 1920 by 1080 with 32-bit colour), and the "Welcome to Windows 98" window](./Screenshots/Win98_VBESVGA_largefonts.png)

This shows Windows 98 running on the same hardware as above, with large fonts, with the Active Desktop UI fully working. It also shows that the display settings dialog can show the current, but unfortunately [doesn't currently allow](https://github.com/PluMGMK/vbesvga.drv/issues/126) for on-the-fly adjustments.

![True-Colour Full HD screenshot of Windows 98 Active Desktop, with the Channel Bar, two DOS prompts (one showing VER and VIDMODES.COM output, the other showing the main menu of Rayman Designer), and a RetroZilla browser window (showing the home page of raymandesigner.com)](./Screenshots/Win98_VBESVGA_raymandesigner.png)

This one shows _Rayman Designer_ running in a windowed DOS prompt (in this case using Windows 98's stock grabber), and the [go-to site for sharing and downloading levels for that game](https://raymandesigner.com/) in a [RetroZilla](https://github.com/rn10950/RetroZilla/) browser window.

## Usage Notes

### Hardware Support

In theory, this suite of drivers should support _any_ graphics card that properly supports the VESA BIOS Extensions, and doesn't do anything funky with the memory window size. So basically, any hardware made in the last thirty years. Unfortunately, real life is rarely as simple as one would like, so there is some hardware that has some issues:

* The NVIDIA GeForce 1050 GTX has some issues with windowed DOS prompts, and presumably newer NVIDIA hardware has the same problem. The issues include potential freezes when using the `mode` command to change the size of the prompt, and font corruption when switching to full screen (which also affects blue screens).
* AMD Radeons: the RX 5000 series works perfectly, and I use it for development. There has been one report of a 386 Enhanced Mode boot failure with an RX 7000 series card, but it's not clear whether that was caused by the graphics hardware or some other incompatibility on the motherboard.
* Intel 810 chipset integrated graphics [crashes back to DOS during boot](https://github.com/PluMGMK/vbesvga.drv/issues/99) leaving you with a blank screen. It turns out there is an official driver for this chipset, so please use that instead: https://archive.org/details/w-810-r-209

In general, if your hardware is old enough, it probably has an official driver for Windows 3.1 (like the i810). Official drivers should be preferred where available because they generally use hardware acceleration and don't use inefficient Real-Mode BIOS calls. On processors from that era (especially early on), the CPU-bound routines of `VBESVGA.DRV` tend to give **really** poor performance!

### Integrity Verification

From v0.9.4, the releases ship with SHA1 sums for integrity verification, to ensure corrupt driver files or helper programs don't cause weird crashes or instability.

To make sure the files aren't corrupt, ensure everything is in one folder and use the [`MD5SUM`](https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/util/file/md5sum/md5sumx.zip) utility from FreeDOS, as follows:

```
md5sum/m:sha/v/c VBESVGA.SHA
```

If any file from the release archive is corrupt, it will come up as "FAILED".

### Large, Small and Tiny Fonts

Most Windows 3.1 display drivers supported "small" and "large" font modes, setting the display resolution to 96 dpi and 120 dpi respectively. Annoyingly, while the corresponding setting was usually known as "`fontsize`", the actual font size used by the system was determined by three `FON` files (system, OEM and fixed-width fonts) specified elsewhere in the `SYSTEM.INI` file. Driver setup files were programmed to make these settings match, but a manual install could produce weird-looking mismatches.

`VBESVGA.DRV` supports three modes: "large" at 120 dpi, "small" at 96 dpi, and "tiny" at 48 dpi. Unlike old drivers, this doesn't need to be configured explicitly: it automatically detects the DPI of the currently-installed system font, and picks the closest of the three supported values. However, you can still use the `fontsize` setting in `SYSTEM.INI` to override this if you wish.

There is also a `fontsize=nativedpi` setting, which calculates the physical dots per inch of your screen, and again picks the closest of the three supported values. Again though, this can lead to a mismatch with the system font size.

### Setup / Configuration Procedure

There are a few different ways to setup and configure the driver, according to your tastes and requirements. In all cases, the first step is to extract the `vbesvga-release.zip` archive to a folder on your DOS/Win3.1/Win9x machine, or else mount the `vbesvga.img` as a floppy image (or put it on a real floppy).

#### Generic `OEMSETUP.INF`

The `OEMSETUP.INF` file provided in the release archives and images, which can be used with the Windows Setup tool, includes some basic profiles, typical of early SVGA hardware. You can choose a resolution of 320×200, 640×480, 800×600, 1024×768, or "Automatic", meaning that your monitor's preferred resolution is auto-detected (this detection falls back to 1024×768 on failure). For each choice of resolution, you can pick 256 (8-bit), 32k (15-bit), 65k (16-bit) or 16M (24-bit) colours.

The 320×200 modes are configured for "tiny" fonts, requiring `LR*.FON` from the Windows 3.0 MME CD-ROM). 640×480 modes are configured for "small" fonts (requiring `VGA*.FON` included in both Windows 3.x and Windows 9x installation media), and the larger modes offer "large" or "small" options (requiring `8514*.FON` and `VGA*.FON` respectively, again included in Windows 3.x and 9x installation media). "Automatic" modes offer all three options, again requiring the respective font files.

There is no guarantee that your system will support all of these modes, so you may wish to use one of the other setup methods to get a more customized configuration.

Thanks to @jschwartzenberg, @corma16 and @albertus82 for their help with creating this file!

#### Interactive `SETUP.EXE`

Also included in the release archives and images is the `SETUP.EXE` tool, which is an interactive DOS program. Simply run it, and it will present a configuration interface and copy the required files into your Windows folder. You can use it to select any display mode supported by your hardware, and choose Large or Small fonts. Unlike the `OEMSETUP.INF`, you can also configure the `SwapBuffersInterval` and `BounceOnModeset` values documented below.

You can select the "tiny" (`LR*.FON`), "small" (`VGA*.FON`) or "large" (`8514*.FON`) system font sets, and/or override the DPI setting ("`fontsize`" in `SYSTEM.INI`) as described [above](#large-small-and-tiny-fonts). You will need to provide the font files yourself, either placing them in the same folder as the setup tool, or directly in the `WINDOWS\SYSTEM` folder. The tool will not let you choose a missing font file (the setting will flash red and you will not be able to save until you change it).

Once it installs the driver, the tool also creates a `VBESVGA.EXE` DOS program in the Windows directory that you can use to reconfigure the driver without reinstalling.

Thanks to @joshudson for creating this tool!

#### Generating a bespoke `OEMSETUP.INF`

You can also use [@albertus82's BASIC script](https://github.com/albertus82/vbesvga-oemsetup/) to generate a bespoke `OEMSETUP.INF` for your machine, and then install the driver using Windows Setup.

#### Full list of configuration options

All of these options are recognized in the `[VBESVGA.DRV]` section of `SYSTEM.INI`. You can edit them manually, but the most important ones can be set using the `SETUP.EXE` / `VBESVGA.EXE` tool described above.

|Parameter |Valid values |Meaning |Default value |
--- | --- | --- | ---
|`Width` | 320 - 65535 | Width in pixels of the desired video mode | Your monitor's preferred width, or **1024** if no EDID |
|`Height` | 200 - 65535 | Height in scanlines of the desired video mode | Your monitor's preferred height, or **768** if no EDID |
|`Depth` | 8 - 24 | Significant bits per pixel of the desired video mode ("significant" means that padding bits are excluded, so for example if you choose 24, both 24-bit and 32-bit modes will qualify) | 24 |
|`fontsize` | `auto`, `nativedpi`, `tiny`, `small` or `large` | Display DPI setting, overriding the detected value from the system font (see [above](#large-small-and-tiny-fonts)) | `auto` |
|`dacdepth` | 6, 8 or `auto` | Significant bits to use per colour in 256-colour modes; `auto` means 8 if the BIOS advertises that 8 is supported, 6 otherwise; if 8 is specified then the driver attempts to use 8 regardless of what the BIOS says! | `auto` |
|`SwapBuffersInterval` | 0 - 55 | Time in milliseconds between buffer swaps if [double-buffering](#linear-modes-and-double-buffering) is enabled; specifying a value of 0 **disables** double-buffering | 16 |
|`PreferBankedModes` | 0 or 1 | If set to 1, then the driver searches for bank-switching modes **before** searching for linear modes; may be useful for debugging | 0 |
|`GarishSystemPalette` | 0 or 1 | This affects colour rendering on the Windows GUI when the driver is in 8-bit mode. When set to 1, the "dark" colours are rendered significantly brighter than their internal representation, like they are in most Windows 3.1 display drivers. When set to 0 (the default), the internal and external representations are the same, which is easier on the eye. A detailed discussion is [here](https://github.com/PluMGMK/vbesvga.drv/issues/70#issuecomment-3198005963) | 0 |
|`EnableSpecialCaseLinearBlits` | 0 or 1 | If set to 1 (the default), then the driver completely bypasses bank-switching code paths to speed up certain common bit-blit operations when using a linear mode (this option is only for debugging) | 1 |
|`Allow3ByteMode` | 0 or 1 | Allow using modes with a *total* depth of 24 bits; disable this to prefer 32-bit modes which give the same colour depth but use more RAM | 1 |
|`BounceOnModeset` | 0 or 1 | This causes the Windows GUI to "bounce" to the background and immediately return to the foreground, when a windowed or background DOS box does a modeset (e.g. when starting up a windowed DOS box). Usually required to prevent display corruption, but does cause an unpleasant flash. You can try disabling it to prevent the flash, but if it causes display corruption you will need to turn it back on! (It is safe to disable this under VirtualBox and DOSBox-X, but not under QEMU or Microsoft Virtual PC.) | 1 |

#### Example configuration (showing only relevant snippets of `SYSTEM.INI`)

```
[boot]
display.drv=vbesvga.drv
386grabber=vbevmdib.3gr
<... more stuff ...>

[386Enh]
display=vddvbe.386
WindowUpdateTime=15
<... more stuff ...>

[drivers]
dci=display
<... more stuff ...>

[vbesvga.drv]
Width=1440
Height=900
Depth=15
SwapBuffersInterval=15
```

#### Using debug builds

To use the debug builds, you can place the `VDDVBE.386`, `VBEVMDIB.3GR` and/or `VBESVGA.DRV` files from the `vbesvga-debug.zip` archive (or the `debug` folder in the `vbesvga.img` floppy image) in your `SYSTEM` directory, replacing the ones installed from `vbesvga-release.zip` (or the root directory of `vbesvga.img`). The corresponding `SYM` files can be used with `WDEB386` (supplied with the [Win16 DDK](http://www.win3x.org/win3board/viewtopic.php?t=2776)) or the Open Watcom debugger (only if the `SYM`s are placed in the `SYSTEM` directory).

To make the aforementioned debugger `WDEB386.EXE` work on anything newer than a 486, you need to change some bytes:

* At position `63D8`, you need to change `0F 24 F0` to `66 33 C0`
* At position `63DF`, you need to change `0F 24 F8` to `66 33 C0`

This removes references to the [`TR6` and `TR7` registers](https://en.wikipedia.org/wiki/Test_register), which crash the system since they only existed on the 386, 486 and a few other less-well-known chips!

### Windows 9x

`VBESVGA.DRV` and `VDDVBE.386` can be used together on Windows 9x, and this configuration even supports colour and animated cursors. However, the lack of integration with the registry and the "Plug-and-Play" system gives rise to the following limitations:

* It is impossible to set the video mode from the GUI settings (as seen in the screenshot above) - although you **can** set the font size
* Hardware / driver names may be reported inconsistently depending on where you look in system settings and/or system information
* `VDDVBE.386` cannot boot on DBCS versions of Windows (e.g. Japanese) unless you load the shim driver `VDDD.386`, found in the Japanese version of Windows 3.1. This will force BSoDs to render in Latin text, which is not ideal - see also [issue #98](https://github.com/PluMGMK/vbesvga.drv/issues/98).

My plan is to refactor `VDDVBE.386` so that it can be compiled in two different ways:

1. A monolithic virtual display driver for Windows 3.x (i.e. what it is now)
2. An installable mini-VDD for Windows 9x, containing a stripped down subset of its code

This will be accompanied by API and configuration changes, and a new installation script designed for Windows 9x, which should hopefully overcome the issues above. The two versions will be shipped side-by-side in this repository.

When I make these changes (hopefully during 2026), the version number will be bumped to 2.0.

### Limitations in Windows programs / components

#### Program Manager icons

When using high-colour modes, Program Manager may complain that there is not enough memory to convert all the icons. There is nothing I can do about this, as it is a limitation of Program Manager itself, as described [in this VOGONS post](https://www.vogons.org/viewtopic.php?t=48203). It tries to stuff all the 32×32 icon bitmaps for each program group into a single 64k segment, so the max icons you can have per group is floor(65535 / (32 × 32 × (Total bit depth / 8))). That's 31 for 16-bit modes, 21 for 24-bit modes (not accessible with `Allow3ByteMode=0`) and 15 for 32-bit modes. (This limitation doesn't come into play for 8-bit modes, because there is a hard limit of 50 icons anyway, regardless of bitmap sizes.)

#### MS-DOS Prompt crashing the system in Standard Mode

On newer graphics cards, when you try to open an MS-DOS prompt in Standard Mode (not 386 Enhanced Mode), the screen may start flashing with various garbage characters appearing in quick succession, and only a reboot will fix it. This happens regardless of whether or not you use this driver. This is caused by a stack overflow in the logo code in `WIN.COM` when it tries to do an `int 10h` call.

To work around this issue, you can try using the `AUXSTACK.COM` TSR, included in newer releases. Simply run `AUXSTACK.COM` _before_ starting Windows, and it will allocate 1 kiB of Conventional Memory to use as an auxiliary stack and prevent the overflow from occurring. You can use the tool `AUXCHECK.COM` to see if this is needed rather than using trial and error[^1].

Please note that, contrary to speculation in earlier versions of this document, this tool **cannot** prevent boot failures! The stack used during Windows boot is much larger than when Standard Mode starts a DOS prompt, so this issue doesn't apply in that situation.

#### Zoom-in in Paintbrush

The zoomed-in editing mode in Paintbrush breaks in high-colour mode if the viewport is wider than about 800 pixels (100 zoomed-in pixels). You can work around this issue by reducing the size of the window while working in this mode. The reason is that this driver doesn't implement `StretchBlt`, and so GDI falls back to its internal implementation, which limits the intermediate DIB size to (again) a 64k segment (more details [here](https://github.com/PluMGMK/vbesvga.drv/issues/77#issuecomment-2913480799)). Because it uses a DIB, the outcome is the same regardless of whether you use a 16-bit, 24-bit or 32-bit video mode.

Note that this limitation doesn't apply in Windows 9x when using Paint, because in Windows 95's version of `GDI.EXE`, the intermediate DIB size limit was increased to three segments (i.e. 192 kiB) for high-colour stretching.

#### Viewing large photographs

The largest bitmap that can be allocated in Windows 3.1 is `0FF0000h`, i.e. about 16.7 million bytes, which is a limitation of `KRNL386.EXE`. This means that the largest photographs that can be viewed are 16.6 MP in 8-bit mode, 8.3 MP in 16-bit mode, ~5 MP in 24-bit mode and ~4 MP in 32-bit mode, or possibly slightly less depending on how the scanlines line up with segment boundaries. I guess this isn't a very common usecase anyway, but I felt I should point it out since there's nothing that can be done about it in this driver. (Despite the fact that ACDSee claims that the "display driver" couldn't create the bitmap in such situations!)

On a somewhat related note, it is also possible to get General Protection Faults when trying to open large-ish bitmaps, e.g. for wallpapers over 1024×768, if you have `PageOverCommit=1` set in the `[386Enh]` section of `SYSTEM.INI`. Apparently QEMM setup for Windows can quietly add this setting, resulting in these kinds of problems. Removing this directive will allow you to view larger bitmaps up to the 16.7-million-byte limit without problems.

### Mode selection

When Windows boots, the driver queries the BIOS for available modes, and evaluates each one which fulfills the following criteria:

* Supported by the current hardware according to the BIOS
* Graphics mode (not text)
* Colour mode (not black & white)
* Total bit depth (i.e. red+green+blue+padding) is exactly 1, 2, 3 (unless `Allow3ByteMode=0`) or 4 bytes
* Either packed-pixel or direct-colour framebuffer

Each mode which fulfills these criteria is assigned a "score", indicating how well it matches the desired resolution and depth specified in `SYSTEM.INI`. The score is the sum of four components:

* Absolute difference of width (in pixels) from the `SYSTEM.INI` spec (or, by default, your monitor's preferred width, or 1024)
* Absolute difference of height (in scanlines) from the `SYSTEM.INI` spec (or, by default, your monitor's preferred height, or 768)
* Absolute difference of significant depth (in bits) from the `SYSTEM.INI` spec (or, by default, 24)
* +1 if you asked for a linear mode (i.e. if `PreferBankedModes=0`) but it can only work with bank switching, or *vice versa* (see [below](#linear-modes-and-double-buffering) for more details)

If it doesn't find a perfect match among your system's VBE modes, the driver also checks mode `13h`, which is the standard 320×200×8 VGA mode. Depending on your configuration options, this may or may not turn out to be the best-scoring mode.

If you know what resolution your monitor and card support, then set the `Width` and `Height` accordingly (or allow them to be autodetected). Note that this automatic search and scoring system is the only way the driver selects modes: you cannot give it a specific VESA mode number to use.

If you're not sure which resolution to try, the `VIDMODES.COM` tool included in the releases can list the available modes on your system to give some idea. Example output running under DOSBox-X 2024.07.01[^2]:
```
Your card: 
DOSBox Development Team DOSBox - The DOS Emulator 2

Your monitor: 
[VBIOS failed to return EDID data]

Available VBE video modes:
0100: 640*400*8 Packed-pixel, linOK, winA@A000: 64k/64k
0101: 640*480*8 Packed-pixel, linOK, winA@A000: 64k/64k
0102: 800*600*4 EGA-type (NG for VBESVGA.DRV)
0103: 800*600*8 Packed-pixel, linOK, winA@A000: 64k/64k
0104: 1024*768*4 EGA-type (NG for VBESVGA.DRV)
0105: 1024*768*8 Packed-pixel, linOK, winA@A000: 64k/64k
0106: 1280*1024*4 EGA-type (NG for VBESVGA.DRV)
0107: 1280*1024*8 Packed-pixel, linOK, winA@A000: 64k/64k
010D: 320*200*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
010E: 320*200*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0110: 640*480*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0111: 640*480*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0113: 800*600*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0114: 800*600*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0116: 1024*768*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0117: 1024*768*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0119: 1280*1024*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
011A: 1280*1024*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
010F: 320*200*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0112: 640*480*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0115: 800*600*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0118: 1024*768*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
01F0: 320*200*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
01F1: 640*480*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
01F2: 800*600*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
01F3: 1024*768*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0151: 320*240*8 Packed-pixel, linOK, winA@A000: 64k/64k
0153: 320*200*8 Packed-pixel, linOK, winA@A000: 64k/64k
015C: 512*384*8 Packed-pixel, linOK, winA@A000: 64k/64k
0159: 400*300*8 Packed-pixel, linOK, winA@A000: 64k/64k
015D: 512*384*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
015A: 400*300*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0160: 320*240*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0161: 320*400*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0162: 320*480*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0165: 640*400*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
0136: 320*240*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0170: 320*240*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0172: 320*480*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0175: 640*400*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
0190: 320*240*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0201: 640*480*8 Packed-pixel, linOK, winA@A000: 64k/64k
0202: 800*600*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0203: 800*600*8 Packed-pixel, linOK, winA@A000: 64k/64k
0204: 1024*768*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0205: 1024*768*8 Packed-pixel, linOK, winA@A000: 64k/64k
0206: 1280*960*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0207: 1152*864*8 Packed-pixel, linOK, winA@A000: 64k/64k
0208: 1280*1024*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0209: 1152*864*15 Direct-colour, 15S/16T, linOK, winA@A000: 64k/64k
020A: 1152*864*16 Direct-colour, 16S/16T, linOK, winA@A000: 64k/64k
020B: 1152*864*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k
0213: 640*400*32 Direct-colour, 24S/32T, linOK, winA@A000: 64k/64k

Perfect usable match for default mode 1024*768*24: 0118
VBESVGA.DRV will attempt to boot in that mode.

To check another mode, use /w, /h and /d switches
to specify desired width / height / depth - e.g.:
	vidmodes/w800/h600/d16

VIDMODES.COM from Git commit ab3f0fc
Total modes found: 53
```
Another example can be seen in the screenshot above, running on real hardware.

You can see that it lists all detected colour graphics modes, showing their resolutions in typical `Width*Height*NominalBitDepth` form. It then indicates the memory model for each one - only *packed-pixel* and *direct-colour* modes are usable with `VBESVGA.DRV`, so all others say "NG" (no good).

Direct-colour modes may have padding bits in each pixel, so the bit depths for these modes are listed with and without padding. The "S" number is what I call the *significant depth*, which excludes padding bits, and the "T" number is the *total depth*, which is the physical size of a pixel in memory. The driver searches for modes whose significant depths match what is specified in `SYSTEM.INI` (or 24 by default), but also makes sure the total depth is divisible by eight. If it is not divisible by eight, then pixels are not byte-aligned, and so those modes are also "NG" as seen above.

For modes which pass these checks, `VIDMODES.COM` also prints out `linOK` if they can be used as linear modes. This is followed by the location, size and granularity of the VRAM window, if they can be used as bank-switched modes. In all the cases I've seen so far, the size has always been 64k, while the granularity can [sometimes](https://github.com/PluMGMK/vbesvga.drv/issues/59) be smaller. If the size is over 64k, or not an integer multiple of the granularity, or less than 64k and not an integer multiple of the scanline width, then `VBESVGA.DRV` cannot bank-switch the mode, and `VIDMODES.COM` will briefly explain why. Such modes can still be used as linear modes, if they support it. These conditions may sound quite complicated, but I would be very surprised if there turned out to be real hardware that violates them!

You can also use `VIDMODES.COM` as part of a batch file to check whether or not `VBESVGA.DRV` can be expected to boot with certain mode settings. An example usage is given at the end of the output above. The errorlevel is set to:
* `0` (**success**) if a perfect match is found
* `1` if a corresponding mode is **not** found, but `VBESVGA.DRV` will attempt to boot with the closest match
* `2` if your graphics card doesn't support VBE at all, in which case `VBESVGA.DRV` will attempt to boot in mode `13h`, i.e. 320×200×8

#### Testing a mode from DOS

Sometimes you may get strange artefacts when booting Windows in certain display modes (e.g. wrong colours, [stair-casing](https://github.com/PluMGMK/vbesvga.drv/issues/119), etc.). In that case, it may be useful to understand whether the problem comes from Windows, your graphics firmware, or some combination of both. To help elucidate this, you can use the `MODETEST.COM` utility (included since `v1.0`) from Real-Mode DOS (i.e. **without** `EMM386` or equivalent) to put up a sixteen-colour test card and see if it looks OK.

To use it, you simply find the desired mode in the `VIDMODES.COM` output, and then pass it as an argument to `MODETEST.COM`, for example:

```
MODETEST 020B
```

Or, to test it with a linear framebuffer (see next section), add 4000 to the number:

```
MODETEST 420B
```

### Linear Modes and Double Buffering

The VBE modes used by this driver involve a framebuffer larger than can be addressed by a single segment (65536 bytes). VBE provides two strategies for dealing with this: bank-switching and using linear framebuffers. Bank-switching involves mapping only one segment at a time into physical memory, usually at address `A0000h`, whereas a linear framebuffer gets fully mapped somewhere in extended memory (i.e. beyond the 1-MiB boundary).

Up to version 0.9.1 inclusive, it was not possible to use linear modes when Windows was running in Standard Mode with a memory manager such as `EMM386`. However, newer versions include a workaround for this bug in `DOSX.EXE`, meaning that this is no longer the case! This should make it easier to use linear modes if your computer can't run 386 Enhanced Mode for whatever reason. The best part is that the fix installed by this driver can also be used by any other drivers you load – for example, [the HD Audio driver](http://www.win3x.org/win3board/viewtopic.php?p=218417#p218417), which normally has the same limitation!

When using a linear framebuffer, on a 386 or newer, the driver also attempts to use [Double Buffering](https://wiki.osdev.org/Double_Buffering), which improves performance by ensuring that GDI operations never have to touch video RAM directly. However, it involves allocating two copies of the framebuffer in system RAM, which is quite expensive (especially given that Windows 3.1 usually can't take advantage of more than a quarter of a GiB). If it can't allocate this much RAM, it falls back to direct VRAM access.

Basically, if you have a modern graphics card and a decent amount of system RAM, then the driver will probably enable Double Buffering. In that case, you can adjust how often the screen is redrawn using the `SwapBuffersInterval=` setting in `SYSTEM.INI`. The default is 16 ms, which means that the screen is redrawn just over sixty times a second. Unfortunately I haven't found a way to synchronize it to your monitor's blanking interval, meaning that "sixty times a second" and "60fps" won't necessarily line up as well as one might hope (see discussion [here](https://github.com/PluMGMK/vbesvga.drv/issues/55)). Shorter intervals lead to smoother drawing - as long as your CPU can keep up!

If you suspect there are problems with Double Buffering, you can force-disable it by setting `SwapBuffersInterval=0`. This can **significantly** degrade performance for certain operations on large screens, but may be useful for debugging...

Note that the DCI Provider (which is a [minimum implementation](https://library.thedatadungeon.com/msdn-2000-04/specs/html/S1CE07.HTM)), used by Video for Windows and certain games, only works in linear modes. The VxD `DVA.386` (or `VFLATD` on Win9x) does provide a mechanism to make a bank-switched framebuffer look like a linear one for DCI, but this only works when the driver provides a snippet of 32-bit code to switch the bank. `VBESVGA.DRV` is not in a position to do this, since it does bank switching by calling out to a 16-bit function provided by the Video BIOS.

### Running DOS programs / games in windowed mode

As you probably know, in 386 Enhanced Mode, Windows 3.1 allows running DOS sessions in a window. With this driver, `VDDVBE.386` and `VBEVMDIB.3GR` are responsible for video memory management and rendering, respectively, of these windowed sessions. These two modules have certain features and limitations you should be aware of when using this functionality.

#### Text mode sessions

Firstly, when starting up a windowed DOS session, the screen will most likely flash momentarily. This is because when a DOS session starts up, it does a mode-set to mode 3 (standard CGA/EGA/VGA text mode). This mode-set does some port I/O to reprogram a bunch of CGA/EGA/VGA registers, which gets trapped by `VDDVBE.386`, and used to update the state of the associated DOS VM. However, on modern graphics cards, this usually does some further I/O to reprogram vendor-specific registers, which `VDDVBE.386` knows nothing about. Since this I/O does not get trapped, it tends to leave the display in some corrupt hybrid mode ([example](https://github.com/PluMGMK/vbesvga.drv/issues/79)). To prevent this, whenever a windowed DOS VM does any kind of mode-set, `VDDVBE.386` immediately instructs `VBESVGA.DRV` to reset the mode and re-draw the display. This tends to flash the screen, but it's vastly preferable to the alternative!

Beyond that, text-mode DOS windows work as you would expect, and there aren't any major gotchas or foibles.

#### Graphical mode sessions

The CGA graphical modes (320×200, 4-colour, and 640×200, 2-colour) are also fully usable in windowed DOS sessions. They are upscaled to 640×400, as one would expect.

Unfortunately, when it comes to EGA and VGA modes, things get a lot hairier. As outlined [here](https://wiki.osdev.org/VGA_Hardware), the EGA and VGA had multiple memory planes (three and four respectively), which could be addressed, read from, and written to, in all kinds of weird and wonderful ways. Virtualizing these memory planes _efficiently_ is far beyond the capabilities of the 386's MMU, or anything descended from it[^3], so Windows 3.1's Virtual Display Driver (VDD) took a different approach. It would look for off-screen pages of Video RAM and assign them to DOS VMs on an as-needed basis, so that the running DOS programs could interface directly with the EGA/VGA hardware and do all the interesting read/write magic. The contents of the planes would then be read by the VDD and passed to the grabber to render in the DOS session's window.

Unfortunately, there are a couple of problems with this approach on modern hardware. First of all, there's the concept of an off-screen page of VRAM. While modern graphics cards do of course have orders of magnitude more VRAM than is needed to display a single frame on the screen, assigning an off-screen page to a DOS VM is easier said than done. The simplest way might be to grab the first page beyond the end of the framebuffer, which will typically have an offset considerably larger than the 256 kiB VRAM size of the original VGA. We could use bank switching to map it somewhere in the physical range `A0000h-B0000h`, but then would that be guaranteed to work if Windows is running in a linear mode? Allocating a page from the linear framebuffer itself would have a very low chance of success, since most (if not all) hardware would map that buffer in a way that bypasses all the EGA/VGA-style addressing mechanisms.

A more promising approach would be to allocate the first 256 kiB of VRAM for this, and have the graphics card render the display starting from that offset. VBE does in fact provide [a function](https://fd.lod.bz/rbil/interrup/video/104f07.html#316) for this, but it turns out that newer hardware [doesn't bother to implement that function](https://www.vogons.org/viewtopic.php?t=57420). In fact, it doesn't even give any indication that the function's not implemented, so I can't even detect it at runtime. So basically, that approach is off-limits too, since I want this driver to work well on even the newest hardware.

Secondly, even if I could reliably find an off-screen VRAM page and map it somewhere in the physical `A0000h-B0000h` range, while Windows is in a VBE mode, there would _still_ be no guarantee that the graphics card would let me treat it like EGA/VGA RAM. There's probably a line in some spec somewhere that says it _should_, but my experience of working on this tells me that modern graphics cards pay very little attention to what they "should" be doing for legacy support once they're in a high-resolution VBE mode!

So, unfortunately, there is no way to run DOS programs in a planar EGA/VGA mode inside a window while using this driver. Using `VBEVMDIB.3GR` will ensure that any DOS sessions that try to use one of these modes get forced into fullscreen (although there might be some display corruption when this happens).

There is a silver lining, however: one of the modes introduced by the VGA doesn't require any of this planar trickery. Mode `13h`, aka 320×200 256-colour, presents a linear 64,000-byte framebuffer at address `A0000h`, which can easily be replaced by virtual memory, just like the framebuffers used in the CGA modes. The grabber that came with Windows 3.1 didn't support this mode (possibly because Windows itself only ran in 16 colours out of the box), but `VBEVMDIB.3GR` does! This means you can run 256-colour games in a window while using this driver, as long as they don't [put the VGA back in planar mode](http://www.phatcode.net/res/224/files/html/ch47/47-01.html#Heading1) (which quite a few games did - oh well...). You can see _Rayman_ (1995) running successfully in mode `13h` in the screenshot above, and its default "PCI1" video mode doesn't use planar mode at all, so it is playable!

Long story short, you can window graphical programs that run in CGA modes, or 256-colour VGA mode, but unfortunately **not** planar EGA/VGA modes.

#### Frame-rate regulation for windowed DOS sessions

A lot of DOS games poll the ["input status 1" register](https://fd.lod.bz/rbil/ports/other/p03d803df.html#table-P0818) to determine when the display is in vertical retrace, and use this to regulate the rendering frame-rate. When running in a window, this register is virtualized by the Virtual Display Driver, in this case `VDDVBE.386`. Microsoft wrote an algorithm where the register would appear as "not in vertical retrace" 255 times, then "in vertical retrace" 12 times, no matter what the time interval was between the polls. In fact, they got it a bit mixed up - it would appear "in vertical retrace" every second poll of the first 255... Anyway, that may have worked to delay display refreshes on a 386, but it won't cut the mustard on modern CPUs that are orders of magnitude faster!

Because of this, `VDDVBE.386` can use timer events to simulate the vertical retrace timing (slightly) more accurately, using a period calculated based on the timing programmed by the DOS program / game into the CRTC registers. This function only activates if the user's config suggests that the CPU can handle it. That is to say, these timer events are only used if the period is no shorter than either `SwapBuffersInterval` (documented above) or the `WindowUpdateTime` setting in the `[386Enh]` section of `SYSTEM.INI`[^4].

For example, if you have a game in a window that wants to run at 60fps (16 ms per frame), your `SwapBuffersInterval` is 16 ms (the default) and your `WindowUpdateTime` is 50 ms (also the default), then timer events will be used to simulate the vertical retrace period accurately. However, if the game wants to run at 70fps (14 ms per frame), timer events will not be used, and `VDDVBE.386` will fall back to the old 255/12 algorithm. To make it use timer events, you would have to reduce the `SwapBuffersInterval` and/or `WindowUpdateTime` to at most 14.

Generally, if you plan to run DOS games windowed, it's a good idea to set both `SwapBuffersInterval` and `WindowUpdateTime` as short as possible (without saturating the CPU).

#### The vertical retrace IRQ

The EGA introduced an optional interrupt signal associated with the vertical retrace, on IRQ2. Unfortunately, hardware implementation of this over the years has been [patchy at best](https://scalibq.wordpress.com/2022/12/06/the-myth-of-the-vertical-retrace-interrupt/). I decided to virtualize this for windowed DOS sessions (since I had gone to the trouble of setting up timer events anyway). So if you have a DOS game that wants to use IRQ2 to signal the next frame, you can try running it in a window, with an appropriately short `SwapBuffersInterval` and `WindowUpdateTime`!

Unfortunately, the practical uses for this are probably nil, since the most reliable implementation of this IRQ was on the original EGA, and any games built for that are likely to use one of the EGA display modes, which (as explained above) can't be windowed. Oh well!

## Build Process

Thanks to @lss4 for [pointing out some omissions](https://github.com/PluMGMK/vbesvga.drv/issues/19) in the setup process!

Note that the only step below which requires Windows is the initial installation of Visual C++ - the build process itself is purely DOS-based and can be automated using a batch file. See the file `release-work/make-release.sh` for an example of how this can be done using DOSBox on Linux.

### `vbesvga.drv` (needed in both Standard and 386 Enhanced Mode, and on Windows 9x)

* Install both the [Win16 DDK](http://www.win3x.org/win3board/viewtopic.php?t=2776) and [a contemporary version of Visual C++](http://www.win3x.org/win3board/viewtopic.php?t=1375)
* Obtain a copy of `EXE2BIN.EXE` (e.g. from FreeDOS, or from the Open Watcom compiler) and place it somewhere in your `PATH`
* Place the `VBESVGA` folder from this repository in the DDK hierarchy, at `286/DISPLAY/8PLANE/VBESVGA`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `286\TOOLS` from the DDK is in your `PATH` and `286\INC` is in your `INCLUDE` variable
* Go to the `VBESVGA\mak` folder and run `make vbesvga.mak`; this should create the file `VBESVGA.DRV` which can be loaded by Windows

### `vddvbe.386` (needed only in 386 Enhanced Mode, and on Windows 9x)

* Place the `VDDVBE` folder from this repository in the DDK hierarchy, at `386/VDDVBE`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `386\TOOLS` from the DDK is in your `PATH`
* Go to the `VDDVBE` folder and run `nmake`; this should create the file `VDDVBE.386` which can be loaded by Windows

### `vbevmdib.3gr` (needed only in 386 Enhanced Mode for running graphical DOS programs in windowed mode, not needed on Windows 9x)

* Place the `VBEGRAB` folder from this repository in the DDK hierarchy, at `386/VBEGRAB`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `386\TOOLS` from the DDK is in your `PATH`
* Go to the `VBEGRAB` folder and run `nmake`; this should create the file `VBEVMDIB.3GR` which can be loaded by Windows

[^1]: Ideally this check would be built into the Windows boot process in the driver, but unfortunately this is basically impossible, since `KRNL386.EXE` appropriates all Conventional Memory during the boot process, and then this gets evicted when you start an MS-DOS Prompt in Standard Mode. So there's really no way to start a TSR from inside Windows that will actually stay resident when you attempt to start a DOS prompt.
[^2]: In the specific case of DOSBox-X, this list can actually be modified using the `VESAMOED` command, which is documented [here](https://dosbox-x.com/wiki/DOSBox%E2%80%90X%E2%80%99s-Supported-Commands) - thanks to @blue-devil-93 for [pointing this out](https://github.com/PluMGMK/vbesvga.drv/issues/84)! More generally, however, this is obviously not the case.
[^3]: Just try running a VGA-mode program under QEMU with hardware virtualization enabled - drawing the display can take several seconds!
[^4]: This setting, also in milliseconds, defines how quickly the display can update in a DOS session window. It is not specific to this driver, but I only found out about it recently, so I thought I should mention it here!
