#!/usr/bin/env bash

set -eu
set -o pipefail

. funcs.sh

add() {
	local configs_ref=$1 bundleImage=$2

	tmpdir=$(mktemp -d -t declcfg-add-XXXXXXX)
	trap "rm -rf $tmpdir" EXIT

	mkdir -p $tmpdir/input
	mkdir -p $tmpdir/tmp
	mkdir -p $tmpdir/output

	opm alpha render ${configs_ref} -o yaml > $tmpdir/input/index.yaml
	opm alpha validate $tmpdir/input

	local configs=$(cat $tmpdir/input/index.yaml)
	local inputBundle=$(opm alpha render "${bundleImage}" -o yaml)
	local package=$(echo "${inputBundle}" | yq e '.package' -)
	local bundleName=$(echo "${inputBundle}" | yq e '.name' -)
	local bundle=$(getBundle "${configs}" "${package}" "${bundleName}")

	if [[ -n "$bundle" ]]; then
		removeIfLatest "$configs" "$bundle" > $tmpdir/tmp/index.yaml
	else
		cp $tmpdir/input/index.yaml $tmpdir/tmp/index.yaml
	fi

	echo "${inputBundle}" >> $tmpdir/tmp/index.yaml

	declcfg-inline-bundles $tmpdir/tmp ${bundleImage}
	opm alpha render $tmpdir/tmp -o yaml > $tmpdir/output/index.yaml
	opm alpha validate $tmpdir/output

	cat $tmpdir/output/index.yaml
}

removeIfLatest() {
	local configs=$1 bundle=$2

	local package=$(echo "${bundle}" | yq e '.package' -)
	local bundleName=$(echo "${bundle}" | yq e '.name' -)

	for ch in $(getBundleChannels "${bundle}"); do
		descs=$(descendents "${configs}" "${package}" "${ch}" "${bundleName}")
		if [[ "$descs" != "" ]]; then
			echo "Cannot overwrite \"${bundleName}\", it is not the head of channel \"${ch}\"" >&2
			exit 1
		fi
	done

	removeBundles "${configs}" "${package}" "${bundleName}"
}

add "$1" "$2"


