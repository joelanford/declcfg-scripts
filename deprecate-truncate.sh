#!/usr/bin/env bash

set -eu

. "$(dirname "$0")/lib/funcs.sh"

deprecateTruncate() {
	local configsRef=$1 bundle_image=$2

	tmpdir=$(mktemp -d -t deprecatetruncate-XXXXXXX)
	trap "rm -rf $tmpdir" EXIT

	mkdir -p $tmpdir/input
	mkdir -p $tmpdir/tmp
	mkdir -p $tmpdir/output

	opm alpha render ${configsRef} -o yaml > $tmpdir/input/index.yaml
	opm alpha validate $tmpdir/input


	local configs=$(cat $tmpdir/input/index.yaml)
        local bundle=$(getBundleFromImage "${configs}" "${bundle_image}")

	if [[ -z "${bundle}" ]]; then
		echo "Cannot deprecate \"${bundle_image}\": not found in index"
		exit 1
	fi

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

	# TODO: if deprecate property already exists, don't add it again
	deprecateBundle "${configs}" "${package}" "${bundleName}" > $tmpdir/tmp/index.yaml

	## Render the final tmp/index.yaml to output/
        ## Validate the final output
        ## Format the input directory or print the final updated configs to stdout (if the input was an index image)
	if [[ -d "${configsRef}" ]]; then
		mv ${configsRef} ${configsRef}.bak
		fmt ${tmpdir}/tmp ${tmpdir}/output
		opm alpha validate ${tmpdir}/output
		mv ${tmpdir}/output ${configsRef}
		rm -r ${configsRef}.bak
	else
		opm alpha render -o yaml ${tmpdir}/tmp > ${tmpdir}/output/index.yaml
		opm alpha validate ${tmpdir}/output
		cat ${tmpdir}/output/index.yaml
	fi

}

deprecateTruncate "$1" "$2"
