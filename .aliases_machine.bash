################################################################################
# Notes:
# This file contains aliases and functions that are specific to this machine.
# Aliases and functions followed by a "# [BH]" is written entirely by me
# Aliases and functions followed by a "# {BH}" is adapted by me from somebody else's code
# Aliases and functions without a comment after it is completely taken from elsewhere
################################################################################

#################
# Pushing Files #
################################################################################
export HOST="bherman-mbp.usoh.ibm.com"

# pmalias: push machine aliases between virtual machine and host
pmalias() { # [BH]
	if [[ `hostname -s` == "bherman-mbp" ]]; then
		scp "$MACHINE_ALIAS_FILE" ubuntu:~
	else
		scp "$MACHINE_ALIAS_FILE" "$HOST":~
	fi
}

# ptools: push terminal tools between virtual machine and host
ptools() { # [BH]
	if [[ `hostname -s` == "bherman-mbp" ]]; then
		scp -r "$termtools" ubuntu:"`ssh ubuntu '. ~/.dirs; echo $termtools'`"
	else
		scp -r "$termtools" "$HOST:`ssh bherman-mbp.usoh.ibm.com '. ~/.dirs; echo $termtools'`"
	fi
}
################################################################################

#####################
# Clipboard Parsing #
################################################################################
# skey: parse the UCD_SESSION_KEY from the clipboard contents and replace the contents with the parsed value
skey() { pbpaste | grep 'UCD_SESSION_KEY' | awk '{print $2}' | tr -d '\n' | pbcopy; } # [BH]
# stripid: strip the first column from a comma separated list in the clipboard
stripid() { pbpaste | awk -F , '{print $1}' | tr -d '\n' | pbcopy; } # [BH]
################################################################################

#######
# Git #
################################################################################
# clone: clone the specified UrbanCode project
clone() { # [BH]
	if [[ $1 == '--help' ]]; then
		echo "Usage: clone <remote_project> [<local_dir>]"
		echo "Arguments:"
		echo "  <remote_project>"
		echo "    The name of the remote UrbanCode project repository."
		echo "  <local_dir>"
		echo "    Path to the location in which to store the cloned repository. If not"
		echo "    provided, will replace word separators in the remote project with"
		echo "    underscores and create a new folder within the current directory."
		return 0
	fi
	local local_dir="${@: +2}"
	if [[ -z $local_dir ]]; then
		local_dir="`echo "$1" | tr '/- ' '___'`"
	fi
	mkdir -p "$local_dir"
	git clone ssh://bpherman@urbancodegit.rtp.raleigh.ibm.com:29418/$1 "$local_dir"
	cd "$local_dir"
	hooks
}

# pushci: push a change to gerrit
pushci() { # [BH]
	if [[ $1 == '--help' ]]; then
		echo "Usage: pushci [options] [<branch_name>]"
		echo "Options:"
		echo "  -o <push_location>"
		echo "    Use <push_location> as the push location no matter what."
		echo "Arguments:"
		echo "  <branch_name>"
		echo "    If provided, the push location will be 'refs/for/<branch_name>'."
		echo "Notes:"
		echo "  - Push location resolution follows these rules until one evaluates to true:"
		echo "    1. If -o option is specified, <push_location> is used"
		echo "    2. If the current branch name starts with 'patches/', the current branch"
		echo "       name is used."
		echo "    3. If <branch_name> is specified, use 'refs/for/<branch_name>'"
		echo "    4. Use '/refs/for/master'"
		return 0
	fi

	# parse options
	local push_loc branch="`br`" override=0
	if [[ $1 == '-o' ]]; then
		override=1
		shift
	fi

	if [[ $override -eq 1 ]]; then
		push_loc="$1"
	elif [[ $branch =~ ^patches/ ]]; then
		push_loc="$branch"
	else
		push_loc="refs/for/${1:-master}"
	fi

	local commit_id="`prevci 0`"
	if [[ -n $(gitcf -s $commit_id) ]]; then
		echo "Some changes have not been committed:" >&2
		gitcf -s $commit_id | awk '{print "    "$1}' >&2
		answer=""
		while [[ $answer != "y" && $answer != "n" ]]; do
			echo "Continue? [y/n]" >&2
			read -sn 1 answer
		done
		if [[ $answer == "n" ]]; then return 1; fi
	fi

	gitcf | tr '\n' '\0' | xargs -0 jslint
	if [[ $? -ne 0 ]]; then
		echo "Not pushing to Gerrit: JSLint step failed"
		return 1
	fi
	git push origin HEAD:"$push_loc"
}

