#!/bin/bash

detect_build_host() {
	local uname_s

	uname_s="$(uname -s 2>/dev/null || echo unknown)"
	case "${uname_s}" in
	  MSYS*|MINGW*|CYGWIN*)
		  BUILD_HOST="msys2"
		  ;;
	  Linux*)
		  if grep -qi microsoft /proc/version 2>/dev/null; then
			  BUILD_HOST="wsl"
		  else
			  BUILD_HOST="linux"
		  fi
		  ;;
	  *)
		  BUILD_HOST="linux"
		  ;;
	esac
	export BUILD_HOST
}

to_shell_path() {
	local path_value="$1"

	if [ "${BUILD_HOST}" = "msys2" ] && command -v cygpath >/dev/null 2>&1; then
		cygpath -u "${path_value}"
	else
		printf '%s\n' "${path_value}"
	fi
}

to_native_path() {
	local path_value="$1"

	if [ "${BUILD_HOST}" = "msys2" ] && command -v cygpath >/dev/null 2>&1; then
		cygpath -aw "${path_value}" | tr '\\' '/'
	else
		printf '%s\n' "${path_value}"
	fi
}

latest_child_dir() {
	local parent_dir="$1"

	[ -d "${parent_dir}" ] || return 1
	find "${parent_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1
}

find_vs_install_dir() {
	local vswhere="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
	local found=

	if [ -n "${VSINSTALLDIR:-}" ]; then
		to_shell_path "${VSINSTALLDIR}"
		return 0
	fi

	if [ -x "${vswhere}" ]; then
		found="$("${vswhere}" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>/dev/null | tr -d '\r' | tail -n 1)"
		if [ -n "${found}" ]; then
			to_shell_path "${found}"
			return 0
		fi
	fi

	for found in \
		"/c/Program Files/Microsoft Visual Studio/2022/Enterprise" \
		"/c/Program Files/Microsoft Visual Studio/2022/Professional" \
		"/c/Program Files/Microsoft Visual Studio/2022/Community" \
		"/c/Program Files/Microsoft Visual Studio/2022/BuildTools"; do
		if [ -d "${found}" ]; then
			printf '%s\n' "${found}"
			return 0
		fi
	done

	return 1
}

discover_windows_sdk() {
	local kits_root="/c/Program Files (x86)/Windows Kits/10"
	local include_dir lib_dir

	if [ -n "${WINSDKINC:-}" ] && [ -n "${WINSDKLIB:-}" ]; then
		WINSDKINC="$(to_shell_path "${WINSDKINC}")"
		WINSDKLIB="$(to_shell_path "${WINSDKLIB}")"
		export WINSDKINC WINSDKLIB
		return 0
	fi

	if [ "${BUILD_HOST}" = "msys2" ]; then
		include_dir="$(latest_child_dir "${kits_root}/Include")" || return 1
		lib_dir="${kits_root}/Lib/$(basename "${include_dir}")"
		WINSDKINC="${include_dir}"
		WINSDKLIB="${lib_dir}"
	else
		WINSDKINC="${WINSDKINC:-/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0}"
		WINSDKLIB="${WINSDKLIB:-/mnt/c/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0}"
	fi

	export WINSDKINC WINSDKLIB
}

discover_msvc() {
	local vs_dir msvc_dir

	if [ -n "${VCLIB:-}" ] && [ -n "${VCINC:-}" ]; then
		VCLIB="$(to_shell_path "${VCLIB}")"
		VCINC="$(to_shell_path "${VCINC}")"
		export VCLIB VCINC
		return 0
	fi

	if [ "${BUILD_HOST}" = "msys2" ]; then
		vs_dir="$(find_vs_install_dir)" || return 1
		msvc_dir="$(latest_child_dir "${vs_dir}/VC/Tools/MSVC")" || return 1
		VCLIB="${msvc_dir}/lib"
		VCINC="${msvc_dir}/include"
	else
		VCLIB="${VCLIB:-/mnt/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/lib}"
		VCINC="${VCINC:-/mnt/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/include}"
	fi

	export VCLIB VCINC
}

