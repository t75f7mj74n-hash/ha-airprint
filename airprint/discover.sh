#!/usr/bin/env bash
set -uo pipefail

VENDOR=/tmp/airprint-vendor-ppds
MODEL_DIR=/usr/share/cups/model

# first `lpinfo -m` row (on stdin) whose PPD came from a driver the user supplied
vendor_first() {
	awk 'NR == FNR { v[$0] = 1; next } ($1 in v) { print $1; exit }' "${VENDOR}" -
}

# a supplied PPD naming this model. Vendor PPDs often carry no 1284DeviceID
# (Brother's do not), so lpinfo cannot match them by device-id
vendor_by_name() {
	local core name

	core=$(printf '%s' "$1" | sed -E 's/[[:space:]]+series$//I')
	[ -n "${core}" ] || return 0

	while read -r name; do
		[ -n "${name}" ] || continue
		if zcat -f "${MODEL_DIR}/${name}" 2>/dev/null |
			grep -E '^\*(ModelName|NickName|Product):' | grep -qiwF -- "${core}"; then
			printf '%s' "${name}"
			return
		fi
	done < "${VENDOR}"
}

driver_for() {
	local device_id=$1 model=$2 driver="" ids="" models=""

	[ -n "${device_id}" ] && ids=$(lpinfo --device-id "${device_id}" -m 2>/dev/null)

	if [ -n "${model}" ] && { [ -z "${ids}" ] || [ -s "${VENDOR}" ]; }; then
		models=$(lpinfo --make-and-model "${model}" -m 2>/dev/null)
	fi

	# a driver the user supplied wins over the bundled free set
	if [ -s "${VENDOR}" ]; then
		driver=$(printf '%s\n%s\n' "${ids}" "${models}" | vendor_first)
		[ -n "${driver}" ] || driver=$(vendor_by_name "${model}")
	fi

	[ -n "${driver}" ] || driver=$(printf '%s\n' "${ids}" | awk 'NF { print $1; exit }')
	[ -n "${driver}" ] || driver=$(printf '%s\n' "${models}" | awk 'NF { print $1; exit }')

	printf '%s' "${driver}"
}

txt_value() {
	printf '%s' "$1" | grep -o "\"$2=[^\"]*\"" | head -1 | sed "s/^\"$2=//; s/\"\$//"
}

FOUND="[]"

while IFS=';' read -r _ _ _ SERVICE _ _ _ IP _ TXT; do
	[ -n "${SERVICE}" ] || continue

	MFG=$(txt_value "${TXT}" usb_MFG)
	MDL=$(txt_value "${TXT}" usb_MDL)

	MODEL="${MDL}"
	[ -n "${MODEL}" ] || MODEL=$(txt_value "${TXT}" ty)
	[ -n "${MODEL}" ] || MODEL=$(txt_value "${TXT}" product | tr -d '()')
	[ -n "${MODEL}" ] || MODEL="${SERVICE}"

	DEVICE_ID=""
	[ -n "${MFG}" ] && DEVICE_ID="MFG:${MFG};"
	[ -n "${MDL}" ] && DEVICE_ID="${DEVICE_ID}MDL:${MDL};"

	DRIVER=$(driver_for "${DEVICE_ID}" "${MODEL}")
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "dnssd://${SERVICE}._pdl-datastream._tcp.local/" \
		--arg name "${MODEL}" --arg address "${IP}" --arg id "${DEVICE_ID}" --arg driver "${DRIVER}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id, driver:$driver}]')
done < <(timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null | grep '^=' | grep ';IPv4;')

printf '%s' "${FOUND}" | jq -c 'unique_by(.device)'
