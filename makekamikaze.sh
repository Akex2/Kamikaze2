#!/bin/bash
set -x
>/root/make-kamikaze.log
exec >  >(tee -ia /root/make-kamikaze.log)
exec 2> >(tee -ia /root/make-kamikaze.log >&2)
#
# base is https://rcn-ee.com/rootfs/2017-01-13/microsd/bone-ubuntu-16.04.1-console-armhf-2017-01-13-2gb.img.xz
#

# TODO 2.1: 
# PCA9685 in devicetree
# Make redeem dependencies built into redeem
# Remove xcb/X11 dependencies
# Add sources to clutter packages
# Slic3r support
# Edit Cura profiles
# Remove root access 
# /dev/ttyGS0

# TODO 2.0:
# After boot, 
# initrd img / depmod-a on new kernel. 

# STAGING: 
# Copy uboot files to /boot/uboot
# Restart commands on install for Redeem
# Update to Clutter 1.26.0+dsfg-1

# DONE: 
# consoleblank=0
# sgx-install after changing kernel
# Custom uboot
# redeem plugin
# Install libyaml
# redeem starts after spidev2.1
# Adafruit lib disregard overlay (Swithed to spidev)
# cura engine
# iptables-persistent https://github.com/eliasbakken/Kamikaze2/releases/tag/v2.0.7rc1
# clear cache
# Update dogtag
# Sync Redeem master with develop.  

# this defines the octoprint release tag version#
OCTORELEASE="1.3.1"
WD=`pwd`/
VERSION="Kamikaze 2.1.1"
OCTORELEASE=1.3.1
ROOTPASS="kamikaze"
DATE=`date`
echo "**Making ${VERSION}**"

export LC_ALL=C

port_forwarding() {
	echo "** Port Forwarding **"
	# Port forwarding
	/sbin/iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 5000
	mkdir -p /etc/iptables
	iptables-save > /etc/iptables/rules
	cat >/etc/network/if-pre-up.d/iptables <<EOL
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules
EOL
	chmod +x /etc/network/if-pre-up.d/iptables
}

