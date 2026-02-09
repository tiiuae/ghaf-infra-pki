# Ghaf Infra PKI Bundle

This repository provides a **Nix flake** that packages public PKI certificates used by the GHAF infrastructure, starting with **SLSA verification material**.

The goal is to distribute **public trust material in a reproducible, Nix-native way**, so that verification scripts can rely on **installed, pinned certificates** instead of downloading public keys from the same location as binaries.

---

## What this flake provides

The flake exposes three main things:

1. **A package** containing public SLSA certificates in the Nix store  
   (`packages.<system>.slsa-pki`)
2. **A small Nix library** exporting canonical store paths to those certificates  
   (`lib.slsaPathsFor`)
3. **An optional NixOS module** to install the certificates into the system trust store

All material in this repository is **public**. No private keys are included.

---

## Repository layout

```
.
├── flake.nix
└── slsa
    ├── bundle.pem
    ├── cacert.pem
    ├── intermediate-ca.pem
    ├── root-ca.pem
    └── tsa.crt
```

### Notes on files

- `root-ca.pem`  
  Root CA (long-lived, offline).

- `intermediate-ca.pem`  
  Intermediate CA used for signing.

- `bundle.pem`  
  CA bundle used for verification.  
  **Ordering:** root first, then intermediate(s).

  ```bash
  cat root-ca.pem intermediate-ca.pem > bundle.pem
  ```

- `cacert.pem`  
  TSA Trust anchor file used by verification scripts.

- `tsa.crt`  
  Time Stamping Authority certificate (usually a leaf, not a CA).

---

## Building the PKI package

To build the SLSA PKI package locally:

```bash
nix build .#slsa-pki
```

The result will contain:

```
result/share/ghaf-infra-pki/slsa/
├── bundle.pem
├── cacert.pem
├── intermediate-ca.pem
├── root-ca.pem
└── tsa.crt
```

These paths are stable and live in the Nix store.

---

## Using the packaged certificates

### From scripts / verification tooling

You can reference the certificates directly from the Nix store.

Example (shell):

```bash
PKI_DIR="$(nix build .#slsa-pki --no-link)/share/ghaf-infra-pki/slsa"

openssl verify \
  -CAfile "$PKI_DIR/bundle.pem" \
  artifact-cert.pem
```

This avoids downloading public keys at runtime and pins trust to the flake revision.

---

### From Nix code (recommended)

The flake exports a helper library that gives canonical paths:

```nix
let
  slsa = ghaf-infra-pki.lib.slsaPathsFor system;
in {
  trustAnchor = slsa.bundle;
  tsaCert     = slsa.tsa;
}
```

This is intended for use by Nix-wrapped verification tools and CI checks.

---

## Optional: NixOS system-wide installation

If you want these certificates installed into the **system trust store** on NixOS, enable the provided module.

### Example NixOS flake usage

```nix
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

This will:

- Install the PKI package into the system
- Add the **root and intermediate CA certificates** to `security.pki.certificates`

### TODO: `tsa.crt`

`tsa.crt` is typically a **leaf certificate** with the `timeStamping` EKU.  
It is **not** usually added to the system trust store.

Timestamp verification should instead:
- validate the TSA certificate chain to the CA, and
- pin or reference the TSA certificate explicitly in verification logic.

---

## Design goals

- Reproducible trust via flake pinning
- No runtime downloads of public keys
- Clear separation of trust material and binaries
- Ready for extension (UEFI PKI, additional domains, etc.)

Future PKI domains (e.g. `uefi/`) can be added following the same pattern as `slsa/`.

---

## Intended usage

This flake is meant to be consumed by:

- Artifact verification scripts
- CI pipelines
- Nix-based security tooling
- Users who want pinned, auditable trust material

It is not a general-purpose CA bundle.