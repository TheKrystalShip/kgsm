# Bash Debugging: Root Cause Analysis

> **Date**: March 2026
> **Purpose**: Investigate why the VS Code bash debugging experience is lacking compared to debuggers for other languages (e.g., .NET), determine where the missing features originate, and assess feasibility of building a replacement extension.

## TL;DR

The frustration comes from three layers, each contributing differently. The **VS Code extension** is the primary culprit — it exposes only a fraction of what bashdb can do. Bashdb itself is surprisingly capable but hampered by being written in bash and having a text-only interface. Bash the language sets a hard ceiling due to its primitive runtime debug support.

---

## Layer 1: Bash Runtime (Fundamental Limitations)

Bash's debugging support is primitive compared to .NET/Python/Java:

- **No native debug API** — Debug support is entirely trap-based (`DEBUG`, `ERR`, `RETURN` traps). Compare this to .NET's `ICorDebug` or V8's inspector protocol, which are purpose-built structured debugging APIs.
- **No structured scoping** — Variables are either global or `local` to a function. There are no block scopes, no stack frames with rich type metadata.
- **Subshell opacity** — You can't debug across subshell boundaries (`$(...)`, pipes). The debugger loses context when crossing them.
- **No structured data types** — Everything is a string. Arrays and associative arrays exist but there's no type system to inspect.

These are permanent, unfixable constraints of the language.

---

## Layer 2: Bashdb (Capable but Slow, Text-Only Interface)

Bashdb is actually quite feature-rich. Its command set (on the `bash-5.2` branch) supports:

| Feature                   | Bashdb Command                                                | Status          |
| ------------------------- | ------------------------------------------------------------- | --------------- |
| Step/Next/Continue        | `step`, `next`, `continue`                                    | ✅ Works         |
| Breakpoints               | `break`                                                       | ✅ Works         |
| Conditional breakpoints   | `break ... if ...`                                            | ✅ Works         |
| **Watchpoints**           | `watch`, `watche`                                             | ✅ **Works**     |
| **Variable listing**      | `info variables` (with filters: `-i`, `-r`, `-x`, `-a`, `-A`) | ✅ **Works**     |
| **Variable examination**  | `examine` / `x` (uses `typeset -p`)                           | ✅ **Works**     |
| **Variable modification** | `eval`, `assign`                                              | ✅ **Works**     |
| Stack trace               | `backtrace` / `T`                                             | ✅ Works         |
| Frame navigation          | `up`, `down`, `frame`                                         | ✅ Works         |
| **Display (auto-print)**  | `display`, `undisplay`                                        | ✅ **Works**     |
| Function tracing          | `trace`, `untrace`                                            | ✅ Works         |
| Signal handling           | `handle`, `info signals`                                      | ✅ Works         |
| Reverse execution         | —                                                             | ❌ Not supported |

### Bashdb's Real Limitations

1. **Performance** — Written entirely in bash. The `DEBUG` trap fires on *every line*, executing bash-level checks each time. The man page itself acknowledges: *"A better and faster architecture would be for the debugger to register conditions inside the bash code itself and have it arrange to call the debugger only when a condition arises. Checks would be faster as this would be done in C code."*

