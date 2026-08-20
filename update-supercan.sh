#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_NAME="${0##*/}"

usage() {
	cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Safely update an existing SuperCAN clone, synchronize the STM32H7 firmware
submodules, and build the default STM32H735ZGT6 image.

Options:
  --repo PATH      SuperCAN checkout to update (default: script directory)
  --branch NAME    Branch to update (default: debug)
  --remote NAME    Git remote to fetch (default: origin)
  --switch         Allow switching to or creating the selected branch
  --no-build       Update sources without building firmware
  -h, --help       Show this help

The updater refuses a dirty worktree, fetches and fast-forwards only, and
checks out Boards plus the four nested dependencies required by the STM32H7
firmware build. By default it then performs a fresh dual-FDCAN, internal-HSI
STM32H735ZGT6 build. It never resets, stashes, flashes, or force-pushes.
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

processor_count() {
	local count=""

	if command -v nproc >/dev/null 2>&1; then
		count="$(nproc 2>/dev/null || true)"
	fi
	if [[ ! "$count" =~ ^[1-9][0-9]*$ ]] \
		&& command -v sysctl >/dev/null 2>&1; then
		count="$(sysctl -n hw.logicalcpu 2>/dev/null || true)"
	fi
	if [[ ! "$count" =~ ^[1-9][0-9]*$ ]] \
		&& command -v sysctl >/dev/null 2>&1; then
		count="$(sysctl -n hw.ncpu 2>/dev/null || true)"
	fi
	if [[ ! "$count" =~ ^[1-9][0-9]*$ ]] \
		&& command -v getconf >/dev/null 2>&1; then
		count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
	fi

	[[ "$count" =~ ^[1-9][0-9]*$ ]] || count=1
	printf '%s\n' "$count"
}

verify_clean_worktree() {
	local context="$1"
	local status

	status="$(git -C "$repo_dir" status --porcelain=v1 \
		--untracked-files=normal --ignore-submodules=none)"
	[[ -z "$status" ]] || {
		printf 'Unexpected worktree changes after %s:\n%s\n' \
			"$context" "$status" >&2
		die "$context finished with a dirty worktree"
	}
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

check_ignored_collisions() {
	local checkout="$1"
	local target="$2"
	local collision=0
	local object_type
	local path
	local probe

	while IFS= read -r -d '' path; do
		probe="$path"
		if object_type="$(git -C "$checkout" cat-file -t \
			"$target:$probe" 2>/dev/null)"; then
			printf 'Ignored path would be overwritten by %s:\n  %q\n' \
				"$target" "$path" >&2
			collision=1
			continue
		fi

		while [[ "$probe" == */* ]]; do
			probe="${probe%/*}"
			if object_type="$(git -C "$checkout" cat-file -t \
				"$target:$probe" 2>/dev/null)"; then
				if [[ "$object_type" != tree ]]; then
					printf 'Ignored path %q conflicts with tracked parent %q in %s\n' \
						"$path" "$probe" "$target" >&2
					collision=1
				fi
				break
			fi
		done
	done < <(git -C "$checkout" ls-files --others --ignored \
		--exclude-standard -z)

	(( ! collision )) || die "ignored files would be overwritten in $checkout"
}

ensure_commit() {
	local checkout="$1"
	local target="$2"

	if git -C "$checkout" cat-file -e "$target^{commit}" 2>/dev/null; then
		return
	fi

	git -C "$checkout" remote get-url origin >/dev/null 2>&1 \
		|| die "submodule has no origin remote: $checkout"
	git -C "$checkout" fetch --no-tags origin
	if ! git -C "$checkout" cat-file -e "$target^{commit}" 2>/dev/null; then
		git -C "$checkout" fetch --no-tags origin "$target"
	fi
	git -C "$checkout" cat-file -e "$target^{commit}" 2>/dev/null \
		|| die "cannot fetch pinned commit $target in $checkout"
}

require_empty_uninitialized_path() {
	local path="$1"
	local contents=""

	if [[ -d "$path" ]]; then
		contents="$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)"
	fi
	[[ -z "$contents" ]] \
		|| die "uninitialized submodule path contains files: $path"
}

checkout_pinned() {
	local checkout="$1"
	local target="$2"

	ensure_commit "$checkout" "$target"
	check_ignored_collisions "$checkout" "$target"
	git -C "$checkout" switch --detach --no-overwrite-ignore "$target"
}

repo_dir=""
branch="debug"
remote="origin"
allow_switch=0
build_firmware=1

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
		--no-build)
			build_firmware=0
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
readonly supercan_build_dir="$boards_dir/examples/device/supercan"
toolchain_prefix="${CROSS_COMPILE-arm-none-eabi-}"
if (( build_firmware )); then
	[[ "$repo_dir" != *[[:space:]]* ]] \
		|| die "firmware builds require a checkout path without whitespace; use --no-build"
	[[ "$toolchain_prefix" != *[[:space:]]* ]] \
		|| die "CROSS_COMPILE must not contain whitespace"
	command -v make >/dev/null 2>&1 || die "make is not installed"
	command -v realpath >/dev/null 2>&1 || die "realpath is not installed"
	for tool in gcc objcopy size; do
		command -v "${toolchain_prefix}${tool}" >/dev/null 2>&1 \
			|| die "${toolchain_prefix}${tool} is not installed; set CROSS_COMPILE or use --no-build"
	done
fi

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

update_target="refs/remotes/$remote/$branch"
if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch" \
	&& git -C "$repo_dir" merge-base --is-ancestor \
		"refs/remotes/$remote/$branch" "refs/heads/$branch"; then
	update_target="refs/heads/$branch"
fi
check_ignored_collisions "$repo_dir" "$update_target"

if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch"; then
	if [[ "$current_branch" != "$branch" ]]; then
		git -C "$repo_dir" switch --no-overwrite-ignore "$branch"
	fi
else
	git -C "$repo_dir" switch --no-overwrite-ignore \
		--create "$branch" --track "$remote/$branch"
fi

git -C "$repo_dir" merge --ff-only "$remote/$branch"

boards_target="$(git -C "$repo_dir" rev-parse HEAD:Boards)"
git -C "$repo_dir" submodule sync -- Boards
if [[ -e "$boards_dir/.git" ]]; then
	checkout_pinned "$boards_dir" "$boards_target"
else
	require_empty_uninitialized_path "$boards_dir"
	git -C "$repo_dir" submodule update --init --checkout Boards
fi

[[ -e "$boards_dir/.git" ]] || die "Boards submodule was not initialized"

for submodule in "${h7_submodules[@]}"; do
	git -C "$boards_dir" submodule sync -- "$submodule"
	expected_commit="$(git -C "$boards_dir" rev-parse "HEAD:$submodule")"
	if [[ -e "$boards_dir/$submodule/.git" ]]; then
		checkout_pinned "$boards_dir/$submodule" "$expected_commit"
	else
		require_empty_uninitialized_path "$boards_dir/$submodule"
		git -C "$boards_dir" submodule update --init --checkout "$submodule"
	fi
done

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

verify_clean_worktree "source update"

if (( build_firmware )); then
	build_jobs="$(processor_count)"
	printf '\nBuilding the default STM32H735ZGT6 firmware (%s jobs)...\n' \
		"$build_jobs"
	if ! MAKEFLAGS= MFLAGS= GNUMAKEFLAGS= MAKEFILES= \
		make -C "$supercan_build_dir" -B -j"$build_jobs" \
		BOARD=stm32h735zgt6 \
		STM32H735_FDCAN_COUNT=2 \
		STM32H735_USE_HSE=0 \
		"CROSS_COMPILE=$toolchain_prefix" \
		all; then
		verify_clean_worktree "failed firmware build"
		die "source update completed, but the STM32H735ZGT6 firmware build failed"
	fi
	for artifact in elf hex bin; do
		[[ -s "$supercan_build_dir/_build/stm32h735zgt6/supercan.$artifact" ]] \
			|| die "build did not produce a nonempty supercan.$artifact"
	done
	verify_clean_worktree "firmware build"
fi

root_commit="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
boards_commit="$(git -C "$boards_dir" rev-parse --short=12 HEAD)"

printf '\nUpdate complete.\n'
printf '  SuperCAN: %s (%s)\n' "$root_commit" "$branch"
printf '  Boards:   %s (detached, pinned by SuperCAN)\n' "$boards_commit"
if (( build_firmware )); then
	printf '  Firmware: %s\n' \
		"$supercan_build_dir/_build/stm32h735zgt6/supercan.bin"
else
	printf '\nFirmware build skipped (--no-build).\n'
fi
