# TensorRT-LLM backend for NVIDIA Triton Inference Server
#
# Extracted from NGC container nvcr.io/nvidia/tritonserver:26.02-trtllm-python-py3
# because TensorRT-LLM cannot be feasibly built from source via Nix (63 GB build
# footprint, proprietary components, custom NVIDIA PyTorch coupling).
#
# The bundle contains:
#   backends/tensorrtllm/  - libtriton_tensorrtllm.so + trtllmExecutorWorker
#   lib/                   - TRT-LLM runtime libs, CUDA 13.x libs, NCCL, OpenMPI
#   hpcx/                  - HPC-X OpenMPI prefix (help files, MCA modules, config)
#
# RPATHs are patched so binaries find their deps via $ORIGIN/../lib.
# CUDA 13.x libs from the container coexist with the system's CUDA 12.x libs
# (different SONAMEs: libcublas.so.13 vs libcublas.so.12).
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "triton-tensorrtllm-backend";
  tag = "r26.02";

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-tensorrtllm-backend.json);
  buildVersion = buildMeta.build_version;
  version = "2.66.0+${buildMeta.git_rev_short}";

  # Bundle is split into two parts to stay under GitHub Releases' 2 GB file size limit.
  # Parts are concatenated during unpackPhase to reconstruct the original tarball.
  bundlePart0 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02/trtllm-backend-bundle-26.02.tar.gz.part0";
    hash = "sha256-GuC1qCh9I5Z221PLajRWWQIlQYNXTwMV+ayJCysaPZQ=";
  };
  bundlePart1 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02/trtllm-backend-bundle-26.02.tar.gz.part1";
    hash = "sha256-3oEXvGqp79UjsI9lKDLaks7i/LcKMmBgEomXgXKxSw0=";
  };

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = bundlePart0;

  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    cat ${bundlePart0} ${bundlePart1} | tar -xzf - -C source
    cd source
  '';

  nativeBuildInputs = [ pkgs.patchelf ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # -- Backend files --
    mkdir -p $out/backends/tensorrtllm
    cp backends/tensorrtllm/libtriton_tensorrtllm.so $out/backends/tensorrtllm/
    cp backends/tensorrtllm/trtllmExecutorWorker $out/backends/tensorrtllm/

    # -- Runtime libs --
    mkdir -p $out/lib
    cp -P lib/*.so lib/*.so.* $out/lib/

    # -- HPC-X OpenMPI prefix (MPI runtime: help files, MCA modules) --
    if [ -d hpcx ]; then
      cp -a hpcx $out/
    fi

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

  # Patch RPATHs so binaries find bundled libs via $ORIGIN
  postFixup = ''
    patchelf --set-rpath '$ORIGIN/../lib' \
      $out/backends/tensorrtllm/libtriton_tensorrtllm.so

    patchelf --set-rpath '$ORIGIN/../lib' \
      $out/backends/tensorrtllm/trtllmExecutorWorker

    for f in $out/lib/*.so $out/lib/*.so.*; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
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
    description = "TensorRT-LLM backend for NVIDIA Triton Inference Server";
    homepage = "https://github.com/triton-inference-server/tensorrtllm_backend";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
