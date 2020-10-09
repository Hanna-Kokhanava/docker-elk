#!/usr/bin/env bash

function log {
	echo -e "\n[+] $1\n"
}

function err {
	echo -e "\n[x] $1\n"
}

function poll_ready {
	local svc=$1
	local url=$2

	local -a args=( '-s' '-D-' '-w' '%{http_code}' "$url" )
	if [ "$#" -ge 3 ]; then
		args+=( '-u' "$3" )
	fi

	local label
	if [ "$MODE" == "swarm" ]; then
		label="com.docker.swarm.service.name=elk_${svc}"
	else
		label="com.docker.compose.service=${svc}"
	fi

	local cid
	# retry for max 60s (30*2s)
	for _ in $(seq 1 30); do
		cid="$(docker container ls -aq -f label="$label")"
		if [ -n "$cid" ]; then
			break
		fi

		echo -n '.'
		sleep 2
	done
	if [ -z "${cid:-}" ]; then
		err "Timed out waiting for creation of container with label ${label}"
		return 1
	fi

	local -i result=1
	local output

	# retry for max 180s (36*5s)
	for _ in $(seq 1 36); do
		if [[ $(docker container inspect "$cid" --format '{{ .State.Status}}') == 'exited' ]]; then
			err "Container exited ($(docker container inspect "$cid" --format '{{ .Name }}'))"
			return 1
		fi

		set +e
		output="$(curl "${args[@]}")"
		set -e
		if [ "${output: -3}" -eq 200 ]; then
			result=0
			break
		fi

		echo -n 'x'
		sleep 5
	done

	echo -e "\n${output::-3}"

	return $result
}
