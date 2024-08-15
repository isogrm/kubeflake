{
  lib,
  buildGoModule,
  fetchFromGitHub,
  which,
  makeWrapper,
  rsync,
  installShellFiles,
  runtimeShell,
  nixosTests,
  versionData,
  components ? [
    "cmd/kubelet"
    "cmd/kube-apiserver"
    "cmd/kube-controller-manager"
    "cmd/kube-proxy"
    "cmd/kube-scheduler"
    "cmd/kubectl"
    "cmd/kubectl-convert"
  ],
}:
buildGoModule rec {
  pname = "kubernetes";
  version = versionData.version;

  src = fetchFromGitHub {
    owner = "kubernetes";
    repo = "kubernetes";
    rev = "v${version}";
    sha256 = versionData.sha256;
  };

  vendorHash = null;

  doCheck = false;

  nativeBuildInputs = [makeWrapper which rsync installShellFiles];

  outputs = ["out" "man" "pause"];

  patches = [./fixup-addonmanager-lib-path.patch];

  WHAT = lib.concatStringsSep " " ([
      "cmd/kubeadm"
    ]
    ++ components);

  buildPhase = ''
    runHook preBuild
    substituteInPlace "hack/update-generated-docs.sh" --replace "make" "make SHELL=${runtimeShell}"
    patchShebangs ./hack ./cluster/addons/addon-manager
    make "SHELL=${runtimeShell}" "WHAT=$WHAT"
    ./hack/update-generated-docs.sh
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for p in $WHAT; do
      install -D _output/local/go/bin/''${p##*/} -t $out/bin
    done

    cc build/pause/linux/pause.c -o pause
    install -D pause -t $pause/bin

    installManPage docs/man/man1/*.[1-9]

    # Unfortunately, kube-addons-main.sh only looks for the lib file in either the
    # current working dir or in /opt. We have to patch this for now.
    substitute cluster/addons/addon-manager/kube-addons-main.sh $out/bin/kube-addons \
      --subst-var out

    chmod +x $out/bin/kube-addons
    wrapProgram $out/bin/kube-addons --set "KUBECTL_BIN" "$out/bin/kubectl"

    cp cluster/addons/addon-manager/kube-addons.sh $out/bin/kube-addons-lib.sh

    installShellCompletion --cmd kubectl \
      --bash <($out/bin/kubectl completion bash) \
      --fish <($out/bin/kubectl completion fish) \
      --zsh <($out/bin/kubectl completion zsh)
    installShellCompletion --cmd kubeadm \
      --bash <($out/bin/kubeadm completion bash) \
      --zsh <($out/bin/kubeadm completion zsh)
    runHook postInstall
  '';

  meta = with lib; {
    description = "Production-Grade Container Orchestration";
    license = licenses.asl20;
    homepage = "https://kubernetes.io";
    maintainers = [];
    platforms = platforms.linux;
  };

  # TODO: We're using upstream nixpkgs tests for now, but we should write our own.
  passthru.tests = nixosTests.kubernetes;
}
