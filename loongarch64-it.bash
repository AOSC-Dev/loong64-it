#!/bin/bash
# A simple loongarch64 => loong64 .deb converter to help traverse the worlds.
#
# Mingcong Bai <jeffbai@aosc.io>, 2024

_display_usage() {
	printf "\
Usage:

	loongarch64-it [PACKAGE1] [PACKAGE2] ...

        - PACKAGE{1..N}: Path to the new-world .deb package to convert.

"
}

# Autobuild-like echo functions.
abwarn() { echo -e "[\e[33mWARN\e[0m]:  \e[1m$*\e[0m"; }
aberr()  { echo -e "[\e[31mERROR\e[0m]: \e[1m$*\e[0m"; exit 1; }
abinfo() { echo -e "[\e[96mINFO\e[0m]:  \e[1m$*\e[0m"; }
abdbg()  { echo -e "[\e[32mDEBUG\e[0m]: \e[1m$*\e[0m"; }

_convert_loong64() {
	abinfo "Examining package information: $1 ..."
	dpkg -I $1 || \
		aberr "Invalid dpkg package: control (metadata) archive not found: $?"
	CONTROL_EXT="$(ar t $1 | grep control.tar* | cut -f3 -d'.')"
	case "${CONTROL_EXT}" in
		gz)
			TAR_COMP_FLAG="z"
			;;
		xz)
			TAR_COMP_FLAG="J"
			;;
		bz2)
			TAR_COMP_FLAG="j"
			;;
		"")
			TAR_COMP_FLAG=""
			;;
		*)
			aberr "Invalid control archive extension ${CONTROL_EXT}!"
			;;
	esac

	abinfo "Unpacking: $1 ..."
	TEMPDIR=$(mktemp -d) || \
		aberr "Failed to create temporary directory to unpack $1: $?."
	cp -v $1 "$TEMPDIR"/ || \
		aberr "Failed to copy $1 to $TEMPDIR: $?."
	cd "$TEMPDIR" || \
		aberr "Failed to change directory to $TEMPDIR: $?."
	ar xv "$TEMPDIR"/$(basename $1) || \
		aberr "Failed to unpack $(basename $1): $?."

	abinfo "Unpacking metadata archive: $(basename $1) ..."
	mkdir "$TEMPDIR"/metadata || \
		aberr "Failed to create temporary directory for extracting the metdata archive from $(basenmae $1): $?."
	tar -C "$TEMPDIR"/metadata -xvf control.tar."${CONTROL_EXT}" || \
		aberr "Failed to unpack metadata archive from $(basename $1): $?."

	abinfo "Converting dpkg Architecture key: $(basename $1) ..."
	if ! egrep '^Architecture: loong64$' "$TEMPDIR"/metadata/control; then
		aberr "Failed to detect a \"loong64\" architecture signature in control file - this is not a valid new-world LoongArch package!"
	fi
	sed -e 's|^Architecture: loong64$|Architecture: loongarch64|g' \
	    -i "$TEMPDIR"/metadata/control

	abinfo "Building metadata archive (control.tar.${CONTROL_EXT}): $(basename $1) ..."
	cd "$TEMPDIR"/metadata
	tar cvf${TAR_COMP_FLAG} "$TEMPDIR"/control.tar."${CONTROL_EXT}" * || \
		aberr "Failed to build metadata archive (control.tar.${CONTROL_EXT}) for $(basename $1): $?."
	cd "$TEMPDIR"

	abinfo "Rebuilding dpkg package $1: loongarch64 ..."
	ar rv "$TEMPDIR"/$(basename $1) control.tar.${CONTROL_EXT} || \
		aberr "Failed to rebuild dpkg package $(basename $1): $?."

	abinfo "Moving package back to where you started ..."
	cp -v "$TEMPDIR"/$(basename $1) \
		"$RUNDIR"/$(basename ${i/loong64/loongarch64}) ||
		aberr "Failed to copy dpkg package $(basename $i) back to ${RUNDIR}: $?."

	abinfo """Your requested package:

    $1

Has been successfully converted as a loongarch64 package:

    "$RUNDIR"/$(basename ${1/loong64/loongarch64})
"""
}

# Display usage info if `-h' or `--help' is specified.
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
	_display_usage
	exit 0
fi

# Display usage info with directions if no option is specified.
if [ -z "$1" ]; then
	abwarn "Please specify package(s) to convert.\n"
	_display_usage
	exit 1
fi

RUNDIR="$PWD"

# Rebuilding all requested packages.
for i in "$@"; do
	_convert_loong64 $i
done
