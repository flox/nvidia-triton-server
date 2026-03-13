# CLAUDE.md - Build Triton Server from Source

## Project Overview

This is a Flox Nix expression build of NVIDIA Triton Inference Server v2.66.0 (r26.02)
from source, plus TRT-LLM model conversion tools via NGC container extraction.

All packages are published to the `flox` Flox catalog (10 total: 5 server/backends + 5 trtllm-tools).

## Key Files

### Server and backends
- `.flox/pkgs/triton-server.nix` - Triton server Nix expression
- `.flox/pkgs/triton-python-backend.nix` - Python backend expression (callPackage)
- `.flox/pkgs/onnxruntime-cuda.nix` - ONNX Runtime C++ library (standalone nixpkgs-pin)
- `.flox/pkgs/triton-onnxruntime-backend.nix` - ORT backend expression (callPackage)
- `.flox/pkgs/tensorrt-cuda.nix` - TensorRT SDK (standalone nixpkgs-pin, build dep only)
- `.flox/pkgs/triton-tensorrt-backend.nix` - TensorRT backend expression (callPackage)
- `.flox/pkgs/triton-tensorrtllm-backend.nix` - TensorRT-LLM backend (NGC bundle extraction)

### TRT-LLM model conversion tools (5 sub-packages)
- `.flox/pkgs/trtllm-tools-parts.nix` - Shared `fetchurl` defs (all 5 pkgs reference same tarballs)
- `.flox/pkgs/trtllm-tools-libs-cuda.nix` - CUDA 13, cuDNN, NCCL, MPI native libs (2.9 GB)
- `.flox/pkgs/trtllm-tools-libs-ml.nix` - TensorRT 10.13, MKL, TBB native libs (3.5 GB)
- `.flox/pkgs/trtllm-tools-python.nix` - Python 3.12 + stdlib + ~290 dist-packages (4.4 GB)
- `.flox/pkgs/trtllm-tools-engine.nix` - PyTorch 2.9.0a0 + tensorrt_llm 1.1.0 (4.2 GB)
- `.flox/pkgs/trtllm-tools.nix` - Wrapper scripts + trtexec + cuda/ + hpcx/ (244 MB)

### Scripts
- `scripts/triton-setup-models` - Model directory assembler (activation-time, Tier 1/Tier 2 model discovery)

### Other
- `.flox/env/manifest.toml` - Flox manifest (minimal, just for `flox build`)
- `build-meta/<package>.json` - Build version metadata (6 packages with markers)
- `result-triton-server/`, `result-trtllm-tools/`, etc. - Build output symlinks

## Build Commands

```bash
cd /home/daedalus/dev/builds/build-triton-server
git add .flox/pkgs/triton-server.nix   # Flox requires tracked files
flox build triton-server

git add .flox/pkgs/triton-python-backend.nix
flox build triton-python-backend

git add .flox/pkgs/onnxruntime-cuda.nix .flox/pkgs/triton-onnxruntime-backend.nix
flox build onnxruntime-cuda                      # ~1 hr, cached after first build
flox build triton-onnxruntime-backend             # ~5 min

git add .flox/pkgs/tensorrt-cuda.nix .flox/pkgs/triton-tensorrt-backend.nix
flox build tensorrt-cuda                          # fast, pre-built SDK
flox build triton-tensorrt-backend                # ~2 min

git add .flox/pkgs/triton-tensorrtllm-backend.nix
flox build triton-tensorrtllm-backend             # fast, pre-built bundle

git add .flox/pkgs/trtllm-tools-parts.nix .flox/pkgs/trtllm-tools-libs-cuda.nix \
       .flox/pkgs/trtllm-tools-libs-ml.nix .flox/pkgs/trtllm-tools-python.nix \
       .flox/pkgs/trtllm-tools-engine.nix .flox/pkgs/trtllm-tools.nix
flox build trtllm-tools-libs-cuda                 # fast, pre-built bundle
flox build trtllm-tools-libs-ml                   # fast, pre-built bundle
flox build trtllm-tools-python                    # fast, pre-built bundle
flox build trtllm-tools-engine                    # fast, pre-built bundle
flox build trtllm-tools                           # fast, wrapper scripts only
```

