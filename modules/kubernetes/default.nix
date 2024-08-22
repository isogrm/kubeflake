{ config, pkgs, lib, ... }:

let
  cfg = config.isogram.kubernetes;
  packageSet = config.isogram.kubernetesPackageSet;
  kubePkgs = [ cfg.package ] ++ (with pkgs; [
    util-linux
    iproute2
    ethtool
    cri-o
    iptables-legacy
    socat
    conntrack-tools
    gvisor
    cri-tools
    ebtables
  ]);

  kubeadmAutoJoin = pkgs.writers.writeBash "kubeadm-autojoin" ''
    set -euo pipefail
    JOIN_METHOD="${cfg.joinToken.method}"

    # Set umask to ensure that the created files aren't world-readable.
    umask 077

    # Check if we've already joined before (/var/lib/isogram/stamp exists).
    if [ -f /var/lib/isogram/stamp ]; then
      exit 0
    fi

    mkdir -p /var/lib/isogram

    ${lib.optionalString (cfg.joinToken.method == "development") ''
      echo "${cfg.joinToken.notProductionUnsupportedConfigurationToken}" > /var/lib/isogram/join-token
    ''}

    ${lib.optionalString (cfg.joinToken.method == "file") ''
      if [ "${cfg.joinToken.file}" != "/var/lib/isogram/join-token" ]; then
        cp ${cfg.joinToken.file} /var/lib/isogram/join-token
      fi
    ''}

    ${lib.optionalString (cfg.joinToken.method == "command") ''
      ${cfg.joinToken.command} > /var/lib/isogram/join-token
    ''}

    # The join token is actually a base64 encoded yaml file, so we need to decode it.
    base64 -d /var/lib/isogram/join-token > /var/lib/isogram/join-config.yaml

    # Run kubeadm join with the decoded join token.
    kubeadm join --config /var/lib/isogram/join-config.yaml

    # Mark that we've joined.
    touch /var/lib/isogram/stamp
  '';
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
      enable = lib.mkEnableOption "automatic joining of nodes to the cluster";

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

  config = lib.mkIf cfg.enable {
    environment.systemPackages = kubePkgs;

    boot = {
      kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
        "net.bridge.bridge-nf-call-iptables" = 1;
        "net.bridge.bridge-nf-call-ip6tables" = 1;
        "fs.inotify.max_user_instances" = 8192;
        "fs.inotify.max_user_watches" = 524288;
      };

      kernelModules = [
        "br_netfilter"
        "ip6_tables"
        "ip6table_mangle"
        "ip6table_raw"
        "ip6table_filter"
      ];
    };

    # <https://docs.cilium.io/en/stable/operations/system_requirements/#mounted-ebpf-filesystem>
    fileSystems."/sys/fs/bpf" = {
      device = "bpffs";
      fsType = "bpf";
    };

    networking.firewall = {
      allowedTCPPorts = [
        # <https://kubernetes.io/docs/reference/ports-and-protocols/>
        443 # Kubernetes API server
        2379 # etcd client requests
        2380 # etcd peer communication
        10250 # Kubelet API
        10259 # kube-scheduler
        10257 # kube-controller-manager

        # <https://docs.cilium.io/en/v1.15/operations/system_requirements/>
        4240 # cluster health checks
        4244 # Hubble server
        4245 # Hubble relay

        # <https://metallb.universe.tf/#requirements>
        7946
      ];

      allowedUDPPorts = [
        # <https://docs.cilium.io/en/v1.15/operations/system_requirements/>
        8472
        # <https://metallb.universe.tf/#requirements>
        7946
      ];

      # <https://kubernetes.io/docs/reference/ports-and-protocols/>
      allowedTCPPortRanges = [{ from = 30000; to = 32767; }];
    };

    # <https://github.com/NixOS/nixpkgs/issues/179741>
    networking.nftables.enable = false;
    networking.firewall.package = pkgs.iptables-legacy;

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
    systemd.services = {
      kubeadm-join = lib.mkIf cfg.joinToken.enable {
        description = "Isogram kubeadm auto-join";
        documentation = [ "https://isogram.com/" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        path = kubePkgs;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = kubeadmAutoJoin;
        };
      };

      kubelet = {
        # Provided by basic kubelet.service
        # https://github.com/kubernetes/release/blob/cd53840/cmd/krel/templates/latest/kubelet/kubelet.service

        description = "kubelet: The Kubernetes Node Agent";
        documentation = [ "https://kubernetes.io/docs/" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        path = kubePkgs;

        serviceConfig = {
          Restart = "always";
          StartLimitIntervalSec = 0;
          RestartSec = 10;

          # Provided by kubeadm drop-in file
          # https://github.com/kubernetes/release/blob/cd53840/cmd/krel/templates/latest/kubeadm/10-kubeadm.conf
          EnvironmentFile = "-/var/lib/kubelet/kubeadm-flags.env";

          ExecStart = ''
            ${config.isogram.kubernetes.package}/bin/kubelet \
              --kubeconfig=/etc/kubernetes/kubelet.conf \
              --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
              --config=/var/lib/kubelet/config.yaml \
              $KUBELET_KUBEADM_ARGS
          '';

          # Create /var/lib/kubelet and /etc/kubernetes with the correct permissions
          StateDirectory = "kubelet";
          ConfiguratonDirectory = "kubernetes";
        };
      };
    };
  };
}
