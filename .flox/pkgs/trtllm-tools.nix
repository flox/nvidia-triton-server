# TRT-LLM model conversion tools for NVIDIA TensorRT-LLM
#
# Self-contained Python 3.12 environment with tensorrt_llm 1.1.0, PyTorch 2.9.0a0,
# and all dependencies needed for HuggingFace → TRT-LLM engine conversion.
#
# Extracted from NGC container nvcr.io/nvidia/tritonserver:26.02-trtllm-python-py3
# because tensorrt_llm requires Python 3.12 and custom NVIDIA PyTorch (incompatible
# with triton-runtime's Python 3.13 environment).
#
# Bundle includes:
#   bin/           - trtllm-build, trtllm-bench, trtllm-eval, trtllm-prune,
#                    trtllm-refit, trtllm-serve, trtexec, trtllm-llmapi-launch
#   python/        - Python 3.12 interpreter + stdlib + dist-packages
#   lib/           - CUDA 13, cuDNN 9.14, TRT 10.13, MKL, NCCL native libs
#   cuda/          - CUDA home structure (bin/ symlinks to ../bin/cuda/, nvvm, lib64)
#   hpcx/ompi/     - OpenMPI prefix for MPI support (OPAL_PREFIX)
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "trtllm-tools";
  version = "2.66.0";
  tag = "r26.02";

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/trtllm-tools.json);
  buildVersion = buildMeta.build_version;

  # Bundle is split into parts to stay under GitHub Releases' 2 GB file size limit.
  # Parts are concatenated during unpackPhase to reconstruct the original tarball.
  bundlePart0 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-bundle-26.02.tar.gz.part0";
    hash = "sha256-ceOeiaV3nS0PJ5nMZt/r4881YDbDaXJerWF7Jy/Rok4=";
  };
  bundlePart1 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-bundle-26.02.tar.gz.part1";
    hash = "sha256-SHiX44YM8PwtPw0iqoe8gTuejPvTmPET8eDJU8E131o=";
  };
  bundlePart2 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-bundle-26.02.tar.gz.part2";
    hash = "sha256-TQEqSG6AjQa54OfZWYKO5BvsIKs8rKZ5l+0/pQxsCWg=";
  };
  bundlePart3 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-bundle-26.02.tar.gz.part3";
    hash = "sha256-IOfg1nYoiX1bwOdUMQt5VHqxe2ye6myCPa7gBm/6Nw0=";
  };
  bundlePart4 = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-bundle-26.02.tar.gz.part4";
    hash = "sha256-ApZuFrid/lQuUXI/s+45GlTfJN9ARDJKCQce+0tIFPg=";
  };

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = bundlePart0;

  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    cat ${bundlePart0} ${bundlePart1} ${bundlePart2} ${bundlePart3} ${bundlePart4} | tar -xzf - -C source
    cd source
  '';

  nativeBuildInputs = [ pkgs.patchelf ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # -- Wrapper scripts --
    mkdir -p $out/bin
    cp bin/trtllm-build bin/trtllm-bench bin/trtllm-eval \
       bin/trtllm-prune bin/trtllm-refit bin/trtllm-serve \
       bin/trtexec bin/trtllm-llmapi-launch \
       $out/bin/
    cp bin/.trtexec.real $out/bin/

    # -- CUDA compiler tools --
    if [ -d bin/cuda ]; then
      mkdir -p $out/bin/cuda
      cp -P bin/cuda/* $out/bin/cuda/
    fi

    # -- Python interpreter + stdlib --
    mkdir -p $out/python/bin
    cp python/bin/python3.12 $out/python/bin/
    cp -a python/lib $out/python/
    cp -a python/dist-packages $out/python/

    # Fix broken symlinks from container layout
    # config dir libpython points to ../../x86_64-linux-gnu/ (doesn't exist)
    rm -f $out/python/lib/python3.12/config-3.12-x86_64-linux-gnu/libpython3.12.so
    ln -sf ../../../../lib/libpython3.12.so \
      $out/python/lib/python3.12/config-3.12-x86_64-linux-gnu/libpython3.12.so
    # sitecustomize.py points to /etc/python3.12/ (container path)
    rm -f $out/python/lib/python3.12/sitecustomize.py

    # -- Native shared libraries --
    mkdir -p $out/lib
    cp -P lib/*.so lib/*.so.* $out/lib/ 2>/dev/null || true
    # nvvm libdevice (needed for runtime compilation)
    if [ -d lib/nvvm ]; then
      cp -a lib/nvvm $out/lib/
    fi

    # -- CUDA home structure (for deep_gemm CUDA_HOME) --
    if [ -d cuda ]; then
      mkdir -p $out/cuda/bin
      cp -P cuda/bin/* $out/cuda/bin/ 2>/dev/null || true
      # Re-create symlinks relative to $out
      if [ -L cuda/nvvm ]; then
        ln -sf ../lib/nvvm $out/cuda/nvvm
      fi
      if [ -L cuda/lib64 ]; then
        ln -sf ../lib $out/cuda/lib64
      fi
    fi

    # -- HPC-X OpenMPI prefix (for MPI/OPAL_PREFIX) --
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
    # ---- lib/*.so: self-relative ----
    for f in $out/lib/*.so $out/lib/*.so.*; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
    done

    # ---- python/bin/python3.12 ----
    patchelf --set-rpath '$ORIGIN/../../lib' \
      $out/python/bin/python3.12 2>/dev/null || true

    # ---- bin/.trtexec.real ----
    patchelf --set-rpath '$ORIGIN/../lib' \
      $out/bin/.trtexec.real 2>/dev/null || true

    # ---- CUDA compiler tools ----
    for f in $out/bin/cuda/*; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN/../../lib' "$f" 2>/dev/null || true
    done

    # ---- python/lib/python3.12/lib-dynload/*.so ----
    for f in $out/python/lib/python3.12/lib-dynload/*.so; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN/../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- tensorrt_llm/libs/*.so ----
    for f in $out/python/dist-packages/tensorrt_llm/libs/*.so; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../../lib' "$f" 2>/dev/null || true
    done
    # tensorrt_llm/libs/nixl/*.so
    for f in $out/python/dist-packages/tensorrt_llm/libs/nixl/*.so \
             $out/python/dist-packages/tensorrt_llm/libs/nixl/plugins/*.so; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- torch/lib/*.so ----
    for f in $out/python/dist-packages/torch/lib/*.so*; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- tensorrt/tensorrt.so ----
    if [ -f "$out/python/dist-packages/tensorrt/tensorrt.so" ]; then
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' \
        "$out/python/dist-packages/tensorrt/tensorrt.so" 2>/dev/null || true
    fi

    # ---- flash_attn *.so ----
    find $out/python/dist-packages/flash_attn -name '*.so' 2>/dev/null | while read f; do
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- triton *.so ----
    find $out/python/dist-packages/triton -name '*.so' 2>/dev/null | while read f; do
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- pydantic_core *.so ----
    for f in $out/python/dist-packages/pydantic_core/*.so; do
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$f" 2>/dev/null || true
    done

    # ---- scipy.libs *.so ----
    for f in $out/python/dist-packages/scipy.libs/*.so*; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN:$ORIGIN/../../../../lib' "$f" 2>/dev/null || true
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