2. **Text-only interface** — No machine-readable output protocol (contrast with GDB's MI protocol or Chrome DevTools Protocol). Frontends must scrape text output.

3. **BASH_REMATCH contamination** — Bashdb uses regex internally, overwriting your script's `$BASH_REMATCH`. This is an architectural flaw.

4. **`$0` shows bashdb** — When invoked as `bashdb script` (which the extension does) rather than `bash --debugger script`.

### Bashdb Repo Status

- **Repository**: https://github.com/Trepan-Debuggers/bashdb
- **Active branch**: `bash-5.2`
- **Maintenance**: Actively maintained (last commit ~3 weeks ago as of March 2026)
- **Author**: Rocky Bernstein (also maintains debuggers for other languages under the "Trepan" family)

---

## Layer 3: vscode-bash-debug (The Primary Culprit)

This is where most of the missing QoL features originate. The extension deliberately doesn't expose capabilities that bashdb already has.

### Repository Status

- **Repository**: https://github.com/rogalmic/vscode-bash-debug
- **Last meaningful activity**: ~2021
- **Status**: Effectively abandoned. Open issues accumulate with no response.
- **Bundled bashdb**: Ships an old copy internally (`bashdb_dir/`) rather than using the system-installed version.
- **SDK version**: Pinned to `vscode-debugadapter` 1.40.0 (from 2019). VS Code's DAP has evolved significantly since then.

### Explicitly Disabled DAP Capabilities

From `bashDebug.ts` → `initializeRequest()`:

```typescript
response.body.supportsConditionalBreakpoints = true;   // ✅ exposed
response.body.supportsEvaluateForHovers = true;         // ✅ exposed
response.body.supportsSetVariable = false;               // ❌ NOT exposed (bashdb CAN do this)
response.body.supportsStepBack = false;                  // ❌ (bashdb can't either — fair)
response.body.supportsConfigurationDoneRequest = false;  // ❌
```

### Features Bashdb Supports but the Extension Ignores

| Missing Feature                    | Bashdb Has It?                      | Why It's Missing in the Extension                                                                             |
| ---------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Auto-populate Variables panel**  | Yes (`info variables`)              | Extension only shows `$PWD` and `$?` ([issue #168](https://github.com/rogalmic/vscode-bash-debug/issues/168)) |
| **Set/modify variables**           | Yes (`eval`, `assign`)              | `supportsSetVariable = false` hardcoded                                                                       |
| **Data breakpoints / watchpoints** | Yes (`watch`, `watche`)             | Not wired up to DAP's `DataBreakpoint`                                                                        |
| **Function breakpoints**           | Yes (`break func`)                  | Not wired up to DAP's `FunctionBreakpoint`                                                                    |
| **Display expressions**            | Yes (`display`)                     | Not implemented                                                                                               |
| **Frame navigation**               | Yes (`up`, `down`)                  | Not exposed in UI                                                                                             |
| **Attach to running script**       | Yes (via `bashdb-trace` + `source`) | No `attach` request type                                                                                      |

### Architecture Problems in the Extension

1. **Text scraping** — The extension spawns bashdb and communicates via named pipes (FIFOs), parsing raw text output line-by-line. It literally looks for the string `"bashdb<"` as a prompt marker and uses `"############################################################"` as an end-of-output sentinel. This is inherently fragile.

2. **Old SDK** — Pinned to `vscode-debugadapter` 1.40.0 (from 2019). VS Code's DAP has evolved significantly since then with new capabilities (e.g., `DataBreakpoint`, `InstructionBreakpoint`, stepping granularity, etc.).

3. **Abandoned** — 5+ years without updates. Issues pile up with no response.

4. **Minimal variable handling** — The `variablesRequest` handler in the extension only queries a tiny hardcoded set of variables rather than using bashdb's `info variables` command to discover all in-scope variables.

---

## Comparison with .NET Debugging

| Aspect                 | .NET                                   | Bash                               |
| ---------------------- | -------------------------------------- | ---------------------------------- |
| Runtime debug API      | `ICorDebug` / DAC (native, structured) | `DEBUG` trap (text-based hooks)    |
| Debugger engine        | vsdbg (C++, speaks DAP natively)       | bashdb (written in bash itself)    |
| Communication protocol | DAP (structured JSON)                  | Text scraping over named pipes     |
| Variable discovery     | Runtime provides full type info        | Must parse `declare -p` output     |
| Performance impact     | Minimal (JIT-aware breakpoints)        | Massive (trap fires on every line) |
| Extension maintenance  | Microsoft-maintained                   | Abandoned since 2021               |

---

## Feasibility Assessment: New VS Code Bash Debugger Extension

### What a new extension could realistically achieve

By properly wiring up bashdb's existing capabilities to DAP, a new extension could provide **significant** improvements over `rogalmic.bash-debug` without needing to modify bashdb itself:

| Feature                                  | Feasibility      | Notes                                                                                                               |
| ---------------------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| Full Variables panel (all in-scope vars) | ✅ High          | Use `info variables` + `examine` to populate                                                                        |
| Variable modification from UI            | ✅ High          | Wire `supportsSetVariable` to bashdb's `eval`/`assign`                                                              |
| Watchpoints / data breakpoints           | ✅ High          | Wire DAP `DataBreakpoint` to bashdb's `watch`                                                                       |
| Function breakpoints                     | ✅ High          | Wire DAP `FunctionBreakpoint` to bashdb's `break func`                                                              |
| Frame navigation (up/down in call stack) | ✅ High          | Wire to bashdb's `up`/`down`/`frame`                                                                                |
| Attach to running script                 | ✅ Medium        | Use bashdb's `bashdb-trace` mechanism                                                                               |
| Fix `$0` showing bashdb                  | ✅ High          | Use `bash --debugger` invocation instead                                                                            |
| Modern DAP SDK                           | ✅ High          | Use `@vscode/debugadapter` (current)                                                                                |
| Reliable communication                   | 🟡 Medium        | Need to design a robust protocol layer over bashdb's text interface or contribute a machine-readable mode to bashdb |
| Array/associative array visualization    | ✅ High          | Parse `declare -p` output into structured tree                                                                      |
| Inline values (hover)                    | ✅ Already works | Already uses `examine`                                                                                              |
| Log points                               | 🟡 Medium        | Could implement via bashdb's `action` command                                                                       |
| Performance improvement                  | ❌ Low           | Fundamental bashdb/bash limitation — DEBUG trap on every line                                                       |
| Subshell debugging                       | ❌ Low           | Fundamental bash limitation                                                                                         |
| Reverse debugging                        | ❌ Not feasible  | Neither bash nor bashdb support this                                                                                |

### Technical approach

1. **Use `bash --debugger`** instead of invoking `bashdb` directly — fixes `$0` and call stack issues.

2. **Modern DAP implementation** — Use `@vscode/debugadapter` (current SDK) or implement DAP directly over stdio.

3. **Structured bashdb communication layer** — The biggest engineering challenge. Options:
   - **Option A**: Continue text-scraping but with a robust parser (regex-based protocol over bashdb's text output). More fragile but requires no bashdb changes.
   - **Option B**: Contribute a machine-readable output mode to bashdb (JSON or similar). Bashdb is actively maintained — Rocky Bernstein might be receptive. This is the better long-term approach.
   - **Option C**: Use bashdb's annotation mode (`set annotate 3`) which was designed for Emacs integration. This provides structured position information but not all features.

4. **Variable introspection** — Use `info variables` for discovery, `examine`/`typeset -p` for values, and parse the structured `declare -p` output for arrays/associative arrays.

5. **Scoping** — Build scope awareness by combining bashdb's frame commands (`up`/`down`) with `info variables` at each frame level.

### Risks and open questions

1. **Bashdb's text interface stability** — Is the text output format stable across bashdb versions? If not, text scraping is risky.
2. **Bashdb version compatibility** — The extension needs to work with whatever bashdb version is installed. Different distros ship different versions.
3. **BASH_REMATCH contamination** — This is a bashdb architectural issue that can't be fixed from the extension side. Would need a bashdb fix.
4. **Performance** — Nothing the extension can do about bashdb's inherent slowness on large scripts. This is a bash runtime limitation.
5. **Market size** — Is the audience large enough to justify the effort? Bash debugging is niche compared to Python/JS/etc.

### Verdict

**Yes, it is plausible and worthwhile.** A properly built extension could deliver roughly **70-80%** of what .NET debugging feels like for bash scripts, primarily by exposing the bashdb features that `rogalmic.bash-debug` leaves on the table. The remaining 20-30% gap is due to fundamental bash runtime limitations (performance, subshell opacity, no type system) that no extension can fix.

The highest-impact improvements (auto-populated Variables panel, variable modification, watchpoints, function breakpoints, frame navigation) are all **low-hanging fruit** that only require proper DAP wiring to existing bashdb commands.
