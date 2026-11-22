"""Verify physical ID across reconnects. Requires bleak/anyio in build/ble-check-deps."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "build/ble-check-deps"))
import anyio
from bleak import BleakClient, BleakScanner

SERVICE = "19b10000-e8f2-537e-4f6c-d104768a1214"
IDENTITY = "19b1000b-e8f2-537e-4f6c-d104768a1214"


async def main() -> None:
    results = []
    previous = None
    previous_address = None
    for cycle in range(2):
        advertisements = {}

        def matches(device, advertisement):
            advertisements[device.address] = advertisement.local_name
            return SERVICE in advertisement.service_uuids and (previous_address is None or device.address == previous_address)

        device = await BleakScanner.find_device_by_filter(matches, timeout=12)
        assert device is not None, "MYMS advertisement missing; disconnect other centrals first"
        name = advertisements[device.address] or ""
        previous_address = device.address
        async with BleakClient(device, timeout=12, winrt={"use_cached_services": False}) as client:
            with anyio.fail_after(5):
                raw = bytes(await client.read_gatt_char(IDENTITY, use_cached=False))
            assert len(raw) == 16, f"Wrong ID byte count: {len(raw)}"
            identity = raw.decode("ascii")
            assert re.fullmatch(r"[0-9A-F]{16}", identity), "Invalid hardware ID"
            if name.startswith("MYMS-"):
                assert identity == name[5:], "Advertisement/GATT identity mismatch"
            assert previous is None or previous == identity, "Board identity changed on reconnect"
            previous = identity
            results.append({"cycle": cycle + 1, "name": name, "hardware_id": identity,
                            "advertisement_compared": name.startswith("MYMS-"), "passed": True})
        await anyio.sleep(1)
    (ROOT / "build/ble-debug/hardware-identity.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results))


if __name__ == "__main__":
    anyio.run(main)
