"""Real-board LED validation; requires build/ble-check-deps (bleak and anyio)."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "build/ble-check-deps"))
import anyio
from bleak import BleakClient, BleakScanner

SERVICE = "19b10000-e8f2-537e-4f6c-d104768a1214"
LED = "19b10003-e8f2-537e-4f6c-d104768a1214"


async def main() -> None:
    device = await BleakScanner.find_device_by_filter(
        lambda _device, advertisement: SERVICE in advertisement.service_uuids, timeout=12)
    assert device is not None, "MYMS advertisement missing"
    results = []
    async with BleakClient(device, timeout=12, winrt={"use_cached_services": False}) as client:
        with anyio.fail_after(5):
            original = bytes(await client.read_gatt_char(LED, use_cached=False))
        assert original in (b"\x00", b"\x01"), "Invalid initial LED state"
        try:
            for state in (b"\x00", b"\x01"):
                with anyio.fail_after(5):
                    await client.write_gatt_char(LED, state, response=True)
                    assert bytes(await client.read_gatt_char(LED, use_cached=False)) == state
                for invalid in (b"\x02", b"\xff"):
                    with anyio.fail_after(5):
                        await client.write_gatt_char(LED, invalid, response=True)
                        actual = bytes(await client.read_gatt_char(LED, use_cached=False))
                    assert actual == state, f"Invalid LED command changed state: {invalid.hex()}"
                    results.append({"state": state.hex(), "rejected_value": invalid.hex(), "passed": True})
        finally:
            with anyio.fail_after(5):
                await client.write_gatt_char(LED, original, response=True)
    (ROOT / "build/ble-debug/led-payload-check.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results))


if __name__ == "__main__":
    anyio.run(main)
