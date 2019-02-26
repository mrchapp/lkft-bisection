#!/bin/bash -e

bisection_config=$1

config_get_section() {
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

echo
echo "======================================================================================================"
SRCREV=$(git rev-parse HEAD)
if [ -n "${SRCREV}" ]; then
  echo "ERROR: Could not determine Git revision"
  bat_error
fi
export SRCREV
export SHORT_SRCREV=${SRCREV:0:10}

#git status

# Build
eval "$(config_get_section build)"

# Publish images
eval "$(config_get_section publish)"

# Create LAVA job
rm -f job.yaml
eval "cat << EOF
$(cat <(config_get_section lavajob))
" > job.yaml 2> /dev/null

# Submit and wait for completion of LAVA job
eval "$(config_get_section test)"

# Determine fail or pass
eval "$(config_get_section discriminator)"
