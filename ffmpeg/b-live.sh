SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "${SCRIPT_DIR}" || exit 1
source "${SCRIPT_DIR}/../env_config.sh"
VERSION="7.1.1"
CURRENTPATH="${SCRIPT_DIR}"
FFMPEG_REPO_URL="${FFMPEG_REPO_URL:-git@code2.sohuno.com:ifox-public/FFmpeg.git}"

set_target_archs "${2:-x64}"

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

resolve_dep_output_dir() {
    local dep_name="$1"
    local build_name="$2"
    local arch_name="$3"
    local live_dir="${CURRENTPATH}/../${dep_name}/output/live/${build_name}/${arch_name}"
    local default_dir="${CURRENTPATH}/../${dep_name}/output/${build_name}/${arch_name}"

    if [ -d "${live_dir}" ]; then
        printf '%s' "${live_dir}"
        return 0
    fi

    if [ -d "${default_dir}" ]; then
        printf '%s' "${default_dir}"
        return 0
    fi

    return 1
}

pkg_module_ready() {
    local pc_dir="$1"
    shift
    local pkg_query="$*"

    [ -d "${pc_dir}" ] || return 1
    compgen -G "${pc_dir}/*.pc" >/dev/null || return 1
    [ -n "${pkg_query}" ] || return 1
    pkg-config --exists ${pkg_query} >/dev/null 2>&1
}

pkg_module_header_ready() {
    local module="$1"
    local header="$2"
    local cflags flag include_dir

    cflags="$(pkg-config --cflags "${module}" 2>/dev/null)" || return 1
    for flag in ${cflags}; do
        case "${flag}" in
          -I*)
              include_dir="${flag#-I}"
              [ -f "${include_dir}/${header}" ] && return 0
              ;;
        esac
    done

    return 1
}

build_enable_flags() {
    local kind="$1"
    shift
    local flags=
    local item

    for item in "$@"; do
        flags="${flags} --enable-${kind}=${item}"
    done

    printf '%s' "${flags}"
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
      # Keep LTO disabled on GitHub Actions for the same stability reasons as
      # the player build: clang-cl/lld-link can hit NASM symbol and disk issues.
      OPTIMIZE="/O2 /MD /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw"
      CMAKE_BUILD_TYPE="Release"
      is_ffmpeg_debug="disable-debug --enable-optimizations --enable-small"
      ;;
  static)
      BUILD="static"
      # Same as release: keep LTO disabled for CI stability.
      OPTIMIZE="/O2 /MT /DNDEBUG ${OPTIMIZE} /GF /Gy /Gw"
      CMAKE_BUILD_TYPE="Release"
      is_ffmpeg_debug="disable-debug --enable-optimizations --enable-small"
      ;;
  *)
      echo "Only support [debug|release|static]" >&2; exit
      ;;
esac

command -v pkg-config >/dev/null 2>&1 || {
    echo "pkg-config not found in PATH." >&2
    exit 1
}

FFMPEG_PATCHES=(
    0001-h264_ps-null-pointer-fault-toleran.patch
    0002-hls-support-discontinuity-tag.patch
    0003-avformat-add-application-and-dns_cache.patch
    0004-http-event-hooks.patch
    0005-tcp-dns-cache.patch
    0006-custom-protocols-and-demuxers-except-lon.patch
    0007-av_dict_get-that-converts-the-value-to-pointer.patch
    0008-correct-file-seekable-value-range.patch
    0009-avformat-mpegts-index-only-keyframes-to-ensure-accur.patch
    0010-support-inherit-hls-opts.patch
    0011-fix-can-t-seek-to-00-00-bug-baidu-neddisk-hls-start_.patch
    0012-Correct-the-wrong-codecpar-codec_id-which-read-from-.patch
    0013-avformat-mov-fix-to-detect-if-stream-position-has-be.patch
    0014-fix-http-chunked-transfer-get-wrong-size-cause-av_re.patch
    0015-not-very-useful-log-use-trace-level.patch
    0016-Audio-Vivid-Parser-and-Demuxer-but-av3a-Decoder-is-a.patch
    0017-http-add-reconnect_first_delay-opt.patch
    0018-fix-http-open-and-http_seek-redirect-authentication-.patch
    0019-add-built-in-smb2-protocol-via-libsmb2.patch
    0020-URLProtocol-add-url_parse_priv-function-pointer.patch
# Live builds intentionally skip the Blu-ray and DRM patches used by the player build.
#    0021-bluray-protocol-add-dvd-fallback.patch
#    0022-custom-bluray-fs-for-network-Blu-ray-Disc-and-BDMV.patch
#    0023-bluray-open-and-find-the-right-m2ts-then-read-seek-i.patch
    0024-dash-mem-alloc-bug-fix.patch
#    0025-drm-plugin.patch
    0026-clean-avio-error-when-meet-eof-or-read-data.patch
    0027-mov-auxiliary_info_sample_count-is-not-required.patch
)

