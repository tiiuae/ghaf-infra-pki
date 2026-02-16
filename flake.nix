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
        {
          slsa-pki = pkgs.stdenvNoCC.mkDerivation {
            pname = "ghaf-infra-slsa-pki";
            version = "0.1.0";
            src = ./slsa;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/ghaf-infra-pki/slsa
              install -m644 ./* $out/share/ghaf-infra-pki/slsa/
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
          in
          {
            dir = "${p}/share/ghaf-infra-pki/slsa";
            bundle = "${p}/share/ghaf-infra-pki/slsa/bundle.pem";
            root = "${p}/share/ghaf-infra-pki/slsa/root-ca.pem";
            intermediate = "${p}/share/ghaf-infra-pki/slsa/intermediate-ca.pem";
            trustAnchor = "${p}/share/ghaf-infra-pki/slsa/cacert.pem";
            tsa = "${p}/share/ghaf-infra-pki/slsa/tsa.crt";
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
