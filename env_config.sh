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

configure_msys2_argument_conversion() {
	[ "${BUILD_HOST}" = "msys2" ] || return 0

	local protect="/nologo;/O;/Od;/O2;/Ob;/MD;/MDd;/MT;/MTd;/D;/D_DEBUG;/DNDEBUG;/Zc:;/bigobj;/utf-8;/GF;/Gy;/Gw;/EH;/std:;/Fo;/fo;/Fd;/fd;/Fe;/fe;/Fp;/fp;/FR;/fr;/Fa;/fa;/Fi;/fi;/FI;/FS;/Zi;/Z7;/RTC;/W;/wd;/WX;/GR;/Gd;/GS;/guard:;/machine:;/MACHINE:;/stack:;/STACK:;/safeseh:;/SAFESEH:;/subsystem:;/SUBSYSTEM:;/libpath:;/LIBPATH:;/manifest;/MANIFEST;/manifestuac;/manifestdependency;/manifestfile:;/debug;/DEBUG;/INCREMENTAL;/OPT:;/LTCG;/DLL;/IMPLIB:;/PDB:;/out:;/OUT:;/def:;/DEF:;/nodefaultlib:;/NODEFAULTLIB:"

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

export_msvc_environment() {
	if [ "${BUILD_HOST}" = "msys2" ]; then
		export INCLUDE="$(to_native_path "${WINSDKINC}/winrt");$(to_native_path "${WINSDKINC}/ucrt");$(to_native_path "${WINSDKINC}/um");$(to_native_path "${WINSDKINC}/shared");$(to_native_path "${VCINC}")"
	else
		export INCLUDE="${WINSDKINC}/winrt;${WINSDKINC}/ucrt;${WINSDKINC}/um;${WINSDKINC}/shared;${VCINC}"
	fi

	export CLANG_CL_TOOL="${CLANG_CL_TOOL:-clang-cl}"
	export LLD_LINK_TOOL="${LLD_LINK_TOOL:-lld-link}"
	export LLVM_LIB_TOOL="${LLVM_LIB_TOOL:-llvm-lib}"
	export LLVM_AR_TOOL="${LLVM_AR_TOOL:-llvm-ar}"
	export LLVM_NM_TOOL="${LLVM_NM_TOOL:-llvm-nm}"
	export LLVM_MT_TOOL="${LLVM_MT_TOOL:-llvm-mt}"
	export LLVM_RC_TOOL="${LLVM_RC_TOOL:-llvm-rc}"
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
	local ninja_path=

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
	cmake "${generator_args[@]}" "-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY" "$@" || exit
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
	  all|both)
		  archs=('x86' 'x64')
		  targets=('i686-w64-mingw32' 'x86_64-w64-mingw32')
		  ;;
	  *)
		  echo "Only support arch [x86|x64|all], got: ${requested}" >&2
		  exit 1
		  ;;
	esac
}

detect_build_host
discover_toolchain
prepend_toolchain_path
configure_msys2_argument_conversion
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
