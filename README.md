# KubeFlake

This flake contains Kubernetes packages in a Nix flake. This is useful because it allows
you to be decoupled from `nixpkgs` with respect to your Kubernetes version, which means
you can use any supported version of Kubernetes, even if it isn't in `nixpkgs`.

## Usage

This is not a full Kubernetes distribution, but it allows you to build your own with
tools like `kubeadm`.

The [Isogram Kubernetes Engine](https://www.isogram.com/products/kubernetes) distribution is a
commercial Kubernetes on NixOS package that includes...

- A fully configured Kubernetes distribution, ready for application deployments.
- Declarative management through [Isogram Architect](https://www.isogram.com/products/architect).
- Comprehensive backup and migration strategy to protect against cluster failures.
- A set of base packages fully separate from `nixpkgs` with a dedicated security team delivering timely security patches.
- Support plan tailored to your needs.

Email `sales@isogram.com` for more information.

## Version Policy

This public repository will, on a best-effort basis, contain the currently supported Kubernetes
minor versions as per the [upstream release policy](https://kubernetes.io/releases/).
