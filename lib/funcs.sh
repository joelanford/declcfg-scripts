#!/usr/bin/env bash

getBundleFromImage() {
	local configs=$1 image=$2
	echo "${configs}" | yq e "select(.image==\"${image}\")" -
}

getPackage() {
	local configs=$1 package=$2
	echo "${configs}" | yq e "select(.schema==\"olm.package\" and .name==\"${package}\")" -
}

getBundle() {
	local configs=$1 package=$2 bundleName=$3
	echo "${configs}" | yq e "select(.schema==\"olm.bundle\" and .package==\"${package}\" and .name==\"${bundleName}\")" -
}

defaultChannelHead() {
	local configs=$1 package=$2
	channelHead "${configs}" "${package}" "$(defaultChannel "${configs}" "${package}")"
}

channelHead() {
	local configs=$1 package=$2 channel=$3
	sortChannel "${configs}" "${package}" "${channel}" | tac | head -1
}

defaultChannel() {
	local configs=$1 package=$2
	echo "${configs}" | yq eval-all "\
		select(.schema==\"olm.package\" and .name==\"${package}\") | \
		.defaultChannel \
	" -
}

sortChannel() {
	local configs=$1 package=$2 channel=$3
	packageEdges "${configs}" "${package}" | yq e "\
		.[] | select(.channel==\"${channel}\") | \
		.from +\" \"+.to \
	" - | tsort
}

packageEdges() {
	local configs=$1 package=$2
	echo "${configs}" | yq eval-all "\
		select(.schema==\"olm.bundle\" and .package==\"${package}\") | \
		{ \
			\"channel\": .properties.[] | select(.type==\"olm.channel\") | .value.name, \
			\"from\":    .properties.[] | select(.type==\"olm.channel\") | .value.replaces, \
			\"to\":      .name \
		} | \
		select(.from != null) | [.] \
	" -
}

getBundleChannels() {
	local bundle=$1
	echo "${bundle}" | yq e ".properties.[] | select(.type==\"olm.channel\") | .value.name" - | sort | uniq
}

ancestors() {
	local configs=$1 package=$2 channel=$3 bundle=$4
	sortChannel "${configs}" "${package}" "${channel}" | tac | sed -n "/^${bundle}$/,\$p" | sed 1d
}

descendents() {
	local configs=$1 package=$2 channel=$3 bundle=$4
	sortChannel "${configs}" "${package}" "${channel}" | sed -n "/^${bundle}$/,\$p" | sed 1d
}

removeBundles() {
	local configs=$1 package=$2 bundles=$3

	local bundleMatchers=""	replaceMatchers=""
	for b in ${bundles}; do
		bundleMatchers="$bundleMatchers or .name == \"${b}\""
		replaceMatchers="$replaceMatchers or .value.replaces == \"${b}\""
	done
	bundleMatchers="(${bundleMatchers#" or "})"
	replaceMatchers="(${replaceMatchers#" or "})"

	configs=$(echo "${configs}" | yq eval-all "[.] | del(.[] | select(.schema==\"olm.bundle\" and .package==\"${package}\" and ${bundleMatchers})) | .[] | splitDoc" -)
	configs=$(echo "${configs}" | yq eval "del(.properties[] | select(.type == \"olm.channel\" and ${replaceMatchers}) | .value.replaces )" -)
	echo "${configs}"
}

removeIfLatest() {
        local configs=$1 bundle=$2

        local bundlePackageName=$(echo "${bundle}" | yq e '.package' -)
        local bundleName=$(echo "${bundle}" | yq e '.name' -)

        for ch in $(getBundleChannels "${bundle}"); do
                descs=$(descendents "${configs}" "${bundlePackageName}" "${ch}" "${bundleName}")
                if [[ "$descs" != "" ]]; then
                        echo "Cannot overwrite \"${bundleName}\", it is not the head of channel \"${ch}\"" >&2
                        exit 1
                fi
        done

        removeBundles "${configs}" "${bundlePackageName}" "${bundleName}"
}

deprecateBundle() {
	local configs=$1 package=$2 bundle=$3
	echo "${configs}" | yq e "\
		select( .schema == \"olm.bundle\" and .package == \"${package}\" and .name == \"${bundle}\").properties += [ \
			{\"type\":\"olm.deprecated\"}
  		] \
	" -
}

fmt() {
        local configsRef=$1 out=$2

        local configs files
        configs=$(opm alpha render "$configsRef" -o json)
        files=$(echo "$configs" | jq --arg out "$out" -sc 'group_by(if .schema=="olm.package" then .name else .package end) | .[] | {filename: ($out + "/" + .[0].name + "/" + .[0].name + ".yaml"), blobs: . }')

        IFS=$'\n'
        for f in $files; do
                local filename blobs
                filename=$(echo "$f" | jq -r '.filename')
                blobs=$(echo "$f" | yq e -P '.blobs[] | splitDoc' -)
                mkdir -p $(dirname $filename)
                echo "$blobs" > "$filename"
        done
}

debug() {
	echo $@ >&2
}

#skips() {
#	local configs=$1
#	local package=$2
#	local bundle=$3
#
#        echo "${configs}" | yq eval-all "\
#                select(.schema==\"olm.bundle\" and .package==\"${package}\" and .name==\"${bundle}\") | \
#                .properties.[] | \
#		select(.type==\"olm.skips\") | \
#		.value \
#        " -
#}
