#!/bin/bash

set -exv

if [ "$BUILD_TYPE" == meson ]; then
    _TRUE=true
    _FALSE=false
elif [ "$BUILD_TYPE" == autotools ]; then
    _TRUE=yes
    _FALSE=no
fi

WITH_MORE_WARNINGS="error"
WITH_LIBTEAM="$_TRUE"
if [ "$CI" == travis ]; then
    WITH_MORE_WARNINGS="no"
    WITH_LIBTEAM="$_FALSE"
elif [ "$CI" == gitlab ]; then
    :
fi

if [ "$CRYPTO" == "" ]; then
    if [ "$CC" == gcc ]; then
        CRYPTO=nss
    else
        CRYPTO=gnutls
    fi
fi

###############################################################################

die() {
    printf "%s\n" "$@"
    exit 1
}

###############################################################################

run_meson() {
    meson build \
        \
        -D ld_gc=false \
        -D session_tracking=no \
        -D systemdsystemunitdir=no \
        -D systemd_journal=false \
        -D selinux=false \
        -D libaudit=no \
        -D libpsl=false \
        -D vapi=false \
        -D introspection=true \
        -D qt=false \
        -D crypto=$CRYPTO \
        -D docs=true \
        \
        -D libnm_glib=true \
        -D iwd=true \
        -D ofono=true \
        -D teamdctl=$WITH_LIBTEAM \
        \
        -D dhclient=/bin/nowhere/dhclient \
        -D dhcpcanon=/bin/nowhere/dhcpcanon \
        -D dhcpcd=/bin/nowhere/dhcpd \
        \
        -D netconfig=/bin/nowhere/netconfig \
        -D resolvconf=/bin/nowhere/resolvconf \
        \
        -D ifcfg_rh=false \
        -D ibft=true \
        -D ifupdown=true \
        \
        #end

    ninja -C build
    ninja -C build test
}

###############################################################################

_autotools_test_print_logs() {
    echo ">>>> PRINT TEST LOGS $1 (start)"
    cat test-suite.log
    echo ">>>> PRINT TEST LOGS $1 (done)"
}

run_autotools() {
    NOCONFIGURE=1 ./autogen.sh
    mkdir ./build
    pushd ./build
        ../configure \
            --prefix="$PWD/INST" \
            --enable-gtk-doc=yes \
            --with-systemd-logind=no \
            --enable-more-warnings=$WITH_MORE_WARNINGS \
            --enable-tests=yes \
            --with-crypto=$CRYPTO \
            \
            --with-libnm-glib=yes \
            --with-iwd=yes \
            --with-ofono=yes \
            --enable-teamdctl=$WITH_LIBTEAM \
            \
            --with-dhcpcanon=yes \
            --with-dhcpcd=yes \
            --with-dhclient=yes \
            \
            --with-netconfig=/bin/nowhere/netconfig \
            --with-resolvconf=/bin/nowhere/resolvconf \
            \
            --enable-ifcfg-rh=yes \
            --enable-config-plugin-ibft=yes \
            --enable-ifupdown=yes \
            \
            #end

        make -j 6
        make install

        export NM_TEST_CLIENT_CHECK_L10N=1

        if [ "$CI" == travis ]; then
            # travis is known to generate the settings doc differently.
            # Don't compare.
            export NMTST_NO_CHECK_SETTINGS_DOCS=yes
        fi

        if ! make check -j 6 -k ; then

            _autotools_test_print_logs "first-test"

            echo ">>>> RUN SECOND TEST (start)"
            NMTST_DEBUG=TRACE,no-expect-message make check -k || :
            echo ">>>> RUN SECOND TEST (done)"

            _autotools_test_print_logs "second-test"
            die "test failed"
        fi
    popd
}

if [ "$BUILD_TYPE" == autotools ]; then
    run_autotools
elif [ "$BUILD_TYPE" == meson ]; then
    run_meson
else
    die "UNKNOWN \$BUILD_TYPE \"$BUILD_TYPE\""
fi
