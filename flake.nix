{
  description = "";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-23.11";

  outputs = {
    self,
    nixpkgs,
  }:
  # All non-EOL Kubernetes are supported. For more information on the EOL dates,
  # see <https://kubernetes.io/releases/>.
  let
    versionList = {
      # EOL 2025-02-28
      v1_29 = {
        version = "1.29.2";
        hash = "sha256-DFQaDlp8CqN0jKTVO5N9ZQYyM2gm/VnQfO4/bfvYrTE=";
        cri-o = {
          version = "1.29.2";
          hash = "sha256-il28u2+Jv2gh6XqRV4y6u0FDZ4flmcp+bOj9aibL+ro=";
        };
      };
      # EOL 2024-10-28
      v1_28 = {
        version = "1.28.7";
        hash = "sha256-Qhx5nB4S5a8NlRhxQrD1U4oOCMLxJ9XUk2XemwAwe5k=";
        cri-o = {
          version = "1.28.4";
          hash = "sha256-uEU5kBOHvlktbo9Fhf2LSWnzmNB8+FDaL/Xoy0XA03A=";
        };
      };
      # EOL 2024-06-28
      v1_27 = {
        version = "1.27.11";
        hash = "sha256-n++nAOvyTjCJVKZfDzFqPj6cjzzLRcrMU7y4QVGDLVk=";
        cri-o = {
          version = "1.27.4";
          hash = "sha256-N5O8rO+LBE7Zb17HBlkt8nrOuOP04dj6gwYP/Tfih/0=";
        };
      };
    };
  in let
    supportedSystems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    nixpkgsFor = forAllSystems (system: import nixpkgs {inherit system;});
    forAllVersions = nixpkgs.lib.genAttrs (builtins.attrNames versionList);
  in {
    packages = forAllSystems (
      system: let
        pkgs = nixpkgsFor.${system};
      in
        forAllVersions (
          version: let
            versionData = builtins.getAttr version versionList;
          in {
            kubernetes = pkgs.callPackage ./binaries/kubernetes {inherit versionData;};
            cri-o = pkgs.callPackage ./binaries/cri-o {inherit versionData;};
            kubectl-ctx = pkgs.callPackage ./binaries/kubectl-ctx {};
          }
        )
    );

    nixosModule = {packageSet, ...}:
      nixpkgs.lib.mkMerge [
        ((import ./modules/cri-o) packageSet)
      ];
  };
}
