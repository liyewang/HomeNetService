#!/bin/bash

DOWNLOAD_LINK_V2RAY="https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh"
DOWNLOAD_LINK_DAT="https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-dat-release.sh"
DOWNLOAD_LINK_H2Y="https://raw.githubusercontent.com/ToutyRater/V2Ray-SiteDAT/blob/master/geofiles/h2y.dat"
V2RAY="/root/v2ray"
V2RAY_DAT="/usr/local/share/v2ray"
PROXY=

evn_check() {
    if [[ "$UID" -ne '0' ]]; then
        echo "error: You must run this script as root!"
        exit 1
    fi
    if [[ ! -d "$V2RAY" ]]; then
        install -d "$V2RAY"
    fi
}

v2ray_update() {
    echo "Downloading: $DOWNLOAD_LINK_V2RAY"
    if ! curl ${PROXY} -L -H 'Cache-Control: no-cache' -o "${V2RAY}/install-release.sh.new" "$DOWNLOAD_LINK_V2RAY"; then
        if [[ ! -f "${V2RAY}/install-release.sh" ]]; then
            echo 'error: Download failed! Please check your network or try again.'
            exit 1
        else
            echo 'warning: Download failed! Use existing script instead.'
        fi
    else
        install -m 755 "${V2RAY}/install-release.sh.new" "${V2RAY}/install-release.sh"
        rm "${V2RAY}/install-release.sh.new"
    fi
    bash ${V2RAY}/install-release.sh
}

geodat_update() {
    echo "Downloading: $DOWNLOAD_LINK_DAT"
    if ! curl ${PROXY} -L -H 'Cache-Control: no-cache' -o "${V2RAY}/install-dat-release.sh.new" "$DOWNLOAD_LINK_DAT"; then
        if [[ ! -f "${V2RAY}/install-release.sh" ]]; then
            echo 'error: Download failed! Please check your network or try again.'
            exit 1
        else
            echo 'warning: Download failed! Use existing script instead.'
        fi
    else
        install -m 755 "${V2RAY}/install-dat-release.sh.new" "${V2RAY}/install-dat-release.sh"
        rm "${V2RAY}/install-dat-release.sh.new"
    fi
    bash ${V2RAY}/install-dat-release.sh
}

h2ydat_update() {
    if [[ ! -d "$V2RAY_DAT" ]]; then
        echo "error: Check v2ray installation!"
        exit 1
    fi
    echo "Downloading: $DOWNLOAD_LINK_H2Y"
    if ! curl ${PROXY} -L -H 'Cache-Control: no-cache' -o "${V2RAY_DAT}/h2y.dat.new" "$DOWNLOAD_LINK_H2Y"; then
        echo 'error: Download failed! Please check your network or try again.'
        exit 1
    else
        install -m 644 "${V2RAY_DAT}/h2y.dat.new" "${V2RAY_DAT}/h2y.dat"
        rm "${V2RAY_DAT}/h2y.dat.new"
    fi
}

evn_check
v2ray_update
# geodat_update
# h2ydat_update

echo 'Success'
exit 0
