#!/usr/bin/env bash

set -eu
set -o pipefail

. "$(dirname "$0")/lib/funcs.sh"

add() {
	local configsRef=$1 bundleImage=$2

	##
	## Setup temporary working directories
	##
	tmpdir=$(mktemp -d -t declcfg-add-XXXXXXX)
	trap "rm -rf ${tmpdir}" EXIT
	mkdir -p ${tmpdir}/input
	mkdir -p ${tmpdir}/tmp
	mkdir -p ${tmpdir}/output

	##
	## Render and validate the provided DC reference,
	## then load them into the $configs variable
	##
	opm alpha render ${configsRef} -o yaml > ${tmpdir}/input/index.yaml
	opm alpha validate ${tmpdir}/input
	local configs=$(cat ${tmpdir}/input/index.yaml)


	##
	## Render the provided bundle image reference
	## Query its packageName and name
	## Search the configs to see if this bundle is already present.
	##   If so, populate the existing bundle into the $bundle variable
	##
	local inputBundle=$(opm alpha render "${bundleImage}" -o yaml)
	local inputBundlePackageName=$(echo "${inputBundle}" | yq e '.package' -)
	local inputBundleName=$(echo "${inputBundle}" | yq e '.name' -)
	local bundle=$(getBundle "${configs}" "${inputBundlePackageName}" "${inputBundleName}")

	##
	## If the bundle already exists and it is the head of every channel it is in,
	## Remove the bundle and write the resulting config to tmp/index.yaml
	##
	## Otherwise, this is a "simple" add, so just copy the input index to tmp/index.yaml
	##
	if [[ -n "${bundle}" ]]; then
		removeIfLatest "${configs}" "${bundle}" > ${tmpdir}/tmp/index.yaml
	else
		cp ${tmpdir}/input/index.yaml ${tmpdir}/tmp/index.yaml
	fi


	##
	## Search the configs to see if the package for the input bundle is present.
	## If not, unpack the bundle and build a new olm.package blob from it.
	##
	local package=$(getPackage "${configs}" "${inputBundlePackageName}")
	if [[ -z "${package}" ]]; then
		mkdir -p ${tmpdir}/bundle
		opm alpha bundle unpack -v "${bundleImage}" -o ${tmpdir}/bundle

		local annotationsFile=$(find ${tmpdir}/bundle -name "annotations.yaml")
		local manifestsDir=$(yq --exit-status eval '.annotations.["operators.operatorframework.io.bundle.manifests.v1"]' ${annotationsFile})

		local bundleDefaultChannel=$(yq eval '.annotations.["operators.operatorframework.io.bundle.channel.default.v1"] // ""' ${annotationsFile})
		if [[ -z "${bundleDefaultChannel}" ]]; then
			bundleDefaultChannel=$(yq -j eval '.' ${annotationsFile} | jq -r '.annotations["operators.operatorframework.io.bundle.channels.v1"] | split(",")[0]')
		fi
		yq eval-all 'select(.kind=="ClusterServiceVersion").spec.description // ""' ${tmpdir}/bundle/${manifestsDir}/* > ${tmpdir}/bundle/description
		yq eval-all 'select(.kind=="ClusterServiceVersion").spec.icon[0].base64data // ""' ${tmpdir}/bundle/${manifestsDir}/* | base64 -d > ${tmpdir}/bundle/icon

		opm alpha init -o yaml ${inputBundlePackageName} --default-channel="${bundleDefaultChannel}" --description="${tmpdir}/bundle/description" --icon="${tmpdir}/bundle/icon" >> ${tmpdir}/tmp/index.yaml
	fi

	##
	## Add the rendered input bundle
	##
	echo "${inputBundle}" >> ${tmpdir}/tmp/index.yaml

	## Inline bundle objects for the added bundle
	declcfg-inline-bundles ${tmpdir}/tmp ${bundleImage}

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

add "$1" "$2"