LIVE_DECODERS=(aac aac_latm ac3 av1 eac3 flac h264 hevc mjpeg mp2 mp2float mp3 mp3float mpeg2video opus pcm_alaw pcm_mulaw pcm_s16le vorbis vp8 vp9)
LIVE_AUDIO_ENCODERS=(aac pcm_alaw pcm_mulaw pcm_s16le)
LIVE_DEMUXERS=(aac ac3 dash eac3 flv hls live_flv matroska mov mpegts mp3 ogg rtsp sdp)
LIVE_MUXERS=(adts flv hls matroska mp4 mpegts null rtsp sdp segment tee)
LIVE_PARSERS=(aac aac_latm ac3 av1 h264 hevc mjpeg mpegaudio opus vorbis vp8 vp9)
LIVE_BSFS=(aac_adtstoasc extract_extradata h264_mp4toannexb hevc_mp4toannexb vp9_superframe)
LIVE_FILTERS=(aformat aresample asetpts format fps scale setpts volume)
LIVE_PROTOCOLS=(async crypto file http pipe rtmp rtmpe rtmps rtmpt rtmpte rtmpts rtp srtp tcp udp)

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
for patch_file in "${FFMPEG_PATCHES[@]}"; do
    echo "Applying patch ${patch_file}..."
    patch -d "${FFMPEG_SRC_DIR}" -p1 <"${CURRENTPATH}/${patch_file}" || exit
done

