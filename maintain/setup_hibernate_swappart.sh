# Setup Hibernate
# Adapted from https://forums.linuxmint.com/viewtopic.php?t=425394 comment/script @random person

helptext(){

    cat << EOH
 $1 [OPTIONS] SWAP_DEVICE

    Setup hibernation for grub/dracut based distros with existing swap 
    partition (NO file support, see original script for swap file)
    
    NOTE:   this script WILL alter your default kernel command line, test first (on a VM,...)    
            and backup your data before testing it on a live machine
            Any misconfig can lead to an unbootable system(!)
    
    Arguments:
        -   SWAP_DEVICE swap device, encrypted, lvm root device or encrypted lvm root (NOT decrypted)
                        use blkid -o device -t TYPE={crypto_LUKS,LVM2} to figure which device

    Options:
        -h/--help       print this message

    Exit codes:
        0   no issue occurred
        1   no required swap root device given
        2   no swap partition found
EOH
}

getSwap(){
    blkid -o device -t TYPE=swap
}
getUUID(){
    blkid -s UUID -o value $1
}
setup_hibernate() {
    [[ "$1" == "-h" || "$1" == "--help" ]] && help_txt 'setup_hibernate' && return 0
    dvc=$(getSwap )
    [ -z "$dvc" ] && echo "ERROR: no swap device found - please setup a swap device before running this script" && return 2
    rtd=$1
    [ -z "$rtd" ] && echo "ERROR: (encrypted) swap device required, in a standard install, /dev/nvme0n1p2, or /dev/sda3,..." && return 1
    uuid=$(getUUID $rtd )
    uuis=$(getUUID $dvc )
    local resume_params="rd\.luks\.uuid=luks\-$uuis rd\.lvm.lv=main_vol\/root rd\.lvm.lv=main_vol\/swap resume=UUID=$uuis "
    
    echo
    echo "Setting up hibernation."
    echo "Please wait..."
    echo
    
    # Adds kernel parameter in grub boot configuration file/dracut kernel_cmdline config file
    confFl=
    if [ -d /etc/dracut.conf.d/ ]; then
        confFl=$(find /etc/dracut.conf.d/ -type f -name "*.conf" -exec grep -l kernel_cmdline {} + )
    else
        confFl=/etc/default/grub
    fi
    if grep resume $confFl > /dev/null; then
        sed -i "s/resume=.\+ \(resume_offset=[0-9] \)\?\+/$resume_params/" $confFl
    else
        sed -i "s/\(quiet \)/$resume_params\1/" $confFl
    fi
    
    # for dracut add a new conf with resume mod and explicit service inclusion
    # for grub: rebuild config
    if echo $confFl | grep -q dracut ; then
        confFl=/etc/dracut.conf.d/resume-from-hibernate.conf
        srvcFl=$(find /usr/lib -type f -name "systemd-hibernate-resume.service" )
        cat << EOI >> $confFL
add_dracutmodules+=" resume "
install_items+=" $srvcFl "
EOI
    else
        update-grub
    fi

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
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.upower.hibernate" ||
        action.id == "org.freedesktop.login1.handle-hibernate-key" ||
        action.id == "org.freedesktop.login1.hibernate-ignore-inhibit")
    {
        return polkit.Result.YES;
    }
});
EOB
    echo "Rebuilding initram and boot options"
    #apt install -y plymouth plymouth-themes plymouth-label firefox
    if echo $confFl | grep -q dracut; then
        /etc/kernel/postinst.d/zzz-dracut-regenerate-all
    else   
        update-initramfs -u -k all
    fi
    echo
    echo "Hibernation setup completed."
    echo "Please reboot your system for all changes to take effect."
    echo
}
