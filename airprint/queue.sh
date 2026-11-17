#!/usr/bin/env bash
set -uo pipefail

QUEUE=$1
DEVICE=$2
LABEL=$3
LOCATION=$4
DRIVER=$5

# The device id is a dnssd URI holding the avahi-escaped service name
# ("Brother\032DCP-1610W\032series"), and it is the printer's identity in Home
# Assistant, so it stays as it is. CUPS' dnssd backend looks that text up
# literally and fails with "Unable to locate printer", so CUPS gets the
# percent-encoded form it generates itself ("Brother%20DCP-1610W%20series").
cups_uri() {
	python3 - "$1" <<'EOF'
import re
import sys
import urllib.parse

uri = sys.argv[1]
match = re.match(r"^dnssd://(.*?)(?<!\\)(\._[^/]*)(/.*)?$", uri)
if not match:
    print(uri)
    sys.exit()

name, rest, path = match.group(1), match.group(2), match.group(3) or "/"

raw = bytearray()
i = 0
while i < len(name):
    if name[i] == "\\" and re.match(r"\d{3}", name[i + 1:i + 4]):
        raw.append(int(name[i + 1:i + 4]))
        i += 4
    elif name[i] == "\\" and i + 1 < len(name):
        raw += name[i + 1].encode()
        i += 2
    else:
        raw += name[i].encode()
        i += 1

print("dnssd://" + urllib.parse.quote(bytes(raw), safe="") + rest + path)
EOF
}

URI=$(cups_uri "${DEVICE}")
[ -n "${URI}" ] || URI=${DEVICE}

lpadmin -p "${QUEUE}" \
	-v "${URI}" \
	-m "${DRIVER}" \
	-D "${LABEL}" \
	-L "${LOCATION}" \
	-o printer-is-shared=true \
	-o printer-error-policy=retry-job \
	-E || exit 1

mkdir -p /var/cache/cups/images
cp /usr/share/airprint/printer.png "/var/cache/cups/images/${QUEUE}.png"
