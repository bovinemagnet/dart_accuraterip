# test/fixtures

Captured AccurateRip database response files used for golden tests.

## dBAR-002-0000f21c-00027ef8-05021002.bin

A real 62-byte AccurateRip database response for a 2-track disc,
containing two pressings (i.e. two chunks of equal length).

**Source:** [whipper-team/whipper][whipper], GPL-3.0, at commit
[`bbed92bb3070af8f85d1148970f3269a97abcdb3`][sha], file path
`whipper/test/dBAR-002-0000f21c-00027ef8-05021002.bin`.

**Upstream copyright:**

    Copyright (C) 2017 Samantha Baldwin
    Copyright (C) 2009 Thomas Vander Stichele

Redistributed here under the GNU General Public License v3.0, the
same licence as `dart_accuraterip` itself. See [`../../LICENSE`](
../../LICENSE) for the full text.

The fixture is used verbatim — not modified. The expected parsed
values pinned by `test/accuraterip_golden_test.dart` were taken
from whipper's own `test/test_common_accurip.py`, cross-checked
against the raw bytes, and cross-referenced against CUETools.NET's
entry layout in `CUETools.AccurateRip/AccurateRip.cs`.

### Wire-format note

Each 9-byte entry in an AccurateRip response chunk is:

    confidence : u8
    crc        : u32 little-endian   (the server's stored CRC — may be
                                      an AR v1 or AR v2 value depending
                                      on which era the submitter used)
    frame450Crc: u32 little-endian   (CRC over the first 450 frames,
                                      used by CUETools for drive-offset
                                      detection; can be zero for older
                                      submissions)

There is **no separate `crcV1`/`crcV2` pair per entry.** To verify
a rip, compute both `computeArV1` and `computeArV2` locally and
match either against `entry.crc`. See `AccurateRipEntry.matches`.

[whipper]: https://github.com/whipper-team/whipper
[sha]: https://github.com/whipper-team/whipper/commit/bbed92bb3070af8f85d1148970f3269a97abcdb3
