---
name: Boot failure
about: Report a situation where Windows fails to boot with the driver installed
title: "[BOOTFAIL]"
labels: bug
assignees: ''

---

**Driver version**
Please specify the version number, or Git commit if you built it yourself, and whether you're using a debug or release build

**Windows version**
E.g. Windows 3.1, WfW 3.11, Windows 95, Windows 98 FE/SE, Windows Me

**Windows Operating mode**
Standard, Enhanced, or Both (for WfW 3.11 or later, it will always be Enhanced)

**Have you checked the integrity of the driver files as per instructions in `README.md`?**
(If the answer is no, please try that first, if you can, just to make sure)

**Does boot failure also occur with standard VGA driver?**
(If the answer is yes, maybe this shouldn't be filed as an issue here! Depending on your hardware configuration, you may want to try `patcher9x` and/or `ahcifix.386` to make these old Windows versions boot.)

**Type of Machine (Real or Virtual)**
E.g. Real machine with BIOS firmware, Real machine with UEFI firmware, VMware VM, VirtualBox VM, QEMU VM, etc.

**Are you running a DOS memory manager?**
E.g. EMM386, QEMM, etc.
If so, does the issue still occur without it?

**`VIDMODES.COM` output**
```
<Please paste your VIDMODES output in here>
```

**Type of Boot Failure**
Freeze on Windows logo, Freeze on blank screen, Error message and crash to DOS, Silent crash to DOS

**Is keyboard responsive after attempting to boot?**
(For example, what happens if you try to toggle Num Lock, or press Ctrl+Alt+Del?)

**Additional context**
Add any other context about the problem here.
