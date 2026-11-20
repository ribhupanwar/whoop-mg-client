"""CI guard for the approved STRAP home score ring styling.

Source-level checks for shared geometry and typography.
"""
from pathlib import Path
import unittest

HOME = Path(__file__).resolve().parents[1] / "ios" / "Strap" / "HomeView.swift"


class HomeRingGeometryGuardTests(unittest.TestCase):
    def test_percent_sign_uses_bold_din_weight(self):
        components = (HOME.parent / "Components.swift").read_text(encoding="utf-8")
        self.assertRegex(
            components,
            r'Text\("%"\)\s*\.font\(StrapTypography\.metric\(size \* (?:AppLayout\.percentSignScale|0\.72), weight: \.bold\)\)',
            "Percent sign should retain approved bold DIN typography.",
        )

    def test_primary_score_ring_stroke_and_center_font(self):
        source = HOME.read_text(encoding="utf-8")
        self.assertIn("RingView(progress: progress, color: color, size: ringSize, centerText: text)", source)
        self.assertEqual(source.count("ringSize: diameter"), 3)

    def test_ring_gap_is_18_pt(self):
        source = HOME.read_text(encoding="utf-8")
        self.assertIn("HStack(spacing: AppLayout.ringGap)", source)


if __name__ == "__main__":
    unittest.main()
