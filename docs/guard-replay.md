# Guard replay

Replay is a development aid for synthetic or explicitly sanitised exported fixtures.
Pass every input file or folder explicitly; there is no default history search. Never
point an agent at raw native history, session databases, credentials or personal stores.
No model calls are made by the replay utility. Node 18+ is a development requirement.

Run `bash tests/replay/run.sh --help`, then supply fixture paths. Results may include
complete synthetic tool inputs; keep them outside the plugin tree. Counts-only summaries
are safer to share but still need review. Remapping can alter apparent paths: use made-up
values such as ~/old-code and ~/code, and always compare against the original fixture.

Every probe needs an expected-deny control and an expected-allow control. A missing guard
or mangled path must not masquerade as a successful bypass test. Git branch reconstruction
is heuristic; replay counts are not a live guard's false-positive rate.

Earlier parser work was exercised on a single-author private corpus. That corpus is not
distributed, not required to install or test this plugin, and not accessed by this release
workflow. Public verification uses synthetic unit and behavior fixtures. Runtime tests
remain necessary for hook failure, trust, usage freshness and session isolation.
