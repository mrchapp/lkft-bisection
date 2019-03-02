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

function bat_old() {
  echo "BISECTION OLD: This iteration (kernel rev ${SRCREV}) presents old behavior."
  exit 0
}

function bat_new() {
  echo "BISECTION NEW: This iteration (kernel rev ${SRCREV}) presents new behavior."
  exit 1
}

function bat_error() {
  echo "BISECTION ERROR: Script error, can't continue testing"
  exit 125
}
trap bat_error INT TERM

function bat_run_stage() {
  stage=$1
  echo "BAT Bisection: Configuration [${bisection_config}]; Stage: ${stage}"
  # FIXME: Trap exit status
  eval "$(bat_get_section ${stage})"
}

function ext42simg() {
  sinext=${1%.ext4.gz}
  pigz -k -d "$1"
  ext2simg -v "${sinext}.ext4" "${sinext}.img"
  pigz -9 "${sinext}.img"
  rm "${sinext}.ext4"
}

function lkft_env() {
  BUILD_DIR=build-${MACHINE}

  COLOR_ON="\\[\\e[1;37;44m\\]"
  COLOR_OFF="\\[\\e[0m\\]"
  export NPS1="${COLOR_ON}[lkft:${MACHINE}]${COLOR_OFF} \\u\\[\\]@\\[\\]\\h\\[\\]:\\[\\]\\w$ "
  COMMANDS=""
  if [ $# -gt 0 ]; then
    COMMANDS="$*; exit $?"
  fi

  echo "Entering LKFT environment..."
  bash --rcfile <( \
    cat "${HOME}/.bashrc" && \
    echo "export PS1=\"${NPS1}\"" && \
    echo "export MACHINE=\"${MACHINE}\"" && \
    echo "export DISTRO=\"${DISTRO}\"" && \
    echo "source setup-environment \"${BUILD_DIR}\"" && \
    echo "${COMMANDS}" \
  ) -i
}

function usage() {
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

BAT_DEFAULT_STAGES=(build publish test discriminator)

[ $# -eq 0 ] && usage

if [ $# -eq 1 -a -e "$1" ]; then
  # Managed mode
  export bisection_config=$(readlink -e $1)
  echo "BAT Bisection: Configuration [${bisection_config}]"
  # Read bisection parameters
  eval "$(bat_get_section bat)"
  echo "BAT Bisection: OLD: [${BISECTION_OLD}]"
  echo "BAT Bisection: NEW: [${BISECTION_NEW}]"
  git bisect start
  git bisect old ${BISECTION_OLD}
  git bisect new ${BISECTION_NEW}
  git bisect run $(readlink -e $0) --all "${bisection_config}"
  $(readlink -e $0) --all "${bisection_config}"

  echo "BAT Bisection: Done"
  exit 0
fi

declare -a stages_to_run
for arg in $@; do
  if [ "${arg:0:2}" = "--" ]; then
    stage="${arg:2}"
    stages_to_run+=(${stage})
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

if ! git status > /dev/null 2>&1; then
  echo "ERROR: Not a Git repository, can't bisect."
  bat_error
fi
SRCREV=$(git rev-parse HEAD)
if [ -z "${SRCREV}" ]; then
  echo "ERROR: Could not determine Git revision"
  bat_error
fi
export SRCREV
export SHORT_SRCREV=${SRCREV:0:10}


for st in ${stages_to_run[@]}; do
  bat_run_stage ${st}
done
