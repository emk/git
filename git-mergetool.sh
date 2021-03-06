#!/bin/sh
#
# This program resolves merge conflicts in git
#
# Copyright (c) 2006 Theodore Y. Ts'o
#
# This file is licensed under the GPL v2, or a later version
# at the discretion of Junio C Hamano.
#

USAGE='[--tool=tool] [-y|--no-prompt|--prompt] [file to merge] ...'
SUBDIRECTORY_OK=Yes
OPTIONS_SPEC=
. git-sh-setup
require_work_tree

# Returns true if the mode reflects a symlink
is_symlink () {
    test "$1" = 120000
}

local_present () {
    test -n "$local_mode"
}

remote_present () {
    test -n "$remote_mode"
}

base_present () {
    test -n "$base_mode"
}

cleanup_temp_files () {
    if test "$1" = --save-backup ; then
	mv -- "$BACKUP" "$MERGED.orig"
	rm -f -- "$LOCAL" "$REMOTE" "$BASE"
    else
	rm -f -- "$LOCAL" "$REMOTE" "$BASE" "$BACKUP"
    fi
}

describe_file () {
    mode="$1"
    branch="$2"
    file="$3"

    printf "  {%s}: " "$branch"
    if test -z "$mode"; then
	echo "deleted"
    elif is_symlink "$mode" ; then
	echo "a symbolic link -> '$(cat "$file")'"
    else
	if base_present; then
	    echo "modified"
	else
	    echo "created"
	fi
    fi
}


resolve_symlink_merge () {
    while true; do
	printf "Use (l)ocal or (r)emote, or (a)bort? "
	read ans
	case "$ans" in
	    [lL]*)
		git checkout-index -f --stage=2 -- "$MERGED"
		git add -- "$MERGED"
		cleanup_temp_files --save-backup
		return 0
		;;
	    [rR]*)
		git checkout-index -f --stage=3 -- "$MERGED"
		git add -- "$MERGED"
		cleanup_temp_files --save-backup
		return 0
		;;
	    [aA]*)
		return 1
		;;
	    esac
	done
}

resolve_deleted_merge () {
    while true; do
	if base_present; then
	    printf "Use (m)odified or (d)eleted file, or (a)bort? "
	else
	    printf "Use (c)reated or (d)eleted file, or (a)bort? "
	fi
	read ans
	case "$ans" in
	    [mMcC]*)
		git add -- "$MERGED"
		cleanup_temp_files --save-backup
		return 0
		;;
	    [dD]*)
		git rm -- "$MERGED" > /dev/null
		cleanup_temp_files
		return 0
		;;
	    [aA]*)
		return 1
		;;
	    esac
	done
}

check_unchanged () {
    if test "$MERGED" -nt "$BACKUP" ; then
	status=0;
    else
	while true; do
	    echo "$MERGED seems unchanged."
	    printf "Was the merge successful? [y/n] "
	    read answer < /dev/tty
	    case "$answer" in
		y*|Y*) status=0; break ;;
		n*|N*) status=1; break ;;
	    esac
	done
    fi
}

checkout_staged_file () {
    tmpfile=$(expr "$(git checkout-index --temp --stage="$1" "$2")" : '\([^	]*\)	')

    if test $? -eq 0 -a -n "$tmpfile" ; then
	mv -- "$(git rev-parse --show-cdup)$tmpfile" "$3"
    fi
}

