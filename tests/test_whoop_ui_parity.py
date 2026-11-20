"""WHOOP UI Parity, Original Assets & Device Action Audit Guard Tests.

Guards:
1. Genuine WHOOP hardware and wordmark asset catalog presence, validity, and aspect ratios.
2. Centralized color tokens sampled from official WHOOP reference screenshots.
3. Ring geometry constants (84 pt / 104 pt diameter, 5.0 pt stroke, 18.0 pt gap, 23 pt DIN Pro font, 72% percent scale).
4. Home view header branding and accessibility identity preservation.
5. Device settings layout, genuine hardware hero, battery gauge, and command quarantine safety.
6. Licensed font preservation (DIN Pro, Proxima Nova).
"""
from pathlib import Path
import json
import re
import struct
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
IOS_DIR = REPO_ROOT / "ios" / "Strap"
ASSETS_DIR = IOS_DIR / "Assets.xcassets"
FONTS_DIR = IOS_DIR / "Fonts"


def read_png_dimensions(path: Path) -> tuple[int, int, int, int]:
    """Read width, height, bit_depth, color_type from standard PNG IHDR without third-party dependencies."""
    with open(path, "rb") as f:
        magic = f.read(8)
        if magic != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path} is not a valid PNG file")
        length, chunk_type = struct.unpack(">I4s", f.read(8))
        if chunk_type != b"IHDR":
            raise ValueError(f"Expected IHDR chunk, got {chunk_type}")
        w, h, bit_depth, color_type = struct.unpack(">IIBB", f.read(10))
        return w, h, bit_depth, color_type


