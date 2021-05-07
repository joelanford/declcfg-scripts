#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

. "$(dirname "$0")/lib/funcs.sh"

deprecateTruncate() {
	local configsRef=$1 bundleImage=$2

	##
	## Setup temporary working directories
	##
	local tmpdir
	tmpdir=$(mktemp -d -t deprecatetruncate-XXXXXXX)
	trap "rm -rf $tmpdir" EXIT
	mkdir -p $tmpdir/input
	mkdir -p $tmpdir/tmp
	mkdir -p $tmpdir/output

	##
        ## Render and validate the provided DC reference,
        ## then load them into the $configs variable
        ##
	opm alpha render ${configsRef} -o yaml > $tmpdir/input/index.yaml
	opm alpha validate $tmpdir/input
	local configs
	configs=$(cat $tmpdir/input/index.yaml)



	##
	## Find the bundle created from the bundle image
	## If we can't find it, error out.
	##
        local bundle
	bundle=$(getBundleFromImage "${configs}" "${bundleImage}")
	if [[ -z "${bundle}" ]]; then
		echo "Cannot deprecate \"${bundleImage}\": not found in index"
		exit 1
	fi

	##
	## Query the package name, bundle name, and default channel head
	##
        local bundlePackageName bundleName defChHead
        bundlePackageName=$(echo "${bundle}" | yq e '.package' -)
        bundleName=$(echo "${bundle}" | yq e '.name' -)
	defChHead=$(defaultChannelHead "${configs}" "${bundlePackageName}")

	##
	## For each channel the bundle is in, get the bundle's ancestors
	## If any ancestor is the default channel head, error out.
	## Otherwise, remove all of the ancestors and update the working configs variable.
	##
	for ch in $(getBundleChannels "${bundle}"); do
		ancs=$(ancestors "${configs}" "${bundlePackageName}" "${ch}" "${bundleName}")
		if [[ "$ancs" == "" ]]; then continue; fi
		for anc in $ancs; do
			if [[ "${anc}" == "${defChHead}" ]]; then
				echo "Cannot deprecate \"${bundleImage}\" because it would cause removal of \"${anc}\", which is the head of the default channel"
				exit 1
			fi
		done
		configs=$(removeBundles "${configs}" "${bundlePackageName}" "${ancs}")
	done

	##
	## Deprecate the bundle, and write the resulting configs to tmp/index.yaml
	##
	# TODO: if deprecate property already exists, don't add it again
	deprecateBundle "${configs}" "${bundlePackageName}" "${bundleName}" > $tmpdir/tmp/index.yaml

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
