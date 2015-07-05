#!/bin/bash

# Author: Viacheslav Lotsmanov <lotsmanov89@gmail.com>
# License: GNU/GPLv3 (https://www.gnu.org/licenses/gpl-3.0.txt)

# constants
contents_limit=80
line_more='...'
real_contents_limit=$[$contents_limit-${#line_more}]

catch_fak() {
	[ $1 -ne 0 ] && { echo fak 1>&2; exit 1; }
}

gpaste_list=$(gpaste history --oneline 2>/dev/null)
catch_fak $?

clear_line() {
	echo "$(echo "$1" \
		| sed 's/[\t ]\+/ /g' \
		| sed 's/\(^[ ]\+\|[ ]\+$\)//g' \
		2>/dev/null)"
}

gen_pipe() {
	
	while read item; do
		
		num=$(echo "$item" | grep -o '^[0-9]\+: ' 2>/dev/null)
		catch_fak $?
		contents=$(clear_line "${item:${#num}}")
		num=$(echo "${num:0:-2}")
		
		if [ ${#contents} -gt $contents_limit ]; then
			contents="${contents::real_contents_limit}${line_more}"
		fi
		
		echo $num
		echo "$contents"
	done
}

choose=$(echo "$gpaste_list" | gen_pipe | zenity \
	--title 'gpaste-zenity' \
	--text 'GPaste' \
	--list \
	--width 800 \
	--height 600 \
	--print-column=1 \
	--column '#' --column 'Contents' \
	2>/dev/null)
[ $? -ne 0 ] && exit 1

gpaste select $choose
catch_fak $?
