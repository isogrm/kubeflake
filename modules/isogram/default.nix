{ lib, pkgs, ... }: with lib; {
  options.isogram = {
    kubernetesPackageSet = mkOption {
      type = types.attrsOf types.package;
      default = pkgs.isogram.kubernetes.v1_32;
      description = ''
        A set of packages compatible with the desired Kubernetes version (e.x. pkgs.isogram.kubernetes.v1_32).
      '';
    };
  };
}
