{ lib
, gcc14Stdenv
, fetchFromGitHub
, cmake
, ninja
, python3
, python3Packages
, git
, pkg-config
, cudaPackages
, openssl
, zlib
, libarchive
, rapidjson
, boost
, protobuf
, grpc
, re2
, libevent
, nlohmann_json
, curl
, gtest
, numactl
, libb64
}:

let
  tag = "r26.02";

  # ---------------------------------------------------------------------------
  # Build versioning — pre-computed in build-meta/*.json before each build
  # ---------------------------------------------------------------------------
  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-server.json);
  buildVersion = buildMeta.build_version;
  version = "2.66.0+${buildMeta.git_rev_short}";
  pname = "triton-server";

  buildPython = python3.withPackages (ps: [
    ps.setuptools ps.wheel ps.build ps.numpy ps.mypy
  ]);

  # ---------------------------------------------------------------------------
  # Pre-fetch Triton sub-repos
  # ---------------------------------------------------------------------------

  serverSrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "server";
    rev = tag;
    hash = "sha256-oXVEq9wDqLyHvzeoRWsUMxf16JFgWt1w5xpREDWj8Ck=";
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

  thirdPartySrc = fetchFromGitHub {
    owner = "triton-inference-server";
    repo = "third_party";
    rev = tag;
    hash = "sha256-gaoQcLRqDMf/FaqczWvuHy59K7LQ/J4KP3/qJf7U5mM=";
  };

  pybind11Src = fetchFromGitHub {
    owner = "pybind";
    repo = "pybind11";
    rev = "v2.13.1";
    hash = "sha256-sQUq39CmgsDEMfluKMrrnC5fio//pgExcyqJAE00UjU=";
  };

  # ---------------------------------------------------------------------------
  # Pre-fetch third-party dependencies (used by ExternalProject_Add)
  # ---------------------------------------------------------------------------

  grpcRepoSrc = fetchFromGitHub {
    owner = "grpc";
    repo = "grpc";
    rev = "v1.54.3";
    hash = "sha256-UdQrBTNNfpoFYN6O92aUMhZEdfZZ3hqLp4lJMPjy7tM=";
    fetchSubmodules = true;
  };

  libeventSrc = fetchFromGitHub {
    owner = "libevent";
    repo = "libevent";
    rev = "release-2.1.12-stable";
    hash = "sha256-M/OgLkgQs+LwGkqv5vu26vluntDAJX5ZsHjjMVM1BqU=";
  };

  prometheusCppSrc = fetchFromGitHub {
    owner = "jupp0r";
    repo = "prometheus-cpp";
    rev = "v1.0.1";
    hash = "sha256-F8paJhptEcOMtP0FCJ3ragC4kv7XSVPiZheM5UZChno=";
  };

  nlohmannJsonSrc = fetchFromGitHub {
    owner = "nlohmann";
    repo = "json";
    rev = "v3.11.3";
    hash = "sha256-7F0Jon+1oWL7uqet5i1IgHX0fUw/+z0QwEcA3zs5xHg=";
  };

  curlSrc = fetchFromGitHub {
    owner = "curl";
    repo = "curl";
    rev = "curl-7_86_0";
    hash = "sha256-EEBRMdJrDkFL9Ol00hobmLouUBwdLEZPUEetVjIjXno=";
  };

  crc32cSrc = fetchFromGitHub {
    owner = "google";
    repo = "crc32c";
    rev = "b9d6e825a1e6783195a6051639179152dac70b3b";
    hash = "sha256-8lylNeaKkGSOJVQcbSEpMxT1IFF1OsCAzpYVPrynxiQ=";
  };

in