discover_toolchain() {
	if [ -z "${TOOLCHAIN:-}" ]; then
		if [ "${BUILD_HOST}" = "msys2" ] && [ -d "/c/Program Files/LLVM" ]; then
			TOOLCHAIN="/c/Program Files/LLVM"
		elif [ -d "/usr/lib/llvm-21" ]; then
			TOOLCHAIN="/usr/lib/llvm-21"
		elif command -v clang-cl >/dev/null 2>&1; then
			TOOLCHAIN="$(cd "$(dirname "$(command -v clang-cl)")/.." && pwd)"
		else
			TOOLCHAIN="/usr/lib/llvm-21"
		fi
	fi

	TOOLCHAIN="$(to_shell_path "${TOOLCHAIN}")"
	export TOOLCHAIN
}

prepend_toolchain_path() {
	case ":${PATH}:" in
	  *":${TOOLCHAIN}/bin:"*) ;;
	  *) export PATH="${TOOLCHAIN}/bin:${PATH}" ;;
	esac
}

configure_msys2_tmpdir() {
	[ "${BUILD_HOST}" = "msys2" ] || return 0

	# On GitHub Actions the runner temp directory is guaranteed to exist and
	# be writable from both MSYS2 and native Windows tools. Point TMPDIR there
	# so ffmpeg configure's test compilations create files in a path that
	# clang-cl can actually open.
	if [ -n "${RUNNER_TEMP:-}" ]; then
		export TMPDIR="$(cygpath -u "$RUNNER_TEMP")"
	fi
}

configure_msys2_argument_conversion() {
	[ "${BUILD_HOST}" = "msys2" ] || return 0

	local protect="/nologo;-nologo;/O;-O;/Od;-Od;/O2;-O2;/Ob;-Ob;/MD;-MD;/MDd;-MDd;/MT;-MT;/MTd;-MTd;/D;-D;/D_DEBUG;-D_DEBUG;/DNDEBUG;-DNDEBUG;/Zc:;-Zc:;/bigobj;-bigobj;/utf-8;-utf-8;/GF;-GF;/Gy;-Gy;/Gw;-Gw;/EH;-EH;/std:;-std:;/Fo;-Fo;/fo;-fo;/Fd;-Fd;/fd;-fd;/Fe;-Fe;/fe;-fe;/Fp;-Fp;/fp;-fp;/FR;-FR;/fr;-fr;/Fa;-Fa;/fa;-fa;/Fi;-Fi;/fi;-fi;/FI;-FI;/FS;-FS;/Zi;-Zi;/Z7;-Z7;/RTC;-RTC;/W;-W;/wd;-wd;/WX;-WX;/GR;-GR;/Gd;-Gd;/GS;-GS;/guard:;-guard:;/machine:;-machine:;/MACHINE:;-MACHINE:;/stack:;-stack:;/STACK:;-STACK:;/safeseh:;-safeseh:;/SAFESEH:;-SAFESEH:;/subsystem:;-subsystem:;/SUBSYSTEM:;-SUBSYSTEM:;/libpath:;-libpath:;/LIBPATH:;-LIBPATH:;/manifest;-manifest;/MANIFEST;-MANIFEST;/manifestuac;-manifestuac;/manifestdependency;-manifestdependency;/manifestfile:;-manifestfile:;/debug;-debug;/DEBUG;-DEBUG;/INCREMENTAL;-INCREMENTAL;/OPT:;-OPT:;/LTCG;-LTCG;/DLL;-DLL;/IMPLIB:;-IMPLIB:;/PDB:;-PDB:;/out:;-out:;/OUT:;-OUT:;/def:;-def:;/DEF:;-DEF:;/nodefaultlib:;-nodefaultlib:;/NODEFAULTLIB:;-NODEFAULTLIB:"

	if [ -n "${MSYS2_ARG_CONV_EXCL:-}" ]; then
		export MSYS2_ARG_CONV_EXCL="${protect};${MSYS2_ARG_CONV_EXCL}"
	else
		export MSYS2_ARG_CONV_EXCL="${protect}"
	fi
}

