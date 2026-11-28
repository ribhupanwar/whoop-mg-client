import unittest
from tools.sleep_cardio_shadow import evidence


def rows(n, *, heart=60):
    return [(t, {'heartRate': heart, 'gravityXG': 1., 'gravityYG': 0., 'gravityZG': 0., 'dynamicAccelG': .01, 'rrIntervalsMS': [1000]}) for t in range(n)]


class ShadowTests(unittest.TestCase):
    def test_stillness_and_unknown_tail(self):
        r = evidence(rows(900), 0, 900)
        self.assertGreater(r['wristRestSeconds'], 0)
        self.assertEqual(r['wristRestRuleFailedSeconds'], 0)
        self.assertGreaterEqual(r['wristUnknownSeconds'], 299)
        self.assertEqual(sum(r[k] for k in ('wristRestSeconds','wristRestRuleFailedSeconds','wristUnknownSeconds')), 900)

    def test_missing_and_conflicting_seconds(self):
        data = rows(900)
        data.append((400, {'heartRate': 80}))
        r = evidence(data, 0, 900)
        self.assertEqual(r['validHRSeconds'], 899)
        self.assertEqual(r['validGravitySeconds'], 899)
        self.assertGreater(r['wristUnknownSeconds'], 300)

    def test_no_gravity_not_wake(self):
        r = evidence([(i, {'heartRate': 60}) for i in range(600)], 0, 600)
        self.assertEqual(r['wristUnknownSeconds'], 600)
        self.assertEqual(r['wristRestRuleFailedSeconds'], 0)

    def test_slow_posture_change(self):
        import math
        data = rows(900)
        for i in range(400, 900):
            angle = math.radians(min(20, (i-400)*3))
            data[i][1]['gravityXG'] = math.cos(angle)
            data[i][1]['gravityZG'] = math.sin(angle)
        self.assertGreater(evidence(data, 0, 900)['wristRestRuleFailedSeconds'], 0)

    def test_local_baseline_and_no_stage_inference(self):
        data = rows(10800)
        for t, row in data:
            if t < 5400:
                row['heartRate'] = 80
        r = evidence(data, 0, 10800)
        self.assertGreater(r['wholeOnlyElevatedEpochs'], 0)
        self.assertTrue(all('stage' not in e for e in r['epochs']))
        self.assertIsNone(evidence(rows(60),0,60)['epochs'][0]['local90mHRBaseline'])

if __name__ == '__main__':
    unittest.main()
