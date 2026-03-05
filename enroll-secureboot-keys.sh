#!/usr/bin/env bash

# Enrolls UEFI Secure Boot keys (DB, KEK, PK) into EFI firmware variables.

set -euo pipefail

check_file() {
  if [[ ! -f $1 ]]; then
    echo "File '$1' not found!"
    exit 1
  fi
}

check_file "$DBPEM"
check_file "$KEKPEM"
check_file "$PKAUTH"

run_chattr() {
  VAR="$(find /sys/firmware/efi/efivars/ -maxdepth 1 -name "$1" -print -quit)"
  if [[ -n $VAR ]]; then
    echo "[+] Running chattr on $VAR"
    sudo chattr -i "$VAR"
  fi
}

run_chattr "db-*"
run_chattr "KEK-*"

echo "Updating efi variables"
sudo efi-updatevar -c "$DBPEM" db
sudo efi-updatevar -c "$KEKPEM" KEK
sudo efi-updatevar -f "$PKAUTH" PK
echo "Success!"
