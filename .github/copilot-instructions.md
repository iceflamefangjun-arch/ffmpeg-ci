# clang-shell Copilot Instructions

## Scope and role
- This repository contains the Windows FFmpeg dependency build scripts that were previously kept under `ijkplayer/clang-shell`.
- Treat the repository root as the build script root. Do not assume there is an outer `ijkplayer/` checkout or a nested `clang-shell/` directory.
- Keep changes focused on dependency scripts, patches, CI wiring, and packaging behavior.

## Big picture
- `build-all.sh` is the player FFmpeg build entry point.
- `build-all-live.sh` is the live FFmpeg build entry point.
- Dependency build scripts live in top-level directories such as `ffmpeg/`, `json-c/`, `pthread-win32/`, `zlib/`, `x264/`, `fdk-aac/`, and `ffnvcodec/`.
- Shared environment defaults live in `env_config.sh`; CI injects MSVC, Windows SDK, dependency cache, and LLVM paths explicitly.
- Generated FFmpeg packages are written to the repository root as `ffmpeg-7.1.1-*.zip` or `ffmpeg-live-7.1.1-*.zip`.

## Build and validation
- GitHub Actions runs on `windows-2022`, prepares WSL, installs LLVM 21, resolves Visual Studio and Windows SDK paths, then invokes the selected root script.
- Repository variables `FFMPEG_REPO_URL`, `FDK_AAC_REPO_URL`, and `X264_REPO_URL` point at the GitHub mirrors used by dependency scripts.
- Repository secret `MIRROR_REPO_TOKEN` is optional, but when set it is used to rewrite GitHub clone URLs for private mirror access.
- Do not run local or CI builds unless the user explicitly asks for a build. Prefer static checks for workflow/script edits.

## Local coding conventions
- Match existing shell script style: small direct changes, explicit error checks, and no new abstraction for one-off behavior.
- Keep path handling repository-root relative unless a dependency script already expects `DEPENDSPATH`.
- Do not add `ijkplayer` playback-engine assumptions, Windows demo project steps, renderer guidance, or app-layer packaging rules here.
- Preserve UTF-8 BOM and CRLF formatting for repository instruction/config files when editing on Windows.
