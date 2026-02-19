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

## Repository layout

.
├── flake.nix
├── flake.lock
├── slsa/
├── yubi-slsa/
└── yubi-uefi/
└── auth/

The built artifacts are installed under:

-   `…/share/ghaf-infra-pki/slsa/`
-   `…/share/ghaf-infra-pki/uefi/`
-   `…/share/ghaf-infra-pki/uefi/auth/`

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

------------------------------------------------------------------------

## Using the packaged certificates

### From scripts / verification tooling

Example:

``` bash
PKI_DIR="$(nix build .#slsa-pki --no-link)/share/ghaf-infra-pki/slsa"

openssl verify \
  -CAfile "$PKI_DIR/bundle.pem" \
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

## Optional: NixOS system-wide installation (SLSA)

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
