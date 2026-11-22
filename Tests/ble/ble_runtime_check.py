from __future__ import annotations

import json
import math
import struct
import sys
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager, closing
from dataclasses import asdict, dataclass, field
from enum import StrEnum
from pathlib import Path
from typing import Final, Literal, assert_never

ROOT: Final = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "build/ble-check-deps"))
import anyio
from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic
from bleak.exc import BleakError
from winrt.windows.devices.bluetooth import BluetoothLEDevice, BluetoothLEPreferredConnectionParameters

SERVICE: Final = "19b10000-e8f2-537e-4f6c-d104768a1214"
UUIDS: Final = {n: f"19b100{n:02x}-e8f2-537e-4f6c-d104768a1214" for n in (1, 2, 3, 4, 5, 9, 10)}
USE_THROUGHPUT: Final = len(sys.argv) > 4 and sys.argv[4] == "throughput"


@asynccontextmanager
async def throughput_profile(address: str) -> AsyncIterator[BluetoothLEDevice | None]:
    if not USE_THROUGHPUT:
        yield None
        return
    device = await BluetoothLEDevice.from_bluetooth_address_async(int(address.replace(":", ""), 16))
    assert device is not None, "Native BLE reference missing"
    with closing(device), closing(device.request_preferred_connection_parameters(
        BluetoothLEPreferredConnectionParameters.throughput_optimized
    )) as request:
        print(f"Windows throughput request status={request.status}", flush=True)
        yield device


class Mode(StrEnum):
    NOTIFY_ONLY = "notify_only"
    ALL = "all_notify_and_read"
    REDUCED = "reduced_notify_and_read"
    CONTROL = "all_notify_and_led"


@dataclass(slots=True)
class Session:
    mode: Mode
    cycle: int
    passed: bool = False
    connected: bool = False
    reads: int = 0
    last_operation: str = "scan"
    error: str | None = None
    read_latencies: list[float] = field(default_factory=list)
    counts: dict[str, int] = field(default_factory=dict)
    max_gaps: dict[str, float] = field(default_factory=dict)
    elapsed: float = 0
    intervals_ms: list[float] = field(default_factory=list)


async def read(client: BleakClient, index: Literal[1, 3, 4, 9, 10], report: Session) -> bytes:
    report.last_operation = f"read {index}"
    began = time.monotonic()
    with anyio.fail_after(5):
        value = bytes(await client.read_gatt_char(UUIDS[index], use_cached=False))
    report.read_latencies.append(round(time.monotonic() - began, 4))
    report.reads += 1
    match index:
        case 1 | 9:
            assert len(value) == 4, (index, value.hex())
            assert math.isfinite(struct.unpack("<f", value)[0]), (index, value.hex())
        case 10:
            assert len(value) == 12, value.hex()
            assert all(math.isfinite(x) for x in struct.unpack("<fff", value)), value.hex()
        case 4:
            assert value == b"\x00\x00", value.hex()
        case 3:
            assert value in (b"\x00", b"\x01"), value.hex()
        case unreachable:
            assert_never(unreachable)
    return value


async def run_session(report: Session) -> None:
    began = time.monotonic()
    packets: dict[int, list[tuple[float, bytes]]] = {}
    try:
        device = await BleakScanner.find_device_by_filter(
            lambda _d, advertisement: SERVICE in advertisement.service_uuids, timeout=12,
        )
        assert device is not None, "MYMS advertisement missing"
        async with BleakClient(device, timeout=12, winrt={"use_cached_services": False}) as client, throughput_profile(device.address) as native:
            report.connected = client.is_connected
            for index in (1, 4, 9, 10):
                await read(client, index, report)
            match report.mode:
                case Mode.NOTIFY_ONLY | Mode.ALL | Mode.CONTROL:
                    subscribed = (1, 2, 4, 5, 9, 10)
                case Mode.REDUCED:
                    subscribed = (9, 10)
                case unreachable:
                    assert_never(unreachable)
            for index in subscribed:
                packets[index] = []

                def callback(_sender: BleakGATTCharacteristic, data: bytearray, key: int = index) -> None:
                    packets[key].append((time.monotonic(), bytes(data)))

                report.last_operation = f"subscribe {index}"
                with anyio.fail_after(5):
                    await client.start_notify(UUIDS[index], callback)
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if native is not None:
                    report.intervals_ms.append(native.get_connection_parameters().connection_interval * 1.25)
                await anyio.sleep(0.5)
                match report.mode:
                    case Mode.ALL | Mode.REDUCED:
                        for index in (1, 4, 9, 10):
                            await read(client, index, report)
                    case Mode.NOTIFY_ONLY | Mode.CONTROL:
                        pass
                    case unreachable:
                        assert_never(unreachable)
                match report.mode:
                    case Mode.NOTIFY_ONLY:
                        pass
                    case Mode.ALL | Mode.REDUCED | Mode.CONTROL:
                        report.last_operation = "LED write"
                        with anyio.fail_after(5):
                            await client.write_gatt_char(UUIDS[3], b"\x01", response=True)
                        assert await read(client, 3, report) == b"\x01"
                        report.last_operation = "LED off"
                        with anyio.fail_after(5):
                            await client.write_gatt_char(UUIDS[3], b"\x00", response=True)
                        assert await read(client, 3, report) == b"\x00"
                    case unreachable:
                        assert_never(unreachable)
            assert len(packets[10]) >= 20, f"vector notifications={len(packets[10])}"
            assert len(packets[9]) >= 3, f"brightness notifications={len(packets[9])}"
            for index in (1, 2, 4):
                if index in packets:
                    assert len(packets[index]) >= 3, f"stream {index} notifications={len(packets[index])}"
            for index in subscribed:
                report.last_operation = f"unsubscribe {index}"
                with anyio.fail_after(5):
                    await client.stop_notify(UUIDS[index])
            report.passed = True
    except (TimeoutError, BleakError, OSError, AssertionError) as exc:
        report.error = f"{type(exc).__name__}: {exc}"
    finally:
        report.elapsed = round(time.monotonic() - began, 3)
        report.counts = {str(k): len(v) for k, v in packets.items()}
        report.max_gaps = {str(k): round(max((b[0] - a[0] for a, b in zip(v, v[1:])), default=0), 4)
                           for k, v in packets.items()}
        print(json.dumps(asdict(report)), flush=True)


async def main() -> None:
    label = sys.argv[1] if len(sys.argv) > 1 else "baseline"
    reports: list[Session] = []
    evidence = ROOT / "build/ble-debug" / f"{label}.json"
    modes = (Mode(sys.argv[2]),) if len(sys.argv) > 2 else (Mode.CONTROL,)
    cycles = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    for mode in modes:
        for cycle in range(1, cycles + 1):
            report = Session(mode, cycle)
            reports.append(report)
            await run_session(report)
            evidence.write_text(json.dumps([asdict(r) for r in reports], indent=2), encoding="utf-8")
            await anyio.sleep(1)
    assert all(r.passed for r in reports), "One or more BLE scenarios failed; see evidence"


anyio.run(main)
