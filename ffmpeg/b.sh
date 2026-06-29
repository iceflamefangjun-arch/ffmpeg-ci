SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"
VERSION="7.1.1"
CURRENTPATH="${SCRIPT_DIR}"
FFMPEG_REPO_URL="${FFMPEG_REPO_URL:-git@code2.sohuno.com:ifox-public/FFmpeg.git}"

set_target_archs "${2:-x86}"

# Rewrite through a WSL temp file to avoid sed -i failures on /mnt/c.
rewrite_file() {
    local target="$1"
    shift
    local temp_file

    temp_file=$(mktemp) || return 1
    "$@" > "${temp_file}" || {
        rm -f "${temp_file}"
        return 1
    }
    cat "${temp_file}" > "${target}" || {
        rm -f "${temp_file}"
        return 1
    }
    rm -f "${temp_file}"
}

append_pkg_config_dir() {
    local dir="$1"

    if [ ! -d "${dir}" ]; then
        return 0
    fi

    if [ -n "${PKG_CONFIG_PATH}" ]; then
        export PKG_CONFIG_PATH="${dir}:${PKG_CONFIG_PATH}"
    else
        export PKG_CONFIG_PATH="${dir}"
    fi

    if [ -n "${PKG_CONFIG_LIBDIR}" ]; then
        export PKG_CONFIG_LIBDIR="${dir}:${PKG_CONFIG_LIBDIR}"
    else
        export PKG_CONFIG_LIBDIR="${dir}"
    fi
}

pkg_module_ready() {
    local pc_dir="$1"
    local module="$2"

    [ -d "${pc_dir}" ] || return 1
    compgen -G "${pc_dir}/*.pc" >/dev/null || return 1
    pkg-config --exists "${module}" >/dev/null 2>&1
}

OPTIMIZE="-fmerge-all-constants /Zc:sizedDealloc- /Zc:twoPhase /bigobj /utf-8"

if [ $# -lt 1 ]; then echo "Usage: $0 [debug|release|static]" >&2; exit; fi
case $1 in
  debug)
      BUILD="debug"
      OPTIMIZE="/Od /MDd /D_DEBUG ${OPTIMIZE}"
      CMAKE_BUILD_TYPE="Debug"
      is_ffmpeg_debug="enable-debug --disable-optimizations --disable-small"
      ;;
  release)
      BUILD="release"
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      CMAKE_BUILD_TYPE="Release"
      is_ffmpeg_debug="disable-debug --enable-optimizations --enable-small --enable-lto"
      ;;
  static)
      BUILD="static"
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw -flto=thin -fsplit-lto-unit"
      CMAKE_BUILD_TYPE="Release"
      is_ffmpeg_debug="disable-debug --enable-optimizations --enable-small --enable-lto"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

command -v pkg-config >/dev/null 2>&1 || {
    echo "pkg-config not found in PATH." >&2
    exit 1
}

BASE_PATH="${PATH}"
BASE_CPPFLAGS="${CPPFLAGS:-}"
BASE_LIBS="${LIBS:-}"

FFMPEG_SRC_DIR="${DEPENDSPATH}/ffmpeg"

if [ ! -e "${FFMPEG_SRC_DIR}" ] && [ -e "${DEPENDSPATH}/FFmpeg" ]; then
    mv "${DEPENDSPATH}/FFmpeg" "${FFMPEG_SRC_DIR}" || exit
fi

############################################################################################
if [ ! -e "${FFMPEG_SRC_DIR}" ]; then
    echo "Downloading ffmpeg"
    pushd ${DEPENDSPATH}
    git clone "${FFMPEG_REPO_URL}" ffmpeg
    cd "${FFMPEG_SRC_DIR}" && git checkout n${VERSION} || exit
    popd
else
    echo "Update ffmpeg"
    pushd "${FFMPEG_SRC_DIR}"
    #git checkout master && git pull
    git checkout n${VERSION} || exit
    popd
fi
############################################################################################

