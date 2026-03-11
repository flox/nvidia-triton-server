# Triton Inference Server - Nix Build

Build NVIDIA Triton Inference Server v2.66.0 and its backends (Python, ONNX Runtime) from source using Flox/Nix.

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
```

Build output appears at `./result-triton-server/`, `./result-triton-python-backend/`,
`./result-onnxruntime-cuda/`, and `./result-triton-onnxruntime-backend/`.

## Build Output

```
result-triton-server/
  bin/
    tritonserver              # Main server binary (18 MB)
    triton-serve              # Server launcher script
    triton-preflight          # Pre-flight validation script
    triton-resolve-model      # Model provisioning script
    triton-setup-backends     # Backend directory assembler (activation-time)
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

# With multiple backends (symlink both into a combined directory)
mkdir -p ./backends
ln -s $(readlink -f ./result-triton-python-backend/backends/python) ./backends/python
ln -s $(readlink -f ./result-triton-onnxruntime-backend/backends/onnxruntime) ./backends/onnxruntime
./result-triton-server/bin/tritonserver \
  --model-repository=/path/to/models \
  --backend-directory=./backends
```

In the consuming runtime repo (triton-runtime), `triton-setup-backends` automates this
symlink assembly at `flox activate` time. It builds a unified backend directory under
`$FLOX_ENV_CACHE/backends/` by combining package-provided backends (Tier 1, from the Flox
profile) with repo-local Python backends (Tier 2, with automatic stub injection from the
python backend package).

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

Each publishable package embeds a version marker at
`$out/share/<pname>/flox-build-version-<N>` containing the build number, git revision,
and a changelog. This provides provenance tracking for every store path.

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

1. Edit `.flox/pkgs/triton-server.nix`, `.flox/pkgs/triton-python-backend.nix`, and
   `.flox/pkgs/triton-onnxruntime-backend.nix`
2. Update `version` and `tag` at the top of all three files
3. Clear all `fetchFromGitHub` `hash` fields (set to `""`)
4. Run `flox build` repeatedly - each failure prints the correct hash
5. Fix any new build errors (new deps, changed cmake structure, etc.)

All three expressions share the same `tag`/`version` and 3 of the same source repos
(core, common, backend), so they should always be upgraded together. The ORT library
version in `onnxruntime-cuda.nix` may also need updating to match what the new Triton
release expects.

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
triton-server:              /nix/store/383pyayhwglsv3ywgzlzaf3pd2i72xmq-triton-server-2.66.0
triton-python-backend:      /nix/store/yhk1sv3ycny5k27nyfimsa4pb9xdin9y-triton-python-backend-2.66.0
onnxruntime-cuda:           /nix/store/3hys619h5k6bdsp6c2jf2r378q63h354-onnxruntime-cuda-1.24.2
triton-onnxruntime-backend: /nix/store/x7wsykzn8xrwn1vrf6a7h6k1193i5jcd-triton-onnxruntime-backend-2.66.0
```

Consuming Flox environments reference these via `store-path` in their `manifest.toml`.

## License

Triton Inference Server is licensed under BSD-3-Clause by NVIDIA Corporation.
