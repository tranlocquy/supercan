#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"

usage() {
	cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Safely update an existing SuperCAN clone and the STM32H7 firmware submodules.

Options:
  --repo PATH      SuperCAN checkout to update (default: script directory)
  --branch NAME    Branch to update (default: debug)
  --remote NAME    Git remote to fetch (default: origin)
  --switch         Allow switching to or creating the selected branch
  -h, --help       Show this help

The updater refuses a dirty worktree, fetches and fast-forwards only, and
checks out Boards plus the four nested dependencies required by the STM32H7
firmware build. It never resets, stashes, builds, flashes, or force-pushes.
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_value() {
	local option="$1"
	local count="$2"
	(( count >= 2 )) || die "${option} requires a value"
}

check_git_operation() {
	local checkout="$1"
	local git_dir
	local state
	local state_path

	git_dir="$(git -C "$checkout" rev-parse --absolute-git-dir)"
	for state in \
		MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_START \
		rebase-merge rebase-apply sequencer; do
		state_path="$git_dir/$state"
		[[ ! -e "$state_path" ]] \
			|| die "Git operation '$state' is in progress in $checkout"
	done
}

repo_dir=""
branch="debug"
remote="origin"
allow_switch=0

while (( $# > 0 )); do
	case "$1" in
		--repo)
			require_value "$1" "$#"
			repo_dir="$2"
			shift 2
			;;
		--branch)
			require_value "$1" "$#"
			branch="$2"
			shift 2
			;;
		--remote)
			require_value "$1" "$#"
			remote="$2"
			shift 2
			;;
		--switch)
			allow_switch=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "unknown option: $1 (use --help)"
			;;
	esac
done

command -v git >/dev/null 2>&1 || die "git is not installed"

if [[ -z "$repo_dir" ]]; then
	repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd -P)"
fi

requested_repo="$repo_dir"
repo_dir="$(git -C "$requested_repo" rev-parse --show-toplevel 2>/dev/null)" \
	|| die "not a Git checkout: $requested_repo"

git -C "$repo_dir" ls-files --error-unmatch .gitmodules src/supercan.h \
	>/dev/null 2>&1 || die "not a SuperCAN checkout: $repo_dir"

readonly boards_dir="$repo_dir/Boards"
readonly h7_submodules=(
	lib/CMSIS_5
	lib/FreeRTOS-Kernel
	hw/mcu/st/cmsis_device_h7
	hw/mcu/st/stm32h7xx_hal_driver
)

[[ "$branch" != -* ]] || die "branch must not begin with '-': $branch"
git check-ref-format --branch "$branch" >/dev/null 2>&1 \
	|| die "invalid branch name: $branch"

[[ "$remote" != -* ]] || die "remote must not begin with '-': $remote"
git -C "$repo_dir" remote get-url "$remote" >/dev/null 2>&1 \
	|| die "unknown remote: $remote"

check_git_operation "$repo_dir"
if [[ -e "$boards_dir/.git" ]]; then
	check_git_operation "$boards_dir"
	for submodule in "${h7_submodules[@]}"; do
		if [[ -e "$boards_dir/$submodule/.git" ]]; then
			check_git_operation "$boards_dir/$submodule"
		fi
	done
fi

dirty="$(git -C "$repo_dir" status --porcelain=v1 \
	--untracked-files=normal --ignore-submodules=none)"
if [[ -n "$dirty" ]]; then
	printf 'Refusing to update a dirty worktree:\n%s\n' "$dirty" >&2
	die "commit, stash, or remove the listed changes first"
fi

current_branch="$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD || true)"
if (( ! allow_switch )); then
	[[ -n "$current_branch" ]] \
		|| die "checkout is detached; rerun with --switch to select $branch"
	[[ "$current_branch" == "$branch" ]] \
		|| die "current branch is '$current_branch', not '$branch'; rerun with --switch"
fi

printf 'Updating %s from remote %s, branch %s\n' \
	"$repo_dir" "$remote" "$branch"

git -C "$repo_dir" fetch "$remote" \
	"refs/heads/$branch:refs/remotes/$remote/$branch"

if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
	if ! git -C "$repo_dir" merge-base --is-ancestor \
		"refs/heads/$branch" "refs/remotes/$remote/$branch" \
		&& ! git -C "$repo_dir" merge-base --is-ancestor \
		"refs/remotes/$remote/$branch" "refs/heads/$branch"; then
		die "local $branch and $remote/$branch have diverged; update manually"
	fi
fi

if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
	if [[ "$current_branch" != "$branch" ]]; then
		git -C "$repo_dir" switch "$branch"
	fi
else
	git -C "$repo_dir" switch --create "$branch" --track "$remote/$branch"
fi

git -C "$repo_dir" merge --ff-only "$remote/$branch"

git -C "$repo_dir" submodule sync -- Boards
git -C "$repo_dir" submodule update --init --checkout Boards

[[ -e "$boards_dir/.git" ]] || die "Boards submodule was not initialized"

git -C "$boards_dir" submodule sync -- "${h7_submodules[@]}"
git -C "$boards_dir" submodule update --init --checkout \
	"${h7_submodules[@]}"

expected_commit="$(git -C "$repo_dir" rev-parse HEAD:Boards)"
actual_commit="$(git -C "$boards_dir" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] \
	|| die "Boards is not at the revision pinned by SuperCAN"

for submodule in "${h7_submodules[@]}"; do
	expected_commit="$(git -C "$boards_dir" rev-parse "HEAD:$submodule")"
	actual_commit="$(git -C "$boards_dir/$submodule" rev-parse HEAD)"
	[[ "$actual_commit" == "$expected_commit" ]] \
		|| die "$submodule is not at the revision pinned by Boards"
done

final_status="$(git -C "$repo_dir" status --porcelain=v1 \
	--untracked-files=normal --ignore-submodules=none)"
[[ -z "$final_status" ]] || {
	printf 'Unexpected worktree changes after update:\n%s\n' "$final_status" >&2
	die "update finished with a dirty worktree"
}

root_commit="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
boards_commit="$(git -C "$boards_dir" rev-parse --short=12 HEAD)"

printf '\nUpdate complete.\n'
printf '  SuperCAN: %s (%s)\n' "$root_commit" "$branch"
printf '  Boards:   %s (detached, pinned by SuperCAN)\n' "$boards_commit"
printf '\nBuild the default H735 firmware with:\n'
printf '  make -C %q BOARD=stm32h735zgt6\n' \
	"$boards_dir/examples/device/supercan"
