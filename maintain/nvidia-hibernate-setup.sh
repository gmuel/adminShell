#!/bin/bash

helptxt(){
    cat << EOH
$0 [options]
    create nvidia driver required service units for hibernation/suspend-2-disk
    
    info    -   service units were taken from https://github.com/MrJimm/Ubuntu-Nvidia-GPU-hibernation-fix/tree/main
    info    -   correction of /lib/systemd/system-sleep/nvidia taken from https://forum.artixlinux.org/index.php/topic,7425.0.html
    
    options:
        -h/--help   print this message
EOH
}
case "$1" in
    '-h'|'--help') helptxt && exit
esac
fl=/etc/systemd/system/nvidia-hibernate.service

if [ ! -f $fl ]; then
    cat << EOI >> $fl
[Unit]
Description=NVIDIA system hibernate actions
Before=systemd-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/bin/logger -t hibernate -s "nvidia-hibernate.service"
ExecStart=/usr/bin/nvidia-sleep.sh "hibernate"

[Install]
RequiredBy=systemd-hibernate.service
EOI

fi

fl=/etc/systemd/system/nvidia-suspend.service

if [ ! -f $fl ]; then
    cat << EOI >> $fl
[Unit]
Description=NVIDIA system suspend actions
Before=systemd-suspend.service

[Service]
Type=oneshot
ExecStart=/usr/bin/logger -t suspend -s "nvidia-suspend.service"
ExecStart=/usr/bin/nvidia-sleep.sh "suspend"

[Install]
RequiredBy=systemd-suspend.service
EOI

fi

fl=/etc/systemd/system/nvidia-resume.service

if [ ! -f $fl ]; then
    cat << EOI >> $fl
[Unit]
Description=NVIDIA system resume actions
After=systemd-suspend.service
After=systemd-hibernate.service

[Service]
Type=oneshot
ExecStart=/usr/bin/logger -t suspend -s "nvidia-resume.service"
ExecStart=/usr/bin/nvidia-sleep.sh "resume"

[Install]
RequiredBy=systemd-suspend.service
RequiredBy=systemd-hibernate.service
EOI

fi

fl=/lib/systemd/system-sleep/nvidia
if [ -f $fl ] && grep -v -q 'pre)' $fl ; then
    sed -i.1 "s/\(post)\)/pre)\n        \/usr\/bin\/nvidia-sleep\.sh \"suspend\"\n    \1/g" /lib/systemd/system-sleep/nvidia
fi

fl=/etc/modprobe.d/nvidia-graphics-drivers-kms.conf
if [ -f $fl ] && grep -q 'NVreg_PreserveVideoMemoryAllocations=1'; then
    sed -i.1 "s/\(NVreg_PreserveVideoMemoryAllocations=\)1/\10/g" $fl
fi
