#!/bin/bash
# Read-only guard against linking libraries built with different IFO layouts.
set -euo pipefail

dvdread_output="$1"
header="${dvdread_output}/include/dvdread/ifo_types.h"
stamp="${dvdread_output}/lib/dvdread-ifo-types.sha256"
if [ ! -f "${header}" ] || [ ! -f "${stamp}" ] ||
   ! grep -Fq 'DVDREAD_LAYOUT_ASSERT(cell_playback,' "${header}"; then
    echo "Rebuild libdvdread with the IFO layout fix: ${dvdread_output}" >&2
    exit 1
fi
actual="$(sha256sum "${header}" | cut -d ' ' -f 1)"
if [ "$(cat "${stamp}")" != "${actual}" ]; then
    echo "libdvdread header changed after its library was built: ${dvdread_output}" >&2
    exit 1
fi
if [ "$#" -gt 1 ]; then
    nav_stamp="$2/lib/dvdread-ifo-types.sha256"
    if [ ! -f "${nav_stamp}" ] || [ "$(cat "${nav_stamp}")" != "${actual}" ]; then
        echo "Rebuild libdvdnav against this libdvdread before building FFmpeg: $2" >&2
        exit 1
    fi
fi
