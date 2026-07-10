# Ghaf Infra PKI Bundle

This repository provides a **Nix flake** that packages **public PKI
certificates** used by the Ghaf infrastructure.

The goal is to distribute public trust material in a **reproducible,
Nix-native way**, so that verification scripts and CI can rely on
**installed, pinned certificates** instead of downloading public keys
from the same location as binaries.

All material in this repository is **public**. **No private keys** are
included.

------------------------------------------------------------------------

## What this flake provides

The flake exposes:

### Packages (`packages.<system>.*`)

-   `slsa-pki` --- public SLSA verification certificates (default
    package)
-   `yubi-slsa-pki` --- public SLSA verification certificates (YubiHSM
    variant)
-   `yubi-uefi-pki` --- public UEFI Secure Boot certificates (YubiHSM
    variant)
-   `enroll-secureboot-keys` --- Secure Boot key enrollment script
    (bundled with the UEFI PKI material)
-   ´nethsm-slsa-pki-tampere´ --- public SLSA verification certificates (NetHSM-Tampere)
-   `default` → `slsa-pki`

Supported systems: `x86_64-linux`, `aarch64-linux`.

### Library helpers (`lib.*`)

-   `lib.slsaPathsFor <system>` --- canonical Nix store paths for the
    SLSA bundle
-   `lib.yubiUefiPathsFor <system>` --- canonical Nix store paths for
    the UEFI bundle

### NixOS module (`nixosModules.default`)

Optional module to install the **SLSA** bundle and (optionally) add its
CA certs into `security.pki.certificates`.

------------------------------------------------------------------------

## The built artifacts are installed under:

-   `…/share/ghaf-infra-pki/slsa/`
-   `…/share/ghaf-infra-pki/slsa/nethsm-tampere/`
-   `…/share/ghaf-infra-pki/slsa/nethsm-tampere-mca/`
-   `…/share/ghaf-infra-pki/uefi/`
-   `…/share/ghaf-infra-pki/uefi/auth/`

------------------------------------------------------------------------

## SLSA NetHSM Tampere MCA CA structure

The `slsa/nethsm-tampere-mca/` certificate set uses one common root CA
and four environment-specific intermediate CAs:

``` text
root-ca.pem
├── intermediate-ca-dbg.pem
│   └── GhafInfraSign*-dbg.pem
├── intermediate-ca-dev.pem
│   └── GhafInfraSign*-dev.pem
├── intermediate-ca-prod.pem
│   └── GhafInfraSign*-prod.pem
└── intermediate-ca-release.pem
    ├── GhafInfraSign*-release.pem
    └── GhafInfraSignReleasePolicy.pem
```

Each environment has its own bundle:

-   `bundle-dbg.pem`
-   `bundle-dev.pem`
-   `bundle-prod.pem`
-   `bundle-release.pem`

The `release` hierarchy also includes
`GhafInfraSignReleasePolicy.pem`, which is exposed separately by the Nix
library helper.

------------------------------------------------------------------------

## Quick start

Show flake outputs:

``` bash
nix flake show
```

Build the default (SLSA) package:

``` bash
nix build .#slsa-pki
# or
nix build .#default
```

Build the other bundles:

``` bash
nix build .#yubi-slsa-pki
nix build .#yubi-uefi-pki
```

Run the Secure Boot enrollment script:

``` bash
nix run .#enroll-secureboot-keys
```

------------------------------------------------------------------------

## Using the packaged certificates

### From scripts / verification tooling

Example:

``` bash
PKI_DIR="$(nix build .#slsa-pki --no-link --print-out-paths)/share/ghaf-infra-pki/slsa"

openssl verify \
  -CAfile "$PKI_DIR/bundle.pem" \
  artifact-cert.pem
```

NetHSM Tampere MCA example for an environment-specific verification
bundle:

``` bash
PKI_DIR="$(nix build .#slsa-pki --no-link --print-out-paths)/share/ghaf-infra-pki/slsa"
ENV=prod

openssl verify \
  -CAfile "$PKI_DIR/nethsm-tampere-mca/bundle-$ENV.pem" \
  artifact-cert.pem
```

### From Nix code

``` nix
let
  slsa = ghaf-infra-pki.lib.slsaPathsFor system;
in {
  trustAnchor = slsa.bundle;
  tsaCert     = slsa.tsa;
}
```

NetHSM Tampere MCA example:

``` nix
let
  slsa = ghaf-infra-pki.lib.slsaPathsFor system;
  mca = slsa.nethsmTampereMca;
in {
  prodBundle = mca.bundle.prod;
  prodRoot = mca.root;
  prodIntermediate = mca.intermediate.prod;
  prodSigningCert = mca.signing.prod;

  releaseBundle = mca.bundle.release;
  releasePolicyCert = mca.releasePolicy;
}
```

UEFI example:

``` nix
let
  uefi = ghaf-infra-pki.lib.yubiUefiPathsFor system;
in {
  pk  = uefi.PK;
  kek = uefi.KEK;
  db  = uefi.DB;
}
```

------------------------------------------------------------------------

## Enrolling Secure Boot keys

The `enroll-secureboot-keys` package wraps `enroll-secureboot-keys.sh`
and embeds paths to the UEFI PKI material from `yubi-uefi-pki`. It
updates `db`, `KEK`, and `PK` EFI variables and **requires** running on
a system booted in UEFI mode with `sudo` available.

Example:

``` bash
nix run .#enroll-secureboot-keys
```

------------------------------------------------------------------------

## Optional: NixOS system-wide installation (SLSA)

The default NixOS module installs the `slsa-pki` package and, when
`installSlsaIntoSystemTrust` is enabled, adds the top-level SLSA root
and intermediate CA certificates to `security.pki.certificates`.

``` nix
{
  inputs.ghaf-infra-pki.url = "github:tiiuae/ghaf-infra-pki";

  outputs = { self, nixpkgs, ghaf-infra-pki, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ghaf-infra-pki.nixosModules.default
        {
          ghafInfraPki.enable = true;
          ghafInfraPki.installSlsaIntoSystemTrust = true;
        }
      ];
    };
  };
}
```

To install the NetHSM Tampere MCA CA certificates into the system trust
store, add the common root CA and the intermediate CAs that the host
should trust explicitly:

``` nix
{ pkgs, ghaf-infra-pki, ... }:

let
  slsa = ghaf-infra-pki.lib.slsaPathsFor pkgs.system;
  mca = slsa.nethsmTampereMca;
in {
  environment.systemPackages = [
    ghaf-infra-pki.packages.${pkgs.system}.slsa-pki
  ];

  security.pki.certificates = [
    (builtins.readFile mca.root)
    (builtins.readFile mca.intermediate.dbg)
    (builtins.readFile mca.intermediate.dev)
    (builtins.readFile mca.intermediate.prod)
    (builtins.readFile mca.intermediate.release)
  ];
}
```

For verification scripts and CI, prefer the environment-specific bundle
path, such as `mca.bundle.prod` or `mca.bundle.release`, instead of
adding all MCA CAs to the operating system trust store.

------------------------------------------------------------------------

## Design goals

-   Reproducible trust via flake pinning
-   No runtime downloads of public keys
-   Clear separation of trust material and binaries
-   Ready for extension

------------------------------------------------------------------------

## Intended usage

This flake is meant to be consumed by:

-   Artifact verification scripts
-   CI pipelines
-   CI test agents

It is **not** a general-purpose CA bundle.
