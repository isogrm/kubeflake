{
  lib,
  btrfs-progs,
  buildGoModule,
  fetchFromGitHub,
  glibc,
  gpgme,
  installShellFiles,
  libapparmor,
  libseccomp,
  libselinux,
  lvm2,
  pkg-config,
  nixosTests,
  versionData,
}:
buildGoModule rec {
  pname = "cri-o";
  version = versionData.cri-o.version;

  src = fetchFromGitHub {
    owner = "cri-o";
    repo = "cri-o";
    rev = "v${version}";
    sha256 = versionData.cri-o.hash;
  };
  vendorHash = null;

  doCheck = false;

  outputs = ["out" "man"];
  nativeBuildInputs = [installShellFiles pkg-config];

  buildInputs =
    [
      btrfs-progs
      gpgme
      libapparmor
      libseccomp
      libselinux
      lvm2
    ]
    ++ lib.optionals (glibc != null) [glibc glibc.static];

  BUILDTAGS = "apparmor seccomp selinux containers_image_openpgp containers_image_ostree_stub";
  buildPhase = ''
    runHook preBuild
    make binaries docs BUILDTAGS="$BUILDTAGS"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/* -t $out/bin

    for shell in bash fish zsh; do
      installShellCompletion --$shell completions/$shell/*
    done

    install contrib/cni/*.conflist -Dt $out/etc/cni/net.d
    install crictl.yaml -Dt $out/etc

    installManPage docs/*.[1-9]
    runHook postInstall
  '';

  passthru.tests = {inherit (nixosTests) cri-o;};

  meta = with lib; {
    homepage = "https://cri-o.io";
    description = ''
      Lightweight Container Runtime for Kubernetes
    '';
    license = licenses.asl20;
    maintainers = [];
    platforms = platforms.linux;
  };
}