gcc14Stdenv.mkDerivation {
  inherit pname version;

  src = serverSrc;

  nativeBuildInputs = [
    cmake
    ninja
    buildPython
    pkg-config
    git
  ];

  buildInputs = [
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    openssl
    zlib
    libarchive
    rapidjson
    boost
    protobuf
    grpc
    re2
    libevent
    nlohmann_json
    curl
    gtest
    numactl
    libb64
  ];

  cmakeFlags = [
    "-DFETCHCONTENT_SOURCE_DIR_REPO-BACKEND=${backendSrc}"
    "-DFETCHCONTENT_SOURCE_DIR_PYBIND11=${pybind11Src}"
    "-DFETCHCONTENT_FULLY_DISCONNECTED=ON"

    "-DTRITON_COMMON_REPO_TAG=${tag}"
    "-DTRITON_CORE_REPO_TAG=${tag}"
    "-DTRITON_BACKEND_REPO_TAG=${tag}"
    "-DTRITON_THIRD_PARTY_REPO_TAG=${tag}"
    "-DTRITON_VERSION=${version}"

    "-DTRITON_ENABLE_HTTP=ON"
    "-DTRITON_ENABLE_GRPC=ON"
    "-DTRITON_ENABLE_GPU=ON"
    "-DTRITON_ENABLE_LOGGING=ON"
    "-DTRITON_ENABLE_STATS=ON"
    "-DTRITON_ENABLE_METRICS=ON"
    "-DTRITON_ENABLE_METRICS_GPU=OFF"
    "-DTRITON_ENABLE_METRICS_CPU=ON"
    "-DTRITON_ENABLE_ENSEMBLE=ON"
    "-DTRITON_MIN_COMPUTE_CAPABILITY=8.0"

    "-DTRITON_ENABLE_GCS=OFF"
    "-DTRITON_ENABLE_S3=OFF"
    "-DTRITON_ENABLE_AZURE_STORAGE=OFF"
    "-DTRITON_ENABLE_TRACING=OFF"

    "-DCUDAToolkit_ROOT=${cudaPackages.cudatoolkit}"
    "-DCMAKE_CUDA_ARCHITECTURES=80${"\\;"}86${"\\;"}89${"\\;"}90"
  ];

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail 'file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")' \
                     'set(DISTRO_ID_LIKE "")'
    substituteInPlace src/CMakeLists.txt \
      --replace-fail 'file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")' \
                     'set(DISTRO_ID_LIKE "")' \
      --replace-fail 'add_subdirectory(test test)' \
                     '# add_subdirectory(test test)  # disabled: test linker scripts missing'
  '';

  preConfigure = let
    # Python script to patch third_party CMakeLists.txt
    # Replaces git clones with pre-fetched local sources
    patchScript = builtins.toFile "patch-third-party.py" ''
      import re, sys, json

      tmpdir = sys.argv[1]
      cmake_file = f"{tmpdir}/third-party-src/CMakeLists.txt"

      with open(cmake_file) as f:
          content = f.read()

      # Replace all GIT_REPOSITORY URLs with DOWNLOAD_COMMAND ""
      git_urls = [
          "https://github.com/grpc/grpc.git",
          "https://github.com/curl/curl.git",
          "https://github.com/nlohmann/json.git",
          "https://github.com/libevent/libevent.git",
          "https://github.com/jupp0r/prometheus-cpp.git",
          "https://github.com/google/crc32c.git",
          "https://github.com/googleapis/google-cloud-cpp.git",
          "https://github.com/Azure/azure-iot-sdk-c.git",
          "https://github.com/Azure/azure-sdk-for-cpp.git",
          "https://github.com/aws/aws-sdk-cpp.git",
          "https://github.com/open-telemetry/opentelemetry-cpp.git",
      ]
      for url in git_urls:
          content = content.replace(f'GIT_REPOSITORY "{url}"', 'DOWNLOAD_COMMAND ""')

      # Remove GIT_TAG and GIT_SHALLOW lines
      content = re.sub(r'\n[^\n]*GIT_TAG\s+"[^"]*"', "", content)
      content = re.sub(r'\n[^\n]*GIT_SHALLOW\s+\w+', "", content)

      # Global path replacements: cmake build paths -> pre-fetched local copies
      # Replace ALL occurrences (SOURCE_DIR, PATCH_COMMAND -d args, etc.)
      # Order matters: replace longer paths first (submodules before root)
      path_map = [
          ("grpc-repo/src/grpc/third_party/abseil-cpp", "grpc/third_party/abseil-cpp"),
          ("grpc-repo/src/grpc/third_party/protobuf/cmake", "grpc/third_party/protobuf/cmake"),
          ("grpc-repo/src/grpc/third_party/re2", "grpc/third_party/re2"),
          ("grpc-repo/src/grpc/third_party/googletest", "grpc/third_party/googletest"),
          ("grpc-repo/src/grpc/third_party/cares/cares", "grpc/third_party/cares/cares"),
          ("grpc-repo/src/grpc", "grpc"),
          ("curl/src/curl", "curl"),
          ("json", "nlohmann-json"),
          ("libevent/src/libevent", "libevent"),
          ("prometheus-cpp/src/prometheus-cpp", "prometheus-cpp"),
          ("crc32c/src/crc32c", "crc32c"),
      ]

      for old_suffix, local_name in path_map:
          # Replace CMAKE_CURRENT_BINARY_DIR paths with pre-fetched local paths
          old_path = f"''${{CMAKE_CURRENT_BINARY_DIR}}/{old_suffix}"
          new_path = f"{tmpdir}/prefetched/{local_name}"
          content = content.replace(old_path, new_path)

      # Force lib (not lib64) for all ExternalProject installs
      # GNUInstallDirs defaults to lib64 on x86_64 but Triton expects lib
      content = re.sub(
          r'(-DCMAKE_INSTALL_PREFIX:PATH=)',
          r'-DCMAKE_INSTALL_LIBDIR:STRING=lib\n    \1',
          content
      )

      with open(cmake_file, "w") as f:
          f.write(content)
      print("third_party CMakeLists.txt patched successfully")
    '';
  in ''
    # Create writable copies of core, common, and third_party
    cp -r ${coreSrc} $TMPDIR/core-src
    chmod -R u+w $TMPDIR/core-src

    cp -r ${commonSrc} $TMPDIR/common-src
    chmod -R u+w $TMPDIR/common-src

    cp -r ${thirdPartySrc} $TMPDIR/third-party-src
    chmod -R u+w $TMPDIR/third-party-src

    # Create writable copies of all pre-fetched third-party sources
    mkdir -p $TMPDIR/prefetched
    cp -r ${grpcRepoSrc} $TMPDIR/prefetched/grpc
    chmod -R u+w $TMPDIR/prefetched/grpc
    cp -r ${libeventSrc} $TMPDIR/prefetched/libevent
    chmod -R u+w $TMPDIR/prefetched/libevent
    cp -r ${prometheusCppSrc} $TMPDIR/prefetched/prometheus-cpp
    chmod -R u+w $TMPDIR/prefetched/prometheus-cpp
    cp -r ${nlohmannJsonSrc} $TMPDIR/prefetched/nlohmann-json
    chmod -R u+w $TMPDIR/prefetched/nlohmann-json
    cp -r ${curlSrc} $TMPDIR/prefetched/curl
    chmod -R u+w $TMPDIR/prefetched/curl
    cp -r ${crc32cSrc} $TMPDIR/prefetched/crc32c
    chmod -R u+w $TMPDIR/prefetched/crc32c

    # Patch /etc/os-release references
    substituteInPlace $TMPDIR/core-src/CMakeLists.txt \
      --replace-fail 'file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")' \
                     'set(DISTRO_ID_LIKE "")'

    substituteInPlace $TMPDIR/third-party-src/CMakeLists.txt \
      --replace-fail 'file(STRINGS "/etc/os-release" DISTRO_ID_LIKE REGEX "ID_LIKE")' \
                     'set(DISTRO_ID_LIKE "")'

    # Patch build_wheel.py to use --no-isolation (no pip downloads in sandbox)
    substituteInPlace $TMPDIR/core-src/python/build_wheel.py \
      --replace-fail 'args = ["python3", "-m", "build"]' \
                     'args = ["python3", "-m", "build", "--no-isolation"]'

    # Loosen pyproject.toml build-system version pins (Nix provides different versions)
    substituteInPlace $TMPDIR/core-src/pyproject.toml \
      --replace-fail '"setuptools==75.3.0"' '"setuptools"' \
      --replace-fail '"wheel==0.44.0"' '"wheel"' \
      --replace-fail '"mypy==1.11.0"' '"mypy"' \
      --replace-fail '"numpy<2"' '"numpy"'

    # Disable tests in core and common (they fetch googletest from the internet)
    substituteInPlace $TMPDIR/core-src/src/CMakeLists.txt \
      --replace-fail 'add_subdirectory(test test)' \
                     '# add_subdirectory(test test)  # disabled: no network in sandbox'
    substituteInPlace $TMPDIR/common-src/src/CMakeLists.txt \
      --replace-fail 'add_subdirectory(test)' \
                     '# add_subdirectory(test)  # disabled: no network in sandbox'

    # Pass FETCHCONTENT vars into triton-core ExternalProject (separate cmake process)
    substituteInPlace $TMPDIR/core-src/CMakeLists.txt \
      --replace-fail 'CMAKE_CACHE_ARGS' \
        'CMAKE_CACHE_ARGS
      -DFETCHCONTENT_SOURCE_DIR_REPO-COMMON:PATH='"$TMPDIR"'/common-src
      -DFETCHCONTENT_FULLY_DISCONNECTED:BOOL=ON'

    # Patch third_party ExternalProject_Add to use pre-fetched sources
    python3 ${patchScript} "$TMPDIR"

    # Inject FETCHCONTENT vars into server/src/CMakeLists.txt so the triton-server
    # ExternalProject sub-build finds pre-fetched sources (no network in sandbox)
    substituteInPlace src/CMakeLists.txt \
      --replace-fail 'include(FetchContent)' \
        'include(FetchContent)
set(FETCHCONTENT_SOURCE_DIR_REPO-COMMON "'"$TMPDIR"'/common-src" CACHE PATH "")
set(FETCHCONTENT_SOURCE_DIR_REPO-CORE "'"$TMPDIR"'/core-src" CACHE PATH "")
set(FETCHCONTENT_SOURCE_DIR_REPO-BACKEND "${backendSrc}" CACHE PATH "")
set(FETCHCONTENT_SOURCE_DIR_PYBIND11 "${pybind11Src}" CACHE PATH "")
set(FETCHCONTENT_FULLY_DISCONNECTED ON CACHE BOOL "")
set(CMAKE_CUDA_ARCHITECTURES "80;86;89;90" CACHE STRING "")'

    # Set FETCHCONTENT source dirs to writable copies
    cmakeFlagsArray+=(
      "-DFETCHCONTENT_SOURCE_DIR_REPO-COMMON=$TMPDIR/common-src"
      "-DFETCHCONTENT_SOURCE_DIR_REPO-CORE=$TMPDIR/core-src"
      "-DFETCHCONTENT_SOURCE_DIR_REPO-THIRD-PARTY=$TMPDIR/third-party-src"
    )

    export CUDA_HOME="${cudaPackages.cudatoolkit}"
    # Backend repo reads CUDA_ARCH_LIST (space-separated) to set architectures.
    # Without it, defaults include 100f/120f which nvcc 12.8 doesn't support.
    # PTX JIT provides forward compat for newer GPUs (Blackwell, etc.)
    export CUDA_ARCH_LIST="80 86 89 90"
    export CUDAARCHS="80;86;89;90"
    export CUDAHOSTCXX="${gcc14Stdenv.cc}/bin/g++"
    # CMake 4.x dropped compat with cmake_minimum_required < 3.5
    # Many third_party deps still declare old versions
    export CMAKE_POLICY_VERSION_MINIMUM=3.5
  '';

  postInstall = ''
    cp ${../../scripts/_lib.sh} $out/bin/_lib.sh
    cp ${../../scripts/triton-preflight} $out/bin/triton-preflight
    cp ${../../scripts/triton-resolve-model} $out/bin/triton-resolve-model
    cp ${../../scripts/triton-serve} $out/bin/triton-serve
    cp ${../../scripts/triton-setup-backends} $out/bin/triton-setup-backends
    cp ${../../scripts/triton-setup-models} $out/bin/triton-setup-models
    chmod +x $out/bin/triton-{preflight,resolve-model,serve,setup-backends,setup-models}

    # OpenAI-compatible frontend source
    mkdir -p $out/python/openai
    cp -r ${serverSrc}/python/openai/openai_frontend $out/python/openai/
    cp ${serverSrc}/python/openai/openai_frontend/main.py $out/python/openai/
    cp ${serverSrc}/python/openai/requirements.txt $out/python/openai/

    # Patch main.py: add --backend-directory, --model-control-mode, --load-model args
    chmod +w $out/python/openai/main.py
    substituteInPlace $out/python/openai/main.py \
      --replace-fail \
        '        "--default-max-tokens",' \
        '        "--backend-directory",
        type=str,
        default=None,
        help="Path to the Triton backend directory",
    )
    triton_group.add_argument(
        "--model-control-mode",
        type=str,
        default=None,
        choices=["none", "explicit", "poll"],
        help="Triton model control mode (default: none)",
    )
    triton_group.add_argument(
        "--load-model",
        type=str,
        action="append",
        default=None,
        help="Model(s) to load in explicit mode (repeatable)",
    )
    triton_group.add_argument(
        "--default-max-tokens",' \
      --replace-fail \
        'model_repository=args.model_repository,' \
        'model_repository=args.model_repository,
        **({"backend_directory": args.backend_directory} if args.backend_directory else {}),
        **({"model_control_mode": getattr(tritonserver.ModelControlMode, args.model_control_mode.upper())} if args.model_control_mode else {}),' \
      --replace-fail \
        ').start(wait_until_ready=True)' \
        ').start(wait_until_ready=True)
    if args.load_model:
        for _model_name in args.load_model:
            server.load_model(_model_name)'

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

  # Move lib64 contents to lib before fixupPhase tries (and fails due to subdirs)
  preFixup = ''
    if [ -d "$out/lib64" ]; then
      cp -rn "$out/lib64/"* "$out/lib/" 2>/dev/null || true
      rm -rf "$out/lib64"
    fi
  '';

  doCheck = false;

  meta = with lib; {
    description = "NVIDIA Triton Inference Server";
    homepage = "https://github.com/triton-inference-server/server";
    license = licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
}
