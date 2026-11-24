"""Decoder and data structures for WHOOP 5.0 / MG GET_DATA_RANGE command response (opcode 0x22 / 34)."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Optional

DATA_RANGE_BODY_LEN = 65
MIN_PLAUSIBLE_UNIX = 1_600_000_000
MAX_PLAUSIBLE_UNIX = 2_500_000_000


@dataclass(frozen=True)
class DataRangeResponse:
    revision: int
    raw_old_page: int
    read_page: int
    write_page: int
    trim_page: int
    wrap_count: int
    total_pages: int
    used_records: int
    free_records: int
    oldest_unix: Optional[int]
    trim_unix: Optional[int]
    current_read_unix: Optional[int]
    newest_unix: Optional[int]

    @property
    def pages_behind(self) -> int:
        """Calculate pages behind taking ring wrap into account."""
        if self.total_pages <= 0:
            return 0
        if self.write_page >= self.trim_page:
            return self.write_page - self.trim_page
        return (self.write_page + self.total_pages) - self.trim_page

    @property
    def is_empty(self) -> bool:
        """True if the strap reports no recorded history."""
        return self.newest_unix is None or self.pages_behind == 0


def _parse_unix(val: int) -> Optional[int]:
    if MIN_PLAUSIBLE_UNIX <= val <= MAX_PLAUSIBLE_UNIX:
        return val
    return None


def decode_data_range_response(body: bytes) -> Optional[DataRangeResponse]:
    """Decode the 65-byte body of a GET_DATA_RANGE (0x22) response."""
    if len(body) < DATA_RANGE_BODY_LEN:
        return None

    revision = body[0]
    # Offsets:
    # 0: u8 revision
    # 1: u32 raw_old_page
    # 5: u32 read_page
    # 9: u32 write_page
    # 13: u32 trim_page
    # 17: u32 wrap_count
    # 21: u32 total_pages
    # 25: u32 used_records
    # 29: u32 free_records
    # 33: u32 oldest_unix + 37: u32 oldest_subsec
    # 41: u32 trim_unix + 45: u32 trim_subsec
    # 49: u32 read_unix + 53: u32 read_subsec
    # 57: u32 newest_unix + 61: u32 newest_subsec
    fields = struct.unpack_from("<B8I8I", body, 0)
    rev = fields[0]
    raw_old = fields[1]
    read_p = fields[2]
    write_p = fields[3]
    trim_p = fields[4]
    wrap_c = fields[5]
    total_p = fields[6]
    used_rec = fields[7]
    free_rec = fields[8]

    oldest_s = fields[9]
    # fields[10] is oldest_subsec
    trim_s = fields[11]
    # fields[12] is trim_subsec
    read_s = fields[13]
    # fields[14] is read_subsec
    newest_s = fields[15]
    # fields[16] is newest_subsec

    return DataRangeResponse(
        revision=rev,
        raw_old_page=raw_old,
        read_page=read_p,
        write_page=write_p,
        trim_page=trim_p,
        wrap_count=wrap_c,
        total_pages=total_p,
        used_records=used_rec,
        free_records=free_rec,
        oldest_unix=_parse_unix(oldest_s),
        trim_unix=_parse_unix(trim_s),
        current_read_unix=_parse_unix(read_s),
        newest_unix=_parse_unix(newest_s),
    )
