#!/bin/bash
set -x
apt update

if ! apt list --installed 2>> /dev/null | grep sbsigntool; then
    apt -y install sbsigntool efitools efivar openssl
fi
[ ! -d /boot/efikeys ]  && mkdir -p /boot/efikeys

[ -f /boot/efikeys/PK.key ] && exit 0

openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 PK/" -keyout /boot/efikeys/PK.key -out /boot/efikeys/PK.crt -days 3650 -nodes -sha256

openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 KEK/" -keyout /boot/efikeys/KEK.key -out /boot/efikeys/KEK.crt -days 3650 -nodes -sha256

openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 db/" -keyout /boot/efikeys/db.key -out /boot/efikeys/db.crt -days 3650 -nodes -sha256

openssl x509 -in /boot/efikeys/PK.crt -out /boot/efikeys/PK.cer -outform DER

openssl x509 -in /boot/efikeys/KEK.crt -out /boot/efikeys/KEK.cer -outform DER

openssl x509 -in /boot/efikeys/db.crt -out /boot/efikeys/db.cer -outform DER

GUID="$(uuidgen --random)"

echo "$GUID" | tee -a /boot/efikeys/GUID

echo "GUID = $GUID"

cert-to-efi-sig-list -g $GUID /boot/efikeys/PK.crt /boot/efikeys/PK.esl

cert-to-efi-sig-list -g $GUID /boot/efikeys/KEK.crt /boot/efikeys/KEK.esl

cert-to-efi-sig-list -g $GUID /boot/efikeys/db.crt /boot/efikeys/db.esl

echo -n | tee -a /boot/efikeys/PK_null.esl

sign-efi-sig-list -k /boot/efikeys/PK.key -c /boot/efikeys/PK.crt PK /boot/efikeys/PK.esl /boot/efikeys/PK.auth

sign-efi-sig-list -k /boot/efikeys/PK.key -c /boot/efikeys/PK.crt PK /boot/efikeys/PK_null.esl /boot/efikeys/PK_null.auth

sync

efi-updatevar -e -f /boot/efikeys/KEK.esl KEK

efi-updatevar -e -f /boot/efikeys/db.esl db

efi-updatevar -f /boot/efikeys/PK.auth PK

sbsign --key /boot/efikeys/db.key --cert /boot/efikeys/db.crt --output /boot/efi/EFI/Boot/Bootx64.efi /boot/efi/EFI/Boot/Bootx64.efi

sbsign --key /boot/efikeys/db.key --cert /boot/efikeys/db.crt --output /boot/efi/EFI/systemd/systemd-bootx64.efi /boot/efi/EFI/systemd/systemd-bootx64.efi

sync

sbverify --cert /boot/efikeys/db.crt /boot/efi/EFI/Boot/Bootx64.efi

sbverify --cert /boot/efikeys/db.crt /boot/efi/EFI/systemd/systemd-bootx64.efi

echo 'uefi_secureboot_cert="/boot/efikeys/db.crt"' | tee -a /etc/dracut.conf.d/90-tpm2.conf

echo 'uefi_secureboot_key="/boot/efikeys/db.key"' | tee -a /etc/dracut.conf.d/90-tpm2.conf

for _kver in $(ls /boot | grep vmlinuz- | sed "s|vmlinuz-||g" ); do
    /etc/kernel/postinst.d/zzz-dracut-regenerate-all $_kver
done

