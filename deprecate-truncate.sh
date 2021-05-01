#!/usr/bin/env bash

set -e

. funcs.sh

deprecateTruncate() {
	local configs_ref=$1 bundle_image=$2

	tmpdir=$(mktemp -d -t deprecatetruncate-XXXXXXX)
	#trap "rm -rf $tmpdir" EXIT
	mkdir -p $tmpdir/input
	opm alpha unpack ${configs_ref} > $tmpdir/input/index.yaml
	opm validate $tmpdir/input

	local configs=$(cat $tmpdir/input/index.yaml)
        local bundle=$(getBundleFromImage "${configs}" "${bundle_image}")
        local package=$(echo "${bundle}" | yq e '.package' -)
        local bundleName=$(echo "${bundle}" | yq e '.name' -)
	local defChHead=$(defaultChannelHead "${configs}" "${package}")

	for ch in $(getBundleChannels "${bundle}"); do
		ancs=$(ancestors "${configs}" "${package}" "${ch}" "${bundleName}")
		if [[ "$ancs" == "" ]]; then continue; fi
		for anc in $ancs; do
			if [[ "${anc}" == "${defChHead}" ]]; then
				echo "Cannot deprecate \"${bundle_image}\" because it would cause removal of \"${anc}\", which is the head of the default channel"
				exit 1
			fi
		done
		configs=$(removeBundles "${configs}" "${package}" "${ancs}")
	done
	mkdir -p $tmpdir/output
	deprecateBundle "${configs}" "${package}" "${bundleName}" > $tmpdir/output/index.yaml
	opm validate $tmpdir/output
	cat $tmpdir/output/index.yaml
}

deprecateTruncate "$1" "$2"
