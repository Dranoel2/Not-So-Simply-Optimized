#!/bin/bash
set -e
cd $(dirname $0)

USER_AGENT=$(jq -r '.user_agent' options.json)
UPSTREAM_VERSION=$(jq -r '.upstream_version' options.json)
EXTRA_MODS=( $(jq -r '.extra_mods | values | .[]' options.json) )
NAME=$(jq -r '.name' options.json)

fetch() {
	url=$1

	curl -A "$USER_AGENT" -L $url
}

usage () {
	code=$1

	cat <<-__EOF__
		usage: pack.sh <COMMAND>

		COMMAND:
		  download
		    Download and extract the upstream
		  
		  patch
		    Patch the source and compress it

		  get_info <ID>
		    Get the info for a mod; useful for adding it to the pack.

		    ID: The id (slug) of the modpack 
		  
		  clean
		    Delete source and output files

		  help
		    Show this message
	__EOF__

	exit $code
}

download_upstream() {
	if [ "$#" -ne 0 ]; then
		usage 1
	fi

	rm -rf source source.zip

	version_data=$(fetch https://api.modrinth.com/v2/version/$UPSTREAM_VERSION)
	file_data=$(echo $version_data | jq ".files[0]")

	url=$(echo $file_data | jq -r ".url")
	curl -L $url -o source.mrpack

	unzip source.mrpack -d source
}

patch_source() {
	if [ "$#" -ne 0 ]; then
		usage 1
	fi
	
	echo $EXTRA_MODS

	rm -rf out out.zip
	cp -r source out

	modpack_data=$(jq --arg name "$NAME" '.name = $name | .' source/modrinth.index.json)
	for mod in "${EXTRA_MODS[@]}"; do
		version_data=$(fetch https://api.modrinth.com/v2/version/$mod)
		file_data=$(echo $version_data | jq -r '.files[0]')
		mod_data=$(echo $file_data | jq -r '{ "hashes": .hashes, "downloads": [ .url ], "path": "mods/\(.filename)", "size": .size }')
		modpack_data=$(echo $modpack_data | jq -r --arg data "$mod_data" '.files = .files + [$data | fromjson] | .')
	done

	echo $modpack_data > out/modrinth.index.json

	cp -R overrides/* out/overrides/

	cd out
	zip -r ../out.mrpack .
}

get_info() {
	echo $#
	if [ "$#" -ne 1 ]; then
		usage 1
	fi

	id=$1

	project_data=$(fetch https://api.modrinth.com/v2/project/$id/version)

	versions_message=$(echo $project_data | jq -r '.[] | "Id: \(.id), Version: \(.version_number), Game Versions: \(.game_versions), Loaders: \(.loaders)"')

	echo "$versions_message" | less
}

clean() {
	if [ "$#" -ne 0 ]; then
		usage 1
	fi

	rm -rf source.mrpack source out.mrpack out
}

main() {
	if ! [ "$#" -ge 1 ]; then
		usage 1
	fi
		
	command=$1
	
	case $command in
		download) download_upstream ${@:2};;
		patch) patch_source ${@:2};;
		get_info) get_info ${@:2};;
		clean) clean ${@:2};;
		help) usage 0;;
		*) usage 1;;
	esac
}

main $@
