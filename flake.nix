{
  description = "Ghaf Infra PKI bundle (public certificates)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      # 1) Package: put certs into the Nix store
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          slsa-pki = pkgs.stdenvNoCC.mkDerivation {
            pname = "ghaf-infra-slsa-pki";
            version = "0.1.0";
            src = ./slsa;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/ghaf-infra-pki/slsa
              cp -R . $out/share/ghaf-infra-pki/slsa/
              find $out/share/ghaf-infra-pki/slsa -type f -exec chmod 0644 {} \;
              find $out/share/ghaf-infra-pki/slsa -type d -exec chmod 0755 {} \;
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Ghaf Infra public SLSA verification certificates";
              platforms = platforms.linux;
            };
          };

          yubi-uefi-pki = pkgs.stdenvNoCC.mkDerivation {
            pname = "ghaf-infra-yubi-uefi-pki";
            version = "0.1.0";
            src = ./yubi-uefi;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/ghaf-infra-pki/uefi/auth
              install -m644 ./auth/* $out/share/ghaf-infra-pki/uefi/auth
              install -m644 ./*.pem $out/share/ghaf-infra-pki/uefi/
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Ghaf Infra public UEFI Secure Boot certificates (YubiHSM)";
              platforms = platforms.linux;
            };
          };

          yubi-slsa-pki = pkgs.stdenvNoCC.mkDerivation {
            pname = "ghaf-infra-yubi-slsa-pki";
            version = "0.1.0";
            src = ./yubi-slsa;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/ghaf-infra-pki/slsa
              install -m644 ./* $out/share/ghaf-infra-pki/slsa/
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Ghaf Infra public SLSA verification certificates (YubiHSM)";
              platforms = platforms.linux;
            };
          };

          enroll-secureboot-keys = pkgs.writeShellApplication {
            name = "enroll-secureboot-keys";
            runtimeInputs = with pkgs; [
              efitools
              systemd
              e2fsprogs
            ];
            runtimeEnv = {
              DBPEM = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/DB.pem";
              KEKPEM = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/KEK.pem";
              PKAUTH = "${yubi-uefi-pki}/share/ghaf-infra-pki/uefi/auth/PK.auth";
            };
            text = builtins.readFile ./enroll-secureboot-keys.sh;
          };

          default = self.packages.${system}.slsa-pki;
        }
      );

      lib = {
        # helper: get store paths for a system
        yubiUefiPathsFor =
          system:
          let
            p = self.packages.${system}.yubi-uefi-pki;
          in
          {
            dir = "${p}/share/ghaf-infra-pki/uefi";
            PK = "${p}/share/ghaf-infra-pki/uefi/PK.pem";
            KEK = "${p}/share/ghaf-infra-pki/uefi/KEK.pem";
            DB = "${p}/share/ghaf-infra-pki/uefi/DB.pem";
          };
        slsaPathsFor =
          system:
          let
            p = self.packages.${system}.slsa-pki;
            nethsmTampereMcaDir = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere-mca";
          in
          {
            dir = "${p}/share/ghaf-infra-pki/slsa";
            bundle = "${p}/share/ghaf-infra-pki/slsa/bundle.pem";
            root = "${p}/share/ghaf-infra-pki/slsa/root-ca.pem";
            intermediate = "${p}/share/ghaf-infra-pki/slsa/intermediate-ca.pem";
            trustAnchor = "${p}/share/ghaf-infra-pki/slsa/cacert.pem";
            tsa = "${p}/share/ghaf-infra-pki/slsa/tsa.crt";
            nethsmTampere = {
              dir = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere";
              bundle = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere/bundle.pem";
              root = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere/root-ca.pem";
              intermediate = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere/intermediate-ca.pem";
              signing = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere/GhafInfraSignECP256.pem";
              provisioning = "${p}/share/ghaf-infra-pki/slsa/nethsm-tampere/GhafInfraSignProv.pem";
            };
            nethsmTampereMca = {
              dir = nethsmTampereMcaDir;
              root = "${nethsmTampereMcaDir}/root-ca.pem";
              intermediate = {
                dbg = "${nethsmTampereMcaDir}/intermediate-ca-dbg.pem";
                dev = "${nethsmTampereMcaDir}/intermediate-ca-dev.pem";
                prod = "${nethsmTampereMcaDir}/intermediate-ca-prod.pem";
                release = "${nethsmTampereMcaDir}/intermediate-ca-release.pem";
              };
              bundle = {
                dbg = "${nethsmTampereMcaDir}/bundle-dbg.pem";
                dev = "${nethsmTampereMcaDir}/bundle-dev.pem";
                prod = "${nethsmTampereMcaDir}/bundle-prod.pem";
                release = "${nethsmTampereMcaDir}/bundle-release.pem";
              };
              signing = {
                dbg = "${nethsmTampereMcaDir}/GhafInfraSignECP256-dbg.pem";
                dev = "${nethsmTampereMcaDir}/GhafInfraSignECP256-dev.pem";
                prod = "${nethsmTampereMcaDir}/GhafInfraSignECP256-prod.pem";
                release = "${nethsmTampereMcaDir}/GhafInfraSignECP256-release.pem";
              };
              provisioning = {
                dbg = "${nethsmTampereMcaDir}/GhafInfraSignProv-dbg.pem";
                dev = "${nethsmTampereMcaDir}/GhafInfraSignProv-dev.pem";
                prod = "${nethsmTampereMcaDir}/GhafInfraSignProv-prod.pem";
                release = "${nethsmTampereMcaDir}/GhafInfraSignProv-release.pem";
              };
              cosign = {
                dbg = "${nethsmTampereMcaDir}/GhafInfraSignCosign-dbg.pem";
                dev = "${nethsmTampereMcaDir}/GhafInfraSignCosign-dev.pem";
                prod = "${nethsmTampereMcaDir}/GhafInfraSignCosign-prod.pem";
                release = "${nethsmTampereMcaDir}/GhafInfraSignCosign-release.pem";
              };
              releasePolicy = "${nethsmTampereMcaDir}/GhafInfraSignReleasePolicy.pem";
            };
          };
      };

      # NixOS module: optional “install into system trust store”
      # --- Use at your own risk ---
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          paths = self.lib.slsaPathsFor pkgs.system;
        in
        {
          options.ghafInfraPki = {
            enable = lib.mkEnableOption "Install Ghaf Infra PKI certs (SLSA)";

            # If you later add uefi/, other/, you can expand this to a set of toggles.
            installSlsaIntoSystemTrust = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Add Ghaf SLSA PKI certificates to security.pki.certificates.";
            };
          };

          config = lib.mkIf config.ghafInfraPki.enable {
            environment.systemPackages = [
              self.packages.${pkgs.system}.slsa-pki
            ];

            # System-wide trust: makes them available to software that uses the system trust store.
            security.pki.certificates = lib.mkIf config.ghafInfraPki.installSlsaIntoSystemTrust [
              (builtins.readFile paths.root)
              (builtins.readFile paths.intermediate)
            ];
          };
        };
    };
}
