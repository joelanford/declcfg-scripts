#!/usr/bin/env bash

set -e

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
		for anc in $(ancestors "${configs}" "${package}" "${ch}" "${bundleName}"); do
			if [[ "${anc}" == "${defChHead}" ]]; then
				echo "Cannot deprecate \"${bundle_image}\" because it would cause removal of \"${anc}\", which is the head of the default channel"
				exit 1
			fi
			configs=$(removeBundle "${configs}" "${package}" "${anc}")
		done
	done
	mkdir -p $tmpdir/output
	deprecateBundle "${configs}" "${package}" "${bundleName}" > $tmpdir/output/index.yaml
	opm validate $tmpdir/output
	cat $tmpdir/output/index.yaml
}

# ------------------------------------------------------------------------------------ #
# ------------------------------------------------------------------------------------ #
# ------------------------------------------------------------------------------------ #

getBundleFromImage() {
	local configs=$1 image=$2
	echo "${configs}" | yq e "select(.image==\"${image}\")" -
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

removeBundle() {
	local configs=$1 package=$2 bundle=$3
	configs=$(echo "${configs}" | yq eval-all "[.] | del(.[] | select(.schema==\"olm.bundle\" and .package==\"${package}\" and .name==\"${bundle}\") ) | .[] | splitDoc" -)
	#echo "yq eval \"del(.properties.[] | select(.type == \\\"olm.channel\\\" and .value.replaces == \\\"${bundle}\\\") | .value.replaces )\"" 1>&2
	configs=$(echo "${configs}" | yq eval "del(.properties.[] | select(.type == \"olm.channel\" and .value.replaces == \"${bundle}\") | .value.replaces )" -)
	echo "${configs}"
}

deprecateBundle() {
	local configs=$1 package=$2 bundle=$3
	echo "${configs}" | yq e "\
		select( .schema == \"olm.bundle\" and .package == \"${package}\" and .name == \"${bundle}\").properties += [ \
    			{\"type\":\"olm.deprecated\", \"value\":true}
  		] \
	" -
}

deprecateTruncate "$1" "$2"
