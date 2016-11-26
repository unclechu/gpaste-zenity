#!/bin/bash

# Author: Viacheslav Lotsmanov <lotsmanov89@gmail.com>
# License: GNU/GPLv3 (https://www.gnu.org/licenses/gpl-3.0.txt)

exec 0</dev/null

LINE_MORE='...'
CONTENTS_LIMIT=80
REAL_CONTENTS_LIMIT=$[$CONTENTS_LIMIT-${#LINE_MORE}]
WND_TITLE=gpaste-zenity

GPASTE_BIN=$(
	(which gpaste-client 1>&- 2>&- && echo 'gpaste-client') || \
	(which gpaste        1>&- 2>&- && echo 'gpaste'       ) || \
	exit 1
	)
if [ $? -ne 0 ]; then
	echo 'GPaste client tool not found' 1>&2
	exit 1
fi

show_usage_info() {
	echo "Usage: $(basename "$0") [OPTION...]"
	echo '  -h       --help       Show this usage info'
	echo '  -m=MODE  --mode=MODE  Examples:'
	echo '                          --mode=select'
	echo '                          --mode=delete'
	echo '                          --mode=select-password'
	echo '                          --mode=mask-password'
	echo '                          --mode=mask-last-password'
	echo '                          --mode=rename-password'
	echo '                          --mode=select-and-rename-password'
	echo '                          --mode=choose'
}

mode=select

for opt in "$@"; do
	case $opt in
		-m=*|--mode=*)
			mode="${opt#*=}"
			shift
			;;
		-h|--help)
			show_usage_info
			exit 0
			;;
		*)
			echo "Unknown option: '$opt'" 1>&2
			show_usage_info 1>&2
			exit 1
			;;
	esac
done

