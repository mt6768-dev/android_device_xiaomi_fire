#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2023 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=earth
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

# If XML files don't have comments before the XML header, use this flag
# Can still be used with broken XML files by using blob_fixup
export TARGET_DISABLE_XML_FIXING=true

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_FIRMWARE=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-firmware )
                ONLY_FIRMWARE=true
                ;;
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup {
    case "$1" in
        system_ext/lib64/libsink.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --add-needed "libshim_sink.so" "$2"
            ;;
        system_ext/lib64/libsource.so)
            [ "$2" = "" ] && return 0
            grep -q "libui_shim.so" "${2}" || "${PATCHELF}" --add-needed "libui_shim.so" "${2}"
            ;;
        vendor/bin/hw/android.hardware.media.c2@1.2-mediatek)
            ;&
        vendor/bin/hw/android.hardware.media.c2@1.2-mediatek-64b)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --add-needed "libstagefright_foundation-v33.so" "${2}"
            ;;
        vendor/bin/hw/android.hardware.gnss-service.mediatek |\
        vendor/lib64/hw/android.hardware.gnss-impl-mediatek.so)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "android.hardware.gnss-V1-ndk_platform.so" "android.hardware.gnss-V1-ndk.so" "$2"
            ;;
        vendor/bin/hw/vendor.mediatek.hardware.mtkpower@1.0-service)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "android.hardware.power-V2-ndk_platform.so" "android.hardware.power-V2-ndk.so" "$2"
            ;;
        vendor/bin/mnld|\
        vendor/lib*/libaalservice.so|\
        vendor/lib64/libcam.utils.sensorprovider.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "libsensorndkbridge.so" "android.hardware.sensors@1.0-convert-shared.so" "${2}"
            ;;
        vendor/lib*/hw/vendor.mediatek.hardware.pq@2.15-impl.so)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "libutils.so" "libutils-v32.so" "$2"
            "${PATCHELF}" --replace-needed "libsensorndkbridge.so" "android.hardware.sensors@1.0-convert-shared.so" "${2}"
            ;;
        vendor/lib64/libmtkcam_featurepolicy.so)
            [ "$2" = "" ] && return 0
            # evaluateCaptureConfiguration()
            sed -i "s/\x34\xE8\x87\x40\xB9/\x34\x28\x02\x80\x52/" "$2"
            ;;
        vendor/lib*/libmtkcam_stdutils.so|\
        vendor/lib64/hw/android.hardware.camera.provider@2.6-impl-mediatek.so)
            [ "$2" = "" ] && return 0
            "${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
            ;;
        vendor/lib64/sensors.camera.light.so)
            [ "$2" = "" ] && return 0
            "$PATCHELF" --replace-needed "libcamera2ndk_vendor.so" "libcamera2ndk_vendor-v35.so" "$2"
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

function blob_fixup_dry() {
    blob_fixup "$1" ""
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

if [ -z "${ONLY_FIRMWARE}" ]; then
    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${SECTION}" ]; then
    extract_firmware "${MY_DIR}/proprietary-firmware.txt" "${SRC}"
fi

"${MY_DIR}/setup-makefiles.sh"
