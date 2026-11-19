"""CI guard for the approved STRAP home score ring styling.

Source-level regression check only; device pixel parity still needs screenshots.
"""
from pathlib import Path
import re
import unittest

HOME = Path(__file__).resolve().parents[1] / "ios" / "Strap" / "HomeView.swift"


class HomeRingGeometryGuardTests(unittest.TestCase):
    def test_percent_sign_uses_bold_din_weight(self):
        components = (HOME.parent / "Components.swift").read_text(encoding="utf-8")
        self.assertRegex(
            components,
            r'Text\("%"\)\s*\.font\(StrapTypography\.metric\(size \* 0\.72, weight: \.bold\)\)',
            "Percent sign should retain approved bold DIN typography.",
        )

    def test_primary_score_ring_stroke_and_center_font(self):
        source = HOME.read_text(encoding="utf-8")
        calls = re.findall(
            r"RingView\(progress:\s*progress,\s*color:\s*color,\s*lineWidth:\s*([0-9.]+),\s*size:\s*ringSize,\s*centerText:\s*text,\s*centerFont:\s*([0-9.]+)\)",
            source,
        )
        self.assertEqual(
            calls,
            [("6.0", "27")],
            "Approved Sleep/Recovery/Strain ring style changed: expected stroke=6.0 and centerFont=27. Update only after visual approval.",
        )


if __name__ == "__main__":
    unittest.main()
