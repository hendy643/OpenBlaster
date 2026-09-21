#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# After a package is installed: every library the app and its plugins need must resolve, including the one the
# app opens at run time (libasound). Run in the CI container that installed the package.
#   packaging/check-install.sh [APPDIR]     (default /usr/lib/openblaster)
set -euo pipefail
app=${1:-/usr/lib/openblaster}
bad=0
for f in "$app/openblaster" "$app"/lib/*.so; do
    if missing=$(ldd "$f" | grep "not found"); then
        echo "$f: $missing"; bad=1
    fi
done
[[ $(ldconfig -p) == *libasound.so.2* ]] || { echo "libasound.so.2 is not installed"; bad=1; }
exit $bad
