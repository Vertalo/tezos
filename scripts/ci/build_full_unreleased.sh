#!/bin/sh
set -eu

if [ -z "${build_deps_image_name}" ]; then echo "build_deps_image_name is unset" && exit 3; fi
if [ -z "${build_deps_image_version}" ]; then echo "build_deps_image_version is unset" && exit 3; fi

# We remove protocols not needed for tests in order to speed up the CI.
old_protocol_store=$(mktemp -d)
./scripts/remove-old-protocols.sh "$old_protocol_store"
. ./scripts/version.sh

# 1. Some basic, fast sanity checks
if [ "${build_deps_image_version}" != "${opam_repository_tag}" ] ; then
    echo "Inconsistent dependencies hash between 'scripts/version.sh' and '.gitlab/ci/templates.yml'." ;
    echo "${build_deps_image_version} != ${opam_repository_tag}" ;
    exit 1 ;
fi

diff poetry.lock /home/tezos/poetry.lock
diff pyproject.toml /home/tezos/pyproject.toml

# 2. Actually build.
#    Also build the tps evaluation tool which is not part of the default build,
#    and the tezt main entrypoint for integration tests, by adding them to the `BUILD_EXTRA` target.
#    NOTE: Making one call to `dune build` a lot of times `dune` would
#    otherwise need to reconstruct its rules. Do not split this
#    invocation.
#    NOTE: We add $COVERAGE_OPTIONS to all dune build commands to
#    enable reuse of build artifacts.
make BUILD_EXTRA="src/bin_tps_evaluation tezt/tests/main.exe"


# 3. clean-up caches before uploading the cache
opam clean
