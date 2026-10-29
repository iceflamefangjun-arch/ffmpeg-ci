"""Exercise the built FFmpeg demuxers, without compiling or modifying inputs.

python tests/test-disc-demux.py --ffprobe <matching ffprobe.exe>
Add --samples <bluray-ISO directory> to include all nine real images.
The synthetic payloads are deliberately not decodable ATRAC: these tests inspect
demuxed packet bytes and timestamps, not successful audio decoding.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest


FFPROBE = None
SAMPLES = None
SECTOR = 2048


def both16(value):
    return struct.pack("<H", value) + struct.pack(">H", value)


def both32(value):
    return struct.pack("<I", value) + struct.pack(">I", value)


def directory_record(name, extent, size, directory=False):
    record = bytearray(33 + len(name) + (len(name) % 2 == 0))
    record[0] = len(record)
    record[2:10] = both32(extent)
    record[10:18] = both32(size)
    record[25] = 2 if directory else 0
    record[28:32] = both16(1)
    record[32] = len(name)
    record[33:33 + len(name)] = name
    return record


def umd_iso(program):
    """A minimal ISO9660 UMD image; no proprietary media is embedded."""
    output = bytearray(max(40, 24 + (len(program) + SECTOR - 1) // SECTOR) * SECTOR)
    pvd = bytearray(SECTOR)
    pvd[:7] = b"\x01CD001\x01"
    pvd[40:72] = b"UMD REGRESSION".ljust(32, b" ")
    pvd[80:88] = both32(len(output) // SECTOR)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(SECTOR)
    root = directory_record(b"\0", 20, SECTOR, True)
    pvd[156:156 + len(root)] = root
    output[16 * SECTOR:17 * SECTOR] = pvd
    output[17 * SECTOR:17 * SECTOR + 7] = b"\xffCD001\x01"
    for sector, parent, child in (
        (20, 20, directory_record(b"UMD_VIDEO", 21, SECTOR, True)),
        (21, 20, directory_record(b"STREAM", 22, SECTOR, True)),
        (22, 21, directory_record(b"00001.MPS;1", 24, len(program))),
    ):
        entries = (directory_record(b"\0", sector, SECTOR, True)
                   + directory_record(b"\1", parent, SECTOR, True) + child)
        output[sector * SECTOR:sector * SECTOR + len(entries)] = entries
    output[24 * SECTOR:24 * SECTOR + len(program)] = program
    return output


def timestamp(value):
    return bytes((0x21 | ((value >> 29) & 14), (value >> 22) & 255,
                  ((value >> 14) & 254) | 1, (value >> 7) & 255,
                  ((value << 1) & 254) | 1))


def pes(track, data, pts=None, first_frame=0):
    header = b"\x80\x00\x00" if pts is None else b"\x80\x80\x05" + timestamp(pts)
    body = header + bytes((track, 0)) + struct.pack(">H", first_frame) + data
    return b"\0\0\1\xbd" + struct.pack(">H", len(body)) + body


def frame(marker):
    payload = bytes((marker,)) * 128
    return b"\x0f\xd0\x48\x10\0\0\0\0" + payload


def probe(arguments):
    result = subprocess.run([str(FFPROBE), "-v", "error", *arguments],
                            capture_output=True, timeout=120)
    if result.returncode:
        raise AssertionError(result.stderr.decode("utf-8", "replace"))
    return json.loads(result.stdout)


class UmdPackets(unittest.TestCase):
    def packets(self, program):
        with tempfile.TemporaryDirectory(prefix="umd-packets-") as directory:
            path = Path(directory) / "fixture.iso"
            path.write_bytes(umd_iso(program))
            result = probe(["-f", "mpeg", "-show_packets",
                            "-show_streams", "-show_data_hash", "sha256", "-of", "json",
                            "umd://" + str(path)])
        ids = {s["index"]: int(s["id"], 0) for s in result.get("streams", [])}
        return [(ids[p["stream_index"]], p) for p in result.get("packets", [])]

    def assert_payloads(self, packets, expected):
        actual = [(track, packet["size"], packet["data_hash"].lower())
                  for track, packet in packets]
        wanted = [(track, "128", "sha256:" + hashlib.sha256(bytes((marker,)) * 128).hexdigest())
                  for track, marker in expected]
        self.assertEqual(actual, wanted)

    def test_legacy_08_and_multiple_frames_per_pes(self):
        packets = self.packets(pes(8, frame(0x31) + frame(0x32), 90000))
        self.assert_payloads(packets, [(8, 0x31), (8, 0x32)])
        self.assertEqual(int(packets[0][1]["pts"]), 90000)
        self.assertAlmostEqual(int(packets[1][1]["pts"]), 90000 + 2048 * 90000 / 44100, delta=1)

    def test_interleaved_tracks_and_fragment_timestamps(self):
        a, b, c, d = (frame(marker) for marker in (0x41, 0x42, 0x43, 0x44))
        program = (pes(0, a[:17], 90000) + pes(1, b, 180000)
                   + pes(2, c[:1], 270000) + pes(0, a[17:] + d, 360000, len(a) - 17)
                   + pes(2, c[1:], first_frame=0xffff))
        packets = self.packets(program)
        self.assert_payloads(packets, [(1, 0x42), (0, 0x41), (0, 0x44), (2, 0x43)])
        self.assertEqual([int(p["pts"]) for _, p in packets], [180000, 90000, 360000, 270000])
        self.assertEqual([int(p["dts"]) for _, p in packets], [180000, 90000, 360000, 270000])

    def test_sync_word_split_after_junk(self):
        audio = frame(0x51)
        packets = self.packets(pes(8, b"broken" + audio[:1], first_frame=0xffff)
                               + pes(8, audio[1:], first_frame=0xffff))
        self.assert_payloads(packets, [(8, 0x51)])

    def test_invalid_empty_frame_does_not_stall(self):
        packets = self.packets(pes(8, b"\x0f\xd0\x48\x00\0\0\0\0" + frame(0x61)))
        self.assert_payloads(packets, [(8, 0x61)])


# Keep this inventory aligned with SHPlayer's DiscProbeSamples tests.
REAL_SAMPLES = (
    ("bluray/Planet.iso", "bluray", 3171.168, 1),
    ("bluray/House.iso", "bluray", 3938.101, 2),
    ("bluray/House.of.the.Dragon.S01E02.2022.UHD.BluRay.2160p.HEVC.Atmos.TrueHD7.1-TAG.iso",
     "bluray", 3232.896, 2),
    ("bluray/Black Hawk Down 2001 UHD Blu-ray 2160p HEVC TrueHD Atmos 7.1-TAG.iso",
     "bluray", 9110.601, 8),
    ("bluray/Wubai&ChinaBlue-Light&HotLiveInTaipei20141080iBlu-rayAVCDTS-HDMA5.1-TTG.iso",
     "bluray", 11551.240, 4),
    ("John.Wick.Chapter.4.2023.UHD.BluRay.2160p.HEVC.Atmos.TrueHD7.1-TAG.iso",
     "bluray", 10158.148, 2),
    ("dvd/Japan.iso", "dvd", 2422.186, 1),
    ("dvd/刘德华.-.[刘德华99演唱会].演唱会.(DVDISO).iso", "dvd", 7008.7, 3),
    ("other/Hero[UCUS-98853].iso", "umd", 5950.328, 3),
)


class RealImages(unittest.TestCase):
    def test_all_nine_images(self):
        for relative, kind, duration, audio_count in REAL_SAMPLES:
            with self.subTest(sample=relative):
                path = SAMPLES / relative
                self.assertTrue(path.is_file(), str(path))
                options = ["-f", "dvdvideo"] if kind == "dvd" else []
                if kind == "bluray":
                    options += ["-analyzeduration", "30000000", "-probesize", "50000000"]
                url = str(path) if kind == "dvd" else kind + "://" + str(path).replace(" ", "%20")
                result = probe([*options, "-show_streams", "-show_format", "-show_chapters",
                                "-of", "json", url])
                streams = result.get("streams", [])
                actual_audio = [s for s in streams if s.get("codec_type") == "audio"]
                self.assertTrue(any(s.get("codec_type") == "video" for s in streams))
                self.assertGreaterEqual(len(actual_audio), audio_count)
                self.assertAlmostEqual(float(result["format"]["duration"]), duration, delta=2)
                if kind == "umd":
                    self.assertEqual({int(s["id"], 0) for s in actual_audio}, {0, 1, 2})
                    self.assertTrue(all(s["codec_name"] == "atrac3p" for s in actual_audio))
                if kind == "dvd":
                    previous = 0
                    for chapter in result.get("chapters", []):
                        start, end = float(chapter["start_time"]), float(chapter["end_time"])
                        self.assertGreaterEqual(start, previous - 0.01)
                        self.assertGreater(end, start)
                        self.assertLessEqual(end, duration + 2)
                        previous = end
                print(json.dumps({"sample": relative, "duration": result["format"]["duration"],
                                  "audio_tracks": len(actual_audio), "status": "demux_pass"},
                                 ensure_ascii=False), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffprobe", type=Path, required=True)
    parser.add_argument("--samples", type=Path)
    args = parser.parse_args()
    FFPROBE, SAMPLES = args.ffprobe.resolve(), args.samples
    for binary in (FFPROBE, FFPROBE.parent / "avformat-61.dll"):
        if binary.is_file():
            print(json.dumps({"binary": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()}),
                  flush=True)
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(UmdPackets)
    if SAMPLES is not None:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(RealImages))
    raise SystemExit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