# gitlint: run jslint on files changed since n commits ago
gitlint() { # [BH]
	if [[ $1 == '--help' ]]; then
		echo "Run jsling on files changed since <number_of_commits_ago>"
		echo "Usage: gitlint <number_of_commits_ago>"
		return 0
	fi
	gitcf -s `prevci $1` | tr '\n' '\0' | xargs -0 jslint
}

# hooks: install hooks for the current repository
alias hooks="scp -p -P 29418 bpherman@urbancodegit.rtp.raleigh.ibm.com:hooks/commit-msg .git/hooks/"

# parent_branch: show the parent branch for the current git branch
parent_branch() {
	git show-branch | \
	grep '*' | \
	grep -v "$(git rev-parse --abbrev-ref HEAD)" | \
	head -n1 | \
	sed 's/.*\[\(.*\)\].*/\1/' | \
	sed 's/[\^~].*//'
}
################################################################################

###############
# Dev Scripts #
################################################################################
_server_agent_helper() { # [BH]
	local bin_name="$1"
	shift

	if [[ -f ./$bin_name && -x ./$bin_name ]]; then
		./$bin_name "$@"
		return $?
	fi

	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo "Usage: $bin_name [<install_dir>] {run [-debug]|start|stop [-force]|restart [-debug] [-force]}"
		echo "Notes:"
		_install_dir_notes $bin_name
		return 0
	fi

	local install_dir
	if [[ $# -lt 2 || $1 =~ run|stop|restart ]]; then
		install_dir="`_resolve_install_dir $bin_name`"
	else
		install_dir="`_resolve_install_dir $bin_name "$1"`"
		shift
	fi

	if [[ -z $install_dir ]]; then
		echo "Error: cannot resolve install directory." >&2
		return 1
	fi

	echo "Using $bin_name at: $install_dir"

	if [[ $1 == restart ]]; then
		shift
		local force debug
		while [[ $# -gt 0 ]]; do
			case $1 in
				-force) force="$1" ;;
				-debug) debug="$1" ;;
				*)
					echo "Error: Unrecognized option for restart command: \"$1\"" >&2
					return 1 ;;
			esac
			shift
		done

		local agent_option=''
		if [[ $bin_name == 'agent' ]]; then
			agent_option='a'
		fi

		local pid=`curserv -${agent_option}l 1 -i "$install_path" pid`
		"$install_dir"/bin/$bin_name stop $force
		# wait for the $bin_name to stop
		while kill -0 $pid &> /dev/null; do
			sleep .5
		done
		"$install_dir"/bin/$bin_name run $debug
	else
		"$install_dir"/bin/$bin_name "$@"
	fi
}

# server: control the deploy server in the specified installation directory
alias server="_server_agent_helper server" # [BH]

# agent: control the agent in the specified installation directory
alias agent="_server_agent_helper agent" # [BH]

# udclient: control the deploy client in the specified installation directory
udclient() { # [BH]
	if [[ -f ./udclient ]]; then
		./udclient "$@"
		return $?
	fi

	if [[ $# -eq 0 ]]; then
		echo "Usage: udclient [<install_dir>] [normal_udclient_usage]"
		echo "Notes:"
		_install_dir_notes
		return 0
	fi

	local install_dir
	if [[ -e "$DS_SERVER_INSTALLATIONS_DIR/$1" || -e "$1" ]]; then
		install_dir="`_resolve_install_dir server "$1"`"
		shift
	else
		install_dir="`_resolve_install_dir server`"
	fi

	if [[ -z $install_dir ]]; then
		echo "Error: cannot resolve install directory (please specify)." >&2
		return 1
	fi

	local tools_dir="$install_dir/opt/tomcat/webapps/ROOT/tools"
	if [[ -e "$tools_dir" && ! -e $tools_dir/udclient/udclient ]]; then
		echo "Unzipping udclient for specified installation directory"
		unzip -d "$tools_dir/"{,udclient.zip}
	fi

	"$tools_dir/udclient/udclient" "$@" | {
		# automatically colify the commands listed in help
		if [[ $@ =~ "--help" ]]; then
			local line cmds
			local commands=0
			# read splits based on IFS, which may contain spaces, causing leading whitespace to be dropped
			local OLD_IFS="$IFS"
			IFS="\n"
			while read -s line; do
				case $commands in
					0)
						if [[ $line =~ ^Commands ]]; then
							commands=1
						fi
						echo "$line" ;;
					1) commands=2; IFS="$OLD_IFS" ;;
					2) cmds="`echo -e "$cmds\n$line"`" ;;
				esac
			done
			echo "$cmds" | colify
		else
			xargs echo
		fi
	}
}

