{ lib
, gcc14Stdenv
, fetchFromGitHub
, cmake
, ninja
, git
, pkg-config
, cudaPackages
, rapidjson
, protobuf
}:

let
  version = "2.66.0";
  tag = "r26.02";

  # ---------------------------------------------------------------------------
  # Build versioning — pre-computed in build-meta/*.json before each build
  # ---------------------------------------------------------------------------
  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-onnxruntime-backend.json);
  buildVersion = buildMeta.build_version;
  pname = "triton-onnxruntime-backend";

  ort = import ./onnxruntime-cuda.nix {};

  # ---------------------------------------------------------------------------
  # Pre-fetch sources (4 total — no pybind11/dlpack/boost needed, pure C++)
  # ---------------------------------------------------------------------------

  onnxrtBackendSrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "onnxruntime_backend";
    rev = tag;
    hash = "sha256-9dynI1lCbv9a1L73Xj7WoxC04OQqB/RIf6A0whjvd4k=";
  };

  coreSrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "core";
    rev = tag;
    hash = "sha256-DWFu/DKFDfnTi6+lEjagGP2GufbK2tjzSYRZR0kBTTg=";
  };

  commonSrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "common";
    rev = tag;
    hash = "sha256-9UbfrOEXhm+jdZCwqGSaQSu7JBK6KG+VLegaO1SoDQ8=";
  };

  backendSrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "backend";
    rev = tag;
    hash = "sha256-DTOtuMq1+hdlDGD4WF1+cA7yI7/i1cqyp+HUfI7q5bQ=";
  };

in

gcc14Stdenv.mkDerivation {
  inherit pname version;

  src = onnxrtBackendSrc;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    git
  ];

  buildInputs = [
    cudaPackages.cudatoolkit
    rapidjson
    protobuf
    ort
  ];

  cmakeFlags = [
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"

    "-DTRITON_COMMON_REPO_TAG=${tag}"
    "-DTRITON_CORE_REPO_TAG=${tag}"
    "-DTRITON_BACKEND_REPO_TAG=${tag}"

    "-DTRITON_ENABLE_GPU=ON"
    "-DTRITON_ENABLE_STATS=ON"
    "-DTRITON_ENABLE_ONNXRUNTIME_TENSORRT=OFF"
    "-DTRITON_ENABLE_ONNXRUNTIME_OPENVINO=OFF"

    "-DTRITON_ONNXRUNTIME_INCLUDE_PATHS=${ort}/include"
    "-DTRITON_ONNXRUNTIME_LIB_PATHS=${ort}/lib"

    "-DCUDAToolkit_ROOT=${cudaPackages.cudatoolkit}"
  ];

  preConfigure = ''
    # Create writable copies of triton sub-repos
    cp -r ${commonSrc} $TMPDIR/common-src
    chmod -R u+w $TMPDIR/common-src

    cp -r ${coreSrc} $TMPDIR/core-src
    chmod -R u+w $TMPDIR/core-src

    cp -r ${backendSrc} $TMPDIR/backend-src
    chmod -R u+w $TMPDIR/backend-src

    # Patch /etc/os-release in core (doesn't exist in Nix sandbox)
    substituteInPlace $TMPDIR/core-src/CMakeLists.txt \
      --replace-fail 'file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")' \
                     'set(DISTRO_ID_LIKE "")'

    # Disable tests in common and core (they fetch googletest from the internet)
    substituteInPlace $TMPDIR/common-src/src/CMakeLists.txt \
      --replace-fail 'add_subdirectory(test)' \
                     '# add_subdirectory(test)  # disabled: no network in sandbox'

    substituteInPlace $TMPDIR/core-src/src/CMakeLists.txt \
      --replace-fail 'add_subdirectory(test test)' \
                     '# add_subdirectory(test test)  # disabled: no network in sandbox'

    # Set FetchContent source dirs and CUDA architectures
    # (cmakeFlagsArray for $TMPDIR paths and unescaped semicolons)
    cmakeFlagsArray+=(
      "-DFETCHCONTENT_SOURCE_DIR_REPO-COMMON=$TMPDIR/common-src"
      "-DFETCHCONTENT_SOURCE_DIR_REPO-CORE=$TMPDIR/core-src"
      "-DFETCHCONTENT_SOURCE_DIR_REPO-BACKEND=$TMPDIR/backend-src"
      "-DCMAKE_CUDA_ARCHITECTURES=80;86;89;90"
    )

    export CUDA_HOME="${cudaPackages.cudatoolkit}"
    export CUDA_ARCH_LIST="80 86 89 90"
    export CUDAARCHS="80;86;89;90"
    export CUDAHOSTCXX="${gcc14Stdenv.cc}/bin/g++"
  '';

  postInstall = ''
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
  '';

  # Move lib64 contents to lib before fixupPhase
  preFixup = ''
    if [ -d "$out/lib64" ]; then
      cp -rn "$out/lib64/"* "$out/lib/" 2>/dev/null || true
      rm -rf "$out/lib64"
    fi
  '';

  doCheck = false;

  meta = with lib; {
    description = "ONNX Runtime backend for NVIDIA Triton Inference Server";
    homepage = "https://github.com/triton-inference-server/onnxruntime_backend";
    license = licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
}
