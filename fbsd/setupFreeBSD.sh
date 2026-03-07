#!/bin/sh

ERR_EMPTY_PKG=1
ERR_NO_SUCH_PKG=2
ERR_UNSUPPORTED_DESKENV=3
ERR_NO_CONF=4

XHOME=/usr/local/etc/X11/xorg.conf.d/

DE_ENVS="cinnamon xfce gnome" # mate not supported as of now
LDM="lightdm lightdm-gtk-greeter"


installIfNotFound(){
	[ -z "$1" ] && echo Empty package name - exiting && return $ERR_EMPTY_PKG
	if ! pkg search $1 | grep .; then
		echo "'$1': No such package found in repo tree, - exiting"
		return $ERR_NO_SUCH_PKG
	fi
	if ! pkg info | grep $1; then
		pkg install -y $1
	fi
}

forEachSpace(){
	for i in $(echo $@ | sed "s/\\\s/\n/g" ); do
		echo $i
	done
}

addAllUsers(){
	for i in $(ls /home/ ); do
		groups $i | grep video || pw groupmod video -m $i
	done
}

createRCEntry(){
	if ! grep $1 /etc/rc.conf || [ "$(grep $1 /etc/rc.conf | sed "s/$1=//g" )" -ne "YES" ]; then
		sysrc $1="YES"
	fi
}

matchDEAndInstall(){
	de_e=
	for i in $(forEachSpace $DE_ENVS ); do
		echo testing $i...
		[ "$1" = "$i" ] && de_e=$i && break
	done
	if [ -z "$de_e" ]; then
		echo Desktop env $1 not supported here - use different method
		return $ERR_UNSUPPORTED_DESKENV
	fi
	if [ "$de_e" = "xfce" ] || [ "$de_e" = "cinnamon" ]; then
		for i in $(forEachSpace "$1 $LDM" ); do
			installIfNotFound $i
		done
		createRCEntry dbus_enable
		createRCEntry lightdm_enable
	else
		installIfNotFound "gnome"
		installIfNotFound "gdm"
		createRCEntry dbus_enable
		createRCEntry gdm_enable
	fi
#	xinit_str=
	case $de_e in
	"xfce")
#		xinit_str='. /usr/local/etc/xdg/xfce4/xinitrc'
	;;
	*)
#		xinit_str="exec dbus-launch --exit-with-x11 ck-launch-session $de_e-session"
		if ! grep procfs /etc/fstab; then
			printf "proc\t/proc\tprocfs\trw\t0\t0\n" >> /etc/fstab
		fi
	;;
	esac
#	for i in $(ls /home/ ); do
#		if [ ! -f /home/$i/.xinitrc ]; then
#			echo $xinit_str > /home/$i/.xinitrc
#			chown $i:$i /home/$i/.xinitrc
#		fi
#	done
}
cnfFl=$(find ./ -type f -name "basic_vm.con*" | head -1 )
cnfFl=${cnfFl:-$2}
if [ -z "$cnfFl" ]; then
	echo no config file given - aborting
	return $ERR_NO_CONF 
fi
setupXOrg(){
	fl=$(grep $1 $cnfFl | cut -d ' ' -f1 )
	if [ -n "$fl" ] && [ ! -f $XHOME$fl ]; then
		printf "$(grep $1 $cnfFl | sed "s/$fl //g" | sed "s/'//g" )" >> $XHOME$fl
	fi
}

enableEVDEV(){	
	sys_fl=/etc/sysctl.conf
	if [ ! -f $sys_fl ] || ! grep "kern\.evdev\.rcpt_mask" $sys_fl || \
		 [ "$(grep "kern\.evdev\.rcpt_mask" $sys_fl | sed "s/\(kern\.evdev\.rcpt_mask=\)\([0-9]\+\)/\2/g" )" -ne "6" ]; then
		echo kern.evdev.rcpt_mask=6 >> $sys_fl 
	fi
}

adjustMemLocked(){
	sed -i'' -e "s/\(memorylocked=\)128M/\1256M/g" /etc/login.conf
	cap_mkdb /etc/login.conf
}

setupStopRestart(){
	fl=/usr/local/etc/polkit-1/rules.d/20-shutdown.rules
	cat << EOI >> $fl
polkit.addRule(function (action, subject) {
  if ((action.id == "org.freedesktop.consolekit.system.restart" ||
      action.id == "org.freedesktop.consolekit.system.stop")
      && subject.isInGroup("video")) {
    return polkit.Result.YES;
  }
});
EOI
}

helpfct(){
	cat << EOH
 $0 [Options] [DESK_ENV]

 Setup script to install scfb driver, xorg window sys and a graphical desktop environment
 on newly installed FreeBSD system (see https://docs.freebsd.org/en/books/handbook/)

 NOTE: this script will change your FreeBSD install, create a backup when in doubt
 
	DESK_ENV	fixed value desktop environment - one of cinnamon, gnome or xfce
				defaults to cinnamon

	Options:	-h/--help 	print this message

	Exit codes:
		0	- install completed successfully
		$ERR_EMPTY_PKG	- empty package name (internal error, missing dependency?)
		$ERR_NO_SUCH_PKG	- no such package found in repo tree (internal error, missing dep?)
		$ERR_UNSUPPORTED_DESKENV	- desktop environment not found in fixed value list, see above
		$ERR_NO_CONF	- missing config file, there should be a config file named 'basic_vm.con' or 'basic_vm.conf'

	Usage:
		$0 xfce > xfce_setup.log # write printout to log file, useful in case of failure
		$0 xfce > xfce_setup.log 2>> xfce_setup.log # as above, append error print-outs to same file

EOH
}

_main(){
	case "$1" in
	"-h"|"--help")
		helpfct
		return 0
	;;
	esac
	installIfNotFound xf86-video-scfb && \
		if ! pkg info | grep "^xorg\-[0-9]\."; then
			pkg install -y xorg
		fi && enableEVDEV && \
			addAllUsers	&& \
				for i in 00- 10- 20- 90-; do
					setupXOrg $i || return $?
				done && \
					matchDEAndInstall $1 && \
						adjustMemLocked && setupStopRestart
}

_main ${1:-cinnamon}
