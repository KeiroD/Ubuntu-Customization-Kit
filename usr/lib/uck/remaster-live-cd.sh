#!/bin/bash

###################################################################################
# UCK - Ubuntu Customization Kit                                                  #
# Copyright (C) 2006-2010 UCK Team                                                #
#                                                                                 #
# UCK is free software: you can redistribute it and/or modify                     #
# it under the terms of the GNU General Public License as published by            #
# the Free Software Foundation, either version 3 of the License, or               #
# (at your option) any later version.                                             #
#                                                                                 #
# UCK is distributed in the hope that it will be useful,                          #
# but WITHOUT ANY WARRANTY; without even the implied warranty of                  #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                   #
# GNU General Public License for more details.                                    #
#                                                                                 #
# You should have received a copy of the GNU General Public License               #
# along with UCK.  If not, see <http://www.gnu.org/licenses/>.                    #
###################################################################################

function check_if_user_is_root()
{
	if [ $UID != 0 ]; then
		echo "You need root privileges"
		exit 2
	fi
}

# The mountpoint utility is buggy as it does not correctly account for bind
# mounts. This makes unmounting of REMASTER_DIR/tmp fail if /tmp is not
# mounted.
function mountpoint()
{
	case "$1" in
	-q) shift;; 	# ignore -q option
	esac

	# /proc/mounts uses octal escapes for non-printable chars.
	# This code uses "echo -e" to expand them for comparison.
	mpoints=`cat /proc/mounts | awk '{ print $2 }'`
	echo -e "$mpoints" | grep "^$1$" >/dev/null
}

# Mount - make sure target exists
function mount_directory()
{
	if [ ! -d "$2" ]; then
		mkdir -p "$2" ||
			failure "Cannot create $2"
	fi
	echo "Mounting $1"
	mount --bind "$1" "$2" ||
		failure "Cannot bind mount $1 to $2"
}

# Unmount - but only if mounted
function unmount_directory()
{
	#if mountpoint -q "$1"; then
	if mountpoint "$1"; then
		echo "Unmounting $1..."
		umount -l "$1" || failure "Cannot unmount $1"
	fi
}

# Check, whether union mounts are possible
function check_union_mounts()
{
	[ -x /sbin/mount.aufs -o -x /usr/bin/unionfs-fuse ]
}

# union_mount -- mount a r/o file system r/w
#	Parameters: src_file dest
function union_mount()
{
	# Mount the readonly volume
	[ ! -d "$2-mount" ] && mkdir -p "$2-mount"
	if mount -o loop -r "$1" "$2-mount"; then
		: ok, mount succeeded
	else
		rmdir "$2-mount" 2>/dev/null
		return 1
	fi

	# Create cache and r/w directory
	[ ! -d "$2-cache" ] && mkdir -p "$2-cache"
	[ ! -d "$2" ] && mkdir -p "$2"

	# mount as union to target
	if [ -x /sbin/mount.aufs ]; then
		mount -t aufs -o br:$2-cache:$2-mount none "$2"
	elif [ -x /usr/bin/unionfs-fuse ]; then
		unionfs-fuse -o cow,max_files=32768,hide_meta_files \
			-o allow_other,suid,dev \
			"$2-cache"=RW:"$2-mount"=RO "$2"
	else
		echo "Cannot use union_mounts!" >&2
		false
	fi
	status=$?
	if [ $status -ne 0 ]; then
		umount "$2-mount" >/dev/null 2>&1
		rmdir "$2" "$2-cache" "$2-mount" >/dev/null 2>&1
	fi
	return $status
}

# union_umount -- unmount a union_mount
#	Paramters: mountdir
function union_umount()
{
	sync
	# Kill processes possibly still using the mount
	for pid in `lsof 2>/dev/null | grep "$1" | grep -v unionfs | awk '{print $2}' | sort -u`
	do
		kill $pid
		sleep 2		# Give some time to terminate...
	done
	sync
	umount "$1"
	rmdir "$1" >/dev/null 2>&1
	rmdir "$1-cache" >/dev/null 2>&1
	umount "$1-mount"
	rmdir "$1-mount" >/dev/null 2>&1
}

