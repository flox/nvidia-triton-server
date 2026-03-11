# TensorRT-LLM backend for NVIDIA Triton Inference Server
#
# Extracted from NGC container nvcr.io/nvidia/tritonserver:26.02-trtllm-python-py3
# because TensorRT-LLM cannot be feasibly built from source via Nix (63 GB build
# footprint, proprietary components, custom NVIDIA PyTorch coupling).
#
# The bundle contains:
#   backends/tensorrtllm/  - libtriton_tensorrtllm.so + trtllmExecutorWorker
#   lib/                   - TRT-LLM runtime libs, CUDA 13.x libs, NCCL, OpenMPI
#
# RPATHs are patched so binaries find their deps via $ORIGIN/../lib.
# CUDA 13.x libs from the container coexist with the system's CUDA 12.x libs
# (different SONAMEs: libcublas.so.13 vs libcublas.so.12).
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "triton-tensorrtllm-backend";
  version = "2.66.0";
  tag = "r26.02";

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-tensorrtllm-backend.json);
  buildVersion = buildMeta.build_version;

  bundle = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02/trtllm-backend-bundle-26.02.tar.gz";
    hash = "sha256-uwT05SXWs2roBg0SyH4SSxweitXe5FiXrrNYGOAZUzU=";
  };

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = bundle;

  # The tarball has no top-level directory; unpack into build dir
  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    tar -xzf $src -C source
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
  '';

  dontStrip = true;

  meta = with pkgs.lib; {
    description = "TensorRT-LLM backend for NVIDIA Triton Inference Server";
    homepage = "https://github.com/triton-inference-server/tensorrtllm_backend";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