class WhoopUIParityTests(unittest.TestCase):

    def test_wordmark_asset_catalog_integrity(self):
        wordmark_dir = ASSETS_DIR / "WhoopWordmark.imageset"
        self.assertTrue(wordmark_dir.is_dir(), "WhoopWordmark.imageset must exist")

        contents_file = wordmark_dir / "Contents.json"
        self.assertTrue(contents_file.is_file(), "Contents.json must exist in WhoopWordmark.imageset")
        with open(contents_file, "r", encoding="utf-8") as f:
            meta = json.load(f)
        self.assertIn("images", meta)

        for scale, fname in [("1x", "wordmark.png"), ("2x", "wordmark@2x.png"), ("3x", "wordmark@3x.png")]:
            img_path = wordmark_dir / fname
            self.assertTrue(img_path.is_file(), f"{fname} must exist")
            w, h, bit_depth, color_type = read_png_dimensions(img_path)
            self.assertEqual(color_type, 6, f"{fname} must be RGBA (color_type=6)")
            self.assertGreater(w, h, f"{fname} must have horizontal wordmark aspect ratio")
            aspect = w / h
            self.assertTrue(5.5 <= aspect <= 6.5, f"Wordmark aspect ratio ({aspect:.2f}) must match ~6.1")

    def test_band_hardware_asset_catalog_integrity(self):
        hardware_dir = ASSETS_DIR / "WhoopBandHardware.imageset"
        self.assertTrue(hardware_dir.is_dir(), "WhoopBandHardware.imageset must exist")

        contents_file = hardware_dir / "Contents.json"
        self.assertTrue(contents_file.is_file(), "Contents.json must exist in WhoopBandHardware.imageset")

        for scale, fname in [("1x", "whoop_band_hardware.png"), ("2x", "whoop_band_hardware@2x.png"), ("3x", "whoop_band_hardware@3x.png")]:
            img_path = hardware_dir / fname
            self.assertTrue(img_path.is_file(), f"{fname} must exist")
            w, h, bit_depth, color_type = read_png_dimensions(img_path)
            self.assertEqual(color_type, 6, f"{fname} must be RGBA (color_type=6)")
            self.assertGreater(w, 100, f"{fname} width must be valid")
            self.assertGreater(h, 100, f"{fname} height must be valid")

    def test_theme_color_tokens(self):
        theme_src = (IOS_DIR / "Theme.swift").read_text(encoding="utf-8")
        expected_tokens = {
            "appCanvasTop": "0x252E34",
            "appCanvasMid": "0x161C20",
            "appBG": "0x0E1316",
            "appSurface": "0x1D2429",
            "appRaised": "0x252D33",
            "appCardBorder": "0x303940",
            "appSleep": "0x7EA3B9",
            "appGood": "0x00E676",
            "appWarn": "0xFFDE00",
            "appHigh": "0xFF3B30",
            "appAccent": "0x0091FF",
            "appRingTrack": "0x2A333A",
            "appButtonFill": "0x2A3339",
        }
        for token, hex_val in expected_tokens.items():
            pattern = rf"static\s+let\s+{token}\s*=\s*Color\(hex:\s*{hex_val}\)"
            self.assertRegex(theme_src, pattern, f"Token {token} must be defined with hex {hex_val}")

    def test_ring_geometry_constants(self):
        theme_src = (IOS_DIR / "Theme.swift").read_text(encoding="utf-8")
        expected_geometry = {
            "heroRingDiameter": "84.0",
            "detailRingDiameter": "104.0",
            "ringStrokeWidth": "5.0",
            "ringGap": "18.0",
            "heroMetricFontSize": "23.0",
            "percentSignScale": "0.72",
        }
        for const, val in expected_geometry.items():
            pattern = rf"static\s+let\s+{const}:\s*CGFloat\s*=\s*{val}"
            self.assertRegex(theme_src, pattern, f"Ring geometry constant {const} must be {val}")

    def test_home_view_header_wordmark_and_identity(self):
        home_src = (IOS_DIR / "HomeView.swift").read_text(encoding="utf-8")
        self.assertIn('Image("WhoopWordmark")', home_src)
        self.assertIn('.frame(height: 14)', home_src)
        self.assertIn('"STRAP · WHOOP Client"', home_src)
        # Ensure hardcoded approximate "STRAP" text heading is replaced
        self.assertNotIn('Text("STRAP")\n                    .font', home_src.replace("\r\n", "\n"))
        # Ensure user initials avatar and personalized greeting title
        self.assertIn("userInitials", home_src)
        self.assertIn("outlookTitle", home_src)

    def test_workout_diagnostics_exporter_present(self):
        diag_path = IOS_DIR / "Analysis" / "WorkoutDiagnostics.swift"
        self.assertTrue(diag_path.is_file(), "WorkoutDiagnostics.swift must exist in ios/Strap/Analysis")
        diag_src = diag_path.read_text(encoding="utf-8")
        self.assertIn("enum WorkoutDiagnostics", diag_src)
        self.assertIn("static func csv(", diag_src)
        self.assertIn("heart_rate_bpm", diag_src)
        self.assertIn("is_workout_epoch", diag_src)

    def test_device_settings_hardware_and_quarantine(self):
        home_src = (IOS_DIR / "HomeView.swift").read_text(encoding="utf-8")
        # Ensure genuine BandIllustrationView is used
        self.assertIn("BandIllustrationView(", home_src)
        # Ensure vertical battery indicator is present
        self.assertIn("Capsule().fill(batteryColor)", home_src)
        # Ensure reboot command is verified and destructive erase remains quarantined with explicit notice
        self.assertIn('deviceRow("REBOOT DEVICE"', home_src)
        self.assertIn("Verified warm restart", home_src)
        self.assertIn('deviceRow("ERASE DEVICE DATA"', home_src)
        self.assertIn("protects stored circular buffer", home_src)

    def test_licensed_fonts_integrity(self):
        required_fonts = [
            "DINPro-Bold.ttf",
            "DINPro-Light.ttf",
            "DINPro-Regular.ttf",
            "ProximaNova-Bold.ttf",
            "ProximaNova-Regular.ttf",
            "proxima-nova-medium.ttf",
            "proxima-nova-semibold.ttf",
        ]
        for f in required_fonts:
            p = FONTS_DIR / f
            self.assertTrue(p.is_file(), f"Licensed font {f} must exist in ios/Strap/Fonts")
            self.assertGreater(p.stat().st_size, 1000, f"Font {f} must be non-empty")


if __name__ == "__main__":
    unittest.main()