# Create/Mount all filesystems for chroot environment
function mount_pseudofilesystems()
{
	if [ ! -e "$REMASTER_DIR" ]; then
		failure "Remastering root directory does not exists"
	fi

	# Create the directories we are about to mount in the root_fs tree
	#	- Create an empty apt cache
	if [ ! -d "$REMASTER_HOME/remaster-apt-cache/archives/partial" ]; then
		echo "Creating apt cache..."
		mkdir -p "$REMASTER_HOME/remaster-apt-cache/archives/partial" ||
			failure "Cannot create apt cache"
	fi
	#	- Create an empty home directory for root
	if [ ! -d "$REMASTER_HOME/remaster-root-home" ]; then
		echo "Creating root home..."
		mkdir -p "$REMASTER_HOME/remaster-root-home" ||	
			failure "Cannot create root home"
	fi

	mount_directory /proc "$REMASTER_DIR/proc"
	mount_directory /sys "$REMASTER_DIR/sys"
	mount_directory /dev/pts "$REMASTER_DIR/dev/pts"
	mount_directory /tmp "$REMASTER_DIR/tmp"
	mount_directory "$REMASTER_HOME/remaster-root-home" "$REMASTER_DIR/root"
	mount_directory "$REMASTER_HOME/remaster-apt-cache" "$REMASTER_DIR/var/cache/apt"
	
	if [ -d "/run" ]; then
		HOST_VAR_RUN="/run"
	else
		HOST_VAR_RUN="/var/run"
	fi
	if [ -d "$REMASTER_DIR/run" ]; then
		GUEST_VAR_RUN="$REMASTER_DIR/run"
	else
		GUEST_VAR_RUN="$REMASTER_DIR/var/run"
	fi
	mount_directory "$HOST_VAR_RUN" "$GUEST_VAR_RUN"

	# Mount customization scripts, if any
	if [ -e "$REMASTER_HOME/customization-scripts" ]; then
		if [ ! -d "$REMASTER_DIR/tmp/customization-scripts" ]; then
			mkdir "$REMASTER_DIR/tmp/customization-scripts" ||
				failure "Cannot create $REMASTER_DIR/tmp/customization-scripts"
		fi
		mount_directory "$REMASTER_HOME/customization-scripts" \
			"$REMASTER_DIR/tmp/customization-scripts"
	fi

}

# Unmount all filesystems mounted in chroot environment
function unmount_pseudofilesystems()
{
	if [ -n "$REMASTER_DIR" ]; then
		for i in `mount | grep " $REMASTER_DIR/" | cut -d " " -f3 | sort -r`; do
			unmount_directory "$i"
		done
	fi
}

function unmount_loopfilesystems()
{
	if [ -n "$SQUASHFS_MOUNT_DIR" ]; then
		unmount_directory "$SQUASHFS_MOUNT_DIR"
	fi

	if [ -n "$ISO_MOUNT_DIR" ]; then
		unmount_directory "$ISO_MOUNT_DIR"
	fi
}

function unmount_all()
{
	unmount_pseudofilesystems
	unmount_loopfilesystems
}

function failure()
{
	unmount_all
	echo "$@"
	exit 2
}

function script_cancelled_by_user()
{
	failure "Script cancelled by user"
}

function remove_directory()
{
	DIR_TO_REMOVE="$1"
	if [ "$DIR_TO_REMOVE" = "/" ]; then
		failure "Trying to remove root directory"
	fi
	rm -rf "$DIR_TO_REMOVE"
}

