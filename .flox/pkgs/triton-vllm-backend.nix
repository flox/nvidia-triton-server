# vLLM Python backend for NVIDIA Triton Inference Server
#
# Pure Python backend — no compilation needed. Installs model.py and utils/
# into $out/backends/vllm/ so triton-setup-backends can discover it as a
# Tier 1 package-provided backend.
{ lib, stdenv }:

let
  pname = "triton-vllm-backend";
  version = "2.66.0";
  tag = "r26.02";
  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-vllm-backend.json);
  buildVersion = buildMeta.build_version;
in

stdenv.mkDerivation {
  inherit pname version;
  src = null;
  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/backends/vllm/utils
    cp ${../../backends/vllm/model.py} $out/backends/vllm/model.py
    cp ${../../backends/vllm/utils/__init__.py} $out/backends/vllm/utils/__init__.py
    cp ${../../backends/vllm/utils/metrics.py} $out/backends/vllm/utils/metrics.py
    cp ${../../backends/vllm/utils/request.py} $out/backends/vllm/utils/request.py
    cp ${../../backends/vllm/utils/vllm_backend_utils.py} $out/backends/vllm/utils/vllm_backend_utils.py

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

  meta = with lib; {
    description = "vLLM Python backend for NVIDIA Triton Inference Server";
    homepage = "https://github.com/triton-inference-server/vllm_backend";
    license = licenses.bsd3;
    platforms = [ "x86_64-linux" ];
  };
}
