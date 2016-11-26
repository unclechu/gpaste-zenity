#!/bin/bash

# Author: Viacheslav Lotsmanov <lotsmanov89@gmail.com>
# License: GNU/GPLv3 (https://www.gnu.org/licenses/gpl-3.0.txt)

exec 0</dev/null

CONTENTS_LIMIT=80
LINE_MORE='...'
REAL_CONTENTS_LIMIT=$[$CONTENTS_LIMIT-${#LINE_MORE}]
WND_TITLE=gpaste-zenity

# could be changed by 'choose' mode
mode=select

GPASTE_BIN=$(\
	(which gpaste-client 1>&- 2>&- && echo 'gpaste-client') || \
	(which gpaste        1>&- 2>&- && echo 'gpaste'       ) || \
	exit 1
	)
if [ $? -ne 0 ]; then
	echo 'GPaste client tool not found' 1>&2
	exit 1
fi

for opt in "$@"; do
	case $opt in
		-m=*|--mode=*)
			mode="${opt#*=}"
			shift
			;;
		*)
			echo "Unknown option: '$opt'" 1>&2
			exit 1
			;;
	esac
done

case "$mode" in
	select|delete|choose)
		;;
	*)
		echo "Unknown mode: '$mode'" 1>&2
		exit 1
		;;
esac

catch_fak() {
	[ $1 -ne 0 ] && { echo fak 1>&2; exit 1; }
}

clear_line() {
	echo "$1" \
		| sed 's/[\t\r\n ]\+/ /g' \
		| sed 's/\(^[ ]\+\|[ ]\+$\)//g' \
		2>&-
}

gen_pipe() {
	while read item; do
		num=$(echo "$item" | grep -o '^[0-9]\+: ' 2>&-)
		catch_fak $?
		contents=$(clear_line "${item:${#num}}")
		num=$(echo "${num:0:-2}")
		
		if [ ${#contents} -gt $CONTENTS_LIMIT ]; then
			contents="${contents::REAL_CONTENTS_LIMIT}${LINE_MORE}"
		fi
		
		echo "$contents"
		echo $num
	done
}

# Hack for id-independent multiple deletion
# using passwords naming.
delete_items() {
	local names=()
	while read id; do
		[ "$id" == "" ] && return 1
		local name="__marked_to_delete_$id"
		"$GPASTE_BIN" set-password "$id" "$name" 0<&- 1>&- 2>&-
		if [ $? -ne 0 ]; then
			local given_name=$("$GPASTE_BIN" get "$id" 0<&- 2>&-)
			[ "${given_name:0:11}" != '[Password] ' ] && return 1
			local old_name=${given_name:11}
			"$GPASTE_BIN" rename-password "$old_name" "$name" 0<&- 1>&- 2>&-
			[ $? -ne 0 ] && return 1
		fi
		names+=("$name")
	done
	for name in "${names[@]}"; do
		"$GPASTE_BIN" delete-password "$name" 0<&- 1>&- 2>&-
		[ $? -ne 0 ] && return 1
	done
	return 0
}

choose_mode() {
	local modes=( \
		"Select" "select" \
		"Delete" "delete"
		)
	local chosen_mode=$(printf "|%s" "${modes[@]}" \
		| cut -b '2-' \
		| tr '|' '\n' \
		| zenity \
			--width 320 --height 240 \
			--title "$WND_TITLE" \
			--text 'GPaste (choose action)' \
			--list \
			--print-column=2 \
			--hide-column=2 \
			--hide-header \
			--mid-search \
			--column 'Action' --column='System action' \
			2>/dev/null
		)
	([ $? -ne 0 ] || [ "$chosen_mode" == "" ]) && return 1
	echo "$chosen_mode"
}


gpaste_list=$("$GPASTE_BIN" history --oneline 2>&-)
catch_fak $?

if [ "$gpaste_list" == "" ]; then
	zenity \
		--width 200 \
		--title "$WND_TITLE" \
		--warning --text="Clipboard history is empty"
	exit 1
fi


if [ "$mode" == 'choose' ]; then
	mode=$(choose_mode)
	[ $? -ne 0 ] && exit 1
fi


title="GPaste ($mode)"

choose=$(echo "$gpaste_list" \
	| gen_pipe \
	| zenity \
		--width 800 --height 600 \
		--title "$WND_TITLE" \
		--text "$title" \
		--list \
		--print-column=2 \
		--hide-column=2 \
		--hide-header \
		--mid-search \
		$([ "$mode" == 'delete' ] && echo --multiple) \
		--column 'Contents' --column '#' \
		2>/dev/null
	)
([ $? -ne 0 ] || [ "$choose" == "" ]) && exit 1

if [ "$mode" == 'delete' ]; then
	echo "$choose" | tr '|' '\n' | delete_items
else
	"$GPASTE_BIN" "$mode" "$choose"
fi
catch_fak $?
