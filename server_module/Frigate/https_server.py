import http.server
import ssl
import os
import threading
import ipaddress
from pathlib import Path
from datetime import datetime, timedelta, timezone


def get_cert_paths():
    """Return paths for cert.pem and key.pem next to this script."""
    base = Path(__file__).resolve().parent
    return base / "cert.pem", base / "key.pem"


def generate_self_signed_cert(cert_path: Path, key_path: Path) -> bool:
    """Generate a self-signed certificate using the cryptography library."""
    try:
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa

        print("[HTTPS] Generating new self-signed certificate (cryptography)...")

        # Generate private key
        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048
        )

        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "localhost"),
        ])

        cert = (
            x509.CertificateBuilder()
            .subject_name(subject)
            .issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.now(timezone.utc))
            .not_valid_after(datetime.now(timezone.utc) + timedelta(days=3650))  # 10 years
            .add_extension(
                x509.SubjectAlternativeName([
                    x509.DNSName("localhost"),
                    x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
                ]),
                critical=False,
            )
            .sign(key, hashes.SHA256())
        )

        # Write private key
        with open(key_path, "wb") as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            ))

        # Write certificate
        with open(cert_path, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))

        print(f"[HTTPS] Certificate created → {cert_path}")
        return True

    except ImportError:
        print("[HTTPS] Missing package. Please run:  pip install cryptography")
        return False
    except Exception as e:
        print(f"[HTTPS] Failed to generate certificate: {e}")
        return False


def start_https_server(host, port, handler_class):
    """Start an HTTPS server. Generates cert on first run if needed."""
    cert_path, key_path = get_cert_paths()

    # Generate certificate if it doesn't exist yet
    if not (cert_path.exists() and key_path.exists()):
        if not generate_self_signed_cert(cert_path, key_path):
            print("[HTTPS] Skipping HTTPS server (no certificate available)")
            return False

    try:
        httpd = http.server.HTTPServer((host, port), handler_class)

        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))

        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()

        print(f"[*] HTTPS server running → https://{host}:{port}")
        return True

    except Exception as e:
        print(f"[HTTPS] Failed to start: {e}")
        return False