{
  description = "";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-25.11";

  outputs =
    { self
    , nixpkgs
    ,
    }:
    # All non-EOL Kubernetes are supported. For more information on the EOL dates,
    # see <https://kubernetes.io/releases/>.
    let
      versionList = {
        # EOL 2027-02-28
        v1_35 = {
          version = "1.35.0";
          sha256 = "sha256-AT1/4RhnVK/mAoNVqPIfSwbzD8VNRqKumOpE0fidJ74=";
          cri-o = {
            version = "1.35.0";
            sha256 = "sha256-aP3qhD2d1x+VPDifkg9lXgVD38UcongyN6vHkn8oYos=";
          };
        };
        # EOL 2026-10-27
        v1_34 = {
          version = "1.34.2";
          sha256 = "sha256-3rQyoGt9zTeF8+PIhA5p+hHY1V5O8CawvKWscf/r9RM=";
          cri-o = {
            version = "1.34.2";
            sha256 = "sha256-StvHYzWe/LKgA9NQByfti/xAiHMRuRSF8QVsVcw/A+g=";
          };
        };
        # EOL 2026-06-28
        v1_33 = {
          version = "1.33.6";
          sha256 = "sha256-ywmaMRtq/HqkHO4CGspL4AYcn4IbFzAzA0xZRmAgCWE=";
          cri-o = {
            version = "1.33.6";
            sha256 = "sha256-ztKG34tpTI48SFCR1Is6b5ORmlg+JcH/KS4r+2FK/4E=";
          };
        };
        # EOL 2026-02-28
        v1_32 = {
          version = "1.32.10";
          sha256 = "sha256-8N6Qo0Qqg+lTvBzA6H6lOTWSMxUbjQh1U4iqZ2V679c=";
          cri-o = {
            version = "1.32.10";
            sha256 = "sha256-L0G65y2NdYIUs3/l+Ewd4alxhsOfBVU/1SVgjy8M0hI=";
          };
        };
      };
    in
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
      forAllVersions = nixpkgs.lib.genAttrs (builtins.attrNames versionList);
    in
    rec {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        forAllVersions (
          version:
          let
            versionData = builtins.getAttr version versionList;
          in
          {
            kubernetes = pkgs.callPackage ./binaries/kubernetes { inherit versionData; };
            cri-o = pkgs.callPackage ./binaries/cri-o { inherit versionData; };
            kubectl-ctx = pkgs.callPackage ./binaries/kubectl-ctx { };
          }
        )
      );

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixpkgs-fmt;

      nixosModule = { ... }: {
        imports = [
          ./modules/isogram
          ./modules/kubernetes
          ./modules/cri-o
        ];

        nixpkgs.overlays = [
          (final: prev: {
            isogram.kubernetes = forAllVersions (
              version:
              let
                versionData = builtins.getAttr version versionList;
              in
              {
                kubernetes = final.callPackage ./binaries/kubernetes { inherit versionData; };
                cri-o = final.callPackage ./binaries/cri-o { inherit versionData; };
                kubectl-ctx = final.callPackage ./binaries/kubectl-ctx { };
              }
            );
          })
        ];
      };
    };
}
