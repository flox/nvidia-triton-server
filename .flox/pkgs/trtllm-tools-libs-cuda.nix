# trtllm-tools-libs-cuda: CUDA runtime + math libs + headers for TRT-LLM tools
#
# Contains: CUDA 13 (cudart, cublas, cufft, cusolver, cusparse, curand, nvrtc,
# nvJitLink, nvvm, npp), cuDNN 9.14, NCCL, MPI, UCX, and misc native libs.
# Also includes CUDA 13 toolkit headers (include/) for JIT compilation
# (flashinfer, deep_gemm, etc.).
# Excludes TensorRT and MKL (those are in trtllm-tools-libs-ml).
#
# ~2.9 GB uncompressed (under 5 GB catalog limit)
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "trtllm-tools-libs-cuda";
  version = "2.66.0-29a0e7c";
  tag = "r26.02";

  parts = import ./trtllm-tools-parts.nix { inherit pkgs; };

  # Real x86_64-linux pyconfig.h from NGC 26.02 container (Python 3.12).
  # The tarball's pyconfig.h is a Debian multiarch stub that does:
  #   #include <x86_64-linux-gnu/python3.12/pyconfig.h>
  # which doesn't resolve outside the container.  This is the actual target.
  pyconfig = ./pyconfig-3.12-x86_64-linux.h;

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/trtllm-tools-libs-cuda.json);
  buildVersion = buildMeta.build_version;

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = parts.bundlePart0;

  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    ${parts.catParts parts} | tar -xzf - -C source lib/
    # Remove TensorRT and MKL libs (those belong in trtllm-tools-libs-ml).
    # Cannot use tar --exclude with globs because Nix stdenv sets nullglob,
    # which silently removes unmatched glob arguments before tar sees them.
    cd source
    rm -f lib/libnvinfer* lib/libnvonnxparser* \
          lib/libmkl* lib/libtbb* lib/libtbbbind* lib/libtbbmalloc* \
          lib/libiomp* lib/libiompstubs*

    # Extract CUDA 13 toolkit headers (separate tarball, ~3.3 MB)
    tar -xzf ${parts.cudaInclude}
  '';

  nativeBuildInputs = [ pkgs.patchelf ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    cp -P lib/*.so lib/*.so.* $out/lib/ 2>/dev/null || true
    if [ -d lib/nvvm ]; then
      cp -a lib/nvvm $out/lib/
    fi

    # CUDA toolkit headers for JIT compilation
    if [ -d include ]; then
      cp -a include $out/
    fi

    # Python 3.12 dev headers for torch extension JIT (flashinfer)
    if [ -d python-include/python3.12 ]; then
      mkdir -p $out/include/python3.12
      cp -a python-include/python3.12/* $out/include/python3.12/
    fi
    # Fix Debian multiarch pyconfig.h redirect
    # The extracted pyconfig.h is a multiarch stub that does:
    #   #include <x86_64-linux-gnu/python3.12/pyconfig.h>
    # which requires /usr/include/ system paths from the NGC container.
    # Replace the stub with the real x86_64 pyconfig.h from the container.
    if [ -f $out/include/python3.12/pyconfig.h ]; then
      if grep -q 'x86_64-linux-gnu' $out/include/python3.12/pyconfig.h; then
        cp ${pyconfig} $out/include/python3.12/pyconfig.h
      fi
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

  postFixup = ''
    for f in $out/lib/*.so $out/lib/*.so.*; do
      [ -L "$f" ] && continue
      [ -f "$f" ] || continue
      patchelf --set-rpath '$ORIGIN' "$f" 2>/dev/null || true
    done
  '';

  dontStrip = true;

  meta = with pkgs.lib; {
    description = "CUDA runtime and math libraries for TRT-LLM tools";
    homepage = "https://github.com/NVIDIA/TensorRT-LLM";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
  };
}