merge_file () {
    MERGED="$1"

    f=`git ls-files -u -- "$MERGED"`
    if test -z "$f" ; then
	if test ! -f "$MERGED" ; then
	    echo "$MERGED: file not found"
	else
	    echo "$MERGED: file does not need merging"
	fi
	return 1
    fi

    ext="$$$(expr "$MERGED" : '.*\(\.[^/]*\)$')"
    BACKUP="./$MERGED.BACKUP.$ext"
    LOCAL="./$MERGED.LOCAL.$ext"
    REMOTE="./$MERGED.REMOTE.$ext"
    BASE="./$MERGED.BASE.$ext"

    mv -- "$MERGED" "$BACKUP"
    cp -- "$BACKUP" "$MERGED"

    base_mode=`git ls-files -u -- "$MERGED" | awk '{if ($3==1) print $1;}'`
    local_mode=`git ls-files -u -- "$MERGED" | awk '{if ($3==2) print $1;}'`
    remote_mode=`git ls-files -u -- "$MERGED" | awk '{if ($3==3) print $1;}'`

    base_present   && checkout_staged_file 1 "$MERGED" "$BASE"
    local_present  && checkout_staged_file 2 "$MERGED" "$LOCAL"
    remote_present && checkout_staged_file 3 "$MERGED" "$REMOTE"

    if test -z "$local_mode" -o -z "$remote_mode"; then
	echo "Deleted merge conflict for '$MERGED':"
	describe_file "$local_mode" "local" "$LOCAL"
	describe_file "$remote_mode" "remote" "$REMOTE"
	resolve_deleted_merge
	return
    fi

    if is_symlink "$local_mode" || is_symlink "$remote_mode"; then
	echo "Symbolic link merge conflict for '$MERGED':"
	describe_file "$local_mode" "local" "$LOCAL"
	describe_file "$remote_mode" "remote" "$REMOTE"
	resolve_symlink_merge
	return
    fi

    echo "Normal merge conflict for '$MERGED':"
    describe_file "$local_mode" "local" "$LOCAL"
    describe_file "$remote_mode" "remote" "$REMOTE"
    if "$prompt" = true; then
	printf "Hit return to start merge resolution tool (%s): " "$merge_tool"
	read ans
    fi

    case "$merge_tool" in
	kdiff3)
	    if base_present ; then
		("$merge_tool_path" --auto --L1 "$MERGED (Base)" --L2 "$MERGED (Local)" --L3 "$MERGED (Remote)" \
		    -o "$MERGED" "$BASE" "$LOCAL" "$REMOTE" > /dev/null 2>&1)
	    else
		("$merge_tool_path" --auto --L1 "$MERGED (Local)" --L2 "$MERGED (Remote)" \
		    -o "$MERGED" "$LOCAL" "$REMOTE" > /dev/null 2>&1)
	    fi
	    status=$?
	    ;;
	tkdiff)
	    if base_present ; then
		"$merge_tool_path" -a "$BASE" -o "$MERGED" "$LOCAL" "$REMOTE"
	    else
		"$merge_tool_path" -o "$MERGED" "$LOCAL" "$REMOTE"
	    fi
	    status=$?
	    ;;
	meld)
	    touch "$BACKUP"
	    "$merge_tool_path" "$LOCAL" "$MERGED" "$REMOTE"
	    check_unchanged
	    ;;
	vimdiff)
	    touch "$BACKUP"
	    "$merge_tool_path" -c "wincmd l" "$LOCAL" "$MERGED" "$REMOTE"
	    check_unchanged
	    ;;
	gvimdiff)
	    touch "$BACKUP"
	    "$merge_tool_path" -c "wincmd l" -f "$LOCAL" "$MERGED" "$REMOTE"
	    check_unchanged
	    ;;
	xxdiff)
	    touch "$BACKUP"
	    if base_present ; then
		"$merge_tool_path" -X --show-merged-pane \
		    -R 'Accel.SaveAsMerged: "Ctrl-S"' \
		    -R 'Accel.Search: "Ctrl+F"' \
		    -R 'Accel.SearchForward: "Ctrl-G"' \
		    --merged-file "$MERGED" "$LOCAL" "$BASE" "$REMOTE"
	    else
		"$merge_tool_path" -X --show-merged-pane \
		    -R 'Accel.SaveAsMerged: "Ctrl-S"' \
		    -R 'Accel.Search: "Ctrl+F"' \
		    -R 'Accel.SearchForward: "Ctrl-G"' \
		    --merged-file "$MERGED" "$LOCAL" "$REMOTE"
	    fi
	    check_unchanged
	    ;;
	opendiff)
	    touch "$BACKUP"
	    if base_present; then
		"$merge_tool_path" "$LOCAL" "$REMOTE" -ancestor "$BASE" -merge "$MERGED" | cat
	    else
		"$merge_tool_path" "$LOCAL" "$REMOTE" -merge "$MERGED" | cat
	    fi
	    check_unchanged
	    ;;
	ecmerge)
	    touch "$BACKUP"
	    if base_present; then
		"$merge_tool_path" "$BASE" "$LOCAL" "$REMOTE" --default --mode=merge3 --to="$MERGED"
	    else
		"$merge_tool_path" "$LOCAL" "$REMOTE" --default --mode=merge2 --to="$MERGED"
	    fi
	    check_unchanged
	    ;;
	emerge)
	    if base_present ; then
		"$merge_tool_path" -f emerge-files-with-ancestor-command "$LOCAL" "$REMOTE" "$BASE" "$(basename "$MERGED")"
	    else
		"$merge_tool_path" -f emerge-files-command "$LOCAL" "$REMOTE" "$(basename "$MERGED")"
	    fi
	    status=$?
	    ;;
	*)
	    if test -n "$merge_tool_cmd"; then
		if test "$merge_tool_trust_exit_code" = "false"; then
		    touch "$BACKUP"
		    ( eval $merge_tool_cmd )
		    check_unchanged
		else
		    ( eval $merge_tool_cmd )
		    status=$?
		fi
	    fi
	    ;;
    esac
    if test "$status" -ne 0; then
	echo "merge of $MERGED failed" 1>&2
	mv -- "$BACKUP" "$MERGED"

	if test "$merge_keep_temporaries" = "false"; then
	    cleanup_temp_files
	fi

	return 1
    fi

    if test "$merge_keep_backup" = "true"; then
	mv -- "$BACKUP" "$MERGED.orig"
    else
	rm -- "$BACKUP"
    fi

    git add -- "$MERGED"
    cleanup_temp_files
    return 0
}

prompt=$(git config --bool mergetool.prompt || echo true)

