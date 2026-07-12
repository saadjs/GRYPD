#!/usr/bin/env python3
"""Mint a short-lived ES256 JWT for the App Store Connect API.

Signing is delegated to `openssl` (already required on this machine); this
script only handles JOSE framing (base64url header/payload) and converting
openssl's DER-encoded ECDSA signature into the raw r||s format JWS requires.
No third-party packages needed.

Usage: mint_jwt.py <key-id> <issuer-id> <path-to-p8-key>
"""

import base64
import json
import subprocess
import sys
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes, coord_size: int = 32) -> bytes:
    """Convert a DER-encoded ECDSA SEQUENCE{INTEGER r, INTEGER s} to raw r||s."""

    def read_int(data: bytes, idx: int) -> tuple[bytes, int]:
        assert data[idx] == 0x02, "expected ASN.1 INTEGER"
        idx += 1
        length = data[idx]
        idx += 1
        if length & 0x80:
            nbytes = length & 0x7F
            length = int.from_bytes(data[idx : idx + nbytes], "big")
            idx += nbytes
        value = data[idx : idx + length]
        return value, idx + length

    assert der[0] == 0x30, "expected ASN.1 SEQUENCE"
    idx = 2 if not (der[1] & 0x80) else 2 + (der[1] & 0x7F)
    r, idx = read_int(der, idx)
    s, idx = read_int(der, idx)
    r = r.lstrip(b"\x00")
    s = s.lstrip(b"\x00")
    if len(r) > coord_size or len(s) > coord_size:
        raise ValueError("ECDSA coordinate longer than expected for this curve")
    return r.rjust(coord_size, b"\x00") + s.rjust(coord_size, b"\x00")


def main() -> None:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <key-id> <issuer-id> <path-to-p8-key>", file=sys.stderr)
        sys.exit(1)
    key_id, issuer_id, key_path = sys.argv[1:4]
    now = int(time.time())

    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + 1190, "aud": "appstoreconnect-v1"}

    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload)
    )

    der_sig = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout

    raw_sig = der_to_raw(der_sig)
    print(f"{signing_input}.{b64url(raw_sig)}")


if __name__ == "__main__":
    main()
