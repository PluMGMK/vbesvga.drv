# DOSBox integration frame publication, version 1

This optional interface lets an emulator publish an owned snapshot of the
double-buffered 8-bit display without emulating the full front-buffer comparison
and video-memory update. The ordinary path remains available when negotiation
or submission fails. The driver issues no integration I/O unless
`[vbesvga.drv] DOSBoxPublish=1` is explicitly set.

## Integration transport

The existing DOSBox integration device uses index port `0x28`, data port `0x29`,
and command/status port `0x2a`. Indices and data are DWORD accesses. Before
touching indexed state, issue byte command PUSH_STATE (`0x20`) and check status
error bit 1. Only a successful push is paired with POP_STATE (`0x21`), including
negotiation and submission failures. This preserves other clients' latches,
including the mouse driver. A failed push must never pop another client's state.

| Index | Access | Meaning |
| --- | --- | --- |
| `0x00684582` | Read | Capability value `0x57333101` |
| `0x00684583` | Write | Submit descriptor at this guest linear address |
| `0x00684583` | Read | Status of the preceding submission; no repeated submission |
| `0x00684584` | Write zero | Cancel the pending snapshot |
| `0x00684584` | Read | Cancellation status |

## Submission descriptor

Ten little-endian DWORDs, 40 bytes in total:

| Offset | Field | Value |
| --- | --- | --- |
| 0 | Size | 40 |
| 4 | Version | 1 |
| 8 | Back buffer | Current guest linear address |
| 12 | Reserved front pointer | Zero |
| 16 | Cursor data | Current guest linear address |
| 20 | Frame bytes | Stride multiplied by height |
| 24 | Stride | Bytes per scanline; equal to width in this version |
| 28 | Width | Current display width |
| 32 | Height | Current display height |
| 36 | Bits per pixel | 8 |

Submission status is 0 for accepted, 1 for unsupported context/mode, 2 for invalid
descriptor/geometry, 3 for invalid memory and 4 for invalid cursor metadata.
The host validates geometry arithmetic, current mode, page mappings, RAM
backing, source ranges and cursor clipping before accepting anything. It copies
all source data immediately into host-owned storage, writes no guest memory,
and retains no guest address for later access. A rejected submission also
discards any older pending snapshot.

The cursor snapshot is the existing 16-byte screen metadata, 16,384 bytes of
interleaved AND/XOR byte pairs, and a cursor-flags WORD (bit 2 means visible):
16,402 bytes total. The host composes the cursor from this snapshot. Neither
the guest front-cache buffer nor the appended driver/VDD fields are host inputs.

The host publishes between completion of its previous renderer update and the
start of its next one. This preserves a complete display snapshot while guest
drawing continues. On host failure after an earlier accepted submission, the
VDD cancels pending host output and invalidates its front cache against the
desired frame, including the cursor, before resuming generic comparison/copy.

## Display driver / VDD extension

The generic [double-buffering extension](double-buffering.md) defines nested
GDI guards and the one-shot completion service. This publisher uses its reserved
WORD at16404 and appends one further field:

| Offset | WORD | Required selector limit |
| --- | --- | --- |
| 16402 | GDI drawing nesting count | 16403 |
| 16404 | Host publication opt-in | 16405 |
| 16406 | Pending completion request | 16407 |
| 16408 | Snapshot ownership (0 ordinary, 1 timer, 2 completed text) | 16409 |

The driver checks selector limits before accessing extensions or calling the
new service. Existing drivers leave the opt-in zero, so adding the VDD alone
retains generic publication without integration I/O. Old VDDs never receive the
new AX4 service. Generic completion remains available independently of host
support or configuration.

Periodic and text-completion paths call the same publisher. Accepted periodic
snapshots are timer-owned unless they refresh a completed-text snapshot before
its next outer drawing begin. Completed-text ownership survives those refreshes:
otherwise a timer could replace a completed snapshot and make it revocable
before the host presents it. At the first outermost GDI begin (depth1), AX4
consumes completed-text ownership without cancellation. A timer-owned snapshot
is instead cancelled, rearming one completion request. Nested begins do not
consume ownership or cancel snapshots. This coalesces primitive updates without
discarding every animation frame while the next one is being drawn. It is not an application transaction boundary and
cannot undo an image the host already committed.

Cancellation preserves the last committed display and touches only the pending
snapshot. The VDD checks cancellation status and preserves unresolved ownership
if the transport push or command fails. A subsequent accepted complete-frame
submission replaces that older pending frame. During generic fallback, an
unresolved cancellation retains the front-cache invalidation requirement on
each copy, so a late old host frame cannot leave cache and VRAM permanently
inconsistent. Stop clears the generic completion request; stop/setup attempt
cancellation and retain unresolved ownership on failure for later recovery.

The host protocol and 16,402-byte cursor snapshot remain version1. The additional
fields and AX4 are negotiated only between the display driver and VDD, without
changing the host register interface or retaining guest pointers.
