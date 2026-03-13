# TRT-LLM model conversion tools for NVIDIA TensorRT-LLM
#
# Top-level wrapper package (~244 MB) that generates wrapper scripts
# referencing four sub-packages by Nix store path:
#   - trtllm-tools-libs-cuda (~2.9 GB) — CUDA 13, cuDNN 9.14, NCCL, MPI, misc
#   - trtllm-tools-libs-ml   (~3.5 GB) — TensorRT 10.13, MKL, TBB
#   - trtllm-tools-python    (~4.3 GB) — Python 3.12 + stdlib + most dist-packages
#   - trtllm-tools-engine    (~4.1 GB) — PyTorch 2.9.0a0 + tensorrt_llm 1.1.0
#
# Each sub-package stays under the 5 GB Flox catalog NAR upload limit.
#
# This package contains only:
#   bin/           - wrapper scripts, .trtexec.real, cuda/ compiler tools
#   cuda/          - CUDA home structure (deep_gemm needs CUDA_HOME)
#   hpcx/ompi/     - OpenMPI prefix for MPI support (OPAL_PREFIX)
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "trtllm-tools";
  version = "2.66.0-29a0e7c";
  tag = "r26.02";

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/trtllm-tools.json);
  buildVersion = buildMeta.build_version;

  parts = import ./trtllm-tools-parts.nix { inherit pkgs; };

  # Sub-packages (each under 5 GB NAR)
  libsCuda  = import ./trtllm-tools-libs-cuda.nix { inherit pkgs; };
  libsMl    = import ./trtllm-tools-libs-ml.nix { inherit pkgs; };
  pythonPkg = import ./trtllm-tools-python.nix { inherit pkgs; };
  enginePkg = import ./trtllm-tools-engine.nix { inherit pkgs; };

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = parts.bundlePart0;

  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    ${parts.catParts parts} | tar -xzf - -C source \
      bin/ hpcx/
    cd source
  '';

  nativeBuildInputs = [ pkgs.patchelf ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # -- trtexec binary --
    cp bin/.trtexec.real $out/bin/

    # -- CUDA compiler tools --
    if [ -d bin/cuda ]; then
      mkdir -p $out/bin/cuda
      cp -P bin/cuda/* $out/bin/cuda/
    fi

    # -- CUDA home structure (for deep_gemm CUDA_HOME + flashinfer JIT) --
    # bin/cuda/ has the compiler tools; cuda/bin → ../bin/cuda avoids duplication
    mkdir -p $out/cuda
    ln -sf ../bin/cuda $out/cuda/bin
    ln -sf ${libsCuda}/include $out/cuda/include
    ln -sf ${libsCuda}/lib/nvvm $out/cuda/nvvm
    ln -sf ${libsCuda}/lib $out/cuda/lib64

    # -- HPC-X OpenMPI prefix (for MPI/OPAL_PREFIX) --
    if [ -d hpcx ]; then
      cp -a hpcx $out/
    fi

    # -- Generate Python tool wrappers --
    # Each wrapper sets up the environment using hardcoded store paths
    # to the sub-packages, then invokes the appropriate entry point.

    cat > $out/bin/trtllm-build << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.build import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-build

    cat > $out/bin/trtllm-bench << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.bench import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-bench

    cat > $out/bin/trtllm-eval << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.eval import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-eval

    cat > $out/bin/trtllm-prune << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.prune import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-prune

    cat > $out/bin/trtllm-refit << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.refit import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-refit

    cat > $out/bin/trtllm-serve << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" -c "
from tensorrt_llm.commands.serve import main
import sys; sys.exit(main())
" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtllm-serve

    # -- python3 wrapper (exposes bundled Python 3.12 with tensorrt_llm + torch) --
    cat > $out/bin/python3 << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$(dirname "$SCRIPT_DIR")"
export PYTHONHOME="@pythonPkg@/python"
export PYTHONPATH="@pythonPkg@/python/dist-packages:@enginePkg@/dist-packages"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib:@enginePkg@/dist-packages/tensorrt_llm/libs''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SCRIPT_DIR:$SCRIPT_DIR/cuda:@pythonPkg@/python/bin''${PATH:+:$PATH}"
export OPAL_PREFIX="$PKG_DIR/hpcx/ompi"
export CUDA_HOME="$PKG_DIR/cuda"
export CPATH="@libsCuda@/include/python3.12:@libsCuda@/include''${CPATH:+:$CPATH}"
export TRITON_PTXAS_PATH="$SCRIPT_DIR/cuda/ptxas"
exec "@pythonPkg@/python/bin/python3.12" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/python3
    ln -sf python3 $out/bin/python3.12

    # -- trtexec wrapper --
    cat > $out/bin/trtexec << 'TRTLLM_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
export LD_LIBRARY_PATH="@libsCuda@/lib:@libsMl@/lib:@enginePkg@/dist-packages/torch/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$SCRIPT_DIR/.trtexec.real" "$@"
TRTLLM_WRAPPER_EOF
    chmod +x $out/bin/trtexec

    # -- trtllm-llmapi-launch --
    # Copy from tarball, then patch environment block to use store paths
    cp bin/trtllm-llmapi-launch $out/bin/
    chmod +w $out/bin/trtllm-llmapi-launch

    # -- Replace placeholder tokens with Nix store paths --
    # The heredoc wrappers use @token@ placeholders that Nix can't interpolate
    # inside single-quoted heredocs.  substituteInPlace resolves them.
    for f in $out/bin/trtllm-build $out/bin/trtllm-bench $out/bin/trtllm-eval \
             $out/bin/trtllm-prune $out/bin/trtllm-refit $out/bin/trtllm-serve \
             $out/bin/python3; do
      substituteInPlace "$f" \
        --replace-fail '@pythonPkg@' '${pythonPkg}' \
        --replace-fail '@enginePkg@' '${enginePkg}' \
        --replace-fail '@libsCuda@' '${libsCuda}' \
        --replace-fail '@libsMl@' '${libsMl}'
    done

    # trtexec only needs libs and engine (no Python)
    substituteInPlace $out/bin/trtexec \
      --replace-fail '@enginePkg@' '${enginePkg}' \
      --replace-fail '@libsCuda@' '${libsCuda}' \
      --replace-fail '@libsMl@' '${libsMl}'

    # Patch trtllm-llmapi-launch environment block (replace BUNDLE_DIR references)
    substituteInPlace $out/bin/trtllm-llmapi-launch \
      --replace-fail 'BUNDLE_DIR="$(dirname "$SCRIPT_DIR")"' \
                     'PKG_DIR="$(dirname "$SCRIPT_DIR")"' \
      --replace-fail 'PYTHONHOME="$BUNDLE_DIR/python"' \
                     'PYTHONHOME="${pythonPkg}/python"' \
      --replace-fail 'PYTHONPATH="$BUNDLE_DIR/python/dist-packages"' \
                     'PYTHONPATH="${pythonPkg}/python/dist-packages:${enginePkg}/dist-packages"' \
      --replace-fail 'LD_LIBRARY_PATH="$BUNDLE_DIR/lib:$BUNDLE_DIR/python/dist-packages/torch/lib:$BUNDLE_DIR/python/dist-packages/tensorrt_llm/libs' \
                     'LD_LIBRARY_PATH="${libsCuda}/lib:${libsMl}/lib:${enginePkg}/dist-packages/torch/lib:${enginePkg}/dist-packages/tensorrt_llm/libs' \
      --replace-fail 'PATH="$BUNDLE_DIR/bin:$BUNDLE_DIR/python/bin' \
                     'PATH="$SCRIPT_DIR:${pythonPkg}/python/bin' \
      --replace-fail '"$BUNDLE_DIR/hpcx/ompi"' \
                     '"$PKG_DIR/hpcx/ompi"' \
      --replace-fail '"$BUNDLE_DIR/cuda"' \
                     '"$PKG_DIR/cuda"'

    # -- Version marker --
    mkdir -p $out/share/${pname}
    cat > $out/share/${pname}/flox-build-version-${toString buildVersion} <<'MARKER'
build-version: ${toString buildVersion}
upstream-version: ${version}
upstream-tag: ${tag}
git-rev: ${buildMeta.git_rev}
git-rev-short: ${buildMeta.git_rev_short}
force-increment: ${toString buildMeta.force_increment}
changelog: ${buildMeta.changelog}
MARKER

    runHook postInstall
  '';

  postFixup = ''
    # ---- bin/.trtexec.real ----
    patchelf --set-rpath '${libsCuda}/lib:${libsMl}/lib' \
      $out/bin/.trtexec.real 2>/dev/null || true

    # ---- CUDA compiler tools ----
    for f in $out/bin/cuda/*; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '${libsCuda}/lib' "$f" 2>/dev/null || true
    done

    # ---- hpcx/ompi libraries ----
    find $out/hpcx -name '*.so' -o -name '*.so.*' 2>/dev/null | while read f; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
    done
  '';

  dontStrip = true;

  meta = with pkgs.lib; {
    description = "TRT-LLM model conversion tools (trtllm-build, trtexec, etc.)";
    homepage = "https://github.com/NVIDIA/TensorRT-LLM";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
