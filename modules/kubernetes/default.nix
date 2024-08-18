{ config, pkgs, lib, ... }:

let
  packageSet = config.isogram.kubernetesPackageSet;
  kubePkgs = with pkgs; [ config.isogram.kubernetes.package util-linux iproute2 ethtool cri-o iptables-legacy socat conntrack-tools gvisor cri-tools ebtables ];
in
{
  # Configuration for Nodes
  options.isogram.kubernetes = {
    enable = lib.mkEnableOption "Enable the Isogram Kubernetes distribution.";
    package = lib.mkOption {
      type = lib.types.package;
      default = packageSet.kubernetes;
      description = "The Kubernetes package to use.";
    };
    # Extra packages to inject into the systemd services.
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages to inject into the systemd services. Useful for join token commands.";
    };
    # Join token options.
    joinToken = {
      enable = lib.mkEnableOption "Enable automatic joining of nodes to the cluster.";
      method = lib.mkOption {
        type = lib.types.enum [ "development" "file" "command" ];
        default = "file";
        description = "The method to use to get the join token. Development means the token is directly in the nix config, file means it's read from a file, and command means it's read from a command.";
      };
      command = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "The command to run to get the join token.";
      };
      file = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/isogram/join-token";
        description = "The file to read the join token from.";
      };
      notProductionUnsupportedConfigurationToken = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "The join token to use. This is ONLY for development! It will leak join tokens to the world.";
      };
    };
    isLeader = lib.mkOption {
      default = false;
      example = true;
      description = "Currently identical to worker, but enables kube-vip as a static pod.";
      type = lib.types.bool;
    };
  };

  config = lib.mkIf config.isogram.kubernetes.enable {
    boot.kernelModules = [
      "aes"
      "algif_hash"
      "br_netfilter"
      "ceph"
      "cls_bpf"
      "cryptd"
      "encrypted_keys"
      "ip_tables"
      "iptable_mangle"
      "iptable_raw"
      "iptable_filter"
      "ip6_tables"
      "ip6table_filter"
      "ip6table_mangle"
      "ip6table_raw"
      "ip_set"
      "ip_set_hash_ip"
      "rbd"
      "sch_fq"
      "sha1"
      "sha256"
      "xt_CT"
      "xt_TPROXY"
      "xt_mark"
      "xt_set"
      "xt_socket"
      "xts"
    ];

    # <https://docs.cilium.io/en/stable/operations/system_requirements/#mounted-ebpf-filesystem>
    fileSystems."/sys/fs/bpf" = {
      device = "bpffs";
      fsType = "bpf";
    };

    # Firewall has to be off, these rules aren't enough to make Cilium work apparently. That said,
    # I spent a while typing these out and putting comments on them, so the rules stay! See if you
    # can figure out how to get Firewall to work at some point (or use Cilium host firewall tbh).
    networking.firewall.allowedTCPPorts = [
      # <https://kubernetes.io/docs/reference/ports-and-protocols/>
      6443
      2379
      2380
      10250
      10259
      10257
      10250
      # <https://docs.cilium.io/en/v1.11/operations/system_requirements/#firewall-rules>
      4240
    ];
    # <https://docs.cilium.io/en/v1.11/operations/system_requirements/#firewall-rules>
    networking.firewall.allowedUDPPorts = [ 8472 ];
    # <https://kubernetes.io/docs/reference/ports-and-protocols/>
    networking.firewall.allowedTCPPortRanges = [{ from = 30000; to = 32767; }];

    # <https://github.com/NixOS/nixpkgs/issues/179741>
    networking.nftables.enable = false;
    networking.firewall.package = pkgs.iptables-legacy;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    environment.systemPackages = kubePkgs;

    isogram.cri-o = {
      enable = true;
      extraPackages = [ pkgs.gvisor ];
      settings = {
        crio.runtime.runtimes.runsc = {
          runtime_path = "${pkgs.gvisor}/bin/runsc";
        };
      };
    };

    # Oneshot service to get the join token and write it to a file, then run the command to join the cluster.
    systemd.services.kubeadm = lib.mkIf config.isogram.kubernetes.joinToken.enable {
      description = "Kubeadm <https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm/>";
      wantedBy = [ "multi-user.target" ];

      path = kubePkgs;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writers.writeBash "kubeadm-autojoin" ''
          set -euo pipefail
          JOIN_METHOD="${config.isogram.kubernetes.joinToken.method}"

          # Set umask to ensure that the created files aren't world-readable.
          umask 077

          # Check if we've already joined before (/var/lib/isogram/stamp exists).
          if [ -f /var/lib/isogram/stamp ]; then
            exit 0
          fi

          mkdir -p /var/lib/isogram

          if [ "$JOIN_METHOD" = "development" ]; then
            echo "${config.isogram.kubernetes.joinToken.notProductionUnsupportedConfigurationToken}" > /var/lib/isogram/join-token
          elif [ "$JOIN_METHOD" = "file" ]; then
            if [ "${config.isogram.kubernetes.joinToken.file}" != "/var/lib/isogram/join-token" ]; then
              cp ${config.isogram.kubernetes.joinToken.file} /var/lib/isogram/join-token
            fi
          elif [ "$JOIN_METHOD" = "command" ]; then
            ${config.isogram.kubernetes.joinToken.command} > /var/lib/isogram/join-token
          fi

          # The join token is actually a base64 encoded yaml file, so we need to decode it.
          base64 -d /var/lib/isogram/join-token > /var/lib/isogram/join-config.yaml

          # Run kubeadm join with the decoded join token.
          kubeadm join --config /var/lib/isogram/join-config.yaml

          # Mark that we've joined.
          touch /var/lib/isogram/stamp
        '';
      };
    };

    systemd.services.kubelet = {
      description = "Kubelet <https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/>";
      wantedBy = [ "multi-user.target" ];

      path = kubePkgs;

      serviceConfig = {
        StateDirectory = "kubelet";
        ConfiguratonDirectory = "kubernetes";

        # KUBELET_KUBEADM_ARGS - generated by kubeadm
        EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";

        Restart = "always";
        StartLimitIntervalSec = 0;
        RestartSec = 10;

        ExecStart = ''
          ${config.isogram.kubernetes.package}/bin/kubelet \
            --kubeconfig=/etc/kubernetes/kubelet.conf \
            --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
            --config=/var/lib/kubelet/config.yaml \
            $KUBELET_KUBEADM_ARGS
        '';
      };
    };
  };
}
