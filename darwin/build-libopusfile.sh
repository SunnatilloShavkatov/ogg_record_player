#  Choose your libopusfile version. The iOS SDK version and the minimum deployment
#  target are resolved in function.sh.
VERSION="0.12"

source function.sh

########################################

cd $SRCDIR

# Exit the script if an error happens
set -e

if [ ! -e "${SRCDIR}/opusfile-${VERSION}.tar.gz" ]; then
	echo "Downloading opusfile-${VERSION}.tar.gz"
	curl -LO http://downloads.xiph.org/releases/opus/opusfile-${VERSION}.tar.gz
fi
echo "Using opusfile-${VERSION}.tar.gz"

tar zxf opusfile-${VERSION}.tar.gz -C $SRCDIR
cd "${SRCDIR}/opusfile-${VERSION}"

set +e # don't bail out of bash script if ccache doesn't exist
CCACHE=`which ccache`
if [ $? == "0" ]; then
	echo "Building with ccache: $CCACHE"
	CCACHE="${CCACHE} "
else
	echo "Building without ccache"
	CCACHE=""
fi
set -e # back to regular "bail out on error" mode

export ORIGINALPATH=$PATH

OPUS_FRAMEWORK_DIR="${OUTPUTDIR}/Frameworks/libopus.xcframework"
OGG_FRAMEWORK_DIR="${OUTPUTDIR}/Frameworks/libogg.xcframework"

OPTION_CONFIG="${OPTION_CONFIG} --disable-http --disable-examples"

build_arch_library "$OPUS_FRAMEWORK_DIR $OGG_FRAMEWORK_DIR"

########################################

echo "Build library..."

collect_build_library opusfile

####################

echo "Building done."
echo "Cleaning up..."
rm -fr ${INTERDIR}
rm -fr "${SRCDIR}/libopusfile-${VERSION}"
echo "Done."