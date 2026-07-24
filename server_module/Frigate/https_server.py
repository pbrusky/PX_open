import http.server
import ssl
import tempfile
import os
import threading

# ---------------------------------------------------------
# EMBEDDED CERTIFICATE + PRIVATE KEY
# ---------------------------------------------------------
EMBEDDED_PEM = """
-----BEGIN PRIVATE KEY-----
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
yjsPI3PfYfr5fPHd9Ax4XV9EUdiecvc=
-----END PRIVATE KEY-----
-----BEGIN CERTIFICATE-----
MIIFCTCCAvGgAwIBAgIUBUYOzJhXdkaZjJzU7+IC9dZvmNUwDQYJKoZIhvcNAQEL
BQAwFDESMBAGA1UEAwwJMTI3LjAuMC4xMB4XDTI6MDYyMTA4MzczMVoXDTI7MDYy
MTA8MzczMVowFDESMBAGA1UEAwwJMTI3LjAuMC4xMIICIjANBgkqhkiG9w0BAQEF
AAOCAg8AMIICCgKCAgEArvZv0Vxsxaj47G7/TRhW+DVPhdi8Rq/3kJDuZxKJSnLA
h8hlFdHb291Ewko+wreyTYOP9auNEK/rpjqvfCcnjlVxw5P7qEas1jSQuDWFHmen
K3lcANufxfoI4Hb+2cJkhehC4Mt0wiyLJVucKUwSbiYS3c0s/yKWi2Qd5KpsQFnc
/nx2Roj/s6ojfFbi4+CfV6IZWFrzXHxqCefNx/BK5btuFM9yEat5TWnXW/N8NGlg
78wlQk4nLSx71yU6DM/wZvkEjHiZZeC4kOy1NGA+C13B7EHvqF7HIdY2RI1e05qs
soHddfHwF94FLGKy5qaExnV9sdMABG260q8Ibye2K6/23OobgO5yJkEOnzAFnyd6
56wM1rWeW1nPXGHd0sKxi98hYd3VFnDPisZsi71ANYj4O/SkwLviQpb9AeaofiVE
hzs5Gg6GkhAEJ2ybgPAv8ptLkiH+SEYDQDJrTu8ejv0Fwt9VF9rs6Vi/HqEx3vtH
QXO+T1IdgaNnIdPgAju6eho45ioSKcEn6b/cAwMmKymnPDPX5qeNaXNmYHI3SyQM
5fXlEFC6pa8F3eTuO+4LRqn5jM/+oAcKw9IGZ/iViTeUbWRDmgSwQdrjQ0VxhRy4
sjTggk6yKHCqGBtGwmeySUsiwvgi0g6Ko5RMKn6piPKje/0wvJdfhUwPTo5+F18C
AwEAAaNTMFEwHQYDVR0OBBYEFNzwmTGP1bYKq3jLPPvkwTOrAwZrMB8GA1UdIwQY
MBaAFNzwmTGP1bYKq3jLPPvkwTOrAwZrMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZI
hvcNAQELBQADggIBAIJSTq2W25+XuvxLXCJ95s7na9xS75Ey3TgLhY0m79zyxW+O
DHDNB1qpB0AJMx7682nX71RDSpNN2J4fy9s+EQhMKSVqRftyPF3NuJmwYlHROgHL
eFtiPv3JnjbM/JhVV3ilAd6N0FK0xpNaTtSTyIj5XoD9IsOJs0YiQeC0LR2+okT/
TTupOCAKksjztZlAFL3LIweweOSNs3eDoFeMwHYb5/dByqEAkJuJ1KoJYLkh+1r+
65phcn9MwntFj2sSiG5OMaadQK1T6+T0sQTpUDCyNsijATanvgoh1E+DpAfSUcC/
085hStFKWOs2KMlMNPzpf3iQjZUtyj2gAI6PdYrr+ymPoSwBZSsxa6Sfe3n6oiGN
FDGbHHzvms7KwDzBieE2wn4ZW0AcBciDXiODtsyKVp4ehH3Nj6nlSes/UdxIW8vR
fxy/YwSBIqPku2LBcfFAQBdyMH2B5BBAV1bGk9Ny69QMmlG1HZX7PTx9xgkiJ0G0
h1kKyGZPOeh3Re5Hb1pK5H9RZc0gkf26PWG7CH0ZhVFgu+6FLKV0hmaawAdLhDbw
iJafXmrJT0Ag2C+1ogXHi2BvFjo3GD2FvnwmfeROygMng8e1kNKz2MaODihGTc9N
XHaRhn0EIcglP9zcr1114kGHcrEkvW2fRqb2eylFEDqZBg+gTF73tnE6bDsK
-----END CERTIFICATE-----
""".strip()


def _write_embedded_cert():
    """Write the embedded PEM to a temp file and return its path."""
    temp_dir = tempfile.gettempdir()
    pem_path = os.path.join(temp_dir, "embedded_cert.pem")

    with open(pem_path, "w", encoding="utf-8") as f:
        f.write(EMBEDDED_PEM)

    return pem_path


def start_https_server(host, port, handler_class):
    """Start an HTTPS server using the embedded certificate."""
    try:
        httpd = http.server.HTTPServer((host, port), handler_class)

        pem_path = _write_embedded_cert()

        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=pem_path)

        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()

        print(f"[*] HTTPS server running → https://{host}:{port}")
        return True

    except Exception as e:
        print(f"[HTTPS] Failed to start: {e}")
        return False
