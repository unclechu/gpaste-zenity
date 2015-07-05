#!/bin/bash

# Author: Viacheslav Lotsmanov <lotsmanov89@gmail.com>
# License: GNU/GPLv3 (https://www.gnu.org/licenses/gpl-3.0.txt)

# constants
contents_limit=80
line_separator=' '
line_more='...'
real_contents_limit=$[$contents_limit-${#line_more}]

# variables
i=0
variants=()
last_one_num=
last_one_contents=

catch_fak() {
	[ $1 -ne 0 ] && { echo fak 1>&2; exit 1; }
}

count() {
	echo "$1" | wc -l 2>/dev/null
	catch_fak $?
}

add() {
	
	[ "x$last_one_num" == 'x' ] && return 1
	
	len=${#variants[@]}
	variants[$len]="$last_one_num:$last_one_contents"
}

clear_line() {
	echo "$(echo "$1" \
		| sed 's/[\t ]\+/ /g' \
		| sed 's/\(^[ ]\+\|[ ]\+$\)//g' \
		2>/dev/null)"
}

line_handler() {
	
	line=$1
	echo "$line" | grep '^[0-9]\+: ' &>/dev/null
	
	if [ $? -eq 0 ]; then
		
		add
		
		last_one_num=$(echo "$line" | sed 's/^\([0-9]\+\): .*$/\1/g' 2>/dev/null)
		catch_fak $?
		line=$(echo "$line" | sed 's/^[0-9]\+: //g' 2>/dev/null)
		catch_fak $?
		line=$(clear_line "$line")
		last_one_contents=$line
	else
		line=$(clear_line "$line")
		last_one_contents="${last_one_contents}${line_separator}${line}"
	fi
}

gen_pipe() {
	
	for item in "${variants[@]}"; do
		
		num=$(echo "$item" | sed 's/^\([0-9]\+\):.*$/\1/g' 2>/dev/null)
		catch_fak $?
		contents=$(echo "$item" | sed 's/^[0-9]\+://g' 2>/dev/null)
		catch_fak $?
		
		if [ ${#contents} -gt $contents_limit ]; then
			contents="${contents::real_contents_limit}${line_more}"
		fi
		
		echo $num
		echo "$contents"
	done
}

gpaste_list=$(gpaste history 2>/dev/null)
catch_fak $?

lines_count=$(count "$gpaste_list")

# fill #variants
while [ $i -lt $[$lines_count] ]; do
	
	i=$[$i+1]
	
	line=$(echo "$gpaste_list" | head -n 1)
	gpaste_list=$(echo "$gpaste_list" | tail -n $[`count "$gpaste_list"`-1])
	
	line_handler "$line"
done
add

choose=$(gen_pipe | zenity \
	--list \
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
