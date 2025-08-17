# vbesvga.drv and vddvbe.386
Modern Generic SVGA driver for Windows 3.1

This is a rewrite of the Windows 3.1 SVGA driver, designed to support **ALL** available 8-bit, 16-bit, 24-bit or 32-bit graphic modes on any system providing the [VESA BIOS Extensions](https://en.wikipedia.org/wiki/VESA_BIOS_Extensions) (hence the `VBE` in the name). It is based on the Video 7 SVGA driver included in the [Win16 Driver Development Kit](http://www.win3x.org/win3board/viewtopic.php?t=2776), with most of the hardware-specific code gutted out, and with support added for multi-byte pixels.

## Why on Earth did I make such a thing?

* To demonstrate that it's possible to run Windows 3.1 in True-Colour Full HD
* Because my AMD Radeon RX 5500 XT doesn't support 256-colour modes, rendering the old [VESA Patch](http://www.win3x.org/win3board/viewtopic.php?t=5408&hilit=svga) useless for me
* To help out any fellow enthusiasts who like running old software on new hardware!

## Screenshots

### Using standard Program Manager shell

![True-Colour Full HD screenshot of Windows 3.1 desktop showing colour settings (on "Plasma Power Saver"), Program Manager, a 50-row MS-DOS prompt, Solitaire and Minesweeper](./Screenshots/VBESVGA.BMP.png)

This True-Colour Full HD screenshot, with large fonts, shows the staples of the Windows 3.1 GUI and the iconic games Minesweeper and Solitaire. The windowed 50-row DOS prompt demonstrates that I am running this on MS-DOS 6.20, and that I'm using a real AMD graphics card with [vendor string](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `(C) 1988-2018, Advanced Micro Devices, Inc.` and [product name](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `NAVI14`.

### Using **third-party** [Calmira XP](https://winworldpc.com/product/calmira/4x) shell

![True-Colour Full HD screenshot of Calmira XP shell, with a photographic wallpaper, showing colour settings (on "Bordeaux"), Character Map, Advanced Task Manager, two MS-DOS prompts (one showing the main menu of Rayman, the other showing VIDMODES.COM output), and Calmira Explorer](./Screenshots/VBESVGA2.BMP.png)

This screenshot showcases the True Colour rendering capability, in the wallpaper (a photo I took [here](https://www.buildingsofireland.ie/buildings-search/building/20907021/annahala-east-cork)) and in the Windows-XP-derived icons used by the Calmira XP shell. The [Advanced Task Manager](https://winworldpc.com/product/advanced-task-manage/1x) instance again confirms that we're on DOS 6.20 and Windows 3.10. It also says we're on a 486, which of course isn't true, but that's just the newest CPU that Windows 3.1 knows about! The 25-row DOS prompt shows the output of `VIDMODES.COM` (see below), confirming again that I'm using a real AMD graphics card with [vendor string](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `(C) 1988-2018, Advanced Micro Devices, Inc.` and [product name](https://fd.lod.bz/rbil/interrup/video/104f00.html) equal to `NAVI14` (reported a bit more legibly this time!). And what's that in the other DOS prompt? That's right, it's _Rayman_ (1995)! Thanks to the new 256-colour-capable grabber (see [below](#graphical-mode-sessions)), _Rayman_ can now be played in a window - it's a bit choppy, but it works!

## Usage Notes

### Hardware Support

In theory, this suite of drivers should support _any_ graphics card that properly supports the VESA BIOS Extensions and doesn't do anything funky with the window size. So basically, any hardware made in the last thirty years. Unfortunately, real life is rarely as simple as one would like, so there is some hardware that just doesn't work:

* Intel 810 chipset integrated graphics [crashes back to DOS during boot](https://github.com/PluMGMK/vbesvga.drv/issues/99) leaving you with a blank screen. It turns out there is an official driver for this chipset, please use that instead: https://archive.org/details/w-810-r-209
* The NVIDIA GeForce 1050 GTX triple-faults when attempting to boot Windows in Enhanced Mode, and presumably newer NVIDIA hardware has the same problem. See [issue #94](https://github.com/PluMGMK/vbesvga.drv/issues/94) for more details.
* The AMD Radeon RX 7800 XT (and presumably newer Radeons) likewise [fails to boot in Enhanced Mode](https://github.com/PluMGMK/vbesvga.drv/issues/95). The RX 5000 series is OK (that's what I develop on), and I don't know what the story is with the RX 6000 series.

In general, if your hardware is old enough, it probably has an official driver for Windows 3.1 (like the i810). Official drivers should be preferred where available because they generally use hardware acceleration and don't use inefficient Real-Mode BIOS calls. On processors from that era (especially early on), the CPU-bound routines of `VBESVGA.DRV` tend to give **really** poor performance!

### Setup / Configuration Procedure

There are a few different ways to setup and configure the driver, according to your tastes and requirements. In all cases, the first step is to extract the `vbesvga-release.zip` archive to a folder on your DOS/Win3.1 machine, or else mount the `vbesvga.img` as a floppy image (or put it on a real floppy).

#### Generic `OEMSETUP.INF`

The `OEMSETUP.INF` file provided in the release archives and images, which can be used with the Windows Setup tool, includes some basic profiles, typical of early SVGA hardware. You can choose a resolution of 640×480, 800×600, 1024×768, or "Automatic", meaning that your monitor's preferred resolution is auto-detected (which falls back to 1024×768 on failure). For each choice of resolution, you can pick 256 (8-bit), 32k (15-bit), 65k (16-bit) or 16M (24-bit) colours, and Large (120-dpi) or Small (96-dpi) fonts.

There is no guarantee that your system will support all of these modes, so you may wish to use one of the other setup methods to get a more customized configuration.

Thanks to @jschwartzenberg, @corma16 and @albertus82 for their help with creating this file!

#### Interactive `SETUP.EXE`

Also included in the release archives and images is the `SETUP.EXE` tool, which is an interactive DOS program. Simply run it, and it will present a configuration interface and copy the required files into your Windows folder. You can use it to select any display mode supported by your hardware, and choose Large or Small fonts. Unlike the `OEMSETUP.INF`, you can also configure the `SwapBuffersInterval` and `BounceOnModeset` values documented below.

Once it installs the driver, it also creates a `VBESVGA.EXE` DOS program in the Windows directory that you can use to reconfigure the driver without reinstalling.

Thanks to @joshudson for creating this tool!

#### Generating a bespoke `OEMSETUP.INF`

You can also use [@albertus82's BASIC script](https://github.com/albertus82/vbesvga-oemsetup/) to generate a bespoke `OEMSETUP.INF` for your machine, and then install the driver using Windows Setup.

#### Using the driver with DBCS versions of Windows / DOS (e.g. Japanese)

Currently, `VDDVBE.386` only supports standard text mode for "message mode" (better known as BSoDs). To boot it on a DBCS version of DOS, you will need to use the shim driver `VDDD.386`, found in the Japanese version of Windows 3.1. This problem probably only arises with DBCS versions of Win9x, which normally support graphical-mode BSoDs, but (for now) cannot do so with this driver.

See also [issue #98](https://github.com/PluMGMK/vbesvga.drv/issues/98).

#### Full list of configuration options

All of these options are recognized in the `[VBESVGA.DRV]` section of `SYSTEM.INI`. You can edit them manually, but the most important ones can be set using the `SETUP.EXE` / `VBESVGA.EXE` tool described above.

|Parameter |Valid values |Meaning |Default value |
--- | --- | --- | ---
|`Width` | 320 - 65535 | Width in pixels of the desired video mode | Your monitor's preferred width, or **1024** if no EDID |
|`Height` | 200 - 65535 | Height in scanlines of the desired video mode | Your monitor's preferred height, or **768** if no EDID |
|`Depth` | 8 - 24 | Significant bits per pixel of the desired video mode ("significant" means that padding bits are excluded, so for example if you choose 24, both 24-bit and 32-bit modes will qualify) | 24 |
|`fontsize` | `small` or `large` | Choose whether to use 96dpi or 120dpi fonts | `small` |
|`dacdepth` | 6, 8 or `auto` | Significant bits to use per colour in 256-colour modes; `auto` means 8 if the BIOS advertises that 8 is supported, 6 otherwise; if 8 is specified then the driver attempts to use 8 regardless of what the BIOS says! | `auto` |
|`SwapBuffersInterval` | 0 - 55 | Time in milliseconds between buffer swaps if [double-buffering](#linear-modes-and-double-buffering) is enabled; specifying a value of 0 **disables** double-buffering | 16 |
|`PreferBankedModes` | 0 or 1 | If set to 1, then the driver searches for bank-switching modes **before** searching for linear modes; may be useful for debugging | 0 |
|`EnableSpecialCaseLinearBlits` | 0 or 1 | If set to 1 (the default), then the driver completely bypasses bank-switching code paths to speed up certain common bit-blit operations when using a linear mode | 1 |
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

[vbesvga.drv]
Width=1440
Height=900
Depth=15
SwapBuffersInterval=15
fontsize=large
```

#### Using debug builds

To use the debug builds, you can place the `VDDVBE.386`, `VBEVMDIB.3GR` and/or `VBESVGA.DRV` files from the `vbesvga-debug.zip` archive (or the `debug` folder in the `vbesvga.img` floppy image) in your `SYSTEM` directory, replacing the ones installed from `vbesvga-release.zip` (or the root directory of `vbesvga.img`). The corresponding `SYM` files can be used with `WDEB386` (supplied with the [Win16 DDK](http://www.win3x.org/win3board/viewtopic.php?t=2776)) or the Open Watcom debugger (only if the `SYM`s are placed in the `SYSTEM` directory).

To make the aforementioned debugger `WDEB386.EXE` work on anything newer than a 486, you need to change some bytes:

* At position `63D8`, you need to change `0F 24 F0` to `66 33 C0`
* At position `63DF`, you need to change `0F 24 F8` to `66 33 C0`

This removes references to the [`TR6` and `TR7` registers](https://en.wikipedia.org/wiki/Test_register), which crash the system since they only existed on the 386, 486 and a few other less-well-known chips!

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

### Mode selection

When Windows boots, the driver queries the BIOS for available modes, and automatically selects the first one which fulfills the following criteria:

* Supported by the current hardware according to the BIOS
* Graphics mode (not text)
* Colour mode (not black & white)
* Resolution matches what was specified in `SYSTEM.INI` (or the monitor's preferred resolution, or the default value of 1024×768)
* Total bit depth (i.e. red+green+blue+padding) is exactly 1, 2, 3 (unless `Allow3ByteMode=0`) or 4 bytes
* Either packed-pixel or direct-colour framebuffer
* Significant bit depth (i.e. red+green+blue but without padding) matches what was specified in `SYSTEM.INI`

The driver searches for linear modes (as defined [below](#linear-modes-and-double-buffering)) first, and if it can't find any (or the system can't support them), it goes back and looks for bank-switching modes (or *vice versa* if `PreferBankedModes=1`). If it can't find any mode matching the above criteria, it will switch the display back to text mode, print an error message and return to DOS. Note that this automatic search is the only way the driver selects modes: you cannot give it a specific VESA mode number to use.

If you know what resolution your monitor and card support, then set the `Width` and `Height` accordingly (or allow them to be autodetected), and the driver will either boot successfully or give you a list of `Depth` values to try (if the default, 24 bits, isn't supported).

If you're not sure which resolution to try, the `VIDMODES.COM` tool included in the releases can list the available modes on your system to give some idea. Example output running under DOSBox-X 2024.07.01[^2]:
```
Your card: 
DOSBox Development Team DOSBox - The DOS Emulator 2

Your monitor: 
[VBIOS failed to return EDID data]

Available VBE video modes:
0100: 640*400*8 Packed-pixel
0101: 640*480*8 Packed-pixel
0102: 800*600*4 EGA-type (NG for VBESVGA.DRV)
0103: 800*600*8 Packed-pixel
0104: 1024*768*4 EGA-type (NG for VBESVGA.DRV)
0105: 1024*768*8 Packed-pixel
0106: 1280*1024*4 EGA-type (NG for VBESVGA.DRV)
0107: 1280*1024*8 Packed-pixel
010D: 320*200*15 Direct-colour, 15S/16T
010E: 320*200*16 Direct-colour, 16S/16T
0110: 640*480*15 Direct-colour, 15S/16T
0111: 640*480*16 Direct-colour, 16S/16T
0113: 800*600*15 Direct-colour, 15S/16T
0114: 800*600*16 Direct-colour, 16S/16T
0116: 1024*768*15 Direct-colour, 15S/16T
0117: 1024*768*16 Direct-colour, 16S/16T
0119: 1280*1024*15 Direct-colour, 15S/16T
011A: 1280*1024*16 Direct-colour, 16S/16T
010F: 320*200*32 Direct-colour, 24S/32T
0112: 640*480*32 Direct-colour, 24S/32T
0115: 800*600*32 Direct-colour, 24S/32T
0118: 1024*768*32 Direct-colour, 24S/32T
01F0: 320*200*32 Direct-colour, 24S/32T
01F1: 640*480*32 Direct-colour, 24S/32T
01F2: 800*600*32 Direct-colour, 24S/32T
01F3: 1024*768*32 Direct-colour, 24S/32T
0151: 320*240*8 Packed-pixel
0153: 320*200*8 Packed-pixel
015C: 512*384*8 Packed-pixel
0159: 400*300*8 Packed-pixel
015D: 512*384*16 Direct-colour, 16S/16T
015A: 400*300*16 Direct-colour, 16S/16T
0160: 320*240*15 Direct-colour, 15S/16T
0161: 320*400*15 Direct-colour, 15S/16T
0162: 320*480*15 Direct-colour, 15S/16T
0165: 640*400*15 Direct-colour, 15S/16T
0136: 320*240*16 Direct-colour, 16S/16T
0170: 320*240*16 Direct-colour, 16S/16T
0172: 320*480*16 Direct-colour, 16S/16T
0175: 640*400*16 Direct-colour, 16S/16T
0190: 320*240*32 Direct-colour, 24S/32T
0201: 640*480*8 Packed-pixel
0202: 800*600*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0203: 800*600*8 Packed-pixel
0204: 1024*768*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0205: 1024*768*8 Packed-pixel
0206: 1280*960*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0207: 1152*864*8 Packed-pixel
0208: 1280*1024*4 Packed-pixel (not byte-aligned => NG for VBESVGA.DRV)
0209: 1152*864*15 Direct-colour, 15S/16T
020A: 1152*864*16 Direct-colour, 16S/16T
020B: 1152*864*32 Direct-colour, 24S/32T
0213: 640*400*32 Direct-colour, 24S/32T

VBESVGA.DRV should boot with default / desired mode 1024*768*24
To check another mode, use /w, /h and /d switches
to specify desired width / height / depth - e.g.:
	vidmodes/w800/h600/d16

VIDMODES.COM from Git commit cf263dc
Total modes found: 53
```
Another example can be seen in the screenshot above, running on real hardware.

You can see that it lists all detected colour graphics modes, showing their resolutions in typical `Width*Height*NominalBitDepth` form. It then indicates the memory model for each one - only *packed-pixel* and *direct-colour* modes are usable with `VBESVGA.DRV`, so all others say "NG" (no good).

Direct-colour modes may have padding bits in each pixel, so the bit depths for these modes are listed with and without padding. The "S" number is what I call the *significant depth*, which excludes padding bits, and the "T" number is the *total depth*, which is the physical size of a pixel in memory. The driver searches for modes whose significant depths match what is specified in `SYSTEM.INI` (or 24 by default), but also makes sure the total depth is divisible by eight. If it is not divisible by eight, then pixels are not byte-aligned, and so those modes are also "NG" as seen above.

You can also use `VIDMODES.COM` as part of a batch file to check whether or not `VBESVGA.DRV` can be expected to boot with certain mode settings. An example usage is given at the end of the output above. The errorlevel is set to:
* `0` (**success**) if a successful boot is expected
* `1` if a corresponding mode is **not** found
* `2` if your graphics card doesn't support VBE at all

### Linear Modes and Double Buffering

The VBE modes used by this driver involve a framebuffer larger than can be addressed by a single segment (65536 bytes). VBE provides two strategies for dealing with this: bank-switching and using linear framebuffers. Bank-switching involves mapping only one segment at a time into physical memory, usually at address `A0000h`, whereas a linear framebuffer gets fully mapped somewhere in extended memory (i.e. beyond the 1-MiB boundary). This driver prefers to use linear modes when available, but unfortunately, due to a bug in `DOSX.EXE`, this is not possible when running Windows in Standard Mode while using `EMM386`. To ensure the driver can use linear framebuffers, you will need to run Windows in 386 Enhanced Mode, or else disable `EMM386`.

When using a linear framebuffer, on a 386 or newer, the driver also attempts to use [Double Buffering](https://wiki.osdev.org/Double_Buffering), which improves performance by ensuring that GDI operations never have to touch video RAM directly. However, it involves allocating two copies of the framebuffer in system RAM, which is quite expensive (especially given that Windows 3.1 usually can't take advantage of more than a quarter of a GiB). If it can't allocate this much RAM, it falls back to direct VRAM access.

Basically, if you're using 386 Enhanced Mode (or Standard Mode without `EMM386`), with a modern graphics card and a decent amount of system RAM, then the driver will probably enable Double Buffering. In that case, you can adjust how often the screen is redrawn using the `SwapBuffersInterval=` setting in `SYSTEM.INI`. The default is 16 ms, which means that the screen is redrawn just over sixty times a second. Unfortunately I haven't found a way to synchronize it to your monitor's blanking interval, meaning that "sixty times a second" and "60fps" won't necessarily line up as well as one might hope (see discussion [here](https://github.com/PluMGMK/vbesvga.drv/issues/55)). Shorter intervals lead to smoother drawing - as long as your CPU can keep up!

If you suspect there are problems with Double Buffering, you can force-disable it by setting `SwapBuffersInterval=0`. This can **significantly** degrade performance for certain operations on large screens, but may be useful for debugging...

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

### `vbevmdib.3gr` (needed only in 386 Enhanced Mode for running graphical DOS programs in windowed mode)

* Place the `VBEGRAB` folder from this repository in the DDK hierarchy, at `386/VBEGRAB`
* Ensure `MSVCVARS.BAT` from Visual C++ has been run to setup the environment
* In addition, ensure `386\TOOLS` from the DDK is in your `PATH`
* Go to the `VBEGRAB` folder and run `nmake`; this should create the file `VBEVMDIB.3GR` which can be loaded by Windows

## `TODO` list

### Things that should probably done before v1.0.0

* Figure out some kind of versioning scheme within the code, ideally integrated with Git (because I'm forgetful!), so user can easily figure out which version of the driver they're installing / running
* Add a [minimum implementation of DCI](https://library.thedatadungeon.com/msdn-2000-04/specs/html/S1CE07.HTM) to `VBESVGA.DRV`
* Make sure the driver works just as well [on Win9x](https://github.com/PluMGMK/vbesvga.drv/issues/46) as it does on Win3.1
* See if `VDDVBE.386` can work [on newer NVIDIA hardware](https://github.com/PluMGMK/vbesvga.drv/issues/94) (I have an affected card but need to swap it in for testing, which is manual-labour-intensive)
* Consider adding a paper-thin implementation of `StretchBlt` to overcome the "zoom-in in Paintbrush" limitation above (basically it would punt straight to GDI for smaller scanline widths, and then for wider ones allocate its own DIB and call out to GDI's `StretchDIBits` function)
* Investigate adding support for colour / animated cursors, for Win9x
* Investigate adding proper support for graphical-mode BSoDs, for DBCS versions of Win9x

### Things that might come later

* Consider efficiency improvements in `swap_buffers` and/or `VDD_SwapBuffers`, to reduce [idle CPU usage](https://github.com/PluMGMK/vbesvga.drv/issues/32)
* Consider adding a virtual RAMDAC to the double-buffering code in `VDDVBE.386` to allow standard 256-colour modes to be emulated on hardware that only supports high-colour VBE modes
* See if `VDDVBE.386` can work [on newer AMD hardware](https://github.com/PluMGMK/vbesvga.drv/issues/95) (I don't have any affected hardware)
* Investigate adding [Windows 3.0 support](https://github.com/PluMGMK/vbesvga.drv/issues/49) (perhaps still requiring a 286, i.e. refusing to boot on anything older)
* Investigate [using VBE/AF](https://github.com/PluMGMK/vbesvga.drv/issues/27) where available for 2D acceleration
* Investigate adding [Windows 1/2 support](https://github.com/PluMGMK/vbesvga.drv/issues/49)

[^1]: Ideally this check would be built into the Windows boot process in the driver, but unfortunately this is basically impossible, since `KRNL386.EXE` appropriates all Conventional Memory during the boot process, and then this gets evicted when you start an MS-DOS Prompt in Standard Mode. So there's really no way to start a TSR from inside Windows that will actually stay resident when you attempt to start a DOS prompt.
[^2]: In the specific case of DOSBox-X, this list can actually be modified using the `VESAMOED` command, which is documented [here](https://dosbox-x.com/wiki/DOSBox%E2%80%90X%E2%80%99s-Supported-Commands) - thanks to @blue-devil-93 for [pointing this out](https://github.com/PluMGMK/vbesvga.drv/issues/84)! More generally, however, this is obviously not the case.
[^3]: Just try running a VGA-mode program under QEMU with hardware virtualization enabled - drawing the display can take several seconds!
[^4]: This setting, also in milliseconds, defines how quickly the display can update in a DOS session window. It is not specific to this driver, but I only found out about it recently, so I thought I should mention it here!
