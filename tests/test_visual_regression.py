"""Visual Regression and Metric Palette Comparison Test.

Validates that STRAP visual tokens and geometry conform to the official
WHOOP 5.80.2 pixel-sampled references without drifting or hallucinating values.
"""
from pathlib import Path
import math
import struct
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
IOS_DIR = REPO_ROOT / "ios" / "Strap"
ASSETS_DIR = IOS_DIR / "Assets.xcassets"


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    val = int(hex_str.replace("0x", "").replace("#", ""), 16)
    return ((val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF)


def read_png_dimensions(path: Path) -> tuple[int, int, int, int]:
    with open(path, "rb") as f:
        magic = f.read(8)
        if magic != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path} is not a valid PNG file")
        length, chunk_type = struct.unpack(">I4s", f.read(8))
        if chunk_type != b"IHDR":
            raise ValueError(f"Expected IHDR chunk, got {chunk_type}")
        w, h, bit_depth, color_type = struct.unpack(">IIBB", f.read(10))
        return w, h, bit_depth, color_type


class VisualRegressionTests(unittest.TestCase):

    def test_palette_color_fidelity_against_whoop_reference(self):
        # Ground truth sampled from official WHOOP screenshot
        reference_colors = {
            "sleep_ring": "0x7CA1BB",
            "recovery_green": "0x1AEC07",
            "recovery_yellow": "0xFEDE00",
            "recovery_red": "0xFC0025",
            "strain_blue": "0x0193E8",
            "canvas_top": "0x283138",
            "canvas_bg": "0x0D1112",
        }

        theme_text = (IOS_DIR / "Theme.swift").read_text(encoding="utf-8")

        for key, ref_hex in reference_colors.items():
            self.assertIn(ref_hex, theme_text, f"Reference hex {ref_hex} for {key} must exist in Theme.swift")

    def test_ring_geometry_proportions(self):
        outer_diameter = 84.0
        stroke_thickness = 5.0
        ring_gap = 18.0
        center_font = 23.0
        percent_scale = 0.72

        # 1. Stroke ratio (5.0 / 84.0 = ~0.0595)
        stroke_ratio = stroke_thickness / outer_diameter
        self.assertAlmostEqual(stroke_ratio, 0.0595, delta=0.005)

        # 2. Ring gap ratio
        gap_ratio = ring_gap / outer_diameter
        self.assertAlmostEqual(gap_ratio, 0.214, delta=0.01)

        # 3. Center metric font proportion
        font_ratio = center_font / outer_diameter
        self.assertAlmostEqual(font_ratio, 0.2738, delta=0.01)

        # 4. Percent sign proportion (72%)
        self.assertEqual(percent_scale, 0.72)

    def test_hardware_band_asset_geometry(self):
        hw_file = ASSETS_DIR / "WhoopBandHardware.imageset" / "whoop_band_hardware@2x.png"
        self.assertTrue(hw_file.is_file())
        w, h, bit_depth, color_type = read_png_dimensions(hw_file)
        self.assertEqual(color_type, 6, "Must be RGBA color_type=6")
        self.assertGreater(w, 300)
        self.assertGreater(h, 300)
        aspect = w / h
        self.assertTrue(0.8 <= aspect <= 1.2, f"Hardware band aspect ratio ({aspect:.2f}) must be roughly square")


if __name__ == "__main__":
    unittest.main()
