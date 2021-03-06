#!/bin/bash
#
# Build the snapweb snaps.
#
# Arguments:
#   [arch ...]: The architectures to build for. By default it will build for
#               amd64, arm64, armhf and i386.
#
#   [--ups]:    Build the ubuntu-personal-store snap as well.

set -e

if [ "$#" -eq 0 ] || ([ "$#" -eq 1 ] && [ "$1" = "--ups" ]); then
    architectures=( amd64 arm64 armhf i386 )
else
    architectures=( "$@" )
fi

AVAHI_VERSION="0.6.31-4ubuntu4snap2"
LIBDAEMON0_VERSION="0.14-6"

get_platform_abi() {
    arch=$1

    case $arch in
        amd64|386)
            plat_abi=x86_64-linux-gnu
        ;;
        arm)
            plat_abi=arm-linux-gnueabihf
        ;;
        armhf)
            plat_abi=arm-linux-gnueabihf
        ;;
        arm64)
            plat_abi=aarch64-linux-gnu
        ;;
        *)
            echo "unknown platform for snappy-magic: $arch remember to file a bug or better yet: fix it :)"
            exit 1
        ;;
    esac

    echo $plat_abi
}

gobuild() {
    arch=$1
    build_mode=$2

    plat_abi=$(get_platform_abi $arch)

    if [ $arch = "386" ]; then
        output_dir="bin/i686-linux-gnu"
    else
        output_dir="bin/$plat_abi"
    fi

    build_tags=""
    if [ "${build_mode}" = "ubuntu_personal_store" ]; then
        build_tags="-tags ubuntu_personal_store"
    fi

    mkdir -p $output_dir
    cd $output_dir
    GOARCH=$arch GOARM=7 CGO_ENABLED=1 CC=${plat_abi}-gcc go build ${build_tags} github.com/snapcore/snapweb/cmd/snapweb
    GOARCH=$arch GOARM=7 CGO_ENABLED=1 CC=${plat_abi}-gcc go build -o generate-token -ldflags "-extld=${plat_abi}-gcc" $srcdir/cmd/generate-token/main.go
    cp generate-token ../../
    cd - > /dev/null
}

echo "Building web assets with gulp..."
npm run build

orig_pwd="$(pwd)"

top_builddir="$(mktemp -d)"
trap 'rm -rf "$top_builddir"' EXIT

echo Obtaining go dependencies
go get launchpad.net/godeps
godeps -u dependencies.tsv

# build one snap per arch
for ARCH in "${architectures[@]}"; do
    if [ $ARCH = "--ups" ]; then
        continue
    fi

    echo "Building for ${ARCH}..."
    builddir="${top_builddir}/${ARCH}"
    mkdir -p "$builddir"

    srcdir=`pwd`
    cp -r pkg/. booth-demo-manager.def ${builddir}/
    mkdir $builddir/www
    cp -r www/public www/templates $builddir/www
    cd $builddir

    sed -i "s/\(architectures: \)UNKNOWN_ARCH/\1[$ARCH]/" \
        $builddir/meta/snap.yaml

    # *sigh* armhf in snappy is the go arm arch
    if [ $ARCH = armhf ]; then
        BUILD_ARCH="arm"
    # and 386 vs i386
    elif [ $ARCH = i386 ]; then
        BUILD_ARCH="386"
    else
        BUILD_ARCH=$ARCH
    fi

    gobuild $BUILD_ARCH

    cd "$orig_pwd"
    snapcraft snap $builddir

    # TODO: We only support amd64 ups builds for now -Need a cross-compile fix for "after: [desktop-qt5]"
    if [[ $* == *--ups* ]] && [ $ARCH = amd64 ]; then
        # now build ubuntu-personal-store
        cd $builddir
        gobuild $BUILD_ARCH "ubuntu_personal_store"

        cd $orig_pwd/ubuntu-personal-store

        cp snapcraft.yaml.in snapcraft.yaml
        sed -i "s/\(:\)UNKNOWN_ARCH/\1$ARCH/" snapcraft.yaml

        snapcraft clean
        snapcraft prime

        cp -r $orig_pwd/ubuntu-personal-store/prime/* $builddir
        cp -r $orig_pwd/ubuntu-personal-store/pkg/* ${builddir}
        sed -i "s/\(architectures: \)UNKNOWN_ARCH/\1[$ARCH]/" \
            $builddir/meta/snap.yaml

        cd $orig_pwd
        snapcraft snap $builddir
    fi
done
