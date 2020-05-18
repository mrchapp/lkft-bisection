# Quickstart
```
BAT_GIT_DIR=/data/linux   ./bat.sh  simple-bisection.conf
```

# Config files
Each bisection session can be defined by a configuration file. This file defines
the procedural steps to execute in each step; by default these are:

* build
* publish
* test
* discriminator

If a stage is not defined, it won't be called.

# Stages
If the exit status of any of the stages is an unexpected non-zero, the bisection
step will be marked as "skip".

Those stages are defined as sections in the file (ini-like format), in shell
format. The main section, `[bat]`, defines the general parameters for the
bisection. E.g.:
```
BAT_BISECTION_OLD=v5.0-rc7
BAT_BISECTION_NEW=v5.0-rc8
```

Whatever exists in that section will be exported into the environment for all
stages to use.

Theses stages exist as a general guideline, and boundaries are fuzzy enough to
be used in distinct ways.

More stages can be defined, and the list of stages to run can be set (in `[bat]`
for example) like this:
```
BISECTION_STAGES=(build publish test discriminator)
```

## build
The `[build]` stage can be use a wide variety of mechanisms to build the required
artifacts. The following two variables define the current SHA being evaluated by
the bisection:
* `BAT_KERNEL_SHA`: Current Git SHA.
* `BAT_KERNEL_SHA_SHORT`: Idem, but in 12-hexdigits.

Build example using Tuxbuild:
```
tuxbuild build --git-repo https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git \
  --target-arch i386 \
  --toolchain gcc-9 \
  --json-out build.json \
  --kconfig defconfig \
  --git-sha ${BAT_KERNEL_SHA}
```

Build example for OpenEmbedded using Docker:
```
docker run --rm -it \
  -e MACHINE \
  -e KERNEL_RECIPE \
  -e KERNEL_VERSION \
  -e SRCREV_kernel=${BAT_KERNEL_SHA} \
  -v /opt/oe/downloads:/oe/downloads \
  -v /opt/oe/sstate-cache:/oe/sstate-cache \
  -v $HOME/lkft-bisect/build:/oe/build-lkft \
  mrchapp/lkft-sumo   bitbake rpb-console-image-lkft
```

## publish
Very commonly, a set of build artifacts need to be published somewhere so that
the testing stage can consume them. This can happen here.

Examples of publishing methods are: `rsync`, `scp`, local `cp`, etcetera.
Variables can be defined and exported here so that the `[test]` stage is aware
of the final location.

## test
The `[test]` stage can be used to run actual testing on the build artifacts.
Examples of testing can be submitting tests to LAVA or locally run a testsuite.

## discriminator
This stage can look at test results and then report results to the bisection
process. To do that, two helper functions can signal whether a test presents new
or old behavior: `bat_old` and `bat_new`.

# Example config file
```
[bat]
BAT_BISECTION_OLD=v5.0-rc7
BAT_BISECTION_NEW=v5.0-rc8

[discriminator]
ret=$(grep -c 'Linux kernel release 5.x' Documentation/admin-guide/README.rst ||:)
if [ "${ret}" = "0" ]; then
  bat_old
else
  bat_new
fi
```

The bisection's starting point (old behavior) is defined as v5.0-rc7, with
v5.0-rc8 as containing the new behavior.

This job defines only one stage: `discriminator`. It looks for a specific line
that was added in a recent revision of the file
`Documentation/admin-guide/README.rst`. If it doesn't exist, then the old
behavior is present; if the new line exists, then the new behavior is there.