## Build Versioning (MANDATORY before every build/publish)

6 packages write a version marker file at `$out/share/<pname>/flox-build-version-<N>`:
triton-server, triton-python-backend, triton-onnxruntime-backend, triton-tensorrt-backend,
triton-tensorrtllm-backend, and trtllm-tools (wrapper only). The version info is read from
`build-meta/<package>.json` at Nix eval time — **NOT** from git (builtins.fetchGit
fails during `flox publish` because the source is copied to a store path with no .git).

The 4 trtllm-tools sub-packages (libs-cuda, libs-ml, python, engine) and the 2 build deps
(onnxruntime-cuda, tensorrt-cuda) do NOT get version markers.

### Pre-build checklist

Before running `flox build` or `flox publish` for any package, update its JSON:

1. Compute the new build version: `git rev-list --count HEAD` + `force_increment`
   (the count includes the commit you're about to make)
2. Capture the current git rev: `git rev-parse HEAD` / `git rev-parse --short HEAD`
3. Write a human-readable changelog describing what changed in this build
4. Commit the updated JSON (and any .nix changes) before building

Example — updating triton-server before a build:

```bash
# After making changes to the .nix file, update the metadata:
# build_version = $(git rev-list --count HEAD) + 1 (for the commit we're about to make)
# Then: git add build-meta/triton-server.json .flox/pkgs/triton-server.nix && git commit
# Then: flox build triton-server
```

### JSON schema

```json
{
  "build_version": 10,
  "force_increment": 0,
  "git_rev": "c4a14de09992f5749ee99c68b7720dc3ee51d6a5",
  "git_rev_short": "c4a14de",
  "changelog": "Description of what changed in this build."
}
```

- **build_version**: `git rev-list --count HEAD` + `force_increment` (monotonically increasing)
- **force_increment**: Manually bump this to increase the version without a code change
- **git_rev** / **git_rev_short**: The commit that produced this build
- **changelog**: Human-readable; what changed vs the previous build

Two packages use `version = "2.66.0+${buildMeta.git_rev_short}"` in their Nix expressions
(triton-server and triton-tensorrtllm-backend) so successive builds produce distinct catalog
entries. The remaining packages use plain `version = "2.66.0"`.

### Force increment

To bump the version without code changes (e.g., rebuild with different flags):
increment `force_increment` in the JSON, update `build_version` accordingly, commit,
and rebuild.

### Marker file location

After build: `result-<pkg>/share/<pname>/flox-build-version-<N>`

## Architecture Decisions

### Why Nix Expression (not Manifest Build)
Triton's build is too complex for a manifest `[build]` section. It requires:
- 12 pre-fetched GitHub repos (fixed-output derivations)
- Python patching script (`builtins.toFile`)
- Multiple `substituteInPlace` passes across 4 repos
- `gcc14Stdenv` override (default gcc15 incompatible with CUDA 12.8)

### Why gcc14Stdenv
CUDA 12.8's nvcc rejects gcc >= 15. Using `gcc14Stdenv` instead of default `stdenv`
ensures the entire build (including ExternalProject sub-builds) uses gcc 14.

### Why Tests Are Disabled
Tests in core, common, and server/src all try to `FetchContent` googletest from
GitHub. No network in Nix sandbox. Disabling is safe since we're packaging, not
developing.

### Why METRICS_GPU=OFF
`TRITON_ENABLE_METRICS_GPU` requires DCGM (NVIDIA Data Center GPU Manager), which
isn't packaged in Nix. The server works fine without it - just no GPU power/utilization
metrics via Prometheus.

### CUDA Architectures: 80;86;89;90
The backend repo's `define.cuda_architectures.cmake` defaults to `100f;120f` which
nvcc 12.8 doesn't support (CMake 4.x forward-compatibility syntax). We pin to
80/86/89/90. Forward compat for newer GPUs (Blackwell) works via PTX JIT.

Three separate architecture specifications are needed because different parts of the
build read different sources:
- `CUDA_ARCH_LIST="80 86 89 90"` (space-separated env var) - read by the backend repo's
  `define.cuda_architectures.cmake`
- `CUDAARCHS="80;86;89;90"` (semicolon-separated env var) - read by CMake's standard
  CUDA architecture detection
- `CMAKE_CUDA_ARCHITECTURES` injected via `set(... CACHE ...)` into
  `server/src/CMakeLists.txt` - propagates into the ExternalProject sub-build, which
  runs as a separate cmake process and doesn't inherit env vars or parent cmake vars

### ONNX Runtime Backend: Two-Expression Architecture

The ORT backend is split into two Nix expressions so that the slow ORT library build
(~1 hr) is cached independently from the fast Triton backend shim (~5 min):

1. **`onnxruntime-cuda.nix`** — Uses standalone nixpkgs-pin pattern (not callPackage)
   because it needs to override `nixpkgs.onnxruntime` with a specific nixpkgs revision
   and a CUDA 12.9 overlay. Key differences from the `build-onnx-runtime` repo:
   - `pythonSupport = false` — C++ shared library only, no Python wheel
   - Multi-arch `CMAKE_CUDA_ARCHITECTURES=80;86;89;90` instead of single-arch variants
   - No CPU ISA flags (`-mavx512f` etc.) — irrelevant for GPU inference

2. **`triton-onnxruntime-backend.nix`** — Uses callPackage convention (like
   `triton-python-backend.nix`). Imports `onnxruntime-cuda.nix` and passes the ORT
   output as `TRITON_ONNXRUNTIME_INCLUDE_PATHS` / `TRITON_ONNXRUNTIME_LIB_PATHS` to
   CMake. This bypasses the backend's Docker-based build and download mechanisms.

### CUDA Version Mismatch (ORT vs Backend)

ORT uses nixpkgs CUDA 12.9 (pinned in the nixpkgs overlay); the Triton backend uses
Flox CUDA 12.8. Both are CUDA 12.x minor versions — runtime-compatible. The NVIDIA
driver 590.48.01 supports both. The backend only links `cudart` (no CUDA kernels), so
the version difference is inconsequential.

### ORT Version: 1.24.2 vs 1.24.1

Triton r26.02 specifies ORT 1.24.1, but we use 1.24.2 (patch release, ABI-compatible).
This reuses exact source hashes from the `build-onnx-runtime` repo's `ort-1.24` branch.
If issues arise, pin to 1.24.1 by changing the `tag` and clearing the `hash`.

### TensorRT Backend: Two-Expression Architecture

Same pattern as the ORT backend (slow dep cached separately), except the TRT SDK is fast
(pre-built, no compilation required):

1. **`tensorrt-cuda.nix`** — Uses standalone nixpkgs-pin pattern (same as
   `onnxruntime-cuda.nix`). Provides the TRT SDK via `cudaPackages.tensorrt`, which is
   a multi-output derivation — must use `trt.include` and `trt.lib`, not bare `trt`.
   This is a build dependency only (not published to the `flox` catalog).

2. **`triton-tensorrt-backend.nix`** — Uses callPackage convention (same as other backends).
   Same sandbox adaptations: `/etc/os-release` stub, tests disabled, `CUDA_ARCH_LIST` +
   `CUDAARCHS` env vars. Backend's own `CMakeLists.txt:57` reads `/etc/os-release` and
   needs the same `substituteInPlace` patch as the core repo. Pre-fetches 4 repos
   (tensorrt_backend + core/common/backend shared with all other backends).

### TensorRT-LLM Backend: NGC Container Extraction

Fundamentally different from all other backends — **not built from source**. TensorRT-LLM
cannot be built via Nix due to:
- 63 GB build footprint
- Proprietary components (custom NVIDIA PyTorch, internal TRT-LLM build system)
- Complex transitive dependency chain (NCCL, OpenMPI, custom CUDA 13.x)

Approach: Extract pre-built binaries from the NGC container
`nvcr.io/nvidia/tritonserver:26.02-trtllm-python-py3`, package into a tarball, host on
GitHub Releases, and use `fetchurl` + `patchelf` in the Nix expression (no cmake, no
source compilation).

Key differences from source-built backends:
- Uses `fetchurl` (not `fetchFromGitHub`) — downloads a pre-built tarball
- Uses `patchelf` for RPATH fixing (not Nix's automatic RPATH handling)
- Bundles its own CUDA 13.x, NCCL, OpenMPI, and libstdc++ (SONAME isolation from system libs)
- No callPackage, no sandbox build challenges — just unpack and patch

Container extraction was done with `skopeo` (OCI format pull to `/mnt/scratch/trtllm-container`).
The bundle tarball lives at `/mnt/scratch/trtllm-backend-bundle-26.02.tar.gz`.

### TRT-LLM Model Conversion Tools: 5-Way Split

Standalone Python 3.12 environment for HuggingFace → TRT-LLM engine conversion, extracted
from the same NGC container as the TRT-LLM backend. Consumed by a separate Flox environment
(`triton-trtllm-tools`), not the triton-runtime environment. Python 3.12 is required because
`tensorrt_llm` is not pip-installable on Python 3.13.

The source bundle (~8.2 GB compressed) is split into 5 tarball parts on GitHub Release
`v26.02-tools` (GitHub has a 2 GB per-file limit). All 5 Nix sub-packages reference the
same `fetchurl` definitions in `trtllm-tools-parts.nix`.

Each sub-package stays under the 5 GB Flox catalog NAR upload limit:

| Sub-package | Size | What it contains |
|-------------|------|------------------|
| `trtllm-tools-libs-cuda` | 2.9 GB | CUDA 13, cuDNN 9.14, NCCL, OpenMPI, misc native `.so` |
| `trtllm-tools-libs-ml` | 3.5 GB | TensorRT 10.13, MKL, TBB |
| `trtllm-tools-python` | 4.4 GB | Python 3.12 + stdlib + ~290 dist-packages (excl torch/tensorrt_llm) |
| `trtllm-tools-engine` | 4.2 GB | PyTorch 2.9.0a0 + tensorrt_llm 1.1.0 + torchvision |
| `trtllm-tools` | 244 MB | Wrapper scripts + trtexec + `cuda/` + `hpcx/ompi/` |

Key Nix gotchas specific to trtllm-tools:

- **`@placeholder@` substitution**: Wrapper scripts use `@libs_cuda@`, `@libs_ml@`,
  `@python@`, `@engine@` tokens replaced by `substituteInPlace` with Nix store paths.
  This avoids Nix `''${` escaping hell in heredoc-heavy shell wrappers.
- **DT_RPATH → DT_RUNPATH**: Some NGC container `.so` files use `DT_RPATH` (takes
  precedence over `LD_LIBRARY_PATH`). Must patch to `DT_RUNPATH` so the wrapper's
  `LD_LIBRARY_PATH` works. Use `patchelf --set-rpath` on affected `.so` files.
- **nullglob in wrappers**: Wrapper scripts need `shopt -s nullglob` — Nix bash doesn't
  set it by default, causing glob patterns that match nothing to be passed literally.
- **OCI whiteout markers**: When extracting from the NGC container, layers use
  `.wh..wh..opq` whiteout markers to replace directories. Must extract from the LATEST
  layer containing the whiteout, not the earliest.
- **`_distutils_hack`**: Lives in system Python (`usr/lib/python3/dist-packages/`),
  not local `dist-packages/` — easy to miss during extraction.

## Critical Nix Sandbox Challenges (and solutions)

### 1. No Network Access
Triton's CMake uses `FetchContent` and `ExternalProject_Add` to clone repos at build
time. Solutions:
- **FetchContent repos**: Pre-fetched via `fetchFromGitHub` (FODs), injected via
  `FETCHCONTENT_SOURCE_DIR_*` cmake vars + `FETCHCONTENT_FULLY_DISCONNECTED=ON`
- **ExternalProject (third_party)**: Python patch script replaces `GIT_REPOSITORY`
  with `DOWNLOAD_COMMAND ""` and remaps paths to pre-fetched local copies
- **Python wheel build**: `--no-isolation` flag prevents pip from downloading deps

### 2. ExternalProject Sub-Builds Don't Inherit CMake Vars
`FETCHCONTENT_SOURCE_DIR_*` set at the top-level cmake DON'T propagate into
ExternalProject sub-builds (separate cmake processes). Fix:
- **triton-core ExternalProject**: Patched `CMAKE_CACHE_ARGS` in core/CMakeLists.txt
- **triton-server ExternalProject**: Injected `set(... CACHE ...)` calls into
  server/src/CMakeLists.txt after `include(FetchContent)`

### 3. Read-Only Nix Store Paths
`fetchFromGitHub` results land in `/nix/store/` (read-only). Triton's build patches
sources in-place. Fix: `cp -r` to `$TMPDIR/` writable copies for core, common,
third_party, and all prefetched deps.

### 4. /etc/os-release Doesn't Exist in Sandbox
Four CMakeLists.txt files read `/etc/os-release` to detect CentOS (for lib64). All
patched via `substituteInPlace` to `set(DISTRO_ID_LIKE "")`.

### 5. lib64 vs lib
GNUInstallDirs defaults to `lib64` on x86_64. Triton's third_party cmake expects
`lib`. Fix: Python patch script injects `-DCMAKE_INSTALL_LIBDIR:STRING=lib` into
every ExternalProject. Also `preFixup` merges any remaining lib64 into lib.

### 6. Python Wheel Version Pins
`pyproject.toml` pins `setuptools==75.3.0`, `wheel==0.44.0`, etc. Nix provides
different versions. Fix: `substituteInPlace` to loosen all pins. Also patched
`"numpy<2"` to `"numpy"` (Nix has numpy 2.x).

Note: `mypy` is listed in `pyproject.toml`'s `[build-system] requires` because it's
used for stub generation during the wheel build. This is why `ps.mypy` is included in
`buildPython` - without it, the `--no-isolation` build fails.

## Pre-Fetched Repos (12 total)

| Repo | Version | Notes |
|------|---------|-------|
| server | r26.02 | Main source (src=) |
| core | r26.02 | Writable copy needed |
| common | r26.02 | Writable copy needed |
| backend | r26.02 | Read-only OK (no patching) |
| third_party | r26.02 | Writable copy, heavily patched |
| pybind11 | v2.13.1 | Read-only OK |
| grpc | v1.54.3 | fetchSubmodules=true (abseil, protobuf, re2, cares) |
| libevent | release-2.1.12-stable | |
| prometheus-cpp | v1.0.1 | |
| nlohmann-json | v3.11.3 | |
| curl | curl-7_86_0 | |
| crc32c | b9d6e825... | |

## Pre-Fetched Repos: ONNX Runtime Backend (4 total)

| Repo | Version | Notes |
|------|---------|-------|
| onnxruntime_backend | r26.02 | Main source (src=) |
| core | r26.02 | Writable copy needed (shared hash with server/python) |
| common | r26.02 | Writable copy needed (shared hash with server/python) |
| backend | r26.02 | Read-only OK (shared hash with server/python) |

## Pre-Fetched Repos: TensorRT Backend (4 total)

| Repo | Version | Notes |
|------|---------|-------|
| tensorrt_backend | r26.02 | Main source (src=) |
| core | r26.02 | Writable copy needed (shared hash with server/python/ort) |
| common | r26.02 | Writable copy needed (shared hash with server/python/ort) |
| backend | r26.02 | Read-only OK (shared hash with server/python/ort) |

## TRT-LLM Bundle Contents

The TensorRT-LLM bundle contains ~45 shared libraries extracted from the NGC container.
These are the transitive runtime dependencies of `libtensorrt_llm.so`:

- **TRT-LLM core:** `libtensorrt_llm.so`, `libnvinfer_plugin_tensorrt_llm.so`
- **TensorRT:** `libnvinfer.so.10`, `libnvinfer_dispatch.so.10`, `libnvinfer_lean.so.10`
- **CUDA 13.x:** `libcublas.so.13`, `libcublasLt.so.13`, `libcudart.so.13`, `libcurand.so.10`
- **NCCL:** `libnccl.so.2` (multi-GPU communication)
- **OpenMPI:** `libmpi.so.40`, `libopen-rte.so.40`, `libopen-pal.so.40`
- **System deps:** `libudev.so.1`, `libcap.so.2`, `libstdc++.so.6`

Each library has SONAME symlinks (e.g., `libcublas.so.13` → `libcublas.so.13.0.0.68`).
The CUDA 13.x SONAMEs don't conflict with system CUDA 12.x.

## Pre-Fetched Repos: ORT Library (4 total)

| Repo | Version | Notes |
|------|---------|-------|
| onnxruntime | v1.24.2 | Main source (src=), fetchSubmodules=true |
| cutlass | v4.2.1 | NVIDIA CUTLASS for CUDA kernels |
| onnx | v1.20.1 | ONNX proto definitions |
| abseil-cpp | 20250814.0 | Abseil C++ library |

## Upgrading to a New Triton Version

For source-built packages (server + 4 backends):
1. Update `tag` and `version` in the nix expression
2. Set all `fetchFromGitHub` hashes to `""` (empty string)
3. Run `flox build triton-server` repeatedly - each failure gives the correct hash
4. Check for new `/etc/os-release` references, new test directories, new deps
5. The Python patch script and path mappings may need updates if third_party changes

For NGC-extracted packages (tensorrtllm-backend + trtllm-tools):
1. Pull the new NGC container with `skopeo`
2. Extract the backend bundle and tools bundle from the container layers
3. Split large tarballs for GitHub Releases (`split -b 2000000000`)
4. Upload to new release tags and update `fetchurl` hashes
5. For trtllm-tools, only `trtllm-tools-parts.nix` hashes need updating (shared by all 5 pkgs)

## Known Caveats

These don't affect functionality but a maintainer should know about them:

- **`tritonserver` wheel is version 0.0.0**: The core repo's `build_wheel.py` reads
  `TRITON_VERSION` from a generated file that gets its value from the `VERSION`
  environment variable. The Nix build sets `TRITON_VERSION` as a cmake flag, but the
  wheel build script doesn't pick it up the same way. The `tritonfrontend` wheel
  correctly gets version 2.66.0 because its build reads version info from cmake
  directly. The `.so` inside the wheel is correct - only the package metadata is wrong.
- **GPU metrics disabled**: `TRITON_ENABLE_METRICS_GPU=OFF` because DCGM isn't
  packaged in Nix. CPU metrics and all other Prometheus metrics work fine.
- **Test files included but not runnable**: `python/test/` contains test scripts and
  model configs from the wheel build, but the tests require a running server with
  loaded models and aren't intended to be run standalone.
- **Cloud storage backends disabled**: GCS, S3, and Azure storage are all OFF. These
  require additional SDKs that aren't worth the build complexity for local use.

## Nix Expression Gotchas

- **`''${` in Nix strings**: Literal `${` must be escaped as `''${` in `''...''` strings.
  The Python patch script uses `''${{CMAKE_CURRENT_BINARY_DIR}}` for this reason.
- **CMake semicolons in Nix**: Use `${"\\;"}` to produce a literal `\;` in cmake args
  (Nix eats the first level, cmake needs the backslash-semicolon)
- **`builtins.toFile`**: Creates a file in the Nix store from a string. Used for the
  Python patch script since it's too complex for inline bash.
- **`cmakeFlagsArray`**: Bash array - unlike `cmakeFlags` (Nix list), this preserves
  values containing `$TMPDIR` which is only known at build time.
