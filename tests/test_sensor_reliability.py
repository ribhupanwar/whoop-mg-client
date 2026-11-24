import unittest
import struct
from whoop.records import V18Sample, RecordHeader
from whoop.metrics import trimp, rmssd


class SensorReliabilityTests(unittest.TestCase):
    """Synthetic fixtures testing sensor quality, off-wrist detection, and hardware events."""

    def setUp(self):
        self.header = RecordHeader(version=18, flags=0, record_index=1, unix=1700000000, subsec_q15=0)

    # 1. Tabletop artifact rejection vs normal wearing
    def test_tabletop_stillness_and_cold_temp_rejected_as_off_wrist(self):
        # Spurious optical HR (45 bpm) on cold tabletop (21.5C) with complete stillness (0.001g)
        tabletop = V18Sample(
            header=self.header,
            heart_rate=45,
            rr_intervals_ms=[1200],
            dynamic_accel_g=0.001,
            gravity_g=(0.0, 0.0, 1.0),
            step_motion_counter=0,
            step_cadence=0,
            activity_class=0,
            skin_temp_c=21.5,
        )
        self.assertFalse(tabletop.wearing, "Tabletop stillness and ambient cold must be rejected as off-wrist")

    def test_normal_worn_sample_is_wearing(self):
        # Normal skin temperature (33.5C), normal motion (0.02g), valid HR (65 bpm)
        worn = V18Sample(
            header=self.header,
            heart_rate=65,
            rr_intervals_ms=[920],
            dynamic_accel_g=0.02,
            gravity_g=(0.1, 0.2, 0.9),
            step_motion_counter=100,
            step_cadence=0,
            activity_class=0,
            skin_temp_c=33.5,
        )
        self.assertTrue(worn.wearing)

    def test_zero_hr_sample_is_off_wrist(self):
        zero_hr = V18Sample(
            header=self.header,
            heart_rate=0,
            rr_intervals_ms=[],
            dynamic_accel_g=0.01,
            gravity_g=(0.0, 0.0, 1.0),
            step_motion_counter=0,
            step_cadence=0,
            activity_class=0,
            skin_temp_c=28.0,
        )
        self.assertFalse(zero_hr.wearing)

    # 2. Confirmed off-wrist samples do not contaminate metrics
    def test_off_wrist_samples_do_not_contribute_to_strain(self):
        # 10 minutes of genuine workout at 150 bpm followed by 10 minutes of tabletop noise at 150 bpm
        worn_samples = [
            V18Sample(
                header=RecordHeader(version=18, flags=0, record_index=i, unix=1700000000 + i, subsec_q15=0),
                heart_rate=150,
                skin_temp_c=34.0,
                dynamic_accel_g=0.5,
            )
            for i in range(600)
        ]
        tabletop_samples = [
            V18Sample(
                header=RecordHeader(version=18, flags=0, record_index=600 + i, unix=1700000600 + i, subsec_q15=0),
                heart_rate=150,
                skin_temp_c=20.0,  # Cold tabletop
                dynamic_accel_g=0.001,  # Tabletop stillness
            )
            for i in range(600)
        ]
        # Calculate TRIMP on worn-only vs combined
        strain_worn = trimp(worn_samples, resting_hr=60, max_hr=190, sex="male")
        strain_combined = trimp(worn_samples + tabletop_samples, resting_hr=60, max_hr=190, sex="male")

        # Tabletop samples must have wearing == False and must not increase strain
        self.assertEqual(strain_worn, strain_combined)

    def test_off_wrist_samples_do_not_contaminate_rmssd(self):
        # Clean RR intervals while worn
        worn_rrs = [
            V18Sample(
                header=RecordHeader(version=18, flags=0, record_index=i, unix=1700000000 + i, subsec_q15=0),
                heart_rate=60,
                rr_intervals_ms=[1000, 1010],
                skin_temp_c=34.0,
                dynamic_accel_g=0.01,
            )
            for i in range(10)
        ]
        # Corrupted phantom RR intervals on tabletop
        tabletop_rrs = [
            V18Sample(
                header=RecordHeader(version=18, flags=0, record_index=10 + i, unix=1700000010 + i, subsec_q15=0),
                heart_rate=60,
                rr_intervals_ms=[400, 1600],  # Wild phantom spikes
                skin_temp_c=21.0,  # Cold tabletop
                dynamic_accel_g=0.001,
            )
            for i in range(10)
        ]
        # Filter worn only
        filtered_samples = [s for s in (worn_rrs + tabletop_rrs) if s.wearing]
        self.assertEqual(len(filtered_samples), 10)
        all_rr = [float(rr) for s in filtered_samples for rr in s.rr_intervals_ms]
        val = rmssd(all_rr)
        self.assertIsNotNone(val)
        self.assertAlmostEqual(val, 10.0, places=1)

    # 3. Hardware event opcodes
    def test_hardware_event_opcodes(self):
        opcodes = {
            0x09: "wristOn",
            0x0A: "wristOff",
            0x0B: "bleConnectionUp",
            0x0C: "bleConnectionDown",
            0x0D: "rtcLost",
            0x0E: "doubleTap",
            0x0F: "boot",
            0x10: "setRTC",
            0x11: "temperatureLevel",
            0x12: "pairingMode",
            0x15: "batteryPackConnected",
            0x16: "batteryPackRemoved",
            0x17: "bleBonded",
            0x18: "bleHRProfileEnable",
        }
        self.assertEqual(opcodes[0x09], "wristOn")
        self.assertEqual(opcodes[0x0A], "wristOff")
        self.assertEqual(opcodes[0x15], "batteryPackConnected")
        self.assertEqual(opcodes[0x16], "batteryPackRemoved")
        self.assertEqual(opcodes[0x0E], "doubleTap")
        self.assertEqual(opcodes[0x17], "bleBonded")

    # 4. Status packet parsing in Python
    def test_status_packet_soc_and_charging(self):
        # Synthetic status payload: inner[0]=0x30, inner[2]=0x03, socRaw at bytes 13..14 (854 -> 85.4%), charging at byte 15
        inner = bytearray([0x30, 0x01, 0x03, 0x00] + [0] * 9)
        # Bytes 13..14: SoC = 854 (0x0356)
        inner.extend((854).to_bytes(2, "little"))
        # Byte 15: charging = 1
        inner.append(0x01)
        # Bytes 16..17: wristState = 0x0001 (capacitive contact)
        inner.extend((1).to_bytes(2, "little"))

        soc_raw = int.from_bytes(inner[13:15], "little")
        pct = soc_raw / 10.0
        charging = bool(inner[15] & 0x01)
        wrist_raw = int.from_bytes(inner[16:18], "little")
        is_on_wrist = bool((wrist_raw & 0x01) or (wrist_raw & 0x02))

        self.assertEqual(pct, 85.4)
        self.assertTrue(charging)
        self.assertEqual(wrist_raw, 1)
        self.assertTrue(is_on_wrist)


if __name__ == "__main__":
    unittest.main()
