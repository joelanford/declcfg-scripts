#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

. "$(dirname "$0")/lib/funcs.sh"

: ${MODE:=none}
: ${OVERWRITE_LATEST=false}

add() {
	local configsDir=$1 bundleImage=$2

	if [[ ! -d "${configsDir}" ]]; then
		echo "${configsDir} is not a directory"
		exit 1
	fi

	##
	## Setup temporary working directories
	##
	local tmpdir
	tmpdir=$(mktemp -d -t declcfg-add-XXXXXXX)
	trap "rm -rf ${tmpdir}" EXIT
	mkdir -p ${tmpdir}/input
	mkdir -p ${tmpdir}/tmp
	mkdir -p ${tmpdir}/output

	##
	## Render the provided bundle image reference
	## Query its packageName and name
	##
	local inputBundle inputBundlePackageName inputBundleName
	inputBundle=$(opm alpha render "${bundleImage}" -o yaml)
	inputBundlePackageName=$(echo "${inputBundle}" | yq e '.package' -)
	inputBundleName=$(echo "${inputBundle}" | yq e '.name' -)

	##
	## Render and validate the provided DC reference,
	## then load them into the $configs variable
	##
	local packageDir configs
	packageDir="${configsDir}/${inputBundlePackageName}"
	mkdir -p ${packageDir}
	opm alpha render ${packageDir} -o yaml > ${tmpdir}/input/index.yaml
	#opm alpha validate ${tmpdir}/input
	configs=$(cat ${tmpdir}/input/index.yaml)

	## Search the configs to see if this bundle is already present.
	##   If so, populate the existing bundle into the $bundle variable
	local bundle
	bundle=$(getBundle "${configs}" "${inputBundlePackageName}" "${inputBundleName}")


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
	local package
	package=$(getPackage "${configs}" "${inputBundlePackageName}")
	if [[ -z "${package}" ]]; then
		mkdir -p ${tmpdir}/bundle
		opm alpha bundle unpack -v "${bundleImage}" -o ${tmpdir}/bundle

		local annotationsFile manifestsDir bundleDefaultChannel

		annotationsFile=$(find ${tmpdir}/bundle -name "annotations.yaml")
		manifestsDir=$(yq --exit-status eval '.annotations.["operators.operatorframework.io.bundle.manifests.v1"]' ${annotationsFile})
		bundleDefaultChannel=$(yq eval '.annotations.["operators.operatorframework.io.bundle.channel.default.v1"] // ""' ${annotationsFile})
		if [[ -z "${bundleDefaultChannel}" ]]; then
			bundleDefaultChannel=$(yq -j eval '.' ${annotationsFile} | jq -r '.annotations["operators.operatorframework.io.bundle.channels.v1"] | split(",")[0]')
		fi
		yq eval-all 'select(.kind=="ClusterServiceVersion").spec.description // ""' ${tmpdir}/bundle/${manifestsDir}/* > ${tmpdir}/bundle/description
		yq eval-all 'select(.kind=="ClusterServiceVersion").spec.icon[0].base64data // ""' ${tmpdir}/bundle/${manifestsDir}/* | base64 -d > ${tmpdir}/bundle/icon

		local iconArg iconSize
		iconArg=""
		iconSize=$(wc -c ${tmpdir}/bundle/icon | cut -d' ' -f1)
		if [[ "$iconSize" -gt 0 ]]; then
			iconArg="--icon=\"${tmpdir}/bundle/icon\""
		fi

		opm alpha init -o yaml ${inputBundlePackageName} \
			--default-channel="${bundleDefaultChannel}" \
			--description="${tmpdir}/bundle/description" \
			${iconArg} >> ${tmpdir}/tmp/index.yaml
	fi

	##
	## Add the rendered input bundle
	##
	echo "${inputBundle}" >> ${tmpdir}/tmp/index.yaml

	## Inherit ancestor bundles into descendent channels in replaces mode
	if [[ "$MODE" == "replaces" ]]; then
		$(dirname "$0")/inherit-channels.py ${tmpdir}/tmp/index.yaml
	fi

	## Inline bundle objects for the added bundle
	declcfg-inline-bundles ${tmpdir}/tmp ${bundleImage}

	## Render the final tmp/index.yaml to output/
	## Validate the final output
	## Format the input directory
	opm alpha render ${tmpdir}/tmp -o yaml > ${tmpdir}/output/index.yaml
	opm alpha validate ${tmpdir}/output
	mv ${packageDir} ${packageDir}.bak
	mv ${tmpdir}/output ${packageDir}
	rm -r ${packageDir}.bak
}

add "$1" "$2"