while test $# != 0
do
    case "$1" in
	-t|--tool*)
	    case "$#,$1" in
		*,*=*)
		    merge_tool=`expr "z$1" : 'z-[^=]*=\(.*\)'`
		    ;;
		1,*)
		    usage ;;
		*)
		    merge_tool="$2"
		    shift ;;
	    esac
	    ;;
	-y|--no-prompt)
	    prompt=false
	    ;;
	--prompt)
	    prompt=true
	    ;;
	--)
	    shift
	    break
	    ;;
	-*)
	    usage
	    ;;
	*)
	    break
	    ;;
    esac
    shift
done

valid_custom_tool()
{
    merge_tool_cmd="$(git config mergetool.$1.cmd)"
    test -n "$merge_tool_cmd"
}

valid_tool() {
	case "$1" in
		kdiff3 | tkdiff | xxdiff | meld | opendiff | emerge | vimdiff | gvimdiff | ecmerge)
			;; # happy
		*)
			if ! valid_custom_tool "$1"; then
				return 1
			fi
			;;
	esac
}

init_merge_tool_path() {
	merge_tool_path=`git config mergetool.$1.path`
	if test -z "$merge_tool_path" ; then
		case "$1" in
			emerge)
				merge_tool_path=emacs
				;;
			*)
				merge_tool_path=$1
				;;
		esac
	fi
}

prompt_after_failed_merge() {
    while true; do
	printf "Continue merging other unresolved paths (y/n) ? "
	read ans
	case "$ans" in

	    [yY]*)
		return 0
		;;

	    [nN]*)
		return 1
		;;
	esac
    done
}

if test -z "$merge_tool"; then
    merge_tool=`git config merge.tool`
    if test -n "$merge_tool" && ! valid_tool "$merge_tool"; then
	    echo >&2 "git config option merge.tool set to unknown tool: $merge_tool"
	    echo >&2 "Resetting to default..."
	    unset merge_tool
    fi
fi

if test -z "$merge_tool" ; then
    if test -n "$DISPLAY"; then
        if test -n "$GNOME_DESKTOP_SESSION_ID" ; then
            merge_tool_candidates="meld kdiff3 tkdiff xxdiff gvimdiff"
        else
            merge_tool_candidates="kdiff3 tkdiff xxdiff meld gvimdiff"
        fi
    fi
    if echo "${VISUAL:-$EDITOR}" | grep 'emacs' > /dev/null 2>&1; then
        merge_tool_candidates="$merge_tool_candidates emerge opendiff vimdiff"
    elif echo "${VISUAL:-$EDITOR}" | grep 'vim' > /dev/null 2>&1; then
        merge_tool_candidates="$merge_tool_candidates vimdiff opendiff emerge"
    else
        merge_tool_candidates="$merge_tool_candidates opendiff emerge vimdiff"
    fi
    echo "merge tool candidates: $merge_tool_candidates"
    for i in $merge_tool_candidates; do
        init_merge_tool_path $i
        if type "$merge_tool_path" > /dev/null 2>&1; then
            merge_tool=$i
            break
        fi
    done
    if test -z "$merge_tool" ; then
	echo "No known merge resolution program available."
	exit 1
    fi
else
    if ! valid_tool "$merge_tool"; then
        echo >&2 "Unknown merge_tool $merge_tool"
        exit 1
    fi

    init_merge_tool_path "$merge_tool"

    merge_keep_backup="$(git config --bool merge.keepBackup || echo true)"
    merge_keep_temporaries="$(git config --bool mergetool.keepTemporaries || echo false)"

    if test -z "$merge_tool_cmd" && ! type "$merge_tool_path" > /dev/null 2>&1; then
        echo "The merge tool $merge_tool is not available as '$merge_tool_path'"
        exit 1
    fi

    if ! test -z "$merge_tool_cmd"; then
        merge_tool_trust_exit_code="$(git config --bool mergetool.$merge_tool.trustExitCode || echo false)"
    fi
fi

last_status=0
rollup_status=0

if test $# -eq 0 ; then
    files=`git ls-files -u | sed -e 's/^[^	]*	//' | sort -u`
    if test -z "$files" ; then
	echo "No files need merging"
	exit 0
    fi
    echo Merging the files: "$files"
    git ls-files -u |
    sed -e 's/^[^	]*	//' |
    sort -u |
    while IFS= read i
    do
	if test $last_status -ne 0; then
	    prompt_after_failed_merge < /dev/tty || exit 1
	fi
	printf "\n"
	merge_file "$i" < /dev/tty > /dev/tty
	last_status=$?
	if test $last_status -ne 0; then
	    rollup_status=1
	fi
    done
else
    while test $# -gt 0; do
	if test $last_status -ne 0; then
	    prompt_after_failed_merge || exit 1
	fi
	printf "\n"
	merge_file "$1"
	last_status=$?
	if test $last_status -ne 0; then
	    rollup_status=1
	fi
	shift
    done
fi

exit $rollup_status
