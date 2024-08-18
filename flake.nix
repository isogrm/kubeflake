{
  description = "";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-24.05";

  outputs =
    { self
    , nixpkgs
    ,
    }:
    # All non-EOL Kubernetes are supported. For more information on the EOL dates,
    # see <https://kubernetes.io/releases/>.
    let
      versionList = {
        # EOL 2025-10-28
        v1_31 = {
          version = "1.31.0";
          sha256 = "sha256-Oy638nIuz2xWVvMGWHUeI4T7eycXIfT+XHp0U7h8G9w=";
          cri-o = {
            version = "1.30.4";
            sha256 = "sha256-PfG5RlUmMGMduTApdlHoI+4kdRprvWXeXZDkd6brVkM=";
          };
        };
        # EOL 2025-02-28
        v1_30 = {
          version = "1.30.3";
          sha256 = "sha256-AJ2EQVaW96XzKp7ZaKfsija+fWmkvy0g3qQH0VFcmsQ=";
          cri-o = {
            version = "1.30.4";
            sha256 = "sha256-PfG5RlUmMGMduTApdlHoI+4kdRprvWXeXZDkd6brVkM=";
          };
        };
        # EOL 2025-02-28
        v1_29 = {
          version = "1.29.7";
          sha256 = "sha256-JlKUuYBGMZvPWhzmJyYkhJ1llWAdr/TJk0Ud04KGmXI=";
          cri-o = {
            version = "1.29.7";
            sha256 = "sha256-QtgD05kpbJmZm4+qSjicHr6Dy5FjeSVSFaCGOFQlb4A=";
          };
        };
        # EOL 2024-10-28
        v1_28 = {
          version = "1.28.12";
          sha256 = "sha256-6N22csGx/8KTiULlPuh+O9K0Ei6pvbIsUcQlA57GIfs=";
          cri-o = {
            version = "1.28.9";
            sha256 = "sha256-O7MdNtYo2Md0q2If+8GM7fLkWCv85lPmmEuppRNn7zc=";
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
