"""Container/extraction checks with synthetic data, not distributable firmware.

Tests replace the allowlisted hashes only inside each test's module instance.
Production constants remain pinned to the measured Apple/Linux images.
"""
import importlib.util
from pathlib import Path
import struct
import unittest
import zlib


class ExtractionTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            'extract', Path(__file__).resolve().parents[1] / 'tools/extract-firmware.py')
        self.extract = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.extract)
        payload = bytearray(self.extract.SIZE)
        payload[16:20] = b'$PS1'
        struct.pack_into('>I', payload, 0x60, self.extract.VERSION)
        self.payload = bytes(payload)
        template = bytearray(256 + self.extract.SIZE + 16)
        struct.pack_into('<I', template, 0, len(template))
        struct.pack_into('<II', template, 20, self.extract.SIZE, 256)
        template[-16:] = b'table-preserved!'
        self.template = bytes(template)
        self.extract.PAYLOAD_SHA = self.extract.sha(self.payload)
        self.extract.TEMPLATE_SHA = self.extract.sha(self.template)
        self.prefix = bytes.fromhex('cffaedfe') + bytes(28)

    def test_relocated_and_duplicate_payload(self):
        collection = self.prefix + bytes(113) + self.payload + bytes(7) + self.payload
        result, offsets = self.extract.package(collection, self.template)
        self.assertEqual(offsets, [145, 145 + self.extract.SIZE + 7])
        self.assertEqual(result[256:256+self.extract.SIZE], self.payload)
        self.assertEqual(result[256+self.extract.SIZE:], self.template[256+self.extract.SIZE:])
        self.assertEqual(struct.unpack_from('<I', result, 16)[0], self.extract.VERSION)
        self.assertEqual(struct.unpack_from('<I', result, 28)[0], zlib.crc32(self.payload))

    def test_corrupt_payload_rejected(self):
        corrupted = self.payload[:-1] + b'X'
        with self.assertRaisesRegex(ValueError, 'payload not found'):
            self.extract.package(self.prefix + corrupted, self.template)

    def test_corrupt_template_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Unknown Linux firmware template'):
            self.extract.package(self.prefix + self.payload, self.template[:-1] + b'X')

    def test_truncated_payload_rejected(self):
        with self.assertRaisesRegex(ValueError, 'payload not found'):
            self.extract.package(self.prefix + self.payload[:-1], self.template)

    def test_non_macho_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Mach-O'):
            self.extract.package(b'nope' + self.payload, self.template)


if __name__ == '__main__':
    unittest.main()