discover_dependspath() {
	if [ -n "${DEPENDSPATH:-}" ]; then
		DEPENDSPATH="$(to_shell_path "${DEPENDSPATH}")"
	elif [ "${BUILD_HOST}" = "wsl" ] && [ -d "/mnt/d/Code/ffmpeg-src" ]; then
		DEPENDSPATH="/mnt/d/Code/ffmpeg-src"
	elif [ "${BUILD_HOST}" = "msys2" ] && [ -n "${RUNNER_TEMP:-}" ]; then
		DEPENDSPATH="$(to_shell_path "${RUNNER_TEMP}")/ffmpeg-src"
	else
		DEPENDSPATH="${HOME}/.cache/shplayer/ffmpeg-src"
	fi

	export DEPENDSPATH
	mkdir -p "${DEPENDSPATH}" || {
		echo "Failed to create DEPENDSPATH: ${DEPENDSPATH}" >&2
		exit 1
	}
}

generate_msys2_tool_wrapper() {
	local tool_name="$1"
	local real_tool="$2"
	local wrapper_dir="${DEPENDSPATH}/.clang-shell-wrappers"
	local wrapper_bin_dir="${DEPENDSPATH}/bin"
	local wrapper="${wrapper_bin_dir}/${tool_name}"

	mkdir -p "${wrapper_dir}" "${wrapper_bin_dir}"

	cat > "${wrapper}" <<WRAPPER_EOF
#!/usr/bin/env bash
# On MSYS2, wrap ${tool_name} so Unix-style absolute paths embedded in MSVC-style
# arguments (e.g. -Fo/d/a/_temp/.../test.o or -out:/d/a/_temp/.../test.exe) are
# converted to Windows paths before reaching the native binary. MSYS2_ARG_CONV_EXCL
# protects these flags from automatic conversion, leaving ${tool_name} unable to
# open the Unix-style paths.
set -euo pipefail

real_tool="${real_tool}"
args=()

for arg in "\$@"; do
    converted="\${arg}"

    # Whole argument is a Unix absolute path like /d/a/...
    if [[ "\${arg}" =~ ^/[a-zA-Z]/.*\$ ]]; then
        converted="\$(cygpath -w "\${arg}")"
    # -libpath: is only meaningful to the linker. Drop it for clang-cl,
    # and normalize it to /LIBPATH: for lld-link.
    elif [[ "\${arg}" =~ ^-libpath:(/.+)\$ ]]; then
        path="\${BASH_REMATCH[1]}"
        if [ "${tool_name}" = "lld-link" ]; then
            converted="/LIBPATH:\$(cygpath -w "\${path}")"
        else
            continue
        fi
    # Short flag (e.g. -I, -L, /I) immediately followed by a Windows
    # drive-letter path like D:/... or D:\...  The drive letter is part of
    # the path, not the flag name.  Pass through unchanged — clang-cl and
    # lld-link handle Windows paths natively.  This must be checked BEFORE
    # the colon regex below, which would otherwise eat the drive letter
    # (e.g. -ID:/a/... → -ID: + /a/... → -ID:A:\... — wrong drive!).
    elif [[ "\${arg}" =~ ^[-/]([A-Za-z])([a-zA-Z]:[\\\\/].*)\$ ]]; then
        converted="\${arg}"
    # Option with an attached path using a colon, e.g. /LIBPATH:/d/a/... or -out:/d/a/...
    elif [[ "\${arg}" =~ ^([-/][A-Za-z]+:)(/[a-zA-Z]/.*)\$ ]]; then
        opt="\${BASH_REMATCH[1]}"
        path="\${BASH_REMATCH[2]}"
        converted="\${opt}\$(cygpath -w "\${path}")"
    # Option with an attached path, e.g. -Fo/d/a/... or /I/d/a/...
    elif [[ "\${arg}" =~ ^([-/][A-Za-z]+)(/[a-zA-Z]/.*)\$ ]]; then
        opt="\${BASH_REMATCH[1]}"
        path="\${BASH_REMATCH[2]}"
        converted="\${opt}\$(cygpath -w "\${path}")"
    fi

    args+=("\${converted}")
done

exec "\${real_tool}" "\${args[@]}"
WRAPPER_EOF
	chmod +x "${wrapper}"
}