install_dependencies(){
	echo "** Removing old kernels **"
	apt-get purge -y linux-image-4.4.40-ti* linux-image-4.9* rtl8723bu-modules-4.4.30-ti* rtl8723bu-modules-4.9*
	echo "** Install dependencies **"
	echo "APT::Install-Recommends \"false\";" > /etc/apt/apt.conf.d/99local
	echo "APT::Install-Suggests \"false\";" >> /etc/apt/apt.conf.d/99local
	apt-get install -y libegl1-sgx-omap3 libgles2-sgx-omap3
	apt-get install -y \
	python-pip \
	python-dev \
	swig \
	socat \
	ti-sgx-es8-modules-`uname -r` \
	libyaml-dev \
	gir1.2-mash-0.3-0 \
	gir1.2-mx-2.0 \
	python-scipy \
	python-smbus \
	python-gi-cairo \
	python-numpy \
	libavahi-compat-libdnssd1 \
	
	pip install --upgrade pip
	pip install setuptools
	pip install evdev spidev Adafruit_BBIO

	wget https://github.com/beagleboard/am335x_pru_package/archive/master.zip
	unzip master.zip
	# install pasm PRU compiler
	mkdir /usr/include/pruss
	cd am335x_pru_package-master/
	cp pru_sw/app_loader/include/prussdrv.h /usr/include/pruss/
	cp pru_sw/app_loader/include/pruss_intc_mapping.h /usr/include/pruss
	chmod 555 /usr/include/pruss/*
	cd pru_sw/app_loader/interface
	CROSS_COMPILE= make
	cp ../lib/* /usr/lib
	ldconfig
	cd ../../utils/pasm_source/
	source linuxbuild
	cp ../pasm /usr/bin/
	chmod +x /usr/bin/pasm

	apt-get autoremove -y
}



create_user() {
	echo "** Create user **"
	default_groups="admin,adm,dialout,i2c,kmem,spi,cdrom,floppy,audio,dip,video,netdev,plugdev,users,systemd-journal,tisdk,weston-launch,xenomai"
	mkdir /home/octo/
	mkdir /home/octo/.octoprint
	useradd -G "${default_groups}" -s /bin/bash -m -p octo -c "OctoPrint" octo
	chown -R octo:octo /home/octo
	chown -R octo:octo /usr/local/lib/python2.7/
	chown -R octo:octo /usr/local/bin
	chmod 755 -R /usr/local/lib/python2.7/
}

install_redeem() {
	echo "**install_redeem**"
	cd /usr/src/
	if [ ! -d "redeem" ]; then
		git clone --depth 1 https://bitbucket.org/intelligentagent/redeem
	fi
	cd redeem
	git pull
	python setup.py clean install
	# Make profiles uploadable via Octoprint
	cp -r configs /etc/redeem
	cp -r data /etc/redeem
	touch /etc/redeem/local.cfg
	chown -R octo:octo /etc/redeem/
	chown -R octo:octo /usr/src/redeem/

	cd /usr/src/Kamikaze2

	# Install rules
	cp scripts/spidev.rules /etc/udev/rules.d/

	# Install Kamikaze2 specific systemd script
	cp scripts/redeem.service /lib/systemd/system
	systemctl enable redeem
	systemctl start redeem
}

install_octoprint() {
	echo "** Install OctoPrint **" 
	cd /home/octo
	if [ ! -d "OctoPrint" ]; then
		su - octo -c "git clone --branch ${OCTORELEASE} --depth 1 https://github.com/foosel/OctoPrint.git"
	fi
	chown -R octo:octo /usr/local/lib/python2.7/dist-packages/
	chown -R octo:octo /usr/local/bin/
	su - octo -c 'cd OctoPrint && python setup.py clean install'
	su - octo -c 'pip install https://github.com/Salandora/OctoPrint-FileManager/archive/master.zip --user'
	su - octo -c 'pip install https://github.com/kennethjiang/OctoPrint-Slicer/archive/master.zip --user'

	cd /usr/src/Kamikaze2
	# Make config file for Octoprint
	cp OctoPrint/config.yaml /home/octo/.octoprint/
	chown octo:octo "/home/octo/.octoprint/config.yaml"

	# Fix permissions for STL upload folder
	mkdir -p /usr/share/models
	chown octo:octo /usr/share/models
	chmod 777 /usr/share/models

	# Grant octo redeem restart rights
	echo "%octo ALL=NOPASSWD: /bin/systemctl restart redeem.service" >> /etc/sudoers
	echo "%octo ALL=NOPASSWD: /bin/systemctl restart octoprint.service" >> /etc/sudoers
	echo "%octo ALL=NOPASSWD: /sbin/reboot" >> /etc/sudoers
	echo "%octo ALL=NOPASSWD: /sbin/shutdown -h now" >> /etc/sudoers
	echo "%octo ALL=NOPASSWD: /sbin/poweroff" >> /etc/sudoers

	echo "%octo ALL=NOPASSWD: /usr/bin/make -C /usr/src/redeem install" >> /etc/sudoers
	
	# Install systemd script
	cp ./OctoPrint/octoprint.service /lib/systemd/system/
	systemctl enable octoprint
	systemctl start octoprint
}

install_octoprint_redeem() {
	echo "**install_octoprint_redeem**"
	cd /usr/src/
	if [ ! -d "octoprint_redeem" ]; then
		git clone --depth 1 https://github.com/eliasbakken/octoprint_redeem
	fi
	cd octoprint_redeem
	python setup.py install
}

install_overlays() {
	echo "**install_overlays**"
	cd /usr/src/
	if [ ! -d "bb.org-overlays" ]; then
		git clone --depth 1 https://github.com/eliasbakken/bb.org-overlays
	fi
	cd bb.org-overlays
	./install.sh
}




install_uboot() {
	echo "** install U-boot**" 
	cd /usr/src/Kamikaze2
	export DISK=/dev/mmcblk0
	dd if=./u-boot/MLO of=${DISK} count=1 seek=1 bs=128k
	dd if=./u-boot/u-boot.img of=${DISK} count=2 seek=1 bs=384k
	cp ./u-boot/MLO /boot/uboot/
	cp ./u-boot/u-boot.img /boot/uboot/
}



install_usbreset() {
	echo "** Installing usbreset **"
	cd $WD
	cc usbreset.c -o usbreset
	chmod +x usbreset
	mv usbreset /usr/local/sbin/
}

install_smbd() {
	echo "** Installing samba **"
	apt-get -y install samba
	cat > /etc/samba/smb.conf <<EOF
	dns proxy = no
	log file = /var/log/samba/log.%m
	syslog = 0
	panic action = /usr/share/samba/panic-action %d
	server role = standalone server
	passdb backend = tdbsam
	obey pam restrictions = yes
	unix password sync = yes
	passwd program = /usr/bin/passwd %u
	passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
	pam password change = yes
	map to guest = bad user
	usershare allow guests = yes
	[homes]
		comment = Home Directories
		browseable = no
		read only = no
		create mask = 0777
		directory mask = 0777
		valid users = %S
	[printers]
		comment = All Printers
		browseable = no
		path = /var/spool/samba
		printable = yes
		guest ok = no
		read only = yes
		create mask = 0700
	[print$]
		comment = Printer Drivers
		path = /var/lib/samba/printers
		browseable = yes
		read only = yes
		guest ok = no
	[public]
		path = /usr/share/models
		public = yes
		writable = yes
		comment = smb share
		printable = no
		guest ok = yes
		locking = no
EOF
	systemctl enable smbd
	systemctl start smbd
}



install_mjpgstreamer() {
	echo "** Install mjpgstreamer **"
	apt-get install -y cmake libjpeg62-dev
	cd /usr/src/
	git clone --depth 1 https://github.com/jacksonliam/mjpg-streamer
	cd mjpg-streamer/mjpg-streamer-experimental
	sed -i 's:add_subdirectory(plugins/input_raspicam):#add_subdirectory(plugins/input_raspicam):' CMakeLists.txt
	make
	make install
	echo 'KERNEL=="video0", TAG+="systemd"' > /etc/udev/rules.d/50-video.rules
	cat > /lib/systemd/system/mjpg.service << EOL
[Unit]
 Description=Mjpg streamer
 Wants=dev-video0.device
 After=dev-video0.device

 [Service]
 ExecStart=/usr/local/bin/mjpg_streamer -i "/usr/local/lib/mjpg-streamer/input_uvc.so" -o "/usr/local/lib/mjpg-streamer/output_http.so"

 [Install]
 WantedBy=basic.target
EOL
	systemctl enable mjpg.service
	systemctl start mjpg.service
}

rename_ssh() {
	echo "** Update SSH message **"
	cat > /etc/issue.net << EOL
$VERSION
rcn-ee.net console Ubuntu Image 2017-01-13

Check that nothing is printing before any CPU/disk intensive operations!
EOL
}

dist() {
	port_forwarding
	install_dependencies
	create_user
	install_redeem
	install_octoprint
	install_octoprint_redeem
	install_overlays
	install_uboot
	install_usbreset
	install_smbd
	install_mjpgstreamer
	rename_ssh
}

dist

echo "Now reboot!"