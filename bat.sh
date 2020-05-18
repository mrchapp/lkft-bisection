#!/bin/bash -e

bat_get_section() {
  section=$1
  lin=$(grep -n "^\[${section}\]$" "${bisection_config}" | cut -d: -f1)
  if [ -n "${lin}" ]; then
    linuno=$((lin + 1))
    nextsec=$(tail -n +${linuno} "${bisection_config}" | grep -n "^\[[a-z].*\]$" | cut -d: -f1 | head -n1)
    if [ -n "${nextsec}" ]; then
      hasta=$((nextsec - 2))
      tail -n +${linuno} "${bisection_config}" | head -n ${hasta}
    else
      tail -n +${linuno} "${bisection_config}"
    fi
  fi
}

bat_section_exists() {
  section=$1
  grep -c "^\[${section}\]$" "${bisection_config}" | cut -d: -f1
}

bat_git_status() {
  if ! git -C "${GIT_DIR}" status > /dev/null 2>&1; then
    echo "ERROR: Not a Git repository, can't bisect."
    bat_error
  fi

  BAT_KERNEL_SHA=$(git -C "${GIT_DIR}" rev-parse HEAD)
  if [ -z "${BAT_KERNEL_SHA}" ]; then
    echo "ERROR: Could not determine Git revision"
    bat_error
  fi

  export BAT_KERNEL_SHA
  export BAT_KERNEL_SHA_SHORT=${BAT_KERNEL_SHA:0:12}

  num_steps=$(git -C "${GIT_DIR}" bisect log | grep -c -e '^git bisect old' -e '^git bisect new' || :)
  if [ -n "${num_steps}" ]; then
    # 1 for initial old, 1 for initial new; from there, first step (or #1)
    iter=$((num_steps - 1))
    echo
    echo "=============================================================="
    echo "BAT Iteration #${iter}: ${BAT_KERNEL_SHA}"
  fi
}

bat_old() {
  trap - EXIT
  echo "BAT BISECTION OLD: This iteration (kernel rev ${BAT_KERNEL_SHA}) presents old behavior."
  exit 0
}

bat_new() {
  trap - EXIT
  echo "BAT BISECTION NEW: This iteration (kernel rev ${BAT_KERNEL_SHA}) presents new behavior."
  exit 1
}

bat_error() {
  echo "BAT BISECTION ERROR: Script error, can't continue testing"
  exit 125
}

bat_run_stage() {
  stage=$1
  [ "$(bat_section_exists "${stage}")" = "0" ] && return
  echo "BAT Bisection: Configuration [${bisection_config}]; Stage: ${stage}"
  set -a
  # shellcheck disable=SC1090
  source <(bat_get_section bat)
  set +a
  # FIXME: Trap exit status
  eval "$(bat_get_section "${stage}")"
}

usage() {
  echo "Usage:"
  echo "  $0 bisection.conf"
  echo "will run the whole bisection. Or"
  echo "  $0 --stage bisection.conf"
  echo "to run just one stage of the bisection."
  echo
  echo "Stages can be:"
  echo "* build"
  echo "* publish"
  echo "* test"
  echo "* discriminator"
  echo "and any other custom stage defined in the bisection configuration."
  exit 0
}

# If a stage is not defined, it won't be called
BAT_DEFAULT_STAGES=(build publish test discriminator)

[ $# -eq 0 ] && usage

# Trap unexpected exits
trap bat_error INT TERM EXIT

if [ $# -eq 1 ] && [ -e "$1" ]; then
  # Managed mode
  bisection_config="$(readlink -e "$1")"
  echo "BAT Bisection: Configuration [${bisection_config}]"
  export bisection_config
  # Read bisection parameters
  eval "$(bat_get_section bat)"
  if [ ! -v GIT_DIR ]; then
    export GIT_DIR="."
  fi
  if [ "${BAT_VERIFY}" = "true" ]; then
    $0 --all "${bisection_config}"
    ret=$?
    if [ $ret -eq 0 ]; then
      echo "BAT Bisection: Verified NEW behavior"
    else
      echo "BAT Bisection: Unable to verify NEW behavior. Aborting."
      exit 1
    fi
  fi
  echo "BAT Bisection: OLD: [${BISECTION_OLD}]"
  echo "BAT Bisection: NEW: [${BISECTION_NEW}]"
  git -C "${GIT_DIR}" bisect start
  git -C "${GIT_DIR}" bisect old "${BISECTION_OLD}"
  git -C "${GIT_DIR}" bisect new "${BISECTION_NEW}"
  git -C "${GIT_DIR}" bisect run "$(readlink -e "$0")" --all "${bisection_config}"

  echo "BAT Bisection: Done"
  trap - INT TERM EXIT
  exit 0
fi

declare -a stages_to_run
for arg in "$@"; do
  if [ "${arg:0:2}" = "--" ]; then
    stage="${arg:2}"
    stages_to_run+=("${stage}")
  else
    bisection_config="${arg}"
  fi
done

if [ "${stages_to_run[0]}" = "all" ]; then
  if [[ ! -v BISECTION_STAGES ]]; then
    stages_to_run=("${BAT_DEFAULT_STAGES[@]}")
  else
    stages_to_run=("${BISECTION_STAGES[@]}")
  fi
fi

bat_git_status

for st in "${stages_to_run[@]}"; do
  bat_run_stage "${st}"
done