trap "cd \"${FFMPEG_SRC_DIR}\" && git reset --hard && rm -f libavcodec/{av3a.h,av3a_parser.c} libavformat/{application.c,application.h,av3adec.c,bluray_custom_fs.c,bluray_custom_fs.h,dns_cache.c,dns_cache.h,drm_plugin.c,ijkutils.c,libsmb2.c,lrucache.c,lrucache.h,dvd.c,bluray_util.h} libavutil/{application.h,application.c}" EXIT
pushd "${FFMPEG_SRC_DIR}"
git reset --hard && rm -f libavcodec/{av3a.h,av3a_parser.c} libavformat/{application.c,application.h,av3adec.c,bluray_custom_fs.c,bluray_custom_fs.h,dns_cache.c,dns_cache.h,drm_plugin.c,ijkutils.c,libsmb2.c,lrucache.c,lrucache.h}
sed -i '/test "\$cc_type" != "\$ld_type" && die "LTO requires same compiler and linker"/d' configure
popd

sed -i -r -e 's|^(\s*#define\s+HAVE_7REGS\s+).*|\1(ARCH_X86_64)|g' "${FFMPEG_SRC_DIR}"/libavutil/x86/asm.h
echo "Applying patch 0001-h264_ps-null-pointer-fault-toleran.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0001-h264_ps-null-pointer-fault-toleran.patch || exit
echo "Applying patch 0002-hls-support-discontinuity-tag.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0002-hls-support-discontinuity-tag.patch || exit
echo "Applying patch 0003-avformat-add-application-and-dns_cache.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0003-avformat-add-application-and-dns_cache.patch || exit
echo "Applying patch 0004-http-event-hooks.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0004-http-event-hooks.patch || exit
echo "Applying patch 0005-tcp-dns-cache.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0005-tcp-dns-cache.patch || exit
echo "Applying patch 0006-custom-protocols-and-demuxers-except-lon.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0006-custom-protocols-and-demuxers-except-lon.patch || exit
echo "Applying patch 0007-av_dict_get-that-converts-the-value-to-pointer.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0007-av_dict_get-that-converts-the-value-to-pointer.patch || exit
echo "Applying patch 0008-correct-file-seekable-value-range.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0008-correct-file-seekable-value-range.patch || exit
echo "Applying patch 0009-avformat-mpegts-index-only-keyframes-to-ensure-accur.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0009-avformat-mpegts-index-only-keyframes-to-ensure-accur.patch || exit
echo "Applying patch 0010-support-inherit-hls-opts.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0010-support-inherit-hls-opts.patch || exit
echo "Applying patch 0011-fix-can-t-seek-to-00-00-bug-baidu-neddisk-hls-start_.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0011-fix-can-t-seek-to-00-00-bug-baidu-neddisk-hls-start_.patch || exit
echo "Applying patch 0012-Correct-the-wrong-codecpar-codec_id-which-read-from-.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0012-Correct-the-wrong-codecpar-codec_id-which-read-from-.patch || exit
echo "Applying patch 0013-avformat-mov-fix-to-detect-if-stream-position-has-be.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0013-avformat-mov-fix-to-detect-if-stream-position-has-be.patch || exit
echo "Applying patch 0014-fix-http-chunked-transfer-get-wrong-size-cause-av_re.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0014-fix-http-chunked-transfer-get-wrong-size-cause-av_re.patch || exit
echo "Applying patch 0015-not-very-useful-log-use-trace-level.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0015-not-very-useful-log-use-trace-level.patch || exit
echo "Applying patch 0016-Audio-Vivid-Parser-and-Demuxer-but-av3a-Decoder-is-a.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0016-Audio-Vivid-Parser-and-Demuxer-but-av3a-Decoder-is-a.patch || exit
echo "Applying patch 0017-http-add-reconnect_first_delay-opt.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0017-http-add-reconnect_first_delay-opt.patch || exit
echo "Applying patch 0018-fix-http-open-and-http_seek-redirect-authentication-.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0018-fix-http-open-and-http_seek-redirect-authentication-.patch || exit
echo "Applying patch 0019-add-built-in-smb2-protocol-via-libsmb2.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0019-add-built-in-smb2-protocol-via-libsmb2.patch || exit
echo "Applying patch 0020-URLProtocol-add-url_parse_priv-function-pointer.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0020-URLProtocol-add-url_parse_priv-function-pointer.patch || exit
echo "Applying patch 0021-bluray-protocol-add-dvd-fallback.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0021-bluray-protocol-add-dvd-fallback.patch || exit
echo "Applying patch 0022-custom-bluray-fs-for-network-Blu-ray-Disc-and-BDMV.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0022-custom-bluray-fs-for-network-Blu-ray-Disc-and-BDMV.patch || exit
echo "Applying patch 0023-bluray-open-and-find-the-right-m2ts-then-read-seek-i.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0023-bluray-open-and-find-the-right-m2ts-then-read-seek-i.patch || exit
echo "Applying patch 0024-dash-mem-alloc-bug-fix.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0024-dash-mem-alloc-bug-fix.patch || exit
echo "Applying patch 0025-drm-plugin.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0025-drm-plugin.patch || exit
echo "Applying patch 0026-clean-avio-error-when-meet-eof-or-read-data.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0026-clean-avio-error-when-meet-eof-or-read-data.patch || exit
echo "Applying patch 0027-mov-auxiliary_info_sample_count-is-not-required.patch..."
patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/0027-mov-auxiliary_info_sample_count-is-not-required.patch || exit
#echo "Applying patch ffmpeg-configure.patch..."
#patch -d "${FFMPEG_SRC_DIR}" -p1 <${CURRENTPATH}/ffmpeg-configure.patch || exit

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/${BUILD}/${archs[i]}"
    rm -fr "${CURRENTPATH}/${OUTPUT}"

    WSLPREFIX="${CURRENTPATH}/${OUTPUT}"
    rm -rf "${WSLPREFIX}"
    mkdir -p "${WSLPREFIX}"

    rm -fr "${CURRENTPATH}/build"
    mkdir -p "${CURRENTPATH}/build"
    pushd "${CURRENTPATH}/build"

    echo "CURR DIR:" $(pwd)
    echo "Target:" ${targets[i]}

    export ARCH=${archs[i]}
    export PATH="${TOOLCHAIN}/bin:${BASE_PATH}"

    export AR="${TOOLCHAIN}/bin/llvm-ar"
    export NM="${TOOLCHAIN}/bin/llvm-nm"
    export MT="${TOOLCHAIN}/bin/llvm-mt"
    export CC="${TOOLCHAIN}/bin/clang-cl"
    export CXX="${TOOLCHAIN}/bin/clang-cl"
    export LD="${TOOLCHAIN}/bin/lld-link"
    export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    export STRIP="${TOOLCHAIN}/bin/llvm-strip"

    export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
    echo "INCLUDE:$INCLUDE"
    export LIB="${VCLIB}/${archs[i]};${WINSDKLIB}/um/${archs[i]};${WINSDKLIB}/ucrt/${archs[i]}"
    echo "LIB:$LIB"

    case ${ARCH} in
      x86)
          ffmpeg_arch="x86"
          beenet_arch="x86"
          msvc_arch_cflags="--target=i686-pc-windows-msvc -m32 -msse3"
          msvc_arch_ldflags="/machine:x86 /stack:2097152 /safeseh:no"
          ;;
      x64)
          ffmpeg_arch="x86_64"
          beenet_arch="x86_64"
          msvc_arch_cflags="--target=x86_64-pc-windows-msvc -m64 -msse3"
          msvc_arch_ldflags="/machine:x64 /stack:4194304"
          ;;
      *)
          ffmpeg_arch="${ARCH}"
          beenet_arch="${ARCH}"
          msvc_arch_cflags=
          msvc_arch_ldflags=
          ;;
    esac

    ffmpeg_bluray_protocol_flag="--disable-protocol=bluray"
    ffmpeg_drm_protocol_flag="--disable-protocol=drm"
    ffmpeg_libsmb2_protocol_flag="--disable-protocol=libsmb2"
    ffmpeg_openssl_flag="--disable-openssl"
    ffmpeg_libbluray_flag="--disable-libbluray"
    ffmpeg_libdvdnav_flag="--disable-libdvdnav"
    ffmpeg_libdvdread_flag="--disable-libdvdread"
    ffmpeg_libsmb2_flag="--disable-libsmb2"
    ffmpeg_libxml2_flag="--disable-libxml2"
    ffmpeg_zlib_flag="--disable-zlib"
    ffmpeg_x86asm_flag=
    ffmpeg_optional_cflags=
    ffmpeg_optional_cppflags=
    ffmpeg_optional_lib_path=
    ffmpeg_optional_libs=
    beenet_include_dir="${CURRENTPATH}/../BeeNet/include"
    beenet_lib_dir="${CURRENTPATH}/../BeeNet/lib/${BUILD}/${beenet_arch}"
    libbluray_pc_dir="${CURRENTPATH}/../libbluray/${OUTPUT}/lib/pkgconfig"
    libudfread_pc_dir="${CURRENTPATH}/../libudfread/${OUTPUT}/lib/pkgconfig"
    dvdread_pc_dir="${CURRENTPATH}/../libdvdread/${OUTPUT}/lib/pkgconfig"
    dvdnav_pc_dir="${CURRENTPATH}/../libdvdnav/${OUTPUT}/lib/pkgconfig"
    libsmb2_pc_dir="${CURRENTPATH}/../libsmb2/${OUTPUT}/lib/pkgconfig"
    libxml2_pc_dir="${CURRENTPATH}/../libxml2/${OUTPUT}/lib/pkgconfig"
    zlib_pc_dir="${CURRENTPATH}/../zlib/${OUTPUT}/lib/pkgconfig"
    ffnvcodec_pc_dir="${CURRENTPATH}/../ffnvcodec/nv-codec-headers/lib/pkgconfig"

    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
        ffmpeg_x86asm_flag="--disable-x86asm"
        echo "Assembler not found: disabling x86asm for this build."
    fi

    beenet_required_libs=(beenet.lib lua.lib luacjson.lib luazlib.lib datachannel.lib usrsctp.lib juice.lib curl.lib nghttp2.lib ngtcp2.lib ngtcp2_crypto_quictls.lib nghttp3.lib crypto.lib ssl.lib cares.lib zlib.lib xxtea.lib)
    ffmpeg_beenet_ready=1
    if [ ! -f "${beenet_include_dir}/beenet/interface.h" ] || [ ! -f "${beenet_include_dir}/openssl/ssl.h" ] || [ ! -d "${beenet_lib_dir}" ]; then
        ffmpeg_beenet_ready=0
    else
        for required_lib in "${beenet_required_libs[@]}"; do
            if [ ! -f "${beenet_lib_dir}/${required_lib}" ]; then
                ffmpeg_beenet_ready=0
                break
            fi
        done
    fi

    if [ ${ffmpeg_beenet_ready} -eq 1 ]; then
        ffmpeg_drm_protocol_flag="--enable-protocol=drm"
        ffmpeg_openssl_flag="--enable-openssl"
        ffmpeg_optional_cflags="-DDRM_ASYNC_STREAM"
        ffmpeg_optional_cppflags="-I${beenet_include_dir}"
        ffmpeg_optional_lib_path="${beenet_lib_dir}"
        ffmpeg_optional_libs="beenet.lib lua.lib luacjson.lib luazlib.lib datachannel.lib usrsctp.lib juice.lib"
        ffmpeg_optional_libs="${ffmpeg_optional_libs} curl.lib nghttp2.lib ngtcp2.lib ngtcp2_crypto_quictls.lib nghttp3.lib"
        ffmpeg_optional_libs="${ffmpeg_optional_libs} crypto.lib ssl.lib cares.lib zlib.lib xxtea.lib"
    else
        echo "BeeNet headers or libs missing for ${ARCH}: disabling drm/openssl extras."
    fi

    export PKG_CONFIG_PATH=
    export PKG_CONFIG_LIBDIR=
    append_pkg_config_dir "${libbluray_pc_dir}"
    append_pkg_config_dir "${libudfread_pc_dir}"
    append_pkg_config_dir "${dvdread_pc_dir}"
    append_pkg_config_dir "${dvdnav_pc_dir}"
    append_pkg_config_dir "${libsmb2_pc_dir}"
    append_pkg_config_dir "${libxml2_pc_dir}"
    append_pkg_config_dir "${zlib_pc_dir}"
    append_pkg_config_dir "${ffnvcodec_pc_dir}"

    if pkg_module_ready "${zlib_pc_dir}" "zlib"; then
        ffmpeg_zlib_flag="--enable-zlib"
    else
        echo "zlib metadata missing or incomplete for ${ARCH}: disabling zlib."
    fi

    if pkg_module_ready "${libxml2_pc_dir}" "libxml-2.0"; then
        ffmpeg_libxml2_flag="--enable-libxml2"
    else
        echo "libxml2 metadata missing or incomplete for ${ARCH}: disabling libxml2."
    fi

    if pkg_module_ready "${libbluray_pc_dir}" "libbluray"; then
        ffmpeg_bluray_protocol_flag="--enable-protocol=bluray"
        ffmpeg_libbluray_flag="--enable-libbluray"
    else
        echo "libbluray metadata missing or incomplete for ${ARCH}: disabling bluray support."
    fi

    if pkg_module_ready "${dvdread_pc_dir}" "dvdread"; then
        ffmpeg_libdvdread_flag="--enable-libdvdread"
    else
        echo "dvdread metadata missing or incomplete for ${ARCH}: disabling libdvdread."
    fi

    if pkg_module_ready "${dvdnav_pc_dir}" "dvdnav"; then
        ffmpeg_libdvdnav_flag="--enable-libdvdnav"
    else
        echo "dvdnav metadata missing or incomplete for ${ARCH}: disabling libdvdnav."
    fi

    if pkg_module_ready "${libsmb2_pc_dir}" "libsmb2"; then
        ffmpeg_libsmb2_protocol_flag="--enable-protocol=libsmb2"
        ffmpeg_libsmb2_flag="--enable-libsmb2"
    else
        echo "libsmb2 metadata missing or incomplete for ${ARCH}: disabling libsmb2 support."
    fi

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags} /nologo /subsystem:console"
    export CPPFLAGS="${BASE_CPPFLAGS}"
    export LIBS="${BASE_LIBS}"
    
 #   export LDFLAGS="${LDFLAGS} /libpath:${CURRENTPATH}/../libbluray/${OUTPUT}/lib"
 #   export LDFLAGS="${LDFLAGS} /libpath:${CURRENTPATH}/../libudfread/output/static/${archs[i]}/lib"
 #   export LDFLAGS="${LDFLAGS} /libpath:${CURRENTPATH}/../libdvdnav/${OUTPUT}/lib"
 #   export LDFLAGS="${LDFLAGS} /libpath:${CURRENTPATH}/../libdvdread/${OUTPUT}/lib"

    zlib_pc_file="${zlib_pc_dir}/zlib.pc"
    if [ -f "${zlib_pc_file}" ]; then
        rewrite_file "${zlib_pc_file}" sed \
            -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
            -e 's|^exec_prefix=.*|exec_prefix=${prefix}|' \
            -e 's|^libdir=.*|libdir=${prefix}/lib|' \
            -e 's|^sharedlibdir=.*|sharedlibdir=${prefix}/lib|' \
            -e 's|^includedir=.*|includedir=${prefix}/include|' \
            "${zlib_pc_file}" || exit
    fi

    zconf_h_file="${CURRENTPATH}/../zlib/${OUTPUT}/include/zconf.h"
    if [ -f "${zconf_h_file}" ]; then
        rewrite_file "${zconf_h_file}" sed -r -e 's|^\s*#\s*ifdef\s+(HAVE_UNISTD_H)\s|#if \1|' "${zconf_h_file}" || exit
    fi

    export CFLAGS="${CFLAGS} -I${CURRENTPATH}/../pthread-win32/${OUTPUT}/include ${ffmpeg_optional_cflags}"
    if [ "${ffmpeg_libxml2_flag}" = "--enable-libxml2" ]; then
        export CFLAGS="${CFLAGS} -DLIBXML_STATIC"
    fi

    export CPPFLAGS="${CPPFLAGS} ${ffmpeg_optional_cppflags}"
    export CPPFLAGS="${CPPFLAGS} -I${CURRENTPATH}/../pthread-win32/${OUTPUT}/include"
    export CPPFLAGS="${CPPFLAGS} -I${CURRENTPATH}/../json-c/${OUTPUT}/include/json-c"
    #export CPPFLAGS="${CPPFLAGS} -I${CURRENTPATH}/../libmp3lame/${OUTPUT}/include"
    #export CPPFLAGS="${CPPFLAGS} -I${CURRENTPATH}/../amf"
    if [ "${ffmpeg_libxml2_flag}" = "--enable-libxml2" ]; then
        export CPPFLAGS="${CPPFLAGS} -I${CURRENTPATH}/../libxml2/${OUTPUT}/include"
    fi

    #export LIB="${LIB};${CURRENTPATH}/../libmp3lame/${OUTPUT}/lib"
    if [ -n "${ffmpeg_optional_lib_path}" ]; then
        export LIB="${LIB};${ffmpeg_optional_lib_path}"
        export LDFLAGS="${LDFLAGS} /libpath:${ffmpeg_optional_lib_path}"
    fi

    export LIBS="${LIBS} ${CURRENTPATH}/../pthread-win32/${OUTPUT}/lib/pthreadVC3.lib"
    export LIBS="${LIBS} ${CURRENTPATH}/../json-c/${OUTPUT}/lib/json-c.lib"
    export LIBS="${LIBS} ${ffmpeg_optional_libs}"
    export LIBS="${LIBS} normaliz.lib crypt32.lib user32.lib advapi32.lib ws2_32.lib shell32.lib"

    "${FFMPEG_SRC_DIR}"/configure         \
        --arch=${ffmpeg_arch}               \
        --enable-cross-compile              \
        --target-os=win32                   \
        --nm="${NM}"                        \
        --ar="${AR}"                        \
        --ld="${LD}"                        \
        --strip="${STRIP}"                  \
        --cc="${CC}"                        \
        --cxx="${CXX}"                      \
        --objcc="${CC}"                     \
        --ranlib="${RANLIB}"                \
        --prefix="${WSLPREFIX}"             \
        --${is_ffmpeg_debug}                \
        --enable-pic                        \
        --enable-neon                       \
        --enable-asm                        \
        ${ffmpeg_x86asm_flag}              \
        --disable-static                    \
        --enable-shared                     \
        --enable-gpl                        \
        --enable-nonfree                    \
        --enable-runtime-cpudetect          \
        --disable-programs                  \
        --enable-ffmpeg                     \
        --disable-ffplay                    \
        --enable-ffprobe                    \
        --disable-doc                       \
        --disable-htmlpages                 \
        --disable-manpages                  \
        --disable-podpages                  \
        --disable-txtpages                  \
        --enable-avcodec                    \
        --enable-avformat                   \
        --enable-avutil                     \
        --enable-swresample                 \
        --enable-swscale                    \
        --disable-swscale-alpha             \
        --disable-gray                      \
        --enable-avdevice                   \
        --disable-postproc                  \
        --enable-avfilter                   \
        --enable-network                    \
        --enable-hwaccels                   \
        --enable-decoders                   \
        --enable-encoders                   \
        --enable-demuxers                   \
        --enable-bsfs                       \
        --enable-parsers                    \
        --enable-protocols                  \
        --enable-protocol=async             \
        --enable-protocol=rtmp*             \
        --enable-protocol=rtp               \
        --enable-protocol=srtp              \
        ${ffmpeg_bluray_protocol_flag}      \
        ${ffmpeg_drm_protocol_flag}         \
        ${ffmpeg_libsmb2_protocol_flag}     \
        --disable-protocol=concat           \
        --disable-protocol=crypto           \
        --disable-protocol=ffrtmpcrypt      \
        --disable-protocol=ffrtmphttp       \
        --disable-protocol=gopher           \
        --disable-protocol=icecast          \
        --disable-protocol=librtmp*         \
        --disable-protocol=libssh           \
        --disable-protocol=md5              \
        --disable-protocol=mmsh             \
        --disable-protocol=mmst             \
        --disable-protocol=sctp             \
        --disable-protocol=subfile          \
        --disable-protocol=unix             \
        --disable-devices                   \
        --disable-filters                   \
        --enable-filter=atempo              \
        --enable-filter=aresample           \
        --enable-filter=asetrate            \
        --enable-filter=asetpts             \
        --enable-filter=asettb              \
        --enable-filter=channelsplit        \
        --enable-filter=volume              \
        --enable-filter=scale               \
        --enable-filter=adelay              \
        --disable-vaapi                     \
        --disable-vdpau                     \
        --enable-d3d11va                    \
        --enable-dxva2                      \
        ${ffmpeg_openssl_flag}              \
        ${ffmpeg_zlib_flag}                 \
        ${ffmpeg_libbluray_flag}            \
        ${ffmpeg_libsmb2_flag}              \
        ${ffmpeg_libxml2_flag}              \
        ${ffmpeg_libdvdnav_flag}            \
        ${ffmpeg_libdvdread_flag}           \
        --disable-nvenc                     \
        --disable-cuda                      \
        --extra-libs="${LIBS}"              \
        --extra-cflags="${CFLAGS}"          \
        --extra-ldflags="${LDFLAGS}"        \
        --pkg-config-flags="--static" \
    || exit

    # Force-enable pthreads defines because configure misses them here.
    build_config_h="${CURRENTPATH}/build/config.h"
    rewrite_file "${build_config_h}" sed \
        -e 's/#define HAVE_PTHREADS 0/#define HAVE_PTHREADS 1/g' \
        -e 's/#define HAVE_PTHREAD_CANCEL 0/#define HAVE_PTHREAD_CANCEL 1/g' \
        "${build_config_h}" || exit
    build_config_mak="${CURRENTPATH}/build/ffbuild/config.mak"
    rewrite_file "${build_config_mak}" sed -e 's/^CP=.*/CP=cp/' "${build_config_mak}" || exit
    
    make V=1 -j $(nproc) install || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    for filename in 'avutil-59' 'avfilter-10' 'avcodec-61' 'avformat-61' 'avdevice-61' 'swscale-8' 'swresample-5'; do
      if [ -f ${CURRENTPATH}/build/lib${filename%-*}/${filename}.pdb ]; then
        cp -al ${CURRENTPATH}/build/lib${filename%-*}/${filename}.pdb ${CURRENTPATH}/${OUTPUT}/bin/
      fi
    done

        WINDOWS_DEPEND_DIR="${CURRENTPATH}/../../examples/windows/depend/ffmpeg/${archs[i]}/${BUILD}"
        rm -fr "${WINDOWS_DEPEND_DIR}"
        mkdir -p "${WINDOWS_DEPEND_DIR}/bin" "${WINDOWS_DEPEND_DIR}/lib" "${WINDOWS_DEPEND_DIR}/include"
        cp -af "${CURRENTPATH}/${OUTPUT}/bin/"* "${WINDOWS_DEPEND_DIR}/bin/" 2>/dev/null || true
        cp -af "${CURRENTPATH}/${OUTPUT}/lib/"* "${WINDOWS_DEPEND_DIR}/lib/" 2>/dev/null || true
        cp -af "${CURRENTPATH}/${OUTPUT}/include/"* "${WINDOWS_DEPEND_DIR}/include/" 2>/dev/null || true

        if [ "${BUILD}" = "static" ]; then
            WINDOWS_RELEASE_DIR="${CURRENTPATH}/../../examples/windows/depend/ffmpeg/${archs[i]}/Release"
            rm -fr "${WINDOWS_RELEASE_DIR}"
            mkdir -p "${WINDOWS_RELEASE_DIR}/bin" "${WINDOWS_RELEASE_DIR}/lib" "${WINDOWS_RELEASE_DIR}/include"
            cp -af "${WINDOWS_DEPEND_DIR}/bin/"* "${WINDOWS_RELEASE_DIR}/bin/" 2>/dev/null || true
            cp -af "${WINDOWS_DEPEND_DIR}/lib/"* "${WINDOWS_RELEASE_DIR}/lib/" 2>/dev/null || true
            cp -af "${WINDOWS_DEPEND_DIR}/include/"* "${WINDOWS_RELEASE_DIR}/include/" 2>/dev/null || true
        fi

    make clean

    popd
done
