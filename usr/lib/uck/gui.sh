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

# DESCRIPTION:
#	This shell library module provides user interface funtionality.
#
#	It looks for and uses the best possible UI for shell procedures
#	and falls back to simple builtin functionality if none is found.
#
#	This module has been written so it works in many shells, e.g.:
#		bash, dash, ash, busybox, zsh, ksh
#	have been tested. Minimum requirement is a shell that can handle
#	functions and your typical selection of standard commands.
#
#	For similar work in other areas see:
#		http://sourceforge.net/projects/ui-dialog/
#
# PROVIDES:
#	find_dialog() -- determine dialog system to use
#	dialog_menu(descr, c1, c2, ...) -- solicit a single choice from the user
#	dialog_multi_choice(descr, c1, c2, ...) -- solicit multiple choices
#	dialog_line_input(descr, init) -- solicit a single line of input
#	dialog_choose_file(descr) -- select a file
#	dialog_msgbox(title, message) -- display a message and wait for input
#	dialog_question(title, question) -- display a yes/no question
#
# Some notes on cross-shell portability:
#	- "which" is a zsh builtin that does not work the way we need it. So
#	  we use /usr/bin/which instead.
#	- Using command substitution within a test expression does not work
#	  quite right in some shells. Using intermediate varaibles instead.
#	- Expressions are evaluated by expr and arrays are handled via eval.

# _dialog_type is set when the module is loaded and defines the type
# of user interface. Possible values (in order of preference) are:
#		kdialog		-- use kdialog
#		zenity		-- use zenity
#		dialog		-- use dialog
#		builtin		-- use shell-only builtins
_dialog_type=builtin

# find_dialog -- find the best type of dialog that is usable
find_dialog() {
	if [ -n "$DISPLAY" ]; then
		# Check availability of X windows based dialogs
		kdialog=`/usr/bin/which kdialog`
		zenity=`/usr/bin/which zenity`
		if [ -n "$kdialog" ]; then
			_dialog_type=kdialog
		elif [ -n "$zenity" ]; then
			_dialog_type=zenity
		fi
	fi

	if [ -z "$DISPLAY" -o $_dialog_type = builtin ]; then
		# None of the X windows based dialogs found/usable.
		dialog=`/usr/bin/which dialog`
		if [ -n "$dialog" ]; then
			_dialog_type=dialog
		fi
	fi
}

# dialog_menu -- solicit a single choice from the user
#	Parameters: descr choice [choice [...]]
#	Returns: selected choice on stdout
#	Status: 0 for success, 1 for failure
dialog_menu() {
	descr="$1"; shift

	case $_dialog_type in
	kdialog)
		# Create key/value pairs for argument list
		i=0; args=
		while [ -n "$1" ]; do
			i=`expr $i + 1`
			args="$args $i '$1'"; shift
		done
		eval set -- "$args"

		choice=`kdialog --menu "$descr" "$@"`

		# Convert key returned by dialog to value
		if expr "$choice" : '[1-9][0-9]*$' >/dev/null; then
			eval echo \$`expr $choice \* 2`
			return 0
		fi
		return 1
		;;

	zenity)
		zenity --list --width=500 --height=400 \
			--column "$descr" "$@"
		return $?
		;;

	dialog)
		# Create key/value pairs for argument list
		i=0; args=
		while [ -n "$1" ]; do
			i=`expr $i + 1`
			args="$args $i '$1'"; shift
		done
		eval set -- "$args"

		choice=`dialog --stdout --menu "$descr" 20 30 10 "$@"`

		# Convert key returned by dialog to value
		if expr "$choice" : '[1-9][0-9]*$' >/dev/null; then
			eval echo \$`expr $choice \* 2`
			return 0
		fi
		return 1
		;;

	builtin)
		echo >&2
		echo "$descr" >&2
		i=0
		while [ $i -lt $# ]; do
			i=`expr $i + 1`
			eval echo "$i\)	\$$i" >&2
		done
		echo -n "Your choice (1..$#)> " >&2
		read choice

		# Convert key returned by dialog to value
		if expr "$choice" : '[1-9][0-9]*$' >/dev/null; then
			eval echo \$$choice
			return 0
		fi
		return 1
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac
}

