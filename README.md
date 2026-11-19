# github-cli-wrapper

A wrapper for the `gh` CLI command that adds multi-account support.

`ghx` picks a GitHub account for each invocation and passes that account's token to
`gh` via `GH_TOKEN`. The global active account (`gh auth switch`) is never changed, so
different shells and directories can use different accounts at the same time.

## Requirements

- `gh` with every account logged in: `gh auth login` once per account
  (`gh auth status` lists them)
- bash, git

## Install

```sh
ln -s "$PWD/bin/ghx" ~/.local/bin/ghx
```

To use it transparently, install it as `gh` in a directory that comes before the real
`gh` on your `PATH`. The wrapper skips itself when it looks for the real binary
(override with `GHX_REAL_GH=/path/to/gh`).

```sh
ln -s "$PWD/bin/ghx" ~/.local/bin/gh
```

## Usage

```
gh [--as <account>] <command> [<args>...]
gh --which
gh account [<subcommand>] [<flags>]
```

### Wrapper options

Recognized only before the `gh` command, so they never collide with `gh`'s own flags.

| Option | Description |
|---|---|
| `--as <account>`, `--as=<account>` | Run this one command as `<account>` |
| `--which` | Print the account that would be used here and why, then exit |

Everything else is passed to `gh` unchanged.

### `gh account` subcommands

| Subcommand | Description |
|---|---|
| `gh account` | Same as `gh account which` |
| `gh account which` | Print the account used in the current directory and the rule that selected it |
| `gh account list` (alias `ls`) | List accounts logged in to `gh` and all mappings; `→` marks the mapping in effect here |
| `gh account use <account> [<target flags>]` | Map targets to `<account>`, replacing any existing mapping for the same pattern |
| `gh account forget [<target flags>]` (alias `rm`) | Remove the mappings for the targets; if any target has no mapping, nothing is removed |
| `gh account help` | Print usage |

`<account>` must be a login already added with `gh auth login`. It is matched case-insensitively
and stored as `gh` spells it.

### Target flags

Used by `use` and `forget`. Flags can be combined and repeated. With no flag, the target is the
current repo.

| Flag | Target |
|---|---|
| `--repo` | The current repo: `<owner>/<repo>` from the `origin` remote |
| `--owner` | The current repo's owner: every repo of that user or org |
| `--default` | `*`: every repo with no more specific mapping, and commands run outside a repo |
| `--for <pattern>`, `--for=<pattern>` | An explicit pattern; works from any directory |

`--repo` and `--owner` require a repo with an `origin` remote.

### Config file

`$XDG_CONFIG_HOME/ghx/accounts`, by default `~/.config/ghx/accounts`. One mapping per
line; blank lines and lines starting with `#` are ignored. The file can be edited by hand.

```
# <pattern>         <account>
*                   <account>
<owner>             <account>
<owner>/<repo>      <account>
```

| Pattern | Matches |
|---|---|
| `<owner>/<repo>` | That repo only |
| `<owner>` | Every repo of that user or org |
| `*` | Everything else, including outside a repo |

Patterns are matched case-insensitively against the `origin` remote (HTTPS, SSH, and SSH host
alias URLs). The most specific match wins, regardless of line order.

### Account resolution

First match wins:

1. `--as <account>`
2. `GH_ACCOUNT`
3. The config file
4. `gh`'s active account (no token is injected)

### Environment variables

| Variable | Description |
|---|---|
| `GH_ACCOUNT` | Account to use, overriding the config file |
| `GH_HOST` | Host to fetch tokens for (default `github.com`) |
| `GHX_REAL_GH` | Path to the real `gh` binary, if auto-detection picks the wrong one |
| `XDG_CONFIG_HOME` | Base directory for the config file (default `~/.config`) |

## Notes

- `gh auth ...` commands (except `gh auth git-credential`) are passed through untouched, since
  `gh` refuses to manage stored credentials while `GH_TOKEN` is set.
- Git operations run by `gh` itself (e.g. `gh repo clone`, `gh pr checkout`) use the
  selected account.

## Plain git with the right account

To make `git push`/`git pull` use the account configured for the repo, make `ghx` git's credential helper for GitHub:

```sh
git config --global --replace-all credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper '!ghx auth git-credential'
```

This replaces the helper that `gh auth setup-git` installs. With no account selected it
behaves exactly like the stock `gh` helper.

## Tests

```sh
./test/run.sh
```