export_msvc_environment() {
	if [ "${BUILD_HOST}" = "msys2" ]; then
		export INCLUDE="$(to_native_path "${WINSDKINC}/winrt");$(to_native_path "${WINSDKINC}/ucrt");$(to_native_path "${WINSDKINC}/um");$(to_native_path "${WINSDKINC}/shared");$(to_native_path "${VCINC}")"
	else
		export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
	fi

	export CLANG_CL_TOOL="${CLANG_CL_TOOL:-clang-cl}"
	export LLD_LINK_TOOL="${LLD_LINK_TOOL:-lld-link}"

	# On MSYS2, place small wrappers on PATH for clang-cl and lld-link so that
	# configure's generated MSVC-style flags (e.g. -Fo/... or -out:/...) have
	# their Unix absolute paths translated to Windows paths before reaching the
	# native binaries. MSYS2_ARG_CONV_EXCL protects these flags from automatic
	# conversion, which leaves the tools unable to open the Unix-style paths.
	if [ "${BUILD_HOST}" = "msys2" ] && [ -z "${MSYS2_TOOL_WRAPPERS_READY:-}" ]; then
		local real_clang_cl real_lld_link
		local wrapper_bin_dir="${DEPENDSPATH}/bin"

		real_clang_cl="$(command -v "${CLANG_CL_TOOL}")" || real_clang_cl="${CLANG_CL_TOOL}"
		real_clang_cl="$(to_shell_path "${real_clang_cl}")"
		generate_msys2_tool_wrapper "clang-cl" "${real_clang_cl}"

		real_lld_link="$(command -v "${LLD_LINK_TOOL}")" || real_lld_link="${LLD_LINK_TOOL}"
		real_lld_link="$(to_shell_path "${real_lld_link}")"
		generate_msys2_tool_wrapper "lld-link" "${real_lld_link}"

		case ":${PATH}:" in
		  *":${wrapper_bin_dir}:"*) ;;
		  *) export PATH="${wrapper_bin_dir}:${PATH}" ;;
		esac

		echo "MSYS2 tool wrappers installed in ${wrapper_bin_dir}" >&2
		echo "clang-cl wrapper resolves to: $(command -v clang-cl)" >&2
		echo "lld-link wrapper resolves to: $(command -v lld-link)" >&2
		head -n 5 "${wrapper_bin_dir}/clang-cl" >&2

		export REAL_CLANG_CL_TOOL="${real_clang_cl}"
		export REAL_LLD_LINK_TOOL="${real_lld_link}"
		export MSYS2_TOOL_WRAPPERS_READY=1
	fi

	export LLVM_LIB_TOOL="${LLVM_LIB_TOOL:-llvm-lib}"
	export LLVM_AR_TOOL="${LLVM_AR_TOOL:-llvm-ar}"
	export LLVM_NM_TOOL="${LLVM_NM_TOOL:-llvm-nm}"
	export LLVM_MT_TOOL="${LLVM_MT_TOOL:-llvm-mt}"
	export LLVM_RC_TOOL="${LLVM_RC_TOOL:-llvm-rc}"
	export LLVM_WINDRES_TOOL="${LLVM_WINDRES_TOOL:-llvm-windres}"
	export LLVM_RANLIB_TOOL="${LLVM_RANLIB_TOOL:-llvm-ranlib}"
	export LLVM_STRIP_TOOL="${LLVM_STRIP_TOOL:-llvm-strip}"

	export AR="${AR:-${LLVM_LIB_TOOL}}"
	export NM="${NM:-${LLVM_NM_TOOL}}"
	export MT="${MT:-${LLVM_MT_TOOL}}"
	export RC="${RC:-${LLVM_RC_TOOL}}"
	export CC="${CC:-${CLANG_CL_TOOL}}"
	export CXX="${CXX:-${CLANG_CL_TOOL}}"
	export LD="${LD:-${LLD_LINK_TOOL}}"
	export RANLIB="${RANLIB:-${LLVM_RANLIB_TOOL}}"
	export STRIP="${STRIP:-${LLVM_STRIP_TOOL}}"
}

