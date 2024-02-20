#!/bin/zsh

set -euo pipefail

readonly BUILD_DIR="opencv_build"
readonly OUTPUT_DIR="${BUILD_DIR}/output"

clone() {
    readonly VERSION="${1}"
    git clone --branch "${VERSION}" --depth 1 https://github.com/opencv/opencv.git "${BUILD_DIR}/${VERSION}"
}

build_xcframework() {
    readonly VERSION="${1}"
    shift

    python3 "${BUILD_DIR}/${VERSION}/platforms/apple/build_xcframework.py" \
        --build_only_specified_archs \
        --iphoneos_archs arm64 \
        --iphonesimulator_archs arm64,x86_64 \
        --out "${OUTPUT_DIR}" \
        "$@"
}

build_xcframework_excluding_modules_4_9_0() {
    readonly VERSION="4.9.0"

    # Baseline of which modules to include, obtained from https://github.com/nihui/opencv-mobile/tree/master?tab=readme-ov-file#opencv-modules-included

    # Remove below big files that Revolut does not use
    find "${BUILD_DIR}/${VERSION}/modules/imgproc/src" -maxdepth 1 -type f -name 'imgwarp*' -delete # Delete 691KB
    
    python3 "${BUILD_DIR}/${VERSION}/platforms/apple/build_xcframework.py" \
        --build_only_specified_archs \
        --iphoneos_archs arm64 \
        --iphonesimulator_archs arm64,x86_64 \
        --out "${OUTPUT_DIR}" \
        `# --without calib3d # Needed by Revolut code` \
        `# --without core # based on baseline` \
        --without dnn \
        `# --without features2d # based on baseline` \
        `# --without flann # Needed by calib3d` \
        --without gapi \
        `# --without highgui # based on baseline` \
        `# --without imgcodecs # Needed by Revolut code` \
        `# --without imgproc # based on baseline` \
        --without java \
        --without js \
        `# --without ml # Needed by Incode and IPCheckCapture2` \
        --without objc \
        `# --without objdetect # Needed by Incode` \
        `# --without photo # based on baseline` \
        --without python \
        --without stitching \
        --without ts \
        `# --without video # based on baseline` \
        --without videoio \
        --without world \
        "$@"

        # Outcome at the time of testing, for a release-type build:
        # * Before: opencv size is 13.5MB
        # * After: opencv size is 4MB
}

# OpenCV builds frameworks with symlinks inside them: remove them here, for clarity
patch_xcframework_remove_symlinks() {
    readonly TMP_DIR="${OUTPUT_DIR}/tmp_dir"
    find "$(pwd)/${OUTPUT_DIR}/opencv2.xcframework" -name '*.framework' -print0 | while read -d $'\0' framework; do
        rm -rf "${TMP_DIR}"
        mv "${framework}" "${TMP_DIR}"
        mv "${TMP_DIR}/Versions/A" "${framework}"
        mv "${framework}/Resources/Info.plist" "${framework}/Info.plist"
        rm -rf "${framework}/Resources"
        rm -rf "${TMP_DIR}"
    done
}

# Disable iOS visibility warnings
# See: https://github.com/opencv/opencv/issues/7565#issuecomment-555549631
disable_ios_visibility_warnings() {
    readonly VERSION="${1}"
    readonly FILE_TO_PATCH="${BUILD_DIR}/${VERSION}/CMakeLists.txt"

    # Add the OPENCV_SKIP_VISIBILITY_HIDDEN to the first line of the CMakeLists.txt file
    echo -e "SET(OPENCV_SKIP_VISIBILITY_HIDDEN TRUE)\n$(cat ${FILE_TO_PATCH})" > "${FILE_TO_PATCH}"
}

build_3_4_6() {
    clone 3.4.6
    clone 4.5.2

    # Add xcframework support to opencv 3.4.6
    #
    # Xcframework support was added in a later version of OpenCV here: https://github.com/opencv/opencv/pull/18826
    # The easier way to get an xcframework from an older version of OpenCV is to use
    # the platforms folder (which contains the necessary scripts for xcframework generation) from
    # a newer version
    rm -rf "${BUILD_DIR}/3.4.6/platforms"
    cp -rf "${BUILD_DIR}/4.5.2/platforms" "${BUILD_DIR}/3.4.6/platforms"

    build_xcframework 3.4.6 --legacy_build
    patch_xcframework_remove_symlinks
}

build_4_5_2() {
    clone 4.5.2
    build_xcframework 4.5.2
    patch_xcframework_remove_symlinks
}

build_4_6_0() {
    clone 4.6.0
    disable_ios_visibility_warnings 4.6.0

    # Fix PATH to find python
    # See: https://github.com/opencv/opencv/issues/21926#issuecomment-1156755364
    ln -s "$(which python3)" "$(pwd)/${BUILD_DIR}/python"
    export PATH="$(pwd)/${BUILD_DIR}:${PATH}"

    build_xcframework 4.6.0
    patch_xcframework_remove_symlinks
}

build_4_9_0() {
    clone 4.9.0
    disable_ios_visibility_warnings 4.9.0

    # Fix PATH to find python
    # See: https://github.com/opencv/opencv/issues/21926#issuecomment-1156755364
    ln -s "$(which python3)" "$(pwd)/${BUILD_DIR}/python"
    export PATH="$(pwd)/${BUILD_DIR}:${PATH}"

    build_xcframework_excluding_modules_4_9_0
    patch_xcframework_remove_symlinks
}

rm -rf "${BUILD_DIR}"
"$@"
