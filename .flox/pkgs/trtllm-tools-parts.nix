# Shared fetchurl definitions for trtllm-tools split packages.
# All sub-packages fetch the same tarball parts from GitHub Releases.
# Nix caches fetchurl by hash, so the data is downloaded only once.
{ pkgs }:

{
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

  # CUDA 13.0 toolkit headers (extracted from NGC container layers 19+25)
  # Needed for flashinfer JIT compilation (cuda_runtime.h, CCCL, cuBLAS, etc.)
  cudaInclude = pkgs.fetchurl {
    url = "https://github.com/barstoolbluz/build-triton-server/releases/download/v26.02-tools/trtllm-tools-cuda-include-26.02.tar.gz";
    hash = "sha256-eHYwHrAyY2myo1tjELKQgZLoZHSs33xeg5KKMZP7GAU=";
  };

  # Concatenation command for use in unpackPhase
  catParts = parts: "cat ${parts.bundlePart0} ${parts.bundlePart1} ${parts.bundlePart2} ${parts.bundlePart3} ${parts.bundlePart4}";
}
