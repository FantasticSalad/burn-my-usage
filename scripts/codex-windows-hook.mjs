// Build-time generation only. The native client executes the resulting literal command;
// it never reads or evaluates a script file at runtime.
export function windowsHookCommand(source) {
  const body = source.replace(/\r\n/g, '\n').trim();
  return "$ErrorActionPreference='Stop'; try { $bmuReply = & {\n" + body +
    "\n}; if ($? -and @($bmuReply).Count -eq 1 -and $bmuReply -ceq 'BMU_CODEX_ALLOW_V1') { exit 0 } } catch {}; " +
    "[Console]::Out.WriteLine('{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"burn-my-usage guard: Windows supervisor denied or unavailable\"}}'); exit 0";
}