############################################################################################
for ((i=0; i<${#archs[@]}; i++))
do
    OUTPUT="output/live/${BUILD}/${archs[i]}"
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
    export PATH="${DEPENDSPATH}/bin:${TOOLCHAIN}/bin:${BASE_PATH}"

    export AR="${LLVM_AR_TOOL}"
    export NM="${LLVM_NM_TOOL}"
    export MT="${LLVM_MT_TOOL}"
    export CC="${CLANG_CL_TOOL}"
    export CXX="${CLANG_CL_TOOL}"
    export LD="${LLD_LINK_TOOL}"
    export RANLIB="${LLVM_RANLIB_TOOL}"
    export STRIP="${LLVM_STRIP_TOOL}"

    set_msvc_arch_env "${archs[i]}"
    echo "INCLUDE:$INCLUDE"
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
    ffmpeg_windres_tool="$(windres_for_arch "${archs[i]}")"
    echo "windres: ${ffmpeg_windres_tool}"

    ffmpeg_x86asm_flag=
    ffmpeg_live_openssl_flag="--disable-openssl"
    ffmpeg_live_zlib_flag="--disable-zlib"
    ffmpeg_live_libx264_flag="--disable-libx264"
    ffmpeg_live_libfdk_aac_flag="--disable-libfdk-aac"
    ffmpeg_live_libmfx_flag="--disable-libmfx"
    ffmpeg_live_nvenc_flag="--disable-nvenc"
    ffmpeg_live_mediafoundation_flag="--enable-mediafoundation"
    ffmpeg_live_optional_cppflags=
    ffmpeg_live_optional_lib_path=
    ffmpeg_live_optional_libs=
    ffmpeg_live_video_encoder_ready=0
    ffmpeg_live_decoder_flags=$(build_enable_flags decoder "${LIVE_DECODERS[@]}")
    ffmpeg_live_encoder_flags=$(build_enable_flags encoder "${LIVE_AUDIO_ENCODERS[@]}")
    ffmpeg_live_demuxer_flags=$(build_enable_flags demuxer "${LIVE_DEMUXERS[@]}")
    ffmpeg_live_muxer_flags=$(build_enable_flags muxer "${LIVE_MUXERS[@]}")
    ffmpeg_live_parser_flags=$(build_enable_flags parser "${LIVE_PARSERS[@]}")
    ffmpeg_live_bsf_flags=$(build_enable_flags bsf "${LIVE_BSFS[@]}")
    ffmpeg_live_filter_flags=$(build_enable_flags filter "${LIVE_FILTERS[@]}")
    ffmpeg_live_protocol_flags=$(build_enable_flags protocol "${LIVE_PROTOCOLS[@]}")
    beenet_include_dir="${CURRENTPATH}/../BeeNet/include"
    beenet_lib_dir="${CURRENTPATH}/../BeeNet/lib/${BUILD}/${beenet_arch}"
    pthread_dep_root=$(resolve_dep_output_dir "pthread-win32" "${BUILD}" "${ARCH}") || {
        echo "Missing pthread-win32 output for ${ARCH} (${BUILD}). Build it first." >&2
        exit 1
    }
    jsonc_dep_root=$(resolve_dep_output_dir "json-c" "${BUILD}" "${ARCH}") || {
        echo "Missing json-c output for ${ARCH} (${BUILD}). Build it first." >&2
        exit 1
    }
    zlib_dep_root=$(resolve_dep_output_dir "zlib" "${BUILD}" "${ARCH}" 2>/dev/null || true)
    x264_dep_root=$(resolve_dep_output_dir "x264" "${BUILD}" "${ARCH}" 2>/dev/null || true)
    fdk_aac_dep_root=$(resolve_dep_output_dir "fdk-aac" "${BUILD}" "${ARCH}" 2>/dev/null || true)
    libmfx_dep_root=$(resolve_dep_output_dir "libmfx" "${BUILD}" "${ARCH}" 2>/dev/null || true)

    pthread_include_dir="${pthread_dep_root}/include"
    pthread_lib_file="${pthread_dep_root}/lib/pthreadVC3.lib"
    jsonc_include_dir="${jsonc_dep_root}/include/json-c"
    jsonc_lib_file="${jsonc_dep_root}/lib/json-c.lib"
    zlib_pc_dir=
    x264_pc_dir=
    fdk_aac_pc_dir=
    libmfx_pc_dir=
    if [ -n "${zlib_dep_root}" ]; then
        zlib_pc_dir="${zlib_dep_root}/lib/pkgconfig"
    fi
    if [ -n "${x264_dep_root}" ]; then
        x264_pc_dir="${x264_dep_root}/lib/pkgconfig"
    fi
    if [ -n "${fdk_aac_dep_root}" ]; then
        fdk_aac_pc_dir="${fdk_aac_dep_root}/lib/pkgconfig"
    fi
    if [ -n "${libmfx_dep_root}" ]; then
        libmfx_pc_dir="${libmfx_dep_root}/lib/pkgconfig"
    fi
    ffnvcodec_pc_dir="${CURRENTPATH}/../ffnvcodec/nv-codec-headers/lib/pkgconfig"

    if [ ! -d "${pthread_include_dir}" ] || [ ! -f "${pthread_lib_file}" ]; then
        echo "pthread-win32 include or library missing for ${ARCH}." >&2
        exit 1
    fi

    if [ ! -d "${jsonc_include_dir}" ] || [ ! -f "${jsonc_lib_file}" ]; then
        echo "json-c include or library missing for ${ARCH}." >&2
        exit 1
    fi

    if ! command -v nasm >/dev/null 2>&1 && ! command -v yasm >/dev/null 2>&1; then
        ffmpeg_x86asm_flag="--disable-x86asm"
        echo "Assembler not found: disabling x86asm for this build."
    fi

    openssl_required_libs=(crypto.lib ssl.lib zlib.lib)
    ffmpeg_live_openssl_ready=1
    if [ ! -f "${beenet_include_dir}/openssl/ssl.h" ] || [ ! -d "${beenet_lib_dir}" ]; then
        ffmpeg_live_openssl_ready=0
    else
        for required_lib in "${openssl_required_libs[@]}"; do
            if [ ! -f "${beenet_lib_dir}/${required_lib}" ]; then
                ffmpeg_live_openssl_ready=0
                break
            fi
        done
    fi

    if [ ${ffmpeg_live_openssl_ready} -eq 1 ]; then
        ffmpeg_live_openssl_flag="--enable-openssl"
        ffmpeg_live_protocol_flags="${ffmpeg_live_protocol_flags} --enable-protocol=https --enable-protocol=tls"
        ffmpeg_live_optional_cppflags="-I${beenet_include_dir}"
        ffmpeg_live_optional_lib_path="${beenet_lib_dir}"
        ffmpeg_live_optional_libs="crypto.lib ssl.lib zlib.lib"
    else
        echo "OpenSSL headers or libs missing for ${ARCH}: disabling https/tls support."
    fi

    export PKG_CONFIG_PATH=
    export PKG_CONFIG_LIBDIR=
    append_pkg_config_dir "${x264_pc_dir}"
    append_pkg_config_dir "${fdk_aac_pc_dir}"
    append_pkg_config_dir "${libmfx_pc_dir}"
    append_pkg_config_dir "${zlib_pc_dir}"
    append_pkg_config_dir "${ffnvcodec_pc_dir}"

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

    zconf_h_file="${zlib_dep_root}/include/zconf.h"
    if [ -f "${zconf_h_file}" ]; then
        rewrite_file "${zconf_h_file}" sed -r -e 's|^\s*#\s*ifdef\s+(HAVE_UNISTD_H)\s|#if \1 |' "${zconf_h_file}" || exit
    fi

    if pkg_module_ready "${zlib_pc_dir}" "zlib"; then
        ffmpeg_live_zlib_flag="--enable-zlib"
    else
        echo "zlib metadata missing or incomplete for ${ARCH}: disabling zlib."
    fi

    if pkg_module_ready "${x264_pc_dir}" "x264"; then
        ffmpeg_live_libx264_flag="--enable-libx264"
        ffmpeg_live_encoder_flags="${ffmpeg_live_encoder_flags} --enable-encoder=libx264"
        ffmpeg_live_video_encoder_ready=1
    else
        echo "x264 metadata missing or incomplete for ${ARCH}: disabling libx264."
    fi

    if pkg_module_ready "${fdk_aac_pc_dir}" "fdk-aac"; then
        ffmpeg_live_libfdk_aac_flag="--enable-libfdk-aac"
        ffmpeg_live_encoder_flags="${ffmpeg_live_encoder_flags} --enable-encoder=libfdk_aac"
    else
        echo "fdk-aac metadata missing or incomplete for ${ARCH}: using native AAC encoder only."
    fi

    if pkg_module_ready "${libmfx_pc_dir}" "libmfx >= 1.28 libmfx < 2.0"; then
        ffmpeg_live_libmfx_flag="--enable-libmfx"
        ffmpeg_live_encoder_flags="${ffmpeg_live_encoder_flags} --enable-encoder=h264_qsv --enable-encoder=hevc_qsv"
        ffmpeg_live_video_encoder_ready=1
    else
        echo "libmfx metadata missing/incompatible (<1.28 or >=2.0) for ${ARCH}: disabling QSV encoders."
    fi

    if pkg_module_ready "${ffnvcodec_pc_dir}" "ffnvcodec >= 12.1.14.0" && pkg_module_header_ready "ffnvcodec" "ffnvcodec/nvEncodeAPI.h"; then
        ffmpeg_live_nvenc_flag="--enable-nvenc"
        ffmpeg_live_encoder_flags="${ffmpeg_live_encoder_flags} --enable-encoder=h264_nvenc --enable-encoder=hevc_nvenc"
        ffmpeg_live_video_encoder_ready=1
    else
        echo "ffnvcodec metadata or headers missing/incompatible for ${ARCH}: disabling NVENC encoders."
    fi

    # Media Foundation encoders are always available on Windows target
    ffmpeg_live_encoder_flags="${ffmpeg_live_encoder_flags} --enable-encoder=h264_mf --enable-encoder=hevc_mf --enable-encoder=aac_mf"
    ffmpeg_live_video_encoder_ready=1

    if [ ${ffmpeg_live_video_encoder_ready} -eq 0 ]; then
        echo "No external H.264/H.265 encoder detected for ${ARCH}: this build keeps playback and audio encoding only."
    fi

    export CFLAGS="${OPTIMIZE} ${msvc_arch_cflags} -fuse-ld=lld -fms-compatibility -I${pthread_include_dir}"
    export CXXFLAGS="${CFLAGS} ${CXX_OPTIMIZE} /EHsc -std:c++11"
    export LDFLAGS="${msvc_arch_ldflags} /nologo /subsystem:console"
    export CPPFLAGS="${BASE_CPPFLAGS}"
    export LIBS="${BASE_LIBS}"

    export CPPFLAGS="${CPPFLAGS} ${ffmpeg_live_optional_cppflags}"
    export CPPFLAGS="${CPPFLAGS} -I${pthread_include_dir}"
    export CPPFLAGS="${CPPFLAGS} -I${jsonc_include_dir}"

    if [ -n "${ffmpeg_live_optional_lib_path}" ]; then
        append_msvc_lib_path "${ffmpeg_live_optional_lib_path}"
        export LDFLAGS="${LDFLAGS} $(msvc_libpath_flag "${ffmpeg_live_optional_lib_path}")"
    fi

    export LIBS="${LIBS} ${pthread_lib_file}"
    export LIBS="${LIBS} ${jsonc_lib_file}"
    export LIBS="${LIBS} ${ffmpeg_live_optional_libs}"
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
        --windres="${ffmpeg_windres_tool}"  \
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
        --disable-avdevice                  \
        --disable-postproc                  \
        --enable-avfilter                   \
        --enable-network                    \
        --enable-hwaccels                   \
        --disable-decoders                  \
        ${ffmpeg_live_decoder_flags}        \
        --disable-encoders                  \
        ${ffmpeg_live_encoder_flags}        \
        --disable-demuxers                  \
        ${ffmpeg_live_demuxer_flags}        \
        --disable-muxers                    \
        ${ffmpeg_live_muxer_flags}          \
        --disable-bsfs                      \
        ${ffmpeg_live_bsf_flags}            \
        --disable-parsers                   \
        ${ffmpeg_live_parser_flags}         \
        --disable-protocols                 \
        ${ffmpeg_live_protocol_flags}       \
        --disable-devices                   \
        --disable-filters                   \
        ${ffmpeg_live_filter_flags}         \
        --disable-vaapi                     \
        --disable-vdpau                     \
        --enable-d3d11va                    \
        --enable-dxva2                      \
        ${ffmpeg_live_mediafoundation_flag} \
        ${ffmpeg_live_zlib_flag}            \
        ${ffmpeg_live_openssl_flag}         \
        ${ffmpeg_live_libx264_flag}         \
        ${ffmpeg_live_libfdk_aac_flag}      \
        ${ffmpeg_live_libmfx_flag}          \
        ${ffmpeg_live_nvenc_flag}           \
        --extra-libs="${LIBS}"              \
        --extra-cflags="${CFLAGS}"          \
        --extra-ldflags="${LDFLAGS}"        \
        --pkg-config-flags="--static" \
    || exit

    build_config_h="${CURRENTPATH}/build/config.h"
    rewrite_file "${build_config_h}" sed \
        -e 's/#define HAVE_PTHREADS 0/#define HAVE_PTHREADS 1/g' \
        -e 's/#define HAVE_PTHREAD_CANCEL 0/#define HAVE_PTHREAD_CANCEL 1/g' \
        "${build_config_h}" || exit
    build_config_mak="${CURRENTPATH}/build/ffbuild/config.mak"
    rewrite_file "${build_config_mak}" sed -e 's/^CP=.*/CP=cp/' "${build_config_mak}" || exit
    grep -E '^(ARCH|CC|LD|WINDRES)=' "${build_config_mak}" || true

    make V=1 -j $(nproc) install || exit
    mkdir -p "${CURRENTPATH}/${OUTPUT}"

    for filename in 'avutil-59' 'avfilter-10' 'avcodec-61' 'avformat-61' 'swscale-8' 'swresample-5'; do
      if [ -f ${CURRENTPATH}/build/lib${filename%-*}/${filename}.pdb ]; then
        cp -al ${CURRENTPATH}/build/lib${filename%-*}/${filename}.pdb ${CURRENTPATH}/${OUTPUT}/bin/
      fi
    done

    WINDOWS_DEPEND_DIR="${CURRENTPATH}/../../examples/windows/depend/ffmpeg-live/${archs[i]}/${BUILD}"
    rm -fr "${WINDOWS_DEPEND_DIR}"
    mkdir -p "${WINDOWS_DEPEND_DIR}/bin" "${WINDOWS_DEPEND_DIR}/lib" "${WINDOWS_DEPEND_DIR}/include"
    cp -af "${CURRENTPATH}/${OUTPUT}/bin/"* "${WINDOWS_DEPEND_DIR}/bin/" 2>/dev/null || true
    cp -af "${CURRENTPATH}/${OUTPUT}/lib/"* "${WINDOWS_DEPEND_DIR}/lib/" 2>/dev/null || true
    cp -af "${CURRENTPATH}/${OUTPUT}/include/"* "${WINDOWS_DEPEND_DIR}/include/" 2>/dev/null || true

    if [ "${BUILD}" = "static" ]; then
        WINDOWS_RELEASE_DIR="${CURRENTPATH}/../../examples/windows/depend/ffmpeg-live/${archs[i]}/Release"
        rm -fr "${WINDOWS_RELEASE_DIR}"
        mkdir -p "${WINDOWS_RELEASE_DIR}/bin" "${WINDOWS_RELEASE_DIR}/lib" "${WINDOWS_RELEASE_DIR}/include"
        cp -af "${WINDOWS_DEPEND_DIR}/bin/"* "${WINDOWS_RELEASE_DIR}/bin/" 2>/dev/null || true
        cp -af "${WINDOWS_DEPEND_DIR}/lib/"* "${WINDOWS_RELEASE_DIR}/lib/" 2>/dev/null || true
        cp -af "${WINDOWS_DEPEND_DIR}/include/"* "${WINDOWS_RELEASE_DIR}/include/" 2>/dev/null || true
    fi

    make clean

    popd
done