set_msvc_arch_env() {
	local arch_name="$1"
	shift || true
	local include_value=
	local extra_include

	if [ "${BUILD_HOST}" = "msys2" ]; then
		for extra_include in "$@"; do
			if [ -n "${include_value}" ]; then
				include_value="${include_value};"
			fi
			include_value="${include_value}$(to_native_path "${extra_include}")"
		done
		if [ -n "${include_value}" ]; then
			include_value="${include_value};"
		fi
		include_value="${include_value}$(to_native_path "${WINSDKINC}/winrt");$(to_native_path "${WINSDKINC}/ucrt");$(to_native_path "${WINSDKINC}/um");$(to_native_path "${WINSDKINC}/shared");$(to_native_path "${VCINC}")"
		export INCLUDE="${include_value}"
		export LIB="$(to_native_path "${VCLIB}/${arch_name}");$(to_native_path "${WINSDKLIB}/um/${arch_name}");$(to_native_path "${WINSDKLIB}/ucrt/${arch_name}")"
	else
		for extra_include in "$@"; do
			if [ -n "${include_value}" ]; then
				include_value="${include_value};"
			fi
			include_value="${include_value}${extra_include}"
		done
		if [ -n "${include_value}" ]; then
			include_value="${include_value};"
		fi
		export INCLUDE="${include_value}${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
		export LIB="${VCLIB}/${arch_name};${WINSDKLIB}/um/${arch_name};${WINSDKLIB}/ucrt/${arch_name}"
	fi
}

append_msvc_lib_path() {
	local lib_path="$1"

	if [ "${BUILD_HOST}" = "msys2" ]; then
		export LIB="${LIB};$(to_native_path "${lib_path}")"
	else
		export LIB="${LIB};${lib_path}"
	fi
}

msvc_libpath_flag() {
	local lib_path="$1"

	if [ "${BUILD_HOST}" = "msys2" ]; then
		printf '/libpath:%s' "$(to_native_path "${lib_path}")"
	else
		printf '/libpath:%s' "${lib_path}"
	fi
}

windres_for_arch() {
	local arch_name="$1"
	local windres_tool="${WINDRES:-windres}"

	case "${arch_name}" in
	  x86|i386|i686)
		  printf '%s --target=pe-i386\n' "${windres_tool}"
		  ;;
	  x64|x86_64|amd64)
		  printf '%s --target=pe-x86-64\n' "${windres_tool}"
		  ;;
	  arm64|aarch64|ARM64)
		  if ! command -v "${LLVM_WINDRES_TOOL}" >/dev/null 2>&1; then
			  echo "Required LLVM ARM64 resource compiler not found in PATH: ${LLVM_WINDRES_TOOL}" >&2
			  return 1
		  fi
		  printf '%s --target=aarch64-pc-windows-msvc\n' "${LLVM_WINDRES_TOOL}"
		  ;;
	  *)
		  printf '%s\n' "${windres_tool}"
		  ;;
	esac
}

validate_build_environment() {
	local missing=0
	local tool

	for tool in "${CC}" "${LD}" "${LLVM_LIB_TOOL}" "${LLVM_AR_TOOL}" "${NM}" "${MT}" "${RC}" "${RANLIB}" "${STRIP}"; do
		if ! command -v "${tool}" >/dev/null 2>&1; then
			echo "Required LLVM tool not found in PATH: ${tool}" >&2
			missing=1
		fi
	done

	if [ ! -d "${WINSDKINC}/ucrt" ] || [ ! -d "${WINSDKINC}/um" ] || [ ! -d "${WINSDKINC}/shared" ]; then
		echo "Windows SDK include path is invalid: ${WINSDKINC}" >&2
		missing=1
	fi
	if [ ! -d "${WINSDKLIB}/ucrt" ] || [ ! -d "${WINSDKLIB}/um" ]; then
		echo "Windows SDK lib path is invalid: ${WINSDKLIB}" >&2
		missing=1
	fi
	if [ ! -d "${VCINC}" ] || [ ! -d "${VCLIB}" ]; then
		echo "MSVC include/lib path is invalid: VCINC=${VCINC} VCLIB=${VCLIB}" >&2
		missing=1
	fi

	if [ "${missing}" -ne 0 ]; then
		exit 1
	fi
}

