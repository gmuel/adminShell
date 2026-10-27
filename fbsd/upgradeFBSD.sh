#!/bin/sh

New_Version=$1

[ -z "$New_Version" ] && echo new version string required: $0 new_version, aborting ... && exit 1

pkg upgrade -r FreeBSD-base
# Upgrade the Base System:
pkg -oABI=FreeBSD:15:$(uname -p) -oOSVERSION="${New_Version}" upgrade -r FreeBSD-base
# Upgrade Kernel Modules:
pkg upgrade -r FreeBSD-ports-kmods
