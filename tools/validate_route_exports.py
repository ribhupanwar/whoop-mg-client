"""Independently validate synthetic native route attachments (never user data).

Install fitdecode==0.11.0 in an isolated test environment. The writer is Swift;
this independent decoder verifies FIT CRCs, profile fields and absent values.
"""
import argparse
import io
from pathlib import Path
import xml.etree.ElementTree as ET
import fitdecode


def validate(root: Path):
    fits, gpxs = 0, 0
    for path in root.rglob('*'):
        if not path.is_file():
            continue
        data = path.read_bytes()
        if len(data) > 14 and data[8:12] == b'.FIT':
            with fitdecode.FitReader(io.BytesIO(data), check_crc=fitdecode.CrcCheck.RAISE,
                                     error_handling=fitdecode.ErrorHandling.RAISE) as reader:
                messages = [frame for frame in reader if isinstance(frame, fitdecode.FitDataMessage)]
            records = [m for m in messages if m.name == 'record']
            assert len(records) == 2, 'No synthetic route interpolation allowed'
            assert [m.get_raw_value('timestamp') + 631065600 for m in records] == [1762000000, 1762000010]
            assert [m.get_value('time128') for m in records] == [0.125, 0.375]
            assert records[0].get_raw_value('position_lat') == 0
            assert abs(records[1].get_raw_value('position_long') * 180 / 2147483648 - 0.001) < 0.000001
            session = next(m for m in messages if m.name == 'session')
            assert abs(session.get_value('total_distance') - 111.2) < 0.001
            assert session.get_value('total_elapsed_time') == 30.5
            assert session.get_value('total_timer_time') == 20
            for message in messages:
                names = {field.name for field in message.fields}
                assert not names.intersection({'heart_rate', 'altitude', 'total_calories', 'cadence'}), 'Unknown sensor values must be absent'
            fits += 1
        elif b'<gpx ' in data[:1000] and b'STRAP' in data[:1000]:
            xml = ET.fromstring(data)
            ns = {'g': 'http://www.topografix.com/GPX/1/1', 's': 'https://github.com/ribhupanwar/whoop-mg-client/gpx'}
            points = xml.findall('.//g:trkpt', ns)
            assert len(points) == 2
            assert [float(p.find('g:extensions/s:originalUnix', ns).text) for p in points] == [1762000000.125, 1762000010.375]
            assert not xml.findall('.//g:ele', ns)
            gpxs += 1
    assert fits >= 1 and gpxs >= 1, 'Both native FIT and GPX attachments must be available'
    print(f'Independent route validation passed: {fits} FIT, {gpxs} GPX; CRC/source fields/absence of fabricated sensors verified.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('attachments', type=Path)
    validate(parser.parse_args().attachments)
