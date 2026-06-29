export TOOLCHAIN="${TOOLCHAIN:-/usr/lib/llvm-21}"

export WINSDKINC="${WINSDKINC:-/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0}"
export WINSDKLIB="${WINSDKLIB:-/mnt/c/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0}"

export VCLIB="${VCLIB:-/mnt/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/lib}"
export VCINC="${VCINC:-/mnt/c/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.44.35207/include}"

if [ -z "${DEPENDSPATH:-}" ]; then
	if [ -d "/mnt/d/Code/ffmpeg-src" ]; then
		export DEPENDSPATH="/mnt/d/Code/ffmpeg-src"
	else
		export DEPENDSPATH="${HOME}/.cache/shplayer/ffmpeg-src"
	fi
fi

mkdir -p "${DEPENDSPATH}" || {
	echo "Failed to create DEPENDSPATH: ${DEPENDSPATH}" >&2
	exit 1
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
