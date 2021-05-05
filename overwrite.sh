#!/usr/bin/env bash

set -e

. funcs.sh

overwrite() {
	local configs_ref=$1 bundle_image=$2

	tmpdir=$(mktemp -d -t overwrite-XXXXXXX)
	trap "rm -rf $tmpdir" EXIT
	mkdir -p $tmpdir/input
	opm alpha unpack ${configs_ref} -o yaml > $tmpdir/input/index.yaml
	opm alpha validate $tmpdir/input

	local configs=$(cat $tmpdir/input/index.yaml)
        local bundle=$(getBundleFromImage "${configs}" "${bundle_image}")
        local package=$(echo "${bundle}" | yq e '.package' -)
        local bundleName=$(echo "${bundle}" | yq e '.name' -)

	for ch in $(getBundleChannels "${bundle}"); do
		descs=$(descendents "${configs}" "${package}" "${ch}" "${bundleName}")
		if [[ "$descs" != "" ]]; then
			echo "Cannot overwrite \"${bundleName}\", it is not the head of channel \"${ch}\""
			exit 1
		fi
	done

	mkdir -p $tmpdir/tmp
	removeBundles "${configs}" "${package}" "${bundleName}" > $tmpdir/tmp/index.yaml
	opm alpha unpack ${bundle_image} -o yaml >> $tmpdir/tmp/index.yaml

	mkdir -p $tmpdir/output
	opm alpha unpack $tmpdir/tmp -o yaml > $tmpdir/output/index.yaml

	opm alpha validate $tmpdir/output
	cat $tmpdir/output/index.yaml
}

overwrite "$1" "$2"