# dialog_multi_choice -- solicit multiple choices from the user
#	Parameters: descr choice [choice [...]]
#	Returns: selected choices on stdout
#	Status: 0 for success, 1 for failure
dialog_multi_choice() {
	descr="$1"; shift

	case $_dialog_type in
	kdialog)
		args=
		for i; do
			args="$args '$i' '$i' 0"
		done
		eval set -- "$args"
		kdialog --separate-output --checklist "$descr" "$@"
		;;

	zenity)
		args=
		for i; do
			args="$args '$i' '$i'"
		done
		eval set -- "$args"
		zenity --separator $'\n' --list --checklist --multiple --width=500 --height=400 \
			--text "$descr" --column "" --column ""  "$@"
		;;

	dialog)
		args=
		for i; do
			args="$args '$i' '' 0"
		done
		eval set -- "$args"
		dialog --stdout --separate-output --checklist "$descr" \
			20 30 10 "$@"
		;;

	builtin)
		selection=
		while :
		do
			i=0
			while [ $i -lt $# ]; do
				i=`expr $i + 1`
				eval echo "$i\)	\$$i" >&2
			done
			echo "Currently selected: $selection" >&2
			echo -n "Your choice (1..$#, 0 or epmty line if done, -1 to abort) > " >&2
			read choice

			case $choice in
			-1)	return 1;;
			""|0)	break;;
			esac

			# Sanity checks
			if expr "$choice" : '[1-9][0-9]*$' >/dev/null; then
				: this is what we need
			else
				continue
			fi
			[ "$choice" -gt $# ] && continue

			# Delete if already in selection
			found=0
			nselection=
			for chosen in $selection
			do
				if [ $chosen -eq $choice ]; then
					found=1
				else
					nselection="$nselection $chosen"
				fi
			done
			selection="$nselection"

			# Append if not found
			if [ $found -eq 0 ]; then
				selection="$selection $choice"
			fi
		done

		# Create list with choices selected on stdout
		if [ -n "$selection" ]; then
			for choice in $selection; do
				eval echo \$$choice
			done
			return 0
		fi

		return 1
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac
}

# dialog_line_input -- negotiate a single line of input from the user
#	Arguments: descr initial_value
#	Returns: a single line on stdout
#	Status: 0 for success, 1 for failure
dialog_line_input() {
	descr="$1"; shift
	initial="$1"; shift

	case $_dialog_type in
	kdialog)
		kdialog --inputbox "$descr" "$initial"
		;;

	zenity)
		zenity --entry --text "$descr" --entry-text "$initial"
		;;

	dialog)
		dialog --stdout --inputbox "$descr" 20 30 "$initial"
		;;

	builtin)
		echo >&2
		echo "$descr" >&2
		echo -n "($initial)> " >&2
		read line
		case $line in
		"")	echo "$initial";;
		*)	echo "$line";;
		esac
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac

	return $?
}

# dialog_choose_file -- solicit a single file name from the user
#	Parameters: descr
#	Returns: selected file name on stdout
#	Status: 0 for success, 1 for failure
dialog_choose_file() {
	descr="$1"; shift

	case $_dialog_type in
	kdialog)
		kdialog --title "$descr" --getopenfilename "`pwd`/"
		;;

	zenity)
		zenity --title "$descr" --file-selection "`pwd`/"
		;;

	dialog)
		dialog --stdout --title "$descr" --fselect "`pwd`/" 10 70
		;;

	builtin) # run in subshell to leave cwd alone for caller
		( while :
		do
			echo >&2
			echo "$descr" >&2
			echo "Current working directory: `pwd`" >&2
			ls >&2
			echo -n "Please enter file name, empty to abort > " >&2
			read answ
			if [ -z "$answ" ]; then
				return 1
			fi
			if [ -f "$answ" ]; then
				echo "`pwd`/$answ"
				return 0
			fi
			if [ -d "$answ" ]; then
				cd "$answ"
				continue
			fi
			echo "That is not the name of a file. Try again..." >&2
		done )
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac

	return $?
}

# dialog_msgbox -- Show message and wait for user to acknowledge
#	Parameters: descr text
#	Returns: nothing
#	Status: nothing
dialog_msgbox() {
	descr="$1"; shift
	text="$1"; shift

	case $_dialog_type in
	kdialog)
		kdialog --title "$descr" --msgbox "$text"
		;;

	zenity)
		echo -n "$text" |
		zenity --title "$descr" --text-info --width=500 --height=400
		;;

	dialog)
		dialog --title "$descr" --msgbox "$text" 20 80
		;;

	builtin)
		echo >&2
		echo "$descr" >&2
		echo "$text" >&2
		echo -n "Hit <RETURN> to continue..." >&2
		read dummy
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac
}

# dialog_question -- solicit a yes/no answer from the user
#	Parameters: descr question
#	Returns: nothing
#	Status: 0 for success / yes, 1 for failure / no
dialog_question() {
	descr="$1"; shift
	text="$1"; shift

	case $_dialog_type in
	kdialog)
		kdialog --title "$descr" --yesno "$text"
		;;

	zenity)
		zenity --title "$descr" --question --text "$text"
		;;

	dialog)
		dialog --title "$descr" --yesno "$text" 20 80
		;;

	builtin)
		echo >&2
		echo "$descr" >&2
		echo -n "$text (y/N)> " >&2
		read answ
		case $answ in
		[Yy]*)	return 0;;
		*)	return 1;;
		esac
		;;

	*)	echo "$0: internal error: fall through case" >&2; exit 100
		;;
	esac
}

find_dialog