function unpack_initrd()
{
	remove_remaster_initrd
	mkdir -p "$INITRD_REMASTER_DIR" || failure "Cannot create directory $INITRD_REMASTER_DIR"

	echo "Unpacking initrd image..."
	pushd "$INITRD_REMASTER_DIR" || failure "Failed to change directory to $INITRD_REMASTER_DIR, error=$?"

	if [ -e "$ISO_REMASTER_DIR/casper/initrd.lz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/casper/initrd.lz"
		INITRD_PACK=lzma
	elif [ -e "$ISO_REMASTER_DIR/casper/initrd.gz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/casper/initrd.gz"
		INITRD_PACK=gzip
	elif [ -e "$ISO_REMASTER_DIR/install/initrd.gz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/install/initrd.gz"
		INITRD_PACK=gzip
	else
		failure "Can't find initrd.gz nor initrd.lz file"
	fi

	cat "$INITRD_FILE" | $INITRD_PACK -d | cpio -i
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		failure "Failed to unpack $INITRD_FILE to $INITRD_REMASTER_DIR, error=$RESULT"
	fi

	popd
}

function pack_initrd()
{
	if [ ! -e "$INITRD_REMASTER_DIR" ]; then
		failure "Initrd remastering directory does not exists"
	fi

	echo "Packing initrd image..."
	pushd "$INITRD_REMASTER_DIR" || failure "Failed to change directory to $INITRD_REMASTER_DIR, error=$?"

	if [ -e "$ISO_REMASTER_DIR/casper/initrd.lz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/casper/initrd.lz"
		INITRD_PACK=lzma
	elif [ -e "$ISO_REMASTER_DIR/casper/initrd.gz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/casper/initrd.gz"
		INITRD_PACK=gzip
	elif [ -e "$ISO_REMASTER_DIR/install/initrd.gz" ]; then
		INITRD_FILE="$ISO_REMASTER_DIR/install/initrd.gz"
		INITRD_PACK=gzip
	else
		failure "Can't find where to copy the initrd.packed file"
	fi

	find | cpio -H newc -o | $INITRD_PACK >"$REMASTER_HOME/initrd.packed"
	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		rm "$REMASTER_HOME/initrd.packed"
		failure "Failed to compress initird image $INITRD_REMASTER_DIR to $REMASTER_HOME/initrd.packed, error=$RESULT"
	fi
	popd

	mv "$REMASTER_HOME/initrd.packed" "$INITRD_FILE" || failure "Failed to move $REMASTER_HOME/initrd.packed to $INITRD_FILE, error=$?"
}

function mount_iso()
{
	echo "Mounting ISO image..."
	mkdir -p "$ISO_MOUNT_DIR" || failure "Cannot create directory $ISO_MOUNT_DIR, error=$?"
	mount "$ISO_IMAGE" "$ISO_MOUNT_DIR" -o loop || failure "Cannot mount $ISO_IMAGE in $ISO_MOUNT_DIR, error=$?"
}

function unmount_iso()
{
	if [ -e "$ISO_MOUNT_DIR" ] ; then
		echo "Unmounting ISO image..."
		umount "$ISO_MOUNT_DIR" || echo "Failed to unmount ISO mount directory $ISO_MOUNT_DIR, error=$?"
		rmdir "$ISO_MOUNT_DIR" || echo "Failed to remove ISO mount directory $ISO_MOUNT_DIR, error=$?"
	fi
}

function unpack_iso()
{
	echo "Unpacking ISO image..."
	cp -a "$ISO_MOUNT_DIR" "$ISO_REMASTER_DIR" || failure "Failed to unpack ISO from $ISO_MOUNT_DIR to $ISO_REMASTER_DIR"
	manifest_diff
}

function manifest_diff()
{
	#can't trap errors with diff because of its return codes,
	#we pass the diff's output to cut cause we strip the version number
	if [ -e "$ISO_REMASTER_DIR/casper/filesystem.manifest" ]; then
		if [ -e "$ISO_REMASTER_DIR/casper/filesystem.manifest-desktop" ]; then
			diff --unchanged-group-format='' "$ISO_REMASTER_DIR/casper/filesystem.manifest" "$ISO_REMASTER_DIR/casper/filesystem.manifest-desktop" | cut -d ' ' -f 1 > "$ISO_REMASTER_DIR/casper/manifest.diff"
		fi
	fi
}

function mount_squashfs()
{
	echo "Mounting SquashFS image..."
	mkdir -p "$SQUASHFS_MOUNT_DIR" || failure "Cannot create directory $SQUASHFS_MOUNT_DIR, error=$?"
	mount -t squashfs "$SQUASHFS_IMAGE" "$SQUASHFS_MOUNT_DIR" -o loop || failure "Cannot mount $SQUASHFS_IMAGE in $SQUASHFS_MOUNT_DIR, error=$?"
}

function unmount_squashfs()
{
	if [ -e "$SQUASHFS_MOUNT_DIR" ] ; then
		echo "Unmounting SquashFS image..."
		umount "$SQUASHFS_MOUNT_DIR" ||
			echo "Failed to unmount $SQUASHFS_MOUNT_DIR, error=$?"
		rmdir "$SQUASHFS_MOUNT_DIR" ||
			echo "Failed to remove directory $SQUASHFS_MOUNT_DIR, error=$?"
	fi
}

function unpack_rootfs()
{
	echo "Unpacking SquashFS image..."
	cp -a "$SQUASHFS_MOUNT_DIR" "$REMASTER_DIR" ||
		failure "Cannot copy files from $SQUASHFS_MOUNT_DIR to $REMASTER_DIR, error=$?"
}

#
# REMASTER_DIR -- root_fs tree
# REMASTER_HOME -- project directory
#
function prepare_rootfs_for_chroot()
{
	mount_pseudofilesystems

	if [ ! -e "$REMASTER_DIR/etc/resolv.conf" ] ; then
		echo "Copying resolv.conf..."
		cp -f /etc/resolv.conf "$REMASTER_DIR/etc/resolv.conf" ||
			echo "Failed to copy resolv.conf, error=$?"
	fi
		
	echo "Copying fstab/mtab..."
	if [ -f "$REMASTER_DIR/etc/fstab" ] ; then
		mv "$REMASTER_DIR/etc/fstab" "$REMASTER_DIR/etc/fstab.uck" ||
			failure "Failed to copy fstab, error=$?"
	fi
	cp -f /etc/fstab "$REMASTER_DIR/etc/fstab" ||
		failure "Failed to copy fstab, error=$?"
	cp -f /etc/mtab "$REMASTER_DIR/etc/mtab" ||
		failure "Failed to copy mtab, error=$?"

	echo "Creating DBUS uuid..."
	chroot "$REMASTER_DIR" dbus-uuidgen --ensure 1>/dev/null 2>&1

	if [ -e "$REMASTER_HOME/customization-scripts/Xcookie" ] ; then
		UCK_USER_HOME_DIR=`xauth info|grep 'Authority file'| sed "s/[ \t]//g" | sed "s/\/\.Xauthority//" | cut -d ':' -f2`
		if [ `echo $UCK_USER_HOME_DIR | cut -d '/' -f2` == 'home' ] ; then
			echo "Creating user directory..."
			chroot "$REMASTER_DIR" mkdir -p "$UCK_USER_HOME_DIR" >/dev/null 2>&1
			echo "Copying X authorization file to chroot filesystem..."
			cat "$REMASTER_HOME/customization-scripts/Xcookie" | chroot "$REMASTER_DIR" xauth -f /root/.Xauthority merge - || failure "Failed to merge X authorization file, error=$?"
			cat "$REMASTER_HOME/customization-scripts/Xcookie" | chroot "$REMASTER_DIR" xauth merge - || failure "Failed to merge X authorization file in user directory, error=$?"
		fi
	fi
	
	echo "Deactivating initctl..."
	chroot "$REMASTER_DIR" mv /sbin/initctl /sbin/initctl.uck_blocked
	chroot "$REMASTER_DIR" ln -s /bin/true /sbin/initctl
	
	echo "Deactivating update-grub..."
	chroot "$REMASTER_DIR" mv /usr/sbin/update-grub /usr/sbin/update-grub.uck_blocked
	chroot "$REMASTER_DIR" ln -s /bin/true /usr/sbin/update-grub

	echo "Deactivating grub-probe..."
	chroot "$REMASTER_DIR" mv /usr/sbin/grub-probe /usr/sbin/grub-probe.uck_blocked
	chroot "$REMASTER_DIR" ln -s /bin/true /usr/sbin/grub-probe

	echo "Hacking grub-probe postinst/postrm..."
	chroot "$REMASTER_DIR" sed -i -e "s/exec update-grub/#exec update-grub/" /etc/kernel/postinst.d/zz-update-grub
	chroot "$REMASTER_DIR" sed -i -e "s/exec update-grub/#exec update-grub/" /etc/kernel/postrm.d/zz-update-grub

	echo "Remembering kernel update state..."
	update_flags="reboot-required reboot-required.pkgs do-not-hibernate"
	varrun="$REMASTER_DIR"/var/run
	for flag in $update_flags; do
		[ -f "$varrun"/$flag ] &&
			mv "$varrun"/$flag "$varrun"/$flag.uck_blocked
	done
}

function clean_rootfs_after_chroot()
{
	echo "Restoring kernel update state..."
	update_flags="reboot-required reboot-required.pkgs do-not-hibernate"
	varrun="$REMASTER_DIR"/var/run
	for flag in $update_flags; do
		rm -f "$varrun"/$flag
		[ -f "$varrun"/$flag.uck_blocked ] &&
			mv "$varrun"/$flag.uck_blocked "$varrun"/$flag
	done

	echo "Reactivating initctl..."
	chroot "$REMASTER_DIR" rm /sbin/initctl
	chroot "$REMASTER_DIR" mv /sbin/initctl.uck_blocked /sbin/initctl
	
	echo "Reactivating update-grub..."
	chroot "$REMASTER_DIR" rm /usr/sbin/update-grub
	chroot "$REMASTER_DIR" mv /usr/sbin/update-grub.uck_blocked /usr/sbin/update-grub

	echo "Reactivating grub-probe..."
	chroot "$REMASTER_DIR" rm /usr/sbin/grub-probe
	chroot "$REMASTER_DIR" mv /usr/sbin/grub-probe.uck_blocked /usr/sbin/grub-probe

	echo "Reactivating grub-probe postinst/postrm..."
	chroot "$REMASTER_DIR" sed -i -e "s/#exec update-grub/exec update-grub/" /etc/kernel/postinst.d/zz-update-grub
	chroot "$REMASTER_DIR" sed -i -e "s/#exec update-grub/exec update-grub/" /etc/kernel/postrm.d/zz-update-grub
	
	UCK_USER_HOME_DIR=`xauth info|grep 'Authority file'| sed "s/[ \t]//g" | sed "s/\/\.Xauthority//" | cut -d ':' -f2`
	if [ `echo $UCK_USER_HOME_DIR | cut -d '/' -f2` == 'home' ] ; then
		echo "Removing /home/username directory..."
		chroot "$REMASTER_DIR" rm -rf "$UCK_USER_HOME_DIR"
	fi

	echo "Removing generated machine uuid..."
	chroot "$REMASTER_DIR" rm -f /var/lib/dbus/machine-id

	if [ ! -h "$REMASTER_DIR/etc/resolv.conf" ] ; then
		echo "Removing generated resolv.conf..."
		chroot "$REMASTER_DIR" rm -f /etc/resolv.conf
	fi
	
	echo "Removing generated fstab/mtab..."
	chroot "$REMASTER_DIR" rm -f /etc/mtab
	chroot "$REMASTER_DIR" rm -f /etc/fstab
	if [ -f "$REMASTER_DIR/etc/fstab.uck" ] ; then
		mv "$REMASTER_DIR/etc/fstab.uck" "$REMASTER_DIR/etc/fstab"
	fi

	echo "Removing crash reports..."
	chroot "$REMASTER_DIR" rm -f /var/crash/*

	unmount_pseudofilesystems

	# Need a shell to perform wildcard expansion in chroot environment!
	#	No need to clean /tmp - was a bind mount.
	echo "Cleaning up temporary directories..."
	chroot "$REMASTER_DIR" sh -c "rm -rf /var/tmp/* /var/tmp/.??*"
}

function prepare_new_files_directories()
{
	echo "Preparing directory for new files"
	if [ -e "$NEW_FILES_DIR" ]; then
		remove_directory "$NEW_FILES_DIR" ||
			failure "Failed to remove directory $NEW_FILES_DIR"
	fi
	mkdir -p "$NEW_FILES_DIR"
}

function pack_rootfs()
{
	if [ -e "$REMASTER_DIR" ]; then
		echo "Updating files lists..."
		chroot "$REMASTER_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' > "$ISO_REMASTER_DIR/casper/filesystem.manifest" || failure "Cannot update filesystem.manifest, error=$?"
		if [ $CLEAN_DESKTOP_MANIFEST == 1 ] && [ -e "$ISO_REMASTER_DIR/casper/manifest.diff" ]; then
			#stripping version number from manifest 
			cat "$ISO_REMASTER_DIR/casper/filesystem.manifest" | cut -d ' ' -f 1 > "$ISO_REMASTER_DIR/filesystem.manifest.tmp"
			# can't trap errors with diff because of its return codes
			diff --unchanged-group-format='' "$ISO_REMASTER_DIR/filesystem.manifest.tmp" "$ISO_REMASTER_DIR/casper/manifest.diff" > "$ISO_REMASTER_DIR/filesystem.manifest-desktop.tmp"
			#building the right manifest-desktop file
			chroot "$REMASTER_DIR"  dpkg-query -W --showformat='${Package} ${Version}\n' `cat "$ISO_REMASTER_DIR/filesystem.manifest-desktop.tmp"` | egrep '.+ .+' > "$ISO_REMASTER_DIR/casper/filesystem.manifest-desktop"
			#removing temp files
			rm "$ISO_REMASTER_DIR/filesystem.manifest.tmp" "$ISO_REMASTER_DIR/filesystem.manifest-desktop.tmp"
		else
			cp "$ISO_REMASTER_DIR/casper/filesystem.manifest" "$ISO_REMASTER_DIR/casper/filesystem.manifest-desktop" || failure "Failed to copy $ISO_REMASTER_DIR/casper/filesystem.manifest to $ISO_REMASTER_DIR/casper/filesystem.manifest-desktop"
		fi

		echo "Packing SquashFS image..."
		if [ -e "$ISO_REMASTER_DIR/casper/filesystem.squashfs" ]; then
			rm -f "$ISO_REMASTER_DIR/casper/filesystem.squashfs" || failure "Cannot remove $ISO_REMASTER_DIR/casper/filesystem.squashfs to make room for created squashfs image, error=$?"
		fi

		EXTRA_OPTS=""

		if [ -e "$CUSTOMIZE_DIR/rootfs.sort" ]; then
			#FIXME: space not allowed in $CUSTOMIZE_DIR
			EXTRA_OPTS="-sort $CUSTOMIZE_DIR/rootfs.sort"
		fi
		
		#if mksquashfs version => 4.1 and guest's kernel => 2.6.30 we can enable xz compression
		SQUASHFS_VERSION=`dpkg-query -p squashfs-tools | grep Version | cut -d ':' -f3 | cut -d '-' -f1`
		GUEST_KERNEL_VERSION=`ls /boot/config-* | sed 's/.*config-//' | cut -d '-' -f1 | sort -r | head -n1`
		if [ `echo -e "${SQUASHFS_VERSION}\n4.2" | sort | head -n1` = "4.2" ]; then
			if [ `echo -e "${GUEST_KERNEL_VERSION}\n2.6.30" | sort | head -n1` = "2.6.30" ]; then
				echo "Squashfs>=4.1, guest kernel>=2.6.30: Enabling XZ compression for squashfs..."
				EXTRA_OPTS="${EXTRA_OPTS} -comp xz"
			fi
		fi

		mksquashfs "$REMASTER_DIR" "$ISO_REMASTER_DIR/casper/filesystem.squashfs" $EXTRA_OPTS ||
			failure "Failed to create squashfs image to $ISO_REMASTER_DIR/casper/filesystem.squashfs, error=$?"
	else
		echo "Remastering root directory does not exists"
	fi
}

function remove_iso_remaster_dir()
{
	if [ -e "$ISO_REMASTER_DIR" ] ; then
		echo "Removing ISO remastering dir..."
		remove_directory "$ISO_REMASTER_DIR" ||
			failure "Failed to remove directory $ISO_REMASTER_DIR, error=$?"
	fi
}

function remove_remaster_dir()
{
	if [ -e "$REMASTER_DIR" ] ; then
		unmount_pseudofilesystems
		echo "Removing remastering root dir..."
		remove_directory "$REMASTER_DIR"
	fi
}

function remove_remaster_initrd()
{
	if [ -e  "$INITRD_REMASTER_DIR" ]; then
		echo "Removing initrd remastering dir..."
		remove_directory "$INITRD_REMASTER_DIR"
	fi
}

# update_iso_locale has an optional argument - the language of the live CD
function update_iso_locale()
{
	echo "Updating locale"

	if [ -e "$CUSTOMIZE_DIR/livecd_locale" ]; then
		LIVECD_LOCALE=`cat "$CUSTOMIZE_DIR/livecd_locale"`
	elif [ -n "$1" ]; then
		LIVECD_LOCALE="$1"
	fi

	if [ -n "$LIVECD_LOCALE" ]; then
		cat "$ISO_REMASTER_DIR/isolinux/isolinux.cfg" | sed "s#\<append\>#append debian-installer/locale=$LIVECD_LOCALE#g" >"$NEW_FILES_DIR/isolinux.cfg"
		RESULT=$?
		if [ $RESULT -ne 0 ]; then
			failure "Failed to filter $ISO_REMASTER_DIR/isolinux/isolinux.cfg into $NEW_FILES_DIR/isolinux.cfg, error=$RESULT"
		fi

		cp -a "$NEW_FILES_DIR/isolinux.cfg" "$ISO_REMASTER_DIR/isolinux/isolinux.cfg" || failure "Failed to copy $NEW_FILES_DIR/isolinux.cfg to $ISO_REMASTER_DIR/isolinux/isolinux.cfg, error=$?"
	fi
}

# pack_iso has one mandatory argument (the architecture of the ISO)
# and an optional second argument - the live ISO description
function pack_iso()
{
	if [ ! -e "$ISO_REMASTER_DIR" ]; then
		failure "ISO remastering directory does not exists"
	fi

	#skip boot.cat, isolinux.bin, md5sums.txt
	#mismatches are for those files, because they are generated by mkisofs or by generating MD5 sums:
	EXCLUDED_FROM_MD5="./isolinux/isolinux.bin ./isolinux/boot.cat ./md5sum.txt ./.checksum.md5 ./manifest.diff"
	EXCLUDED_FROM_MD5_EXPRESSION=$(echo $EXCLUDED_FROM_MD5 | tr ' ' '|')
	EXCLUDED_FROM_MD5_EXPRESSION="($EXCLUDED_FROM_MD5_EXPRESSION)"

	echo "Updating md5sums..."
	pushd "$ISO_REMASTER_DIR"
	find . -type f -print0 | grep --null-data -v -E "$EXCLUDED_FROM_MD5_EXPRESSION" | xargs -0 md5sum | tee md5sum.txt | sed 's/ \.\// /g' >.checksum.md5
	popd

	echo "Packing ISO image..."

	if [ -e "$CUSTOMIZE_DIR/iso_description" ] ; then
		LIVECD_ISO_DESCRIPTION=`cat "$CUSTOMIZE_DIR/iso_description"`
	elif [ -n "$2" ]; then
		LIVECD_ISO_DESCRIPTION="$2"
	else
		LIVECD_ISO_DESCRIPTION="Remastered Ubuntu LiveCD"
	fi

	echo "ISO description set to: $LIVECD_ISO_DESCRIPTION"

	MKISOFS_EXTRA_OPTIONS=""
	if [ -e "$CUSTOMIZE_DIR/mkisofs_extra_options" ] ; then
		MKISOFS_EXTRA_OPTIONS=`cat "$CUSTOMIZE_DIR/mkisofs_extra_options"`
	fi

	if [ "$1" = "ppc" ]; then
		genisoimage -o "$NEW_FILES_DIR/$NEW_ISO_FILE_NAME" \
			-p "Ubuntu Customization Kit - http://uck.sf.net" \
			-probe -map "$UCK_LIBRARIES_DIR/hfs.map" -chrp-boot -iso-level 2 \
			-part -no-desktop -r --netatalk -hfs \
			-hfs-bless "$ISO_REMASTER_DIR/install" \
			-x "$ISO_REMASTER_DIR"/casper/manifest.diff \
			-V "$LIVECD_ISO_DESCRIPTION" \
			-joliet-long \
			$MKISOFS_EXTRA_OPTIONS \
			"$ISO_REMASTER_DIR"
	elif [ "$1" = "x86_64" ]; then
		genisoimage -o "$NEW_FILES_DIR/$NEW_ISO_FILE_NAME" \
			-b "isolinux/isolinux.bin" -c "isolinux/boot.cat" \
			-p "Ubuntu Customization Kit - http://uck.sf.net" \
			-no-emul-boot -boot-load-size 4 -boot-info-table \
			-V "$LIVECD_ISO_DESCRIPTION" -cache-inodes -r -J -l \
			-x "$ISO_REMASTER_DIR"/casper/manifest.diff \
			-joliet-long \
			$MKISOFS_EXTRA_OPTIONS \
			"$ISO_REMASTER_DIR"
	elif [ "$1" = "ia64" ]; then
		genisoimage -o "$NEW_FILES_DIR/$NEW_ISO_FILE_NAME" \
		-b "isolinux/isolinux.bin" -c "isolinux/boot.cat" \
		-no-emul-boot -V "$LIVECD_ISO_DESCRIPTION" -J -r \
		-x "$ISO_REMASTER_DIR"/casper/manifest.diff \
		-joliet-long \
		$MKISOFS_EXTRA_OPTIONS \
		"$ISO_REMASTER_DIR"
	else
		genisoimage -o "$NEW_FILES_DIR/$NEW_ISO_FILE_NAME" \
			-b "isolinux/isolinux.bin" -c "isolinux/boot.cat" \
			-p "Ubuntu Customization Kit - http://uck.sf.net" \
			-no-emul-boot -boot-load-size 4 -boot-info-table \
			-V "$LIVECD_ISO_DESCRIPTION" -cache-inodes -r -J -l \
			-x "$ISO_REMASTER_DIR"/casper/manifest.diff \
			-joliet-long \
			$MKISOFS_EXTRA_OPTIONS \
			"$ISO_REMASTER_DIR"
	fi

	RESULT=$?
	if [ $RESULT -ne 0 ]; then
		failure "Failed to pack ISO image, error=$RESULT"
	fi
	
	if [ $HYBRID = 1 ]; then
		if [ -e "/usr/bin/isohybrid" ] ; then
			echo "Making your ISO hybrid..."
			/usr/bin/isohybrid "$NEW_FILES_DIR/$NEW_ISO_FILE_NAME"
			
			RESULT=$?
			if [ $RESULT -ne 0 ]; then
				failure "Failed to pack ISO image, error=$RESULT"
			fi
		else
			failure "You asked for a hybrid ISO but isohybrid command was not found"
		fi
	fi
}

function generate_md5_for_new_iso()
{
	echo "Generating md5sum for newly created ISO..."
	cd $NEW_FILES_DIR
	md5sum $NEW_ISO_FILE_NAME > $NEW_ISO_FILE_NAME.md5
}

######################
# some useful things #
######################

if [ -e libraries/remaster-live-cd.sh ]; then
	UCK_LIBRARIES_DIR=./libraries
else
	UCK_LIBRARIES_DIR=/usr/lib/uck/
fi

export LC_ALL=C
check_if_user_is_root
trap unmount_all EXIT
trap script_cancelled_by_user SIGINT
