# Setup Hibernate

getSwap(){
    blkid -o device -t TYPE=swap
}
getUUID(){
    blkid -s UUID -o value $1
}
setup_hibernate() {
    dvc=$(getSwap )
    [ -z "$dvc" ] && echo "ERROR: no swap device found - please setup a swap device before running this script" && return 2
    rtd=$1
    [ -z "$rtd" ] && echo "ERROR: (encrypted) swap device required, in a standard install, /dev/nvme0n1p2, or /dev/sda3,..." && return 1
    uuid=$(getUUID  $rtd )
    kyfl=/etc/cryptsetup-keys.d/luks-${uuid}.key
    local resume_params="resume=${dvc//'/'/'\/'} rd.luks.name=$(getUUID $dvc )=swap rd.luks.key=${kyfl//'/'/'\/'} "
    
    echo
    echo "Setting up hibernation."
    echo "Please wait..."
    echo
    
    # Adds kernel parameter in grub boot configuration file
    confFl=/etc/dracut.conf.d/90-tpm2.conf
    if grep resume $confFl > /dev/null; then
        sed -i "s/resume=.\+ \(resume_offset=[0-9] \)\?\+/$resume_params/" $confFl
    else
        sed -i "s/\(quiet \)/$resume_params\1/" $confFl
    fi
    sed -i "s/ quiet splash/ BOOT_DEBUG=3 noplymouth/g" $confFl
    confFl=/etc/dracut.conf.d/resume-from-hibernate.conf
    cat << EOI > $confFL
install_items+=" $kyfl "
EOI
    # update-grub

    # Adds device major:minor numbers in resume configuration
    majmin=$(lsblk -o MAJ:MIN $dvc | tail -1 )
    echo $majmin > /sys/power/resume
    fl=/etc/tmpfiles.d/hibernation_resume.conf
    cat << EOI > $fl
#    Path                   Mode UID  GID  Age Argument
w    /sys/power/resume       -    -    -    -   $majmin
EOI

    # Adds hibernation option in power-off menu
    apt install -y -qq polkitd-pkla
    dr=/etc/polkit-1/localauthority/50-local.d
    [ ! -d $dr ] && mkdir -p $dr
    tee $dr/com.ubuntu.enable-hibernate.pkla << 'EOB' >/dev/null
[Re-enable hibernate by default in upower]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate
ResultActive=yes

[Re-enable hibernate by default in logind]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1;org.freedesktop.login1.hibernate-multiple-sessions;org.freedesktop.login1.hibernate-ignore-inhibit
ResultActive=yes
EOB
    dr=/etc/polkit-1/localauthority/90-mandatory.d
    [ ! -d $dr ] &&  mkdir -p $dr
    tee $dr/enable-hibernate.pkla << 'EOB' >/dev/null
[Enable hibernate]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.handle-hibernate-key;org.freedesktop.login1;org.freedesktop.login1.hibernate-multiple-sessions
ResultActive=yes
EOB
    dr=/etc/polkit-1/rules.d
    [ ! -d $dr ] && mkdir -p $dr
    tee $dr/10-enable-hibernate.rules << 'EOB' >/dev/null
polkit.addRule(function(action, subject) {
    if (action.id == \"org.freedesktop.login1.hibernate\" ||
        action.id == \"org.freedesktop.login1.hibernate-multiple-sessions\" ||
        action.id == \"org.freedesktop.upower.hibernate\" ||
        action.id == \"org.freedesktop.login1.handle-hibernate-key\" ||
        action.id == \"org.freedesktop.login1.hibernate-ignore-inhibit\")
    {
        return polkit.Result.YES;
    }
});
EOB
    echo "Rebuilding initram and boot options"
    apt install -y plymouth plymouth-themes plymouth-label firefox
    /etc/kernel/postinst.d/zzz-dracut-regenerate-all
    echo
    echo "Hibernation setup completed."
    echo "Please reboot your system for all changes to take effect."
    echo
}
