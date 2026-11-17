#!/usr/bin/env bash
set -uo pipefail

OPTIONS=/data/options.json
DRIVERS=/share/airprint/drivers
# drivers shipped inside the image (airprint/drivers/ in the repo)
BUNDLED=/usr/share/airprint/drivers
WORK=/tmp/airprint-drivers
DOWNLOADED="${DRIVERS}/.downloaded"
MODEL_DIR=/usr/share/cups/model
# PPDs that came from a driver the user supplied; discover.sh prefers these
VENDOR=/tmp/airprint-vendor-ppds
SHIMS="${WORK}/shims"
LOG="${WORK}/dpkg.log"

mkdir -p "${DRIVERS}" "${WORK}" "${MODEL_DIR}" "${SHIMS}"
touch "${DOWNLOADED}"
: > "${VENDOR}"

# Vendor maintainer scripts (Brother's in particular) run `lpinfo -v` and
# `lpadmin` to make a queue of their own. `lpinfo -v` runs the snmp backend,
# which opens port 9100 and wakes the printer, and their queue would duplicate
# ours. Queues belong to queue.sh, so both are no-ops while a driver installs.
for tool in lpadmin lpinfo; do
	printf '#!/bin/sh\nexit 0\n' > "${SHIMS}/${tool}"
	chmod +x "${SHIMS}/${tool}"
done

WANTED=""

while read -r url; do
	[ -n "${url}" ] || continue

	name="${url##*/}"
	name="${name%%\?*}"
	file="${DRIVERS}/${name}"
	WANTED="${WANTED}${name}"$'\n'

	if [ -f "${file}" ]; then
		continue
	fi

	echo "[airprint] downloading driver ${name}"
	if ! curl -fsSL -o "${file}.part" "${url}"; then
		echo "[airprint] could not download ${url}"
		rm -f "${file}.part"
		continue
	fi
	mv "${file}.part" "${file}"
done < <(jq -r '[(.printers // [])[].driver] | map(select(. != null and . != "")) | unique | .[]' "${OPTIONS}")

while read -r stale; do
	[ -n "${stale}" ] || continue
	printf '%s' "${WANTED}" | grep -qxF "${stale}" && continue
	echo "[airprint] removing driver ${stale}, no longer listed"
	rm -f "${DRIVERS}/${stale}" "${WORK}/${stale}.extracted"
done < "${DOWNLOADED}"

printf '%s' "${WANTED}" > "${DOWNLOADED}"

NATIVE=$(dpkg --print-architecture)

can_run() {
	[ -z "$1" ] || [ "$1" = all ] || [ "$1" = "${NATIVE}" ] ||
		dpkg --print-foreign-architectures | grep -qxF "$1"
}

add_vendor_ppd() {
	local ppd=$1 name

	[ -f "${ppd}" ] || return 0

	case "${ppd}" in
	"${MODEL_DIR}"/*)
		name=${ppd#"${MODEL_DIR}"/}
		;;
	*)
		name=${ppd##*/}
		[ -e "${MODEL_DIR}/${name}" ] || ln -s "${ppd}" "${MODEL_DIR}/${name}"
		;;
	esac

	grep -qxF "${name}" "${VENDOR}" || printf '%s\n' "${name}" >> "${VENDOR}"
}

install_deb() {
	local deb=$1 quiet=${2:-} name=${1##*/} arch package

	arch=$(dpkg-deb -f "${deb}" Architecture 2>/dev/null)
	package=$(dpkg-deb -f "${deb}" Package 2>/dev/null)

	if ! can_run "${arch}"; then
		[ -n "${quiet}" ] || echo "[airprint] skipping ${name}: it is built for ${arch}, and this machine is ${NATIVE}"
		return 0
	fi

	if [ "$(dpkg-query -W -f='${Status} ${Version}' "${package}" 2>/dev/null)" != \
		"install ok installed $(dpkg-deb -f "${deb}" Version 2>/dev/null)" ]; then
		echo "[airprint] installing ${name}"
		if ! PATH="${SHIMS}:${PATH}" dpkg -i "${deb}" > "${LOG}" 2>&1; then
			echo "[airprint] ${name} needs extra packages, fetching them"
			apt-get update -qq >/dev/null 2>&1
			PATH="${SHIMS}:${PATH}" apt-get -y -qq -f install >> "${LOG}" 2>&1
		fi
	fi

	if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q 'install ok installed'; then
		echo "[airprint] could not install ${name}:"
		grep -v '^$' "${LOG}" | tail -5 | sed 's/^/[airprint]   /'
		return 0
	fi

	while read -r ppd; do
		add_vendor_ppd "${ppd}"
	done < <(dpkg -L "${package}" 2>/dev/null | grep -E '\.ppd(\.gz)?$')
}

shopt -s nullglob

for archive in "${DRIVERS}"/*.tar.gz "${DRIVERS}"/*.tgz; do
	name=${archive##*/}
	stamp="${WORK}/${name}.extracted"

	if [ ! -f "${stamp}" ]; then
		echo "[airprint] unpacking ${name}"
		rm -rf "${WORK}/${name}.d"
		mkdir -p "${WORK}/${name}.d"
		tar xzf "${archive}" -C "${WORK}/${name}.d" 2>/dev/null || {
			echo "[airprint] could not unpack ${name}"
			continue
		}
		touch "${stamp}"
	fi

	# every architecture a tarball carries is offered; install_deb keeps the
	# ones this machine can run (Brother names them foo.i386.deb, not foo_i386.deb)
	while read -r deb; do
		install_deb "${deb}" quiet
	done < <(find "${WORK}/${name}.d" -name "*.deb" | sort)
done

for package in "${BUNDLED}"/*.deb "${BUNDLED}"/*/*.deb; do
	# bundled drivers for another architecture are skipped without a log line
	install_deb "${package}" quiet
done

for package in "${DRIVERS}"/*.deb; do
	install_deb "${package}"
done

for ppd in "${DRIVERS}"/*.ppd "${DRIVERS}"/*.ppd.gz; do
	echo "[airprint] adding ${ppd##*/}"
	install -m 0644 "${ppd}" "${MODEL_DIR}/"
	add_vendor_ppd "${MODEL_DIR}/${ppd##*/}"
done

shopt -u nullglob
