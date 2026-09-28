#!/usr/bin/env python3
"""Generate a private HomeKit setup code for a WyreCam.

Every stock WyreCam image ships with the same, publicly documented setup code
(0107-2024). Anyone on your network who knows it can pair with a camera that
has not been paired yet, or that has been reset. This script creates a random
code and the matching HomeKit key-store files. Copy them to the SD card and the
installer (upgrade.sh) will provision the camera with them.

Usage:
    python3 scripts/homekit_setup_code.py /path/to/sdcard

This writes <sdcard>/homekit/40.10 and <sdcard>/homekit/40.11 and prints the
code. Write the code down (or stick it on the camera): it is not stored
anywhere in readable form. The installer deletes the files from the card after
a successful install.

Only the Python 3 standard library is needed.

File format (from HomeKitADK, key-value store domain 0x40 "Provisioning"):
    40.10  HAPSetupInfo: 16 byte SRP salt + 384 byte SRP-6a verifier
    40.11  HAPSetupID:   4 characters [0-9A-Z] + NUL
The verifier is v = g^x mod N with the RFC 5054 3072-bit group (g = 5) and
x = SHA512(salt | SHA512("Pair-Setup:" | code)), matching HAP_srp_verifier().
"""

import argparse
import hashlib
import os
import secrets
import string
import sys

# RFC 5054 3072-bit SRP group, as used by HomeKit.
N_3072 = int(
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E08"
    "8A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B"
    "302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9"
    "A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE6"
    "49286651ECE45B3DC2007CB8A163BF0598DA48361C55D39A69163FA8"
    "FD24CF5F83655D23DCA3AD961C62F356208552BB9ED529077096966D"
    "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3BE39E772C"
    "180E86039B2783A2EC07A28FB5C55DF06F4C52C9DE2BCBF695581718"
    "3995497CEA956AE515D2261898FA051015728E5A8AAAC42DAD33170D"
    "04507A33A85521ABDF1CBA64ECFB850458DBEF0A8AEA71575D060C7D"
    "B3970F85A6E1E4C7ABF5AE8CDB0933D71E8C94E04A25619DCEE3D226"
    "1AD2EE6BF12FFA06D98A0864D87602733EC86A64521F2B18177B200C"
    "BBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFC"
    "E0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF",
    16,
)
G_3072 = 5
SALT_BYTES = 16
VERIFIER_BYTES = 384


def srp_verifier(salt: bytes, code: str) -> bytes:
    inner = hashlib.sha512(b"Pair-Setup:" + code.encode("ascii")).digest()
    x = int.from_bytes(hashlib.sha512(salt + inner).digest(), "big")
    return pow(G_3072, x, N_3072).to_bytes(VERIFIER_BYTES, "big")


def is_valid_setup_code(code: str) -> bool:
    """Mirror HAPAccessorySetupIsValidSetupCode(): XXX-XX-XXX, not trivial."""
    if len(code) != 10 or code[3] != "-" or code[6] != "-":
        return False
    digits = code[:3] + code[4:6] + code[7:]
    if not digits.isdigit():
        return False
    if len(set(digits)) == 1:
        return False
    if digits in ("12345678", "87654321"):
        return False
    return True


def random_setup_code() -> str:
    while True:
        d = "".join(secrets.choice(string.digits) for _ in range(8))
        code = f"{d[:3]}-{d[3:5]}-{d[5:]}"
        if is_valid_setup_code(code):
            return code


def random_setup_id() -> str:
    alphabet = string.digits + string.ascii_uppercase
    return "".join(secrets.choice(alphabet) for _ in range(4))


def self_test() -> None:
    """Check against the default store shipped in general/overlay."""
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "general", "overlay", "PositronStore", ".HomeKitStore", "40.10")
    with open(path, "rb") as f:
        info = f.read()
    assert len(info) == SALT_BYTES + VERIFIER_BYTES
    assert srp_verifier(info[:SALT_BYTES], "010-72-024") == info[SALT_BYTES:], "verifier mismatch"
    print("self-test passed: reproduced the default 40.10 verifier")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sdcard", nargs="?", help="mounted SD card (the files go in <sdcard>/homekit/)")
    ap.add_argument("--code", help="use this setup code (XXX-XX-XXX) instead of a random one")
    ap.add_argument("--self-test", action="store_true", help="verify the implementation and exit")
    args = ap.parse_args()

    if args.self_test:
        self_test()
        return 0
    if not args.sdcard:
        ap.error("the SD card path is required")

    code = args.code or random_setup_code()
    if not is_valid_setup_code(code):
        ap.error("setup code must look like 123-45-678 and must not be trivial (all same, 12345678, 87654321)")

    salt = secrets.token_bytes(SALT_BYTES)
    info = salt + srp_verifier(salt, code)
    setup_id = random_setup_id()

    outdir = os.path.join(args.sdcard, "homekit")
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "40.10"), "wb") as f:
        f.write(info)
    with open(os.path.join(outdir, "40.11"), "wb") as f:
        f.write(setup_id.encode("ascii") + b"\0")

    pretty = code.replace("-", "")
    print(f"Wrote {outdir}/40.10 and {outdir}/40.11")
    print()
    print(f"    HomeKit setup code: {pretty[:4]}-{pretty[4:]}")
    print()
    print("Write this code down now. You need it to add the camera in the Home app.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