# servlog: open a server log
servlog() { # [BH]
	if [[ $1 == "--help" || $1 == "-h" ]]; then
		echo "Usage: servlog [options] [<install_dir>]"
		echo "Options:"
		echo "  -c : Clear the log for the specified server instead of opening it."
		echo "Notes:"
		_install_dir_notes server
		return 0
	fi

	local clear=0
	if [[ $1 == "-c" ]]; then
		shift
		clear=1
	fi

	local install_dir
	if [[ $# -eq 0 ]]; then
		install_dir="`_resolve_install_dir server`"
	else
		install_dir="`_resolve_install_dir server "$1"`"
		shift
	fi

	if [[ -z $install_dir ]]; then
		echo "Error: cannot resolve install directory." >&2
		return 1
	fi

	if [[ $clear -eq 1 ]]; then
		echo "Clearing server log for: $install_dir"
		: > "$install_dir/var/log/deployserver.out"
	else
		echo "Displaying server log for: $install_dir"
		subl "$install_dir/var/log/deployserver.out"
	fi
}

# runtest: run a single test (takes test name)
runtest() { # [BH]
	if [[ $1 == "--help" ]]; then
		echo "Usage: runtest [build_options ...] <test_name>[:<methods>]"
		echo "Build Options:"
		"$termtools"/build -h 1
		echo "Arguments:"
		echo "  <test_name>[:<methods>]"
		echo "    The name of the test class, optionally followed by a colon and a"
		echo "    comma-separated list of methods. Note that there should be no space"
		echo "    surrounding the colon."
		return 0
	fi

	local test_param="-Drun.test"
	local methods_param=""
	local target=run-single-test

	local test_name="${@: -1}"
	local methods="${test_name##*:}"
	test_name="${test_name%%:*}"

	if [[ $methods != $test_name ]]; then
		target=run-single-test-methods
		test_param="${test_param}.class"
		methods_param="-Drun.test.methods=\"$methods\""
	fi
	test_param="${test_param}=${test_name}"

	"$termtools"/build -t $target "${@: 1: $(($#-1))}" -- "$test_param" $methods_param
}

# finish: clean up left overs from a work item that has been resolved
finish() { # [BH]
	if [[ $1 == "--help" ]]; then
		echo "Clean up left overs from a work item that has been resolved."
		echo "Usage: finish [<branch_name>]"
		echo "Arguments:"
		echo "  <branch_name>"
		echo "    The name of the branch for which to clean up left overs."
		echo "    [Default: current branch]"
		return 0
	fi

	local branch_name="$1"
	if [[ -z $branch_name ]]; then
		branch_name="`br`"
	fi

	# make sure that the branch isn't currently active
	if [[ `br` == "$branch_name" ]]; then
		sw master
	fi

	# delete local copy of the branch
	git branch -D "$branch_name"

	# delete any existing server installations for the branch
	rm -rf \
		"$DS_SERVER_INSTALLATIONS_DIR/$branch_name" \
		"$DS_SERVER_INSTALLATIONS_DIR/before_$branch_name" \
		"$DS_SERVER_INSTALLATIONS_DIR/after_$branch_name" \
		"$DS_AGENT_INSTALLATIONS_DIR/$branch_name" \
		"$DS_AGENT_INSTALLATIONS_DIR/before_$branch_name" \
		"$DS_AGENT_INSTALLATIONS_DIR/after_$branch_name"

	# delete associated sublime files
	rm -rf "$branch_name.sublime-"*
}
################################################################################

########
# Misc #
################################################################################
# fixjson: fix the JSON messages that come from udclient and pretty print them
fixjson() { "$termtools"/fix_json.py | fjson; } # [BH]

# home: ssh into my home computer
home() { ssh bryanherman@BryanHerman.1141795176.members.btmm.icloud.com; } # [BH]

# deploycv: show UML diagram for UC Deploy
alias deploycv="jcv -cp dist/server -cp lib build/main/classes" # [BH]

# brs: columnified output of branches for current repository
alias brs="branches | colify 3" # [BH]

# unzmr: unzip the most recent zip archive to the specified location
unzmr() { # [BH]
	local dir=""
	[[ -n $1 ]] && dir="-d '$@'"
	unzip $dir "`lsmr | egrep '\.zip$' | head -1`"
}

# cdinstall: cd to the server installation directory based on context
cdinstall() { # [BH]
	if [[ $1 == '--help' ]]; then
		echo "cd to the installation directory for a UCD server based on context."
		echo "Usage: cdinstall [options] [<prefix>]"
		echo "Options:"
		echo "  -d : Run ${BOLD}cd \$deploy${RES} before resolving installation directory."
		echo "Arguments:"
		echo "  <prefix>"
		echo "    If provided, prepend <prefix> to the basename of the resolved installation"
		echo "    directory."
		echo "Environment Variables:"
		echo "  DS_SERVER_INSTALLATIONS_DIR"
		echo "    Directory in which server installations are located."
		echo "  DS_AGENT_INSTALLATIONS_DIR"
		echo "    Directory in which agent installations are located."
		echo "Notes:"
		echo "  - Installation directory resolution follows these rules (in order):"
		echo "    1. If current directory is a git repository, appends the name of the current"
		echo "       branch to the appropriate installations directory environment variable."
		echo "    2. "
		return 0
	fi

	local prefix="$1"
	local dir installs_dir

	if [[ -n `git log -n 1 2> /dev/null` ]]; then
		# first, switch to the root directory of the project if not already there
		local root_dir="`git rev-parse --show-toplevel`"
		if [[ -n $root_dir && $root_dir != `pwd` ]]; then
			cd "$root_dir"
		fi

		# figure out the correct installations directory to use based on the project
		local project="`ant -debug -p | grep -F ant.project.name | sed 's/.*-> //'`"
		case $project in
			ibm-ucd) installs_dir="${DS_SERVER_INSTALLATIONS_DIR%/}" ;;
			air-agent) installs_dir="${DS_AGENT_INSTALLATIONS_DIR%/}" ;;
		esac

		dir="$installs_dir/`br`"
	else
		# figure out the correct installations directory to use based on current directory
		local project="`pwd | grep "${DS_SERVER_INSTALLATIONS_DIR%/}"`"
		if [[ -n $project ]]; then
			installs_dir="${DS_SERVER_INSTALLATIONS_DIR%/}"
		else
			installs_dir="${DS_AGENT_INSTALLATIONS_DIR%/}"
		fi

		# use install directory of running server as a last resort
		dir="`pwd \
			| grep "$installs_dir" \
			| sed "s:$installs_dir/::" \
			| sed 's:/.*$::'`"
		if [[ -z $dir || ! -d "$installs_dir/$dir" ]]; then
			dir="`curserv -l 1 install_dir 2> /dev/null`"
		else
			dir="$installs_dir/$dir"
		fi
	fi

	# handle prefix (if given)
	if [[ -n $prefix ]]; then
		if [[ `basename "$dir"` =~ ^(before|after)_ ]]; then
			# if the base directory already starts with "before_" or "after_", peel that off before
			# applying the prefix
			dir="`dirname "$dir"`/$prefix`basename "$dir" | sed $SED_EXT_RE 's/^(before|after)_//'`"
		else
			dir="`dirname "$dir"`/$prefix`basename "$dir"`"
		fi
	fi

	cd "${dir:-.}"
}

