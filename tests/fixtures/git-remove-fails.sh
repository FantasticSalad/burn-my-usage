#!/usr/bin/env bash
# Synthetic stand-in for git when a sync client holds a worktree's files open (seen with a
# OneDrive burn home): `git worktree remove` deletes the worktree's admin folder, then fails
# with "Permission denied" and leaves the folder behind. Everything else goes to real git.
# The test copies this file to <tmp>/shim/git and sets REAL_GIT.
case " $* " in
  *" worktree remove "*)
    for wt in "$@"; do :; done
    admin=$("$REAL_GIT" -C "$wt" rev-parse --absolute-git-dir) || exit 2
    # Only ever a linked worktree's admin folder, never a repository's own .git.
    case "$admin" in */.git/worktrees/?*) rm -rf "$admin" ;; *) echo "shim: refusing $admin" >&2; exit 2 ;; esac
    echo "error: failed to delete '$wt': Permission denied" >&2
    exit 255
    ;;
esac
exec "$REAL_GIT" "$@"