print_build_environment_once() {
	[ -z "${CLANG_SHELL_ENV_PRINTED:-}" ] || return 0
	export CLANG_SHELL_ENV_PRINTED=1

	echo "Build host: ${BUILD_HOST}"
	echo "uname: $(uname -a 2>/dev/null || true)"
	echo "SHELL: ${SHELL:-}"
	echo "TOOLCHAIN: ${TOOLCHAIN}"
	echo "DEPENDSPATH: ${DEPENDSPATH}"
	echo "WINSDKINC: ${WINSDKINC}"
	echo "WINSDKLIB: ${WINSDKLIB}"
	echo "VCINC: ${VCINC}"
	echo "VCLIB: ${VCLIB}"
	echo "cmake: $(command -v cmake 2>/dev/null || echo not-found)"
	cmake --version 2>/dev/null | head -n 1 || true
	echo "ninja: $(command -v ninja 2>/dev/null || echo not-found)"
	echo "make: $(command -v make 2>/dev/null || echo not-found)"
	"${CC}" --version 2>/dev/null | head -n 1 || true
	"${RC}" --version 2>/dev/null | head -n 1 || true
}

cmake_tool_path() {
	local tool_name="$1"
	local tool_path

	tool_path="$(command -v "${tool_name}" 2>/dev/null)" || tool_path="${tool_name}"
	printf '%s\n' "${tool_path}"
}

run_cmake_configure() {
	local generator_args=()
	local target_args=()
	local ninja_path=

	if [ "${ARCH:-}" = "arm64" ]; then
		target_args=("-DCMAKE_SYSTEM_PROCESSOR=ARM64")
	fi

	if command -v ninja >/dev/null 2>&1; then
		ninja_path="$(command -v ninja)"
	fi

	if [ "${BUILD_HOST}" = "msys2" ] && [ -x /usr/bin/make ]; then
		# CMake's Ninja generator on MSYS2 frequently trips over path conversion
		# during compiler detection (TryCompile step), so prefer Unix Makefiles.
		generator_args=(-G "Unix Makefiles" "-DCMAKE_MAKE_PROGRAM=/usr/bin/make")
	elif [ -n "${ninja_path}" ]; then
		generator_args=(-G Ninja "-DCMAKE_MAKE_PROGRAM=${ninja_path}")
	elif [ -x /usr/bin/make ]; then
		generator_args=(-G "Unix Makefiles" "-DCMAKE_MAKE_PROGRAM=/usr/bin/make")
	fi

	echo "CMake generator: ${generator_args[*]:-(default)}"
	cmake "${generator_args[@]}" "${target_args[@]}" \
		"-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY" "$@" || exit
}

run_cmake_build_install() {
	cmake --build . --verbose --parallel "$(nproc)" &&
		cmake --install .
}

set_target_archs() {
	local requested="${1:-x86}"

	case "${requested}" in
	  x86|Win32|win32)
		  archs=('x86')
		  targets=('i686-w64-mingw32')
		  ;;
	  x64|amd64|AMD64)
		  archs=('x64')
		  targets=('x86_64-w64-mingw32')
		  ;;
	  arm64|aarch64|ARM64)
		  archs=('arm64')
		  targets=('aarch64-w64-mingw32')
		  ;;
	  all|both)
		  archs=('x86' 'x64')
		  targets=('i686-w64-mingw32' 'x86_64-w64-mingw32')
		  ;;
	  *)
		  echo "Only support arch [x86|x64|arm64|all], got: ${requested}" >&2
		  exit 1
		  ;;
	esac
}

detect_build_host
discover_toolchain
prepend_toolchain_path
configure_msys2_argument_conversion
configure_msys2_tmpdir
discover_dependspath
discover_windows_sdk || {
	echo "Failed to locate Windows SDK paths." >&2
	exit 1
}
discover_msvc || {
	echo "Failed to locate MSVC include/lib paths." >&2
	exit 1
}
export_msvc_environment
validate_build_environment
print_build_environment_once
