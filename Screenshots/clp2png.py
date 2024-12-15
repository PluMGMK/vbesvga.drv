#!/usr/bin/python3
from PIL import Image
from sys import argv
from construct import *
import os.path

if len(argv) < 2:
    print("You need to specify the CLP path as an argument!")
    exit()

BITMAP = Struct(
        "bmType" / Const(0,Int16ul) * "Must be a memory bitmap",
        "bmWidth" / Int16ul * "Width in pixels",
        "bmHeight" / Int16ul * "Height in rows",
        "bmWidthBytes" / Int16ul * "Width in bytes",
        "bmPlanes" / Int8ul * "Planes in the bitmap (we only deal with flat ones)",
        "bmBitsPixel" / Int8ul * "Bits per pixel",
        "bmBits" / Const(0,Int32ul) * "In a file, the pointer is NULL",
        "Bits" / Bytes(this.bmHeight * this.bmWidthBytes) * "In a file, the actual data directly follows the header",
        )

FORMATRECORD = Struct(
        "FormatId" / Int16ul,
        "DataLength" / Int32ul,
        "DataOffset" / Int32ul,
        "FormatName" / CString("ascii"),
        "Data" / Pointer(this.DataOffset,
            Switch(this.FormatId, {2: BITMAP,}, Bytes(this.DataLength))
        ),
        )

CLPHEADER = Struct(
        "FileId" / Const(0xC350,Int16ul),
        "FormatCount" / Int16ul,
        "ClpRecords" / Array(this.FormatCount, FORMATRECORD),
        )

clpfilename = argv[-1]
clpbasename = os.path.basename(clpfilename) # For saving result into cwd
clpfile = CLPHEADER.parse_file(clpfilename)

for idx,record in enumerate(clpfile.ClpRecords):
    if "Bitmap" not in record.FormatName:
        print(f"Record {idx} not a bitmap, skipping...")
        continue
    bitmap = record.Data
    if bitmap.bmPlanes > 1:
        print(f"Record {idx} not a flat bitmap, skipping...")
        continue
    # We have a good flat bitmap, get its size into a tuple
    size = (bitmap.bmWidth, bitmap.bmHeight)
    if bitmap.bmBitsPixel == 24:
        image = Image.frombytes("RGB",size,bitmap.Bits)
    elif bitmap.bmBitsPixel == 32:
        # The extra eight bits are just padding
        image = Image.frombytes("RGBX",size,bitmap.Bits).convert("RGB")
    else:
        print(f"Record {idx} is a {bitmap.bmBitsPixel}-bit bitmap, but only 24- or 32-bit are supported, skipping...")
        continue
    # A lot of the time, these DDBs are actually BGR or BGRA
    if "--swapchan" in argv:
        b,g,r = image.split()
        image = Image.merge("RGB",(r,g,b))
    # Save it as a PNG
    pngname = f"{clpbasename}.rec{idx}.png"
    print(f"Saving record {idx} as {pngname}...")
    image.save(pngname)
