#!/bin/bash

# Author: Viacheslav Lotsmanov <lotsmanov89@gmail.com>
# License: GNU/GPLv3 (https://www.gnu.org/licenses/gpl-3.0.txt)

exec 0</dev/null

CONTENTS_LIMIT=80
LINE_MORE='...'
REAL_CONTENTS_LIMIT=$[$CONTENTS_LIMIT-${#LINE_MORE}]
MODE=select

for opt in "$@"; do
	case $opt in
		-m=*|--mode=*)
			MODE="${opt#*=}"
			shift
			;;
		*)
			echo "Unknown option: '$opt'" 1>&2
			exit 1
			;;
	esac
done

case $MODE in
	select|delete)
		;;
	*)
		echo "Unknown mode: '$MODE'" 1>&2
		exit 1
		;;
esac

gpaste_bin=
if which gpaste-client 1>&- 2>&-; then
	gpaste_bin=gpaste-client
elif which gpaste 1>&- 2>&-; then
	gpaste_bin=gpaste
else
	echo 'GPaste not found' 1>&2
	exit 1
fi

catch_fak() {
	[ $1 -ne 0 ] && { echo fak 1>&2; exit 1; }
}

gpaste_list=$("$gpaste_bin" history --oneline 2>&-)
catch_fak $?

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
		"$gpaste_bin" set-password "$id" "$name" 0<&- 1>&- 2>&-
		if [ $? -ne 0 ]; then
			local given_name=$("$gpaste_bin" get "$id" 0<&- 2>&-)
			[ "${given_name:0:11}" != '[Password] ' ] && return 1
			local old_name=${given_name:11}
			"$gpaste_bin" rename-password "$old_name" "$name" 0<&- 1>&- 2>&-
			[ $? -ne 0 ] && return 1
		fi
		names+=("$name")
	done
	for name in "${names[@]}"; do
		"$gpaste_bin" delete-password "$name" 0<&- 1>&- 2>&-
		[ $? -ne 0 ] && return 1
	done
	return 0
}

title="GPaste ($MODE)"

choose=$(echo "$gpaste_list" \
	| gen_pipe \
	| zenity \
		--title 'gpaste-zenity' \
		--text "$title" \
		--list \
		--width 800 \
		--height 600 \
		--print-column=2 \
		--hide-column=2 \
		--hide-header \
		--mid-search \
		$([ "$MODE" == 'delete' ] && echo --multiple) \
		--column 'Contents' --column '#' \
		2>/dev/null
	)
([ $? -ne 0 ] || [ "$choose" == "" ]) && exit 1

if [ "$MODE" == 'delete' ]; then
	echo "$choose" | tr '|' '\n' | delete_items
else
	"$gpaste_bin" "$MODE" "$choose"
fi
catch_fak $?
