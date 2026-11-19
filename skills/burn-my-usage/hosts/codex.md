# Codex host binding

Codex native unattended acceptance remains blocked. Do not start a mutating
Codex run or claim runtime support until the owner accepts native guard and usage tests.
Setup may prepare and check the experimental package; actual installation or host settings
changes require the user's explicit instruction. Shared instructions, preflight and
synthetic tests are not native proof. Installation details are in
[Codex installation](../../../docs/CODEX-INSTALL.md).

The binding is `BMU_HOST=codex`, `BMU_SKILL_DIR` as the actual skill folder,
and `BMU_SESSION_ID` as the native session identifier supplied by startup context. Resolve values
in the host and pass literal, separately quoted arguments to scripts. A session argument
takes precedence over `BMU_SESSION_ID`; never guess an identifier or treat a marker from
another session as ownership. The Codex marker namespace is distinct from Claude Code's
and the run lock is shared.

When runtime acceptance is complete, the actual script process must receive
`BMU_HOST=codex`; resolving a conceptual value alone does not set its environment.
Pass the resolved session ID as an explicit argument where the script accepts one.
The native guard bridge reads and binds identity from the native hook event itself.
Startup context returns pointers only and does not start a run or set tool-process
environment. Reapply the host environment for each helper call; do not assume it persists.

Codex `usage.sh` fetches fresh subscription quota through the supported local app server
for every authorization check. Set `BMU_CODEX_BIN` to an absolute native client executable
when PATH selects a different installed client. The collector requires both five-hour and
weekly windows, uses the stricter percentage and stops for a service-reported reached limit.
Collection, validation, storage or subprocess cleanup failure yields `unknown`; a prior
snapshot cannot authorize the failed check. `usage-codex.mjs read` only inspects saved data.
An actual native guard self-test and native usage-path test must be accepted
before mutation; synthetic adapter tests alone do not establish enforcement.
Use the user's supplied mode. Existing local policy and permissions apply and can be stricter.

The tested Windows clients ignored the portable inline hook extension. The package now
uses the documented compatibility manifest, which exposes both hooks in controlled native
fixtures. Run the read-only discovery/trust diagnostic in the installation guide, review
the installed definitions natively and retain this mutation gate until enforcement is accepted.
Do not bypass hook trust, change security defaults or start work at `stop`/`unknown`.

The Codex adapters require Node 18 or later. On Windows, set `BMU_BASH` or the product
config key `codex_bash` to the absolute path of the installed Git Bash executable; it does not
use a potentially different Bash from PATH. Elsewhere it uses `bash` from PATH unless
`BMU_BASH` is supplied. These dependencies do not establish native integration.
