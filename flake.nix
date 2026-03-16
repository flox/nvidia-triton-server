{
  description = "NVIDIA Triton Inference Server - TRT-LLM backend and model packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
    in
    {
      packages.${system} = {
        triton-tensorrtllm-backend =
          import ./.flox/pkgs/triton-tensorrtllm-backend.nix { inherit pkgs; };
        triton-model-phi4-mini-trtllm =
          import ./.flox/pkgs/triton-model-phi4-mini-trtllm.nix { inherit pkgs; };
      };
    };
}
