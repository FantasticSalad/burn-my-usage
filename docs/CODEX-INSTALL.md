# Codex package preparation

This is an experimental package for manual Codex desktop installation and review. Its
native discovery, hook trust, enforcement, session identity and usage path still require
acceptance. Do not start unattended mutating work until those gates are accepted. Hooks
are a guardrail, not a sandbox; see SECURITY.md.

Requires Node 18 or newer, Git and Bash. On Windows, set `BMU_BASH` to the absolute path
of the installed Git Bash executable, or set `codex_bash` in the burn home's `config.md`.
The burn home defaults to `~/.burn-my-usage`; `BURN_MY_USAGE_HOME` overrides it. The
preflight checks that the executables run, not that the host invokes the hooks.

From the source folder, choose a new absolute destination whose parent exists:

```text
node scripts/codex-package.mjs prepare ABSOLUTE_DESTINATION
node scripts/codex-package.mjs check ABSOLUTE_DESTINATION
```

Preparation refuses existing destinations and symlink paths and copies an explicit
runtime file list. The generated SHA-256 inventory detects subsequent package changes;
it is not a signature. Failed preparation may leave a partial destination for the owner
to inspect and remove. Rebuild at a fresh destination after changes.

Review the contents and hook commands. When ready to add this prepared local marketplace,
run the following command with the same absolute destination, then select and install the
plugin in Codex desktop and review its hook trust prompt:

```text
codex plugin marketplace add ABSOLUTE_DESTINATION
```

Adding a marketplace changes the owner's Codex configuration; preparation and preflight
do not. See the current [OpenAI plugin packaging instructions](https://developers.openai.com/plugins/build/plugins).
Plugin lifecycle hooks are supported for manually installed desktop plugins and are not
eligible for the public plugin directory. Discovery and a successful preflight are not
proof that hooks run or fail closed. Publication also requires the separate release and
artifact metadata reviews.

After installation, run this read-only discovery/trust diagnostic from the prepared copy:

```text
node scripts/codex-native-check.mjs ABSOLUTE_PROJECT_FOLDER
```

Set `BMU_CODEX_BIN` to an absolute executable path to select a particular installed client;
otherwise the helper uses `codex` from PATH. It calls only supported native discovery APIs,
prints a bounded summary and leaves settings and hook trust unchanged. Exit 1 means a
missing, disabled or untrusted component; exit 2 means the diagnostic could not complete.
A ready result means enforcement tests can begin, not that they have passed. Tested Windows
clients `0.162.0-alpha.17.2` and `0.167.0-alpha.3.2` ignored inline OpenAI hook settings.
These clients also suppress compatibility/default hooks when a schema-bearing portable
manifest remains at the package root. The prepared payload therefore uses the supported
`.codex-plugin/plugin.json` layout alone, preserving portable identity as
`docs/portable-plugin.json`. The source repository retains its root portable manifest;
install the prepared payload for these clients. Both hooks are discoverable as untrusted
in the normal profile. Use the native `/hooks` review
flow for the exact installed definitions. Do not bypass trust or assume discovery means
enforcement. No mutating run is accepted until the native safety tests also pass.

Live quota is checked with `BMU_HOST=codex` passed to `usage.sh` for every authorization
check. `usage-codex.mjs collect` explicitly refreshes a snapshot; `check` refreshes and
returns a verdict; `read` only inspects a saved snapshot and must not authorize work.
The live collector requires five-hour and weekly subscription windows and returns unknown
for unsupported shapes or any collection/validation/storage/cleanup failure. It uses the
client's supported authentication internally, without opening credentials or session stores.
Stop at the configured limit, and retain the native enforcement gate even when quota is go.

Native testing on 12 November 2026 found that Node startup failure let the tested client run
the tool after reporting hook failure. The Windows repair was natively verified on 13 November:
normal inactive use works and the same crash now causes explicit PreToolUse denial with no
command execution. Unattended Codex builds retain their broader acceptance gates. See
[the native acceptance record](NATIVE-ACCEPTANCE.md) for the opt-in supervised probe and
the required independent enforcement boundary. Successful discovery or trust is insufficient.

The subsequent Windows startup repair embeds a bounded PowerShell supervisor in the native
hook command. It emits a denial if Node cannot complete with the expected positive token.
The authoring `.ps1` template is not loaded at runtime, and no execution-policy change is
required. The 18-second internal deadline leaves time before the 40-second native timeout.
Fresh native review of a changed package is required; a previous hook's trust cannot be
assumed to cover it. Both exact v8 hooks were explicitly approved and trusted for the
Windows regression above. See the current acceptance record for actual verification status.
