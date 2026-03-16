# Phi-4-mini-instruct TRT-LLM model for NVIDIA Triton Inference Server
#
# Pre-built TensorRT-LLM engine (INT4 AWQ, single GPU, r26.02).
# Bundle contains:
#   engine/    - rank0.engine + config.json (TRT-LLM engine)
#   tokenizer/ - HuggingFace tokenizer files (microsoft/Phi-4-mini-instruct)
#
# Bundle is split into 2 parts for GitHub Releases 2GB limit.
#
# Output layout:
#   $out/share/models/phi4_mini_trtllm/
#     config.pbtxt.template  - @EXECUTOR_WORKER_PATH@, @GPT_MODEL_PATH@, @TOKENIZER_DIR@
#     engine/                - TRT-LLM engine files
#     tokenizer/             - tokenizer files
#     1/                     - empty version directory (Triton convention)
#   $out/share/models/phi4_mini_trtllm_preprocessing/
#     config.pbtxt.template  - @TOKENIZER_DIR@
#     tokenizer -> ../phi4_mini_trtllm/tokenizer
#     1/model.py             - tokenization (Python backend)
#   $out/share/models/phi4_mini_trtllm_postprocessing/
#     config.pbtxt.template  - @TOKENIZER_DIR@
#     tokenizer -> ../phi4_mini_trtllm/tokenizer
#     1/model.py             - detokenization (Python backend)
#   $out/share/models/phi4_mini_trtllm_ensemble/
#     config.pbtxt.template  - @TOKENIZER_DIR@ (BLS Python model)
#     1/model.py             - BLS orchestration + streaming delta computation
{ pkgs ? import <nixpkgs> {} }:

let
  pname = "triton-model-phi4-mini-trtllm";
  tag = "r26.02";

  buildMeta = builtins.fromJSON (builtins.readFile ../../build-meta/triton-model-phi4-mini-trtllm.json);
  buildVersion = buildMeta.build_version;
  version = "0.1.0+${buildMeta.git_rev_short}";

  modelName = "phi4_mini_trtllm";

  bundlePart0 = pkgs.fetchurl {
    url = "https://github.com/flox/nvidia-triton-server/releases/download/v26.02/phi4_mini_trtllm-r26.02.tar.gz.partaa";
    hash = "sha256-o/tHyHcFlQuMiA8BQBWlSW4tX90Krd3mGc81RvVky2I=";
  };

  bundlePart1 = pkgs.fetchurl {
    url = "https://github.com/flox/nvidia-triton-server/releases/download/v26.02/phi4_mini_trtllm-r26.02.tar.gz.partab";
    hash = "sha256-GJAA9KhE/4bSPg1/GBFdAUzYNd6frYcAg7uEpn3avT8=";
  };

  configTemplate = ../../models/${modelName}/config.pbtxt.template;

in pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = bundlePart0;

  sourceRoot = ".";
  unpackPhase = ''
    mkdir -p source
    cat ${bundlePart0} ${bundlePart1} | tar -xzf - -C source
    cd source
  '';

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    modelDir="$out/share/models/${modelName}"
    mkdir -p "$modelDir"

    # Engine files
    cp -r engine "$modelDir/"

    # Tokenizer files
    cp -r tokenizer "$modelDir/"

    # Config template (tokens expanded at activation by triton-setup-models)
    cp ${configTemplate} "$modelDir/config.pbtxt.template"

    # Empty version directory (Triton convention)
    mkdir -p "$modelDir/1"

    # Preprocessing model
    preDir="$out/share/models/${modelName}_preprocessing"
    mkdir -p "$preDir/1"
    cp ${../../models/${modelName}_preprocessing/config.pbtxt.template} "$preDir/config.pbtxt.template"
    cp ${../../models/${modelName}_preprocessing/1/model.py} "$preDir/1/model.py"
    ln -s ../phi4_mini_trtllm/tokenizer "$preDir/tokenizer"

    # Postprocessing model
    postDir="$out/share/models/${modelName}_postprocessing"
    mkdir -p "$postDir/1"
    cp ${../../models/${modelName}_postprocessing/config.pbtxt.template} "$postDir/config.pbtxt.template"
    cp ${../../models/${modelName}_postprocessing/1/model.py} "$postDir/1/model.py"
    ln -s ../phi4_mini_trtllm/tokenizer "$postDir/tokenizer"

    # Ensemble model (BLS — Python backend orchestrator for streaming)
    ensDir="$out/share/models/${modelName}_ensemble"
    mkdir -p "$ensDir/1"
    cp ${../../models/${modelName}_ensemble/config.pbtxt.template} "$ensDir/config.pbtxt.template"
    cp ${../../models/${modelName}_ensemble/1/model.py} "$ensDir/1/model.py"
    ln -s ../phi4_mini_trtllm/tokenizer "$ensDir/tokenizer"

    # Version marker
    mkdir -p "$out/share/${pname}"
    cat > "$out/share/${pname}/flox-build-version-${toString buildVersion}" <<'MARKER'
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

  dontStrip = true;
  dontFixup = true;

  meta = with pkgs.lib; {
    description = "Phi-4-mini-instruct INT4 AWQ TRT-LLM model for NVIDIA Triton Inference Server";
    homepage = "https://huggingface.co/microsoft/Phi-4-mini-instruct";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
