import unittest
from tools.compare_sleep_epochs import compare


class SleepEpochComparisonTests(unittest.TestCase):
    def test_exact_and_shifted_boundaries(self):
        reference = {0:"wake",30:"light",60:"deep",90:"wake",120:"rem",150:"wake"}
        exact = compare(reference, reference)
        self.assertEqual(exact["pairedAgreement"], 1)
        self.assertEqual(exact["signedDifferences"]["wasoSeconds"], 0)
        shifted = compare(dict(reference, **{}) | {30:"wake",150:"light"}, reference)
        self.assertEqual(shifted["signedDifferences"]["onsetSeconds"], 30)
        self.assertEqual(shifted["signedDifferences"]["wakeSeconds"], 30)
        self.assertEqual(shifted["pairedConfusionMatrixReferenceRows"]["light"]["wake"], 1)

    def test_unknowns_are_not_wake(self):
        result = compare({0:"light",60:"rem"}, {0:"light",30:"wake",60:"rem"})
        self.assertEqual(result["coverageEpochs"]["reference_only"], 1)
        self.assertIsNone(result["signedDifferences"])
        self.assertEqual(result["pairedAgreement"], 1)

    def test_misaligned_grid_rejected(self):
        with self.assertRaises(ValueError):
            compare({0:"light"}, {15:"light"})

if __name__ == "__main__":
    unittest.main()
