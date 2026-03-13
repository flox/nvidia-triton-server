# Triton Inference Server - Nix Build

Build NVIDIA Triton Inference Server v2.66.0 and its backends (Python, ONNX Runtime, TensorRT, TensorRT-LLM) from source using Flox/Nix, plus TRT-LLM model conversion tools via NGC container extraction.

## Prerequisites

- [Flox](https://flox.dev) installed
- NVIDIA GPU with CUDA 12.8 drivers
- ~32 GB disk space for build artifacts
- ~16 GB RAM recommended (build is memory-intensive)

## Quick Start

```bash
git add .flox/pkgs/triton-server.nix
flox build triton-server

git add .flox/pkgs/triton-python-backend.nix
flox build triton-python-backend

git add .flox/pkgs/onnxruntime-cuda.nix .flox/pkgs/triton-onnxruntime-backend.nix
flox build onnxruntime-cuda                      # ~1 hr, cached after first build
flox build triton-onnxruntime-backend             # ~5 min, links against cached ORT

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

Build output appears at `./result-triton-server/`, `./result-triton-python-backend/`,
`./result-onnxruntime-cuda/`, `./result-triton-onnxruntime-backend/`,
`./result-tensorrt-cuda/`, `./result-triton-tensorrt-backend/`,
`./result-triton-tensorrtllm-backend/`, and `./result-trtllm-tools/`.

## Build Output

```
result-triton-server/
  bin/
    tritonserver              # Main server binary (18 MB)
    triton-serve              # Server launcher script
    triton-preflight          # Pre-flight validation script
    triton-resolve-model      # Model provisioning script
    triton-setup-backends     # Backend directory assembler (activation-time)
    triton-setup-models       # Model directory assembler (activation-time)
    _lib.sh                   # Shared library sourced by the scripts
    simple                # Example: single model
    multi_server          # Example: multiple server instances
    memory_alloc          # Example: custom memory allocation
  lib/
    libtritonserver.so    # Core runtime library (7.4 MB)
    libtritonbackendutils.a
    libtritoncommonmodelconfig.a
    libkernel_library_new.a
    ...                   # + 5 more static libs
    stubs/libtritonserver.so
    cmake/TritonCore/     # CMake find_package support
    cmake/TritonBackend/  # Backend development cmake modules
    cmake/TritonCommon/   # Common utilities cmake modules
  include/
    *.pb.h                # 5 protobuf/gRPC service definitions
    triton/core/          # 4 headers: C API, backend, cache, repo agent
    triton/backend/       # 7 headers: backend development utilities
    triton/common/        # 9 headers: shared utilities (logging, JSON, etc.)
  python/
    tritonserver-*.whl    # Python in-process API bindings
    tritonfrontend-*.whl  # Python HTTP/gRPC frontend bindings
    tritonserver-*.tar.gz # Source tarball
```

```
result-triton-python-backend/
  backends/python/
    libtriton_python.so              # Backend shared library (1.4 MB)
    triton_python_backend_stub       # Per-instance Python host executable (1.5 MB)
    triton_python_backend_utils.py   # Python utilities for user model code
```

```
result-onnxruntime-cuda/
  lib/
    libonnxruntime.so                  # Main shared library (29 MB)
    libonnxruntime_providers_shared.so # Provider framework (15 KB)
    libonnxruntime_providers_cuda.so   # CUDA execution provider (272 MB)
```

```
result-triton-onnxruntime-backend/
  backends/onnxruntime/
    libtriton_onnxruntime.so           # Backend shared library (800 KB)
```

The backend's RPATH is automatically patched by Nix to reference the ORT store path,
so `libtriton_onnxruntime.so` finds `libonnxruntime.so` at runtime without copying.

```
result-tensorrt-cuda/
  (build dependency only — not published, consumed by triton-tensorrt-backend)
  bin/ include/ lib/ static/           # TensorRT SDK components (multi-output derivation)
```

```
result-triton-tensorrt-backend/
  backends/tensorrt/
    libtriton_tensorrt.so              # Backend shared library (1.1 MB)
```

```
result-triton-tensorrtllm-backend/
  backends/tensorrtllm/
    libtriton_tensorrtllm.so           # Backend shared library (757 KB)
    trtllmExecutorWorker               # TRT-LLM executor process (73 MB)
  lib/
    libtensorrt_llm.so                 # TRT-LLM runtime + 40+ bundled libs (3.9 GB total)
    libnvinfer_plugin_tensorrt_llm.so
    libnccl.so.2, libmpi.so.40, libcudart.so.13, libcublas.so.13, ...
  hpcx/ompi/                           # OpenMPI prefix (OPAL_PREFIX for MPI_Init_thread)
    share/openmpi/                     # MPI help files and runtime data
    lib/                               # MCA modules (mca_*.so)
    etc/                               # OpenMPI configuration
```

The trtllm-tools output is split across 5 sub-packages (see
[TRT-LLM Model Conversion Tools](#trt-llm-model-conversion-tools)):

| Sub-package | Size | Contents |
|-------------|------|----------|
| `trtllm-tools-libs-cuda` | 2.9 GB | CUDA 13, cuDNN 9.14, NCCL, OpenMPI, misc native `.so` |
| `trtllm-tools-libs-ml` | 3.5 GB | TensorRT 10.13, MKL, TBB |
| `trtllm-tools-python` | 4.4 GB | Python 3.12 interpreter + stdlib + ~290 dist-packages |
| `trtllm-tools-engine` | 4.2 GB | PyTorch 2.9.0a0 + tensorrt_llm 1.1.0 + torchvision |
| `trtllm-tools` (wrapper) | 244 MB | Wrapper scripts + trtexec + `cuda/` + `hpcx/ompi/` |

```
result-trtllm-tools/
  bin/
    trtllm-build              # HuggingFace → TRT-LLM engine conversion
    trtllm-bench              # Benchmarking
    trtllm-eval               # Evaluation
    trtllm-prune              # Model pruning
    trtllm-refit              # Engine refitting
    trtllm-serve              # TRT-LLM serving (standalone)
    trtllm-llmapi-launch      # LLM API launcher
    trtexec                   # TensorRT engine builder/profiler
    cuda/                     # CUDA compiler tools (nvcc, ptxas, etc.)
  cuda/                       # CUDA_HOME structure (bin, nvvm, lib64 symlinks)
  hpcx/ompi/                  # OpenMPI prefix (OPAL_PREFIX)
  share/trtllm-tools/         # Build version marker
```

## Usage

```bash
# Run the server
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --http-port=8000 \
  --grpc-port=8001 \
  --metrics-port=8002

# Check it works
./result-triton-server/bin/tritonserver --help

# With the python backend
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./result-triton-python-backend/backends

# With the ONNX Runtime backend
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./result-triton-onnxruntime-backend/backends

# With the TensorRT backend
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./result-triton-tensorrt-backend/backends

# With the TensorRT-LLM backend (requires LD_LIBRARY_PATH for bundled libs)
LD_LIBRARY_PATH=./result-triton-tensorrtllm-backend/lib \
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./result-triton-tensorrtllm-backend/backends

# With multiple backends (symlink all into a combined directory)
mkdir -p ./backends
ln -s $(readlink -f ./result-triton-python-backend/backends/python) ./backends/python
ln -s $(readlink -f ./result-triton-onnxruntime-backend/backends/onnxruntime) ./backends/onnxruntime
ln -s $(readlink -f ./result-triton-tensorrt-backend/backends/tensorrt) ./backends/tensorrt
ln -s $(readlink -f ./result-triton-tensorrtllm-backend/backends/tensorrtllm) ./backends/tensorrtllm
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./backends
```

In the consuming runtime repo (triton-runtime), `triton-setup-backends` automates this
symlink assembly at `flox activate` time. It builds a unified backend directory under
`$FLOX_ENV_CACHE/backends/` by combining package-provided backends (Tier 1, from the Flox
profile) with repo-local Python backends (Tier 2, with automatic stub injection from the
python backend package). Similarly, `triton-setup-models` assembles a model directory
under `$FLOX_ENV_CACHE/models/` from Nix-store model packages (Tier 1) and repo-local
models (Tier 2), expanding `config.pbtxt.template` token placeholders at activation time.

## Building Custom Backends

The build output includes everything needed to develop custom Triton backends:
- Headers in `include/triton/backend/` and `include/triton/common/`
- CMake integration via `find_package(TritonBackend)` and `find_package(TritonCommon)`
- Stub library at `lib/stubs/libtritonserver.so` for linking without the full runtime

Point your backend's CMake at the build output:

```bash
cmake -DCMAKE_PREFIX_PATH=./result-triton-server/lib/cmake ...
```

## What's Included

| Feature | Status |
|---------|--------|
| HTTP endpoint | Enabled |
| gRPC endpoint | Enabled |
| GPU support (CUDA) | Enabled |
| Logging | Enabled |
| Statistics | Enabled |
| CPU Metrics | Enabled |
| GPU Metrics | Disabled (requires DCGM) |
| Model Ensembles | Enabled |
| Cloud storage (GCS/S3/Azure) | Disabled |
| Tracing | Disabled |

### CUDA Architectures

Built for: Ampere (sm_80, sm_86), Ada Lovelace (sm_89), Hopper (sm_90).

Newer GPUs (Blackwell sm_100+) work via PTX JIT compilation.

## Build Versioning

6 packages embed a version marker at `$out/share/<pname>/flox-build-version-<N>`
containing the build number, git revision, and a changelog: triton-server,
triton-python-backend, triton-onnxruntime-backend, triton-tensorrt-backend,
triton-tensorrtllm-backend, and trtllm-tools (wrapper only). The 4 trtllm-tools
sub-packages and the 2 build deps (onnxruntime-cuda, tensorrt-cuda) do not get markers.

Two packages (triton-server and triton-tensorrtllm-backend) append the git rev short hash
to their Nix `version` attribute (e.g., `2.66.0+c279dda`) so that successive builds
produce distinct store paths in the Flox catalog. The remaining packages use plain
`2.66.0`.

Version metadata is stored in `build-meta/<package>.json` and read by the Nix
expressions at eval time. Before each `flox build` or `flox publish`, update the JSON
with the current git rev count and a description of what changed, then commit.

```bash
# Check current build version
cat result-triton-server/share/triton-server/flox-build-version-*

# Inspect a published store path
cat /nix/store/...-triton-server-2.66.0/share/triton-server/flox-build-version-*
```

Marker contents:

```
build-version: 13
upstream-version: 2.66.0
upstream-tag: r26.02
git-rev: 82b501c69e77d9de40a7623ba8cdd2b603347f4c
git-rev-short: 82b501c
force-increment: 0
changelog: Fix triton-setup-backends: replace compgen with glob loop, remove stray local.
```

See `CLAUDE.md` for the full pre-build workflow.

## Build Details

The Nix expression at `.flox/pkgs/triton-server.nix` pre-fetches 12 GitHub
repositories and patches Triton's CMake build to work in Nix's sandboxed (no-network)
environment. Key adaptations:

- All `FetchContent` and `ExternalProject` git clones replaced with pre-fetched sources
- `gcc14Stdenv` used for CUDA 12.8 compatibility (default gcc15 is unsupported)
- Python wheel build uses `--no-isolation` with loosened dependency version pins
- `/etc/os-release` references stubbed (doesn't exist in Nix sandbox)
- `lib64` paths normalized to `lib` (GNUInstallDirs x86_64 default vs Triton expectation)
- Tests disabled (they require network access to fetch googletest)

The python backend expression at `.flox/pkgs/triton-python-backend.nix` follows the
same pattern but pre-fetches 7 sources instead of 12. Four are shared with the server
(core, common, backend, pybind11); the python backend additionally needs dlpack v0.8
and a Boost 1.80.0 tarball. Boost is fetched via `TRITON_BOOST_URL=file://` redirect
because the upstream CMake uses `ExternalProject` (not `FetchContent`) for it. The same
sandbox adaptations apply: `/etc/os-release` stub, test disabling, and `lib64` merge.

The ONNX Runtime backend is split into two expressions:

- **`.flox/pkgs/onnxruntime-cuda.nix`** — Builds ONNX Runtime 1.24.2 as a C++ shared
  library with CUDA support. Uses a standalone nixpkgs-pin pattern (not callPackage)
  because it overrides `nixpkgs.onnxruntime` with a specific nixpkgs revision and CUDA
  12.9 overlay. Multi-arch build (sm_80/86/89/90). This is the slow build (~1 hr) that
  gets cached independently.

- **`.flox/pkgs/triton-onnxruntime-backend.nix`** — Builds the Triton backend shim that
  links against the pre-built ORT library. Uses the same callPackage/sandbox pattern as
  the python backend. Pre-fetches 4 repos (onnxruntime_backend + core/common/backend
  shared with server and python backend). Fast build (~5 min). Requires `CUDA_ARCH_LIST`
  and `CUDAARCHS` env vars (same as server build) to override the backend repo's default
  `define.cuda_architectures.cmake` which includes `100f`/`120f` — unsupported by nvcc
  12.8.

## TensorRT Backend

The TensorRT backend follows the same two-expression architecture as the ORT backend:

- **`.flox/pkgs/tensorrt-cuda.nix`** — Provides the TensorRT SDK via `cudaPackages.tensorrt`
  from nixpkgs. Uses the standalone nixpkgs-pin pattern (same as `onnxruntime-cuda.nix`).
  TensorRT is a multi-output derivation — use `trt.include` and `trt.lib` (not bare `trt`).
  Fast build (pre-built SDK, no compilation).

- **`.flox/pkgs/triton-tensorrt-backend.nix`** — Builds the Triton backend shim (~2 min).
  Uses the same callPackage/sandbox pattern as the other backends: `/etc/os-release` stub,
  tests disabled, pre-fetched repos. Links against the TRT SDK from `tensorrt-cuda.nix`.
  RPATH is patched to reference the TRT lib store path.

Pre-fetches 4 repos (tensorrt_backend + core/common/backend shared with server and other backends).

## TensorRT-LLM Backend (NGC Extraction)

The TRT-LLM backend is fundamentally different from all other backends — it is **not built
from source**. TensorRT-LLM cannot be feasibly built via Nix due to its 63 GB build footprint,
proprietary components, and tight coupling with a custom NVIDIA PyTorch build.

Instead, pre-built binaries are extracted from the NGC container
`nvcr.io/nvidia/tritonserver:26.02-trtllm-python-py3` (~16 GB), packaged into a tarball
(2.7 GB compressed, 3.9 GB uncompressed), and hosted on GitHub Releases.

The Nix expression (`triton-tensorrtllm-backend.nix`) uses `fetchurl` to download the bundle
and `patchelf` to fix RPATHs — no cmake, no source compilation.

**Bundle contents:**
- `backends/tensorrtllm/libtriton_tensorrtllm.so` — Backend shared library (757 KB)
- `backends/tensorrtllm/trtllmExecutorWorker` — TRT-LLM executor process (73 MB)
- `lib/` — 40+ runtime shared libraries: `libtensorrt_llm.so`, `libnvinfer_plugin_tensorrt_llm.so`,
  NCCL, OpenMPI, CUDA 13.x libs (`libcublas.so.13`, `libcudart.so.13`), `libudev`, `libcap`,
  `libstdc++`
- `hpcx/ompi/` — OpenMPI prefix (share/openmpi/ help files, lib/ MCA modules, etc/ config).
  Required at runtime for `MPI_Init_thread` — the on-activate hook sets `OPAL_PREFIX` and
  prepends `hpcx/ompi/lib` to `LD_LIBRARY_PATH`.

**RPATH patching:**
- Backend `.so` and executor worker: `$ORIGIN/../lib` (finds libs in sibling `lib/` dir)
- Runtime libs: `$ORIGIN` (find each other in the same directory)

**CUDA version coexistence:** The bundled CUDA 13.x libs have different SONAMEs from the
system's CUDA 12.x libs (`libcublas.so.13` vs `libcublas.so.12`), so they load without
conflict. The container's `libnvinfer.so.10.13.3` also doesn't conflict with the TRT
backend's `10.14.1.48` (separate RPATHs).

**Model conversion note:** Converting HuggingFace models to TRT-LLM engine format requires
the `tensorrt_llm` Python package. The `trtllm-tools` package (below) provides a
self-contained Python 3.12 environment for this. Serving TRT-LLM engines is handled by
this backend; conversion is a separate concern.

## TRT-LLM Model Conversion Tools

The `trtllm-tools` package provides a standalone Python 3.12 environment for converting
HuggingFace models to TRT-LLM engine format. Like the TRT-LLM backend, these tools are
extracted from the NGC container — not built from source.

**Why a separate package?** The runtime environment uses Python 3.13, but TensorRT-LLM's
conversion tools require Python 3.12 with a custom NVIDIA PyTorch build. The tools package
is consumed by a separate Flox environment
([triton-trtllm-tools](../../triton-trtllm-tools/)), not the triton-runtime environment.

### 5-Way Split Architecture

Each sub-package must stay under the 5 GB Flox catalog NAR upload limit. The wrapper
package references the four sub-packages by Nix store path via `@placeholder@` tokens
that are substituted during the build.

| Sub-package | Nix expression | Size | Contents |
|-------------|----------------|------|----------|
| `trtllm-tools-libs-cuda` | `trtllm-tools-libs-cuda.nix` | 2.9 GB | CUDA 13, cuDNN 9.14, NCCL, OpenMPI, misc native `.so` |
| `trtllm-tools-libs-ml` | `trtllm-tools-libs-ml.nix` | 3.5 GB | TensorRT 10.13, MKL, TBB |
| `trtllm-tools-python` | `trtllm-tools-python.nix` | 4.4 GB | Python 3.12 interpreter + stdlib + ~290 dist-packages (excluding torch/tensorrt_llm) |
| `trtllm-tools-engine` | `trtllm-tools-engine.nix` | 4.2 GB | PyTorch 2.9.0a0 + tensorrt_llm 1.1.0 + torchvision |
| `trtllm-tools` | `trtllm-tools.nix` | 244 MB | Wrapper scripts + trtexec + `cuda/` + `hpcx/ompi/` |

All five packages share the same `fetchurl` definitions via `trtllm-tools-parts.nix`,
ensuring the ~8.2 GB compressed source bundle (split into 5 tarball parts on GitHub
Release [v26.02-tools](https://github.com/barstoolbluz/build-triton-server/releases/tag/v26.02-tools))
is downloaded and cached once.

### Available Tools

- `trtllm-build` — HuggingFace → TRT-LLM engine conversion
- `trtllm-bench` — Benchmarking
- `trtllm-eval` — Evaluation
- `trtllm-prune` — Model pruning
- `trtllm-refit` — Engine refitting
- `trtllm-serve` — TRT-LLM serving (standalone)
- `trtllm-llmapi-launch` — LLM API launcher
- `trtexec` — TensorRT engine builder/profiler

### Technical Notes

- **`@placeholder@` pattern**: Wrapper scripts use `@libs_cuda@`, `@libs_ml@`, etc. as
  tokens, replaced by `substituteInPlace` with Nix store paths during the build. This
  avoids Nix's `''${` escaping issues in heredoc-heavy shell scripts.
- **DT_RPATH → DT_RUNPATH**: Some `.so` files in the NGC container use `DT_RPATH` which
  takes precedence over `LD_LIBRARY_PATH`. The build patches these to `DT_RUNPATH` so the
  wrapper's `LD_LIBRARY_PATH` works correctly.
- **nullglob gotcha**: The wrapper scripts set `shopt -s nullglob` to handle globs that
  expand to nothing — Nix's bash environment doesn't set this by default.

## Nix Build Parallelism

The build spawns parallel cmake sub-builds. If you run out of memory, adjust
`/etc/nix/flox.conf`:

```
max-jobs = 4
cores = 2
```

`max-jobs` = concurrent derivations, `cores` = threads per derivation.

## Upgrading

To build a different Triton version:

1. Edit `.flox/pkgs/triton-server.nix`, `.flox/pkgs/triton-python-backend.nix`,
   `.flox/pkgs/triton-onnxruntime-backend.nix`, and `.flox/pkgs/triton-tensorrt-backend.nix`
2. Update `version` and `tag` at the top of all four files
3. Clear all `fetchFromGitHub` `hash` fields (set to `""`)
4. Run `flox build` repeatedly - each failure prints the correct hash
5. Fix any new build errors (new deps, changed cmake structure, etc.)

All four source-built expressions share the same `tag`/`version` and 3 of the same source
repos (core, common, backend), so they should always be upgraded together. The ORT library
version in `onnxruntime-cuda.nix` and the TRT SDK version in `tensorrt-cuda.nix` may also
need updating to match what the new Triton release expects.

For the TRT-LLM backend (`triton-tensorrtllm-backend.nix`), extract a new bundle from the
corresponding NGC container for the new Triton release, re-upload to GitHub Releases, and
update the `fetchurl` hash.

For the TRT-LLM tools (`trtllm-tools*.nix`), extract a new tools bundle from the same NGC
container, split into parts for GitHub Releases (`split -b 2000000000`), upload as a new
release tag (e.g., `v26.XX-tools`), and update all `fetchurl` hashes in
`trtllm-tools-parts.nix`. All five sub-packages share the same tarball parts, so only one
set of hashes needs updating.

See `CLAUDE.md` for detailed notes on every sandbox challenge encountered.

## Backends Not Built Here

Not every Triton backend requires a custom Nix build. The **vLLM backend** is pure
Python and needs no compilation — its engine (`vllm` v0.15.1) is available directly
from nixpkgs as `flox-cuda/python3Packages.vllm`. The backend source files (from
[triton-inference-server/vllm_backend](https://github.com/triton-inference-server/vllm_backend)
r26.02) are checked into the runtime repo at `backends/vllm/` as plain `.py` files.

If nixpkgs stops shipping a compatible vLLM version in the future, a build expression
would need to be added here following the same patterns as the other backends.

## Verified Store Paths

Current build outputs (for use in `store-path` references from consuming environments):

```
triton-server:              /nix/store/p7yl6mn4njkr1ax5b18f1wxckhjsd71x-triton-server-2.66.0+c279dda
triton-python-backend:      /nix/store/yhk1sv3ycny5k27nyfimsa4pb9xdin9y-triton-python-backend-2.66.0
onnxruntime-cuda:           /nix/store/3hys619h5k6bdsp6c2jf2r378q63h354-onnxruntime-cuda-1.24.2
triton-onnxruntime-backend: /nix/store/x7wsykzn8xrwn1vrf6a7h6k1193i5jcd-triton-onnxruntime-backend-2.66.0
triton-tensorrt-backend:    /nix/store/alb9fcxjq0pckb2c6dq8k5994yb5gj88-triton-tensorrt-backend-2.66.0
triton-tensorrtllm-backend: /nix/store/5w8yffb35ir2qp8vx1i73c4qjxbbg0wg-triton-tensorrtllm-backend-2.66.0+c279dda
trtllm-tools-libs-cuda:     /nix/store/bi9nmrmqpapwgz97m13q3hz39lgg77hj-trtllm-tools-libs-cuda-2.66.0
trtllm-tools-libs-ml:       /nix/store/jz4hiz38vnly47dw2fkfmaw4ygpsiw74-trtllm-tools-libs-ml-2.66.0
trtllm-tools-python:        /nix/store/02h0m6qc5yqk3bdpghy5jhfl29z5rjfm-trtllm-tools-python-2.66.0
trtllm-tools-engine:        /nix/store/3bl0l898dlinqnksgq6c22h1p8pq9hcw-trtllm-tools-engine-2.66.0
trtllm-tools:               /nix/store/03xgka0z5ikhhi0rvny9rl2qqi8pc9j7-trtllm-tools-2.66.0
```

All packages are published to the `flox` Flox catalog via `pkg-path` references.
The `store-path` references above are for debugging and direct testing only.

## License

Triton Inference Server is licensed under BSD-3-Clause by NVIDIA Corporation.