# cdpatches: cd to the server patches directory based on context
cdpatches() { cdinstall; cd patches; } # [BH]

# cdbefore: cd to the before fix server installation directory based on context
alias cdbefore="cdinstall before_" # [BH]
# cdafter: cd to the after fix server installation directory based on context
alias cdafter="cdinstall after_" # [BH]

# projname: get the project name for the ant project in the current directory
projname() { ant -debug -p | grep ant.project.name | sed 's/.*-> //'; } # [BH]

# inservses: run a command in the "Running Server" session
alias inservses="insession 'Running Server'"
# inagentses: run a command in the "Running Agent" session
alias inagentses="insession 'Running Agent'"
################################################################################

##################
# Tab Completion #
################################################################################
shopt -q login_shell && {
finish_tab_completion (){ # [BH]
	echo "shopt -s progcomp"
	_repo_branches_tab_complete_helper
	echo "complete -F _repo_branches_tab_complete -o nospace -o filenames finish"
}
eval "`finish_tab_completion`"

prepdemo_tab_completion() { # [BH]
	echo 'shopt -s progcomp'
	_repo_branches_tab_complete_helper
	echo 'complete -F _repo_branches_tab_complete -o nospace -o filenames prepdemo'
}
eval "`prepdemo_tab_completion`"
}
################################################################################
