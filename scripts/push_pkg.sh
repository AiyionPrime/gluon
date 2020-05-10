#!/bin/sh

set -e

topdir="$(realpath "$(dirname "${0}")/../openwrt")"

# defaults to qemu run script
ssh_port=2223
ssh_host=localhost
build_only=0

print_help() {
	echo "$0 [OPTIONS] PACAKGE_DIR"
	echo ""
	echo " -h          print this help"
	echo " -r HOST     use ssh host (default port will be 22)"
	echo " -p PORT     use ssh port"
	echo " -b          build only, do not push anywhere"
	echo ""
	echo ' To change gluon variables, run e.g. "make config GLUON_MINIFY=0"'
	echo ' because then the gluon logic will be triggered, and openwrt/.config'
	echo ' will be regenerated. The variables from openwrt/.config are already'
	echo ' automatically used for this script.'
	echo
}

while getopts "p:r:hb" opt
do
	case $opt in
		p) ssh_port="${OPTARG}";;
		r) ssh_host="${OPTARG}"; ssh_port=22;;
		b) build_only=1;;
		h) print_help; exit 0;;
		*) ;;
	esac
done
shift $(( OPTIND - 1 ))

if [ "$build_only" -eq 0 ]; then
	OPENWRT_BOARD="$(ssh -p "${ssh_port}" "root@${ssh_host}" sh -c \''. /etc/os-release; echo "$OPENWRT_BOARD"'\')"
	OPENWRT_ARCH="$(ssh -p "${ssh_port}" "root@${ssh_host}" sh -c \''. /etc/os-release; echo "$OPENWRT_ARCH"'\')"

	# check target
	if ! grep "CONFIG_TARGET_ARCH_PACKAGES=\"${OPENWRT_ARCH}\"" "${topdir}/.config" > /dev/null; then
		echo "Configured OpenWrt Target is not matching remote!" 1>&2
		printf "%s" "Local: " 1>&2
		grep "CONFIG_TARGET_ARCH_PACKAGES" "${topdir}/.config" 1>&2
		echo "Remote: ${OPENWRT_ARCH}" 1>&2
		echo 1>&2
		echo "To switch the local with the run with the corresponding GLUON_TARGET:"  1>&2
		echo "  make GLUON_TARGET=... config" 1>&2
		exit 1
	fi
fi

if [ $# -lt 1 ]; then
	echo ERROR: Please specify a PACKAGE_DIR. For example:
	echo
	echo " \$ $0 package/gluon-core"
	exit 1
fi

while [ $# -gt 0 ]; do

	pkgdir="$1"; shift
	echo "Package: ${pkgdir}"

	if ! [ -f "${pkgdir}/Makefile" ]; then
		echo "ERROR: ${pkgdir} does not contain a Makefile"
		exit 1
	fi

	if ! grep BuildPackage "${pkgdir}/Makefile" > /dev/null; then
		echo "ERROR: ${pkgdir}/Makefile does not contain a BuildPackage command"
		exit 1
	fi

	opkg_packages="$(grep BuildPackage "${pkgdir}/Makefile" | cut -d',' -f 2 | tr -d ')' | tr -d '\n')"

	search_package() {
		find "$2" -name "$1_*.ipk" -printf "%f\n"
	}

	make TOPDIR="${topdir}" -C "${pkgdir}" clean
	make TOPDIR="${topdir}" -C "${pkgdir}" compile

	if [ "$build_only" -eq 1 ]; then
		continue
	fi

	for pkg in ${opkg_packages}; do

		for feed in "${topdir}/bin/packages/${OPENWRT_ARCH}/"*/ "${topdir}/bin/targets/${OPENWRT_BOARD}/packages/"; do
			printf "%s" "searching ${pkg} in ${feed}: "
			filename=$(search_package "${pkg}" "${feed}")
			if [ -n "${filename}" ]; then
				echo found!
				break
			else
				echo not found
			fi
		done

		# IPv6 addresses need brackets around the ${ssh_host} for scp!
		if echo "${ssh_host}" | grep : > /dev/null; then
			BL=[
			BR=]
		fi

		# shellcheck disable=SC2029
		if [ -n "$filename" ]; then
			scp -P "${ssh_port}" "$feed/$filename" "root@${BL}${ssh_host}${BR}:/tmp/${filename}"
			echo Running opkg:
			ssh -p "${ssh_port}" "root@${ssh_host}" opkg install --force-reinstall "/tmp/${filename}"
			echo ok
			ssh -p "${ssh_port}" "root@${ssh_host}" rm "/tmp/${filename}"
			ssh -p "${ssh_port}" "root@${ssh_host}" gluon-reconfigure
		else
			# Some packages (e.g. procd-seccomp) seem to contain BuildPackage commands
			# which do not generate *.ipk files. Till this point, I am not aware why
			# this is happening. However, dropping a warning if the corresponding
			# *.ipk is not found (maybe due to other reasons as well), seems to
			# be more reasonable than aborting. Before this commit, the command
			# has failed.
			echo "Warning: ${pkg}*.ipk not found! Ignoring." 1>&2
		fi

	done
done