case "$mode" in
	select|delete) ;;
	select-password) ;;
	mask-password|mask-last-password) ;;
	rename-password|select-and-rename-password) ;;
	choose) ;;
	*)
		echo "Unknown mode: '$mode'" 1>&2
		show_usage_info 1>&2
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
		num=$(echo "$item" | grep -o '^[0-9]\+: ' 2>&-); catch_fak $?
		contents=$(clear_line "${item:${#num}}")
		num=$(echo "${num:0:-2}")
		
		if [ ${#contents} -gt $CONTENTS_LIMIT ]; then
			contents="${contents::REAL_CONTENTS_LIMIT}${LINE_MORE}"
		fi
		
		echo "$contents"
		echo $num
	done
}

mask_password_with_name_by_id() {
	exec 0</dev/null
	
	local id=$1
	local name=$2
	
	"$GPASTE_BIN" set-password "$id" "$name" 1>&- 2>&-
	if [ $? -ne 0 ]; then
		local given_name=$("$GPASTE_BIN" get "$id" 2>&-)
		[ "${given_name:0:11}" != '[Password] ' ] && return 1
		local old_name=${given_name:11}
		"$GPASTE_BIN" rename-password "$old_name" "$name" 1>&- 2>&-
		[ $? -ne 0 ] && return 1
	fi
}

# Hack for id-independent multiple deletion
# using passwords naming.
delete_items() {
	local names=()
	while read id; do
		[ "$id" == "" ] && return 1
		local name="__marked_to_delete_$id"
		mask_password_with_name_by_id "$id" "$name" 0<&-
		names+=("$name")
	done
	for name in "${names[@]}"; do
		"$GPASTE_BIN" delete-password "$name" 0<&- 1>&- 2>&-
		[ $? -ne 0 ] && return 1
	done
	return 0
}

choose_mode() {
	local modes=(
		'Select'                              'select'
		'Delete'                              'delete'
		'Select password'                     'select-password'
		'Mask last password with name'        'mask-last-password'
		'Select password and mask with name'  'mask-password'
		'Rename password'                     'rename-password'
		'Select password and rename'          'select-and-rename-password'
		)
	local chosen_mode=$(
		printf '|%s' "${modes[@]}" \
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

get_text_from_user() {
	local text=$1
	local given_value=$(
		zenity \
			--title "$WND_TITLE" \
			--entry --text "$text" \
			2>/dev/null
		)
	([ $? -ne 0 ] || [ "$given_value" == "" ]) && return 1
	echo "$given_value"
}

select_from_history() {
	local    title=$1
	local multiple=$2
	local     list=$3
	
	local choose=$(
		echo "$list" \
		| gen_pipe \
		| zenity \
			--width 800 --height 600 \
			--title "$WND_TITLE" \
			--text "GPaste ($title)" \
			--list \
			--print-column=2 \
			--hide-column=2 \
			--hide-header \
			--mid-search \
			$([ "$multiple" -eq 1 ] && echo --multiple) \
			--column 'Contents' --column '#' \
			2>/dev/null
		)
	([ $? -ne 0 ] || [ "$choose" == "" ]) && return 1
	echo "$choose"
}

warning() {
	local msg=$1
	zenity \
		--width 300 \
		--title "$WND_TITLE" \
		--warning --text="$msg" \
		2>/dev/null
}

check_for_passwords() {
	local list=$1
	if [ "$list" == '' ]; then
		warning 'No passwords in clipboard history'
		return 1
	fi
}

get_pass_name_id() {
	local list=$1
	local name=$2
	
	while [ "$list" != '' ]; do
		local item=$(echo "$list" | head -n1)
		local item_name=$(echo "$item" | sed 's/^[0-9]\+: \[Password\] //')
		local item_id=$(echo "$item" | grep -o '^[0-9]\+')
		list=$(echo "$list" | sed 1d)
		
		[ "$item_id" != "$[$item_id]" ] && continue
		
		if [ "$name" == "$item_name" ]; then
			echo -n "$item_id"
			break
		fi
	done
}


gpaste_list=$("$GPASTE_BIN" history --oneline 2>&-); catch_fak $?
only_passwords_list=$(echo "$gpaste_list" | grep '^[0-9]\+: \[Password\] ')

ASK_PASSWORD_TEXT='Enter a name for the password'
ASK_OLD_PASSWORD_TEXT='Enter previous name of the password'
ASK_NEW_PASSWORD_TEXT='Enter new name for the password'


if [ "$gpaste_list" == '' ]; then
	warning 'Clipboard history is empty'
	exit 1
fi

if [ "$mode" == 'choose' ]; then
	mode=$(choose_mode); [ $? -ne 0 ] && exit 1
fi


if [ "$mode" == 'mask-last-password' ]; then
	
	name=$(get_text_from_user "$ASK_PASSWORD_TEXT"); [ $? -ne 0 ] && exit 1
	mask_password_with_name_by_id "$id" "$name" || exit 1
	
elif [ "$mode" == 'mask-password' ]; then
	
	id=$(select_from_history 'select password to mask' 0 "$gpaste_list")
	[ $? -ne 0 ] && exit 1
	name=$(get_text_from_user "$ASK_PASSWORD_TEXT"); [ $? -ne 0 ] && exit 1
	mask_password_with_name_by_id "$id" "$name" || exit 1
	
elif [ "$mode" == 'rename-password' ]; then
	
	check_for_passwords "$only_passwords_list" || exit 1
	
	prev_name=$(get_text_from_user "$ASK_OLD_PASSWORD_TEXT")
	[ $? -ne 0 ] && exit 1
	id=$(get_pass_name_id "$only_passwords_list" "$prev_name")
	[ $? -ne 0 ] && exit 1
	
	if [ "$id" == '' ]; then
		warning "Password by name '$prev_name' not found"
		exit 1
	fi
	
	name=$(get_text_from_user "$ASK_NEW_PASSWORD_TEXT"); [ $? -ne 0 ] && exit 1
	mask_password_with_name_by_id "$id" "$name" || exit 1
	
elif [ "$mode" == 'select-and-rename-password' ]; then
	
	check_for_passwords "$only_passwords_list" || exit 1
	
	echo 'not implemented yet!'
	exit 1
	
elif [ \
	"$mode" == 'select' \
	-o "$mode" == 'delete' \
	-o "$mode" == 'select-password' \
]; then
	if [ "$mode" == 'select-password' ]; then
		check_for_passwords "$only_passwords_list" || exit 1
	fi
	title=$(
		[ "$mode" == 'select-password' ] \
			&& echo 'select password' \
			|| echo "$mode"
		)
	list=$(
		[ "$mode" == 'select-password' ] \
			&& echo "$only_passwords_list" \
			|| echo "$gpaste_list"
		)
	action=$(
		[ "$mode" == 'select-password' ] \
			&& echo 'select' \
			|| echo "$mode"
		)
	choose=$(
		select_from_history \
			"$title" \
			"$([ "$mode" == 'delete' ] && echo 1 || echo 0)" \
			"$list"
		)
	[ $? -ne 0 ] && exit 1
	if [ "$mode" == 'delete' ]; then
		echo "$choose" | tr '|' '\n' | delete_items
	else
		"$GPASTE_BIN" "$action" "$choose"
	fi
	catch_fak $?
else
	echo "Unexpected mode: '$mode'" 1>&2
	exit 1
fi
