#!/bin/bash
set -x
apt update

if ! apt list --installed 2>> /dev/null | grep efitools; then
    apt -y install sbsigntool efitools efivar openssl
fi
[ ! -d /boot/efikeys ]  && mkdir -p /boot/efikeys

[ -f /boot/efikeys/PK.key ] && exit 0

createKey(){
    openssl req -new -x509 -newkey rsa:4096 -subj "$1" -keyout $2 -out $3 -days 3650 -nodes -sha256
}
createCert(){
    openssl x509 -in $1 -out $2 -outform DER
}
addCert2EFISig(){
    cert-to-efi-sig-list -g $1 $2 $3
}
signEFISigList(){
    sign-efi-sig-list -k /boot/efikeys/PK.key -c /boot/efikeys/PK.crt PK $1 ${1//'.esl'/'.auth'}
}
updateEFIVars(){
    efi-updatevar $3 -f $1 $2
}
signEFI(){
    sbsign --key /boot/efikeys/db.key --cert /boot/efikeys/db.crt --output {,}$1
}
verify(){
    sbverify --cert /boot/efikeys/db.crt $1
}
# openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 PK/" -keyout /boot/efikeys/PK.key -out /boot/efikeys/PK.crt -days 3650 -nodes -sha256
createKey "/CN=mint22 PK/" /boot/efikeys/PK.key /boot/efikeys/PK.crt

#openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 KEK/" -keyout /boot/efikeys/KEK.key -out /boot/efikeys/KEK.crt -days 3650 -nodes -sha256
createKey "/CN=mint22 KEK/" /boot/efikeys/KEK.key /boot/efikeys/KEK.crt

#openssl req -new -x509 -newkey rsa:4096 -subj "/CN=mint22 db/" -keyout /boot/efikeys/db.key -out /boot/efikeys/db.crt -days 3650 -nodes -sha256
createKey "/CN=mint22 db/" /boot/efikeys/db.key /boot/efikeys/db.crt


#openssl x509 -in /boot/efikeys/PK.crt -out /boot/efikeys/PK.cer -outform DER
createCert /boot/efikeys/PK.crt /boot/efikeys/PK.cer

#openssl x509 -in /boot/efikeys/KEK.crt -out /boot/efikeys/KEK.cer -outform DER
createCert /boot/efikeys/KEK.crt /boot/efikeys/KEK.cer

#openssl x509 -in /boot/efikeys/db.crt -out /boot/efikeys/db.cer -outform DER
createCert /boot/efikeys/db.crt /boot/efikeys/db.cer

GUID="$(uuidgen --random)"

echo "$GUID" | tee -a /boot/efikeys/GUID

echo "GUID = $GUID"

# cert-to-efi-sig-list -g $GUID /boot/efikeys/PK.crt /boot/efikeys/PK.esl
addCert2EFISig $GUID /boot/efikeys/PK.crt /boot/efikeys/PK.esl

#cert-to-efi-sig-list -g $GUID /boot/efikeys/KEK.crt /boot/efikeys/KEK.esl
addCert2EFISig $GUID /boot/efikeys/KEK.crt /boot/efikeys/KEK.esl

#cert-to-efi-sig-list -g $GUID /boot/efikeys/db.crt /boot/efikeys/db.esl
addCert2EFISig $GUID /boot/efikeys/db.crt /boot/efikeys/db.esl

echo -n | tee -a /boot/efikeys/PK_null.esl

#sign-efi-sig-list -k /boot/efikeys/PK.key -c /boot/efikeys/PK.crt PK /boot/efikeys/PK.esl /boot/efikeys/PK.auth
signEFISigList /boot/efikeys/PK.esl

#sign-efi-sig-list -k /boot/efikeys/PK.key -c /boot/efikeys/PK.crt PK /boot/efikeys/PK_null.esl /boot/efikeys/PK_null.auth
signEFISigList /boot/efikeys/PK_null.esl

sync

#efi-updatevar -e -f /boot/efikeys/KEK.esl KEK
updateEFIVars /boot/efikeys/KEK.esl KEK -e

#efi-updatevar -e -f /boot/efikeys/db.esl db
updateEFIVars /boot/efikeys/db.esl db -e

#efi-updatevar -f /boot/efikeys/PK.auth PK
updateEFIVars /boot/efikeys/PK.auth PK

# sbsign --key /boot/efikeys/db.key --cert /boot/efikeys/db.crt --output /boot/efi/EFI/Boot/Bootx64.efi /boot/efi/EFI/Boot/Bootx64.efi
signEFI /boot/efi/EFI/Boot/Bootx64.efi

#sbsign --key /boot/efikeys/db.key --cert /boot/efikeys/db.crt --output /boot/efi/EFI/systemd/systemd-bootx64.efi /boot/efi/EFI/systemd/systemd-bootx64.efi
signEFI /boot/efi/EFI/systemd/systemd-bootx64.efi

[ -f /boot/efi/EFI/refind/refind_x64.efi ] && signEFI /boot/efi/EFI/refind/refind_x64.efi

sync

verify /boot/efi/EFI/Boot/Bootx64.efi

verify /boot/efi/EFI/systemd/systemd-bootx64.efi

[ -f /boot/efi/EFI/refind/refind_x64.efi ] && verify /boot/efi/EFI/refind/refind_x64.efi

if ! grep uefi_secureboot_cert /etc/dracut.conf.d/90-tpm2.conf; then
    echo 'uefi_secureboot_cert="/boot/efikeys/db.crt"' | tee -a /etc/dracut.conf.d/90-tpm2.conf

    echo 'uefi_secureboot_key="/boot/efikeys/db.key"' | tee -a /etc/dracut.conf.d/90-tpm2.conf
fi

for _kver in $(ls /boot | grep vmlinuz- | sed "s|vmlinuz-||g" ); do
    /etc/kernel/postinst.d/zzz-dracut-regenerate-all $_kver
done

