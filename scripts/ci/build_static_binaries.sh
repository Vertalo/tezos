#!/bin/sh
set -eu

echo "Create destination directory"
mkdir -pv "octez-binaries/$ARCH"

echo "Build and install static binaries"
make static

# Trim the dune cache, if used.
dune cache trim --size=250GB

echo "Check executables and move them to the destination directory"
for executable in $(cat script-inputs/binaries-for-release); do
    if [ ! -f "$executable" ]; then
        echo "Error: $executable does not exist"
        exit 1
    fi

    if (file "$executable" | grep -q "statically linked"); then
        echo "Statically linked: $executable"
    else
        echo "Error: $executable is not statically linked"
        exit 1
    fi

    mv "$executable" "octez-binaries/$ARCH/$executable"
    # Write access is needed by strip below.
    chmod +w "octez-binaries/$ARCH/$executable"
done

echo 'Check octez-client --version'
SHA=$(git rev-parse --short=8 HEAD)
client_version=$("octez-binaries/$ARCH/octez-client" --version | cut -f 1 -d ' ')
if [ "$SHA" != "$client_version" ]; then
    echo "Unexpected version for octez-client (expected $SHA, found $client_version)"
    exit 1
fi
echo "octez-client --version returned the expected commit hash: $SHA"

echo "Strip debug symbols and compress binaries (parallelized)"
# shellcheck disable=SC2046,SC2038
find "octez-binaries/$ARCH" -maxdepth 1 -type f ! -name "*.*" | xargs -n1 -P$(nproc) -i sh -c 'strip --strip-debug {}; upx -6q {};'

# Show the effect of previous actions
find "octez-binaries/$ARCH" -maxdepth 1 -type f ! -name "*.*" |
while read -r b; do
    file "$(realpath "$b")";
done
