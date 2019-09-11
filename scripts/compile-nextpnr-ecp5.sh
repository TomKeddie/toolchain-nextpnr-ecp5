#!/bin/bash
# -- Compile nextpnr-ice40 script

nextpnr_dir=nextpnr
nextpnr_uri=https://github.com/xobs/nextpnr
nextpnr_commit=0d0056a043510d70a39faa84ec0a0db8684c480b
prjtrellis_dir=prjtrellis
prjtrellis_uri=https://github.com/SymbiFlow/prjtrellis.git
prjtrellis_commit=40129f3fe8cd9c09b8a19df480f18cde1042e6a0

# -- Setup
. $WORK_DIR/scripts/build_setup.sh

cd $UPSTREAM_DIR

# -- Clone the sources from github
test -e $nextpnr_dir || git clone $nextpnr_uri $nextpnr_dir
git -C $nextpnr_dir fetch
git -C $nextpnr_dir checkout $nextpnr_commit
git -C $nextpnr_dir log -1

test -e $prjtrellis_dir || git clone $prjtrellis_uri $prjtrellis_dir
git -C $prjtrellis_dir fetch
git -C $prjtrellis_dir checkout $prjtrellis_commit
git -C $prjtrellis_dir submodule init
git -C $prjtrellis_dir submodule update
git -C $prjtrellis_dir log -1

# -- Copy the upstream sources into the build directory
mkdir -p $BUILD_DIR/$nextpnr_dir
mkdir -p $BUILD_DIR/$prjtrellis_dir
rsync -a $nextpnr_dir $BUILD_DIR --exclude .git
rsync -a $prjtrellis_dir $BUILD_DIR --exclude .git

cd $BUILD_DIR/

if [ -e $nextpnr_dir/CMakeCache.txt -o -e $prjtrellis_dir/CMakeCache.txt ]
then
    echo "CMakeCache.txt exists!"
fi
rm -f $nextpnr_dir/CMakeCache.txt $prjtrellis_dir/CMakeCache.txt

# -- Compile it
if [ $ARCH = "darwin" ]
then
    cd $BUILD_DIR/$prjtrellis_dir/libtrellis
    cmake \
        -DBUILD_SHARED=OFF \
        -DSTATIC_BUILD=ON \
        -DBUILD_PYTHON=OFF \
        -DBoost_USE_STATIC_LIBS=ON \
        .
    make -j$J CXX="$CXX" LIBS="-lm -fno-lto -ldl -lutil"

    cd $BUILD_DIR/$nextpnr_dir
    cmake -DARCH=ecp5 \
        -DEXTERNAL_CHIPDB=$WORK_DIR/ecp5 \
        -DTRELLIS_ROOT=$WORK_DIR/$prjtrellis_dir \
        -DPYTRELLIS_LIBDIR=$WORK_DIR/$prjtrellis_dir/libtrellis \
        -DBOOST_ROOT=/tmp/nextpnr \
        -DBoost_USE_STATIC_LIBS=ON \
        -DPYTHON_EXECUTABLE=/tmp/nextpnr/bin/python \
        -DPYTHON_LIBRARY=/tmp/nextpnr/lib/libpython3.7m.a \
        -DEigen3_DIR=/tmp/nextpnr/share/eigen3/cmake \
        -DBUILD_GUI=OFF \
        -DBUILD_PYTHON=ON \
        -DBUILD_HEAP=ON \
        -DCMAKE_EXE_LINKER_FLAGS='-fno-lto -ldl -lutil' \
        -DICEBOX_ROOT="$WORK_DIR/icebox" \
        -DSTATIC_BUILD=ON \
        .
    make -j$J CXX="$CXX" LIBS="-lm -fno-lto -ldl -lutil"
elif [ ${ARCH:0:7} = "windows" ]
then
    echo "Build not functioning on Windows"
    exit 1
else
    cd $BUILD_DIR/$prjtrellis_dir/libtrellis
    cmake \
        -DBUILD_SHARED=OFF \
        -DSTATIC_BUILD=ON \
        -DBUILD_PYTHON=OFF \
        -DBoost_USE_STATIC_LIBS=ON \
        -DCMAKE_FIND_LIBRARY_SUFFIXES=".a" \
        .
    make -j$J CXX="$CXX"

    cd $BUILD_DIR/$nextpnr_dir
    cmake \
        -DARCH=ecp5 \
        -DEXTERNAL_CHIPDB=$WORK_DIR/ecp5 \
        -DTRELLIS_ROOT=$WORK_DIR/$prjtrellis_dir \
        -DPYTRELLIS_LIBDIR=$WORK_DIR/$prjtrellis_dir/libtrellis \
        -DBUILD_HEAP=ON \
        -DBUILD_GUI=OFF \
        -DBUILD_PYTHON=ON \
        -DSTATIC_BUILD=ON \
        -DBoost_USE_STATIC_LIBS=ON \
        .
    make -j$J CXX="$CXX"

    # Install a copy of Python, since Python libraries are not compatible
    # across minor versions.
    mkdir libpython3
    cd libpython3
    for pkg in $(ls -1 ${WORK_DIR}/build-data/linux/*.deb)
    do
        echo "Extracting $pkg..."
        ar p $pkg data.tar.xz | tar xvJ
    done
    mkdir -p $PACKAGE_DIR/$NAME
    mv usr/* $PACKAGE_DIR/$NAME
    cd ..
fi || exit 1

# -- Copy the executables to the bin dir
mkdir -p $PACKAGE_DIR/$NAME/bin
cp $WORK_DIR/$nextpnr_dir/nextpnr-ecp5$EXE $PACKAGE_DIR/$NAME/bin/nextpnr-ecp5$EXE
for i in ecpmulti ecppack ecppll ecpunpack
do
    cp $WORK_DIR/$prjtrellis_dir/libtrellis/$i$EXE $PACKAGE_DIR/$NAME/bin/$i$EXE
done

# Do a test run of the new binary
# $PACKAGE_DIR/$NAME/bin/nextpnr-ice40$EXE --up5k --package sg48 --pcf $WORK_DIR/build-data/test/top.pcf --json $WORK_DIR/build-data/test/top.json --asc /tmp/nextpnr/top.txt --pre-pack $WORK_DIR/build-data/test/top_pre_pack.py --seed 0 --placer heap
