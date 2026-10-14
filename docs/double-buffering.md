# Completed drawing and double-buffering

The display driver brackets ordinary GDI screen operations with a nesting count.
Both the Standard Mode copier and enhanced-mode VDD skip swaps while that count
is nonzero. Recursive `ExtTextOut` calls for framebuffer segment bands retain
the outer guard until the entire text operation returns. DCI cursor exclusion
does not acquire the GDI guard: direct surface access may span an entire video.

In enhanced mode, a periodic swap blocked by GDI requests one catch-up copy.
Outermost text completion can service that request without waiting for
another timer to find an idle gap. Empty or quick-clipped text does not request completion. `TEXT_VISIBLE` marks
positive-count text that survives a conservative quick-clipping estimate; it
is not a precise test of the pixels that text will change. Applications can still build a window from multiple
drawing primitives; this does not define whole-window transactions.

## Driver / VDD extension

The existing shared cursor selector contains 16 bytes of screen metadata,
16,384 bytes of interleaved cursor AND/XOR bytes, and the cursor-flags WORD.
It has these append-only extension fields:

| Offset | WORD | Required selector limit |
| --- | --- | --- |
| 16402 | GDI drawing nesting count | 16403 |
| 16404 | Reserved extension | No access |
| 16406 | Pending completion request | 16407 |

The driver checks the actual selector limit before accessing each extension.
An older VDD receives no out-of-range write or new service call. An older
display driver leaves the appended drawing count zero, retaining ordinary
periodic copying. Standard Mode retains its existing local periodic copier.

A blocked running enhanced-mode timer sets the request. Protected VDD service
AX=3 leaves it pending while the drawing count is nonzero. When the count reaches
zero, it consumes the request once and, if periodic publication is still running,
copies the frame using the same generic comparison/cursor routine as the timer.
Completion does not create, cancel or reschedule any timeout. The ordinary timer
still schedules exactly one successor. Stop clears a pending request.

The copy helper loads its current framebuffer size rather than relying on the
timer callback's EDX argument, since protected service clients do not supply that
argument. It preserves the general and segment registers it uses. The 16-bit
completion wrapper preserves the full client state across the VDD entry.
