# manage.d/ Modularization Analysis

> **Status**: Analysis / Feasibility Study
> **Date**: 2026-03-05
> **Scope**: Evaluate splitting monolithic manage templates into a `manage.d/` directory-based module system

---

## 1. Problem Statement

The management templates (`manage.native.tp` at ~1993 lines and `manage.container.tp` at ~2016 lines) are monolithic scripts that serve as the single entry point for all instance management operations. While functionally complete, their size creates concrete maintenance problems:

- **Readability**: ~2000 lines of densely packed bash with 47+ functions per template makes navigation difficult.
- **Refactoring risk**: Any change to one section risks regressions in unrelated sections due to shared variable scope.
- **Review burden**: Code reviews must process the entire file even for targeted changes.
- **User extensibility**: No mechanism for users to inject pre/post hook logic without modifying the generated script directly.

## 2. Proposed Pattern

Adopt the Linux `.d` directory convention (used by `cron.d/`, `conf.d/`, `init.d/`, `sudoers.d/`, etc.) to split the monolithic manage script into ordered, sourceable modules.

### Proposed directory structure

```
${instance_working_dir}/
├── ${instance_name}.manage.sh          # Slim dispatcher (~200-300 lines)
└── manage.d/
    ├── 00-config.sh                    # Configuration loading, variables, constants
    ├── 01-utilities.sh                 # Print helpers, validation, sanitization
    ├── 02-help.sh                      # Usage/help text for all commands
    ├── 03-version.sh                   # Version checking, comparison, storage
    ├── 04-download.sh                  # Download logic (SteamCMD / docker pull)
    ├── 05-deploy.sh                    # Deployment logic (file moves / no-op)
    ├── 06-lifecycle.sh                 # Start, stop, restart, kill, attach
    ├── 07-io.sh                        # Server input/output, save commands
    ├── 08-backup.sh                    # Backup creation, restoration, listing
    ├── 09-network.sh                   # UPnP port forwarding
    ├── 10-logging.sh                   # Log rotation and display
    ├── 11-status.sh                    # Status reporting (JSON/human)
    └── 12-commands.sh                  # _cmd_* handler functions
```

The main `manage.sh` would:
1. Source `00-config.sh` to establish variables and constants.
2. Source remaining `manage.d/*.sh` files in numeric order.
3. Parse CLI arguments and dispatch to `_cmd_*` handlers.

### User hook extension point

The numeric ordering creates natural insertion points for user-provided hooks:

```
manage.d/
├── 05-deploy.sh                        # KGSM-provided
├── 05-post-deploy-custom.sh            # User-provided hook
├── 06-lifecycle.sh                     # KGSM-provided
```

Users could drop scripts at any priority level to run custom logic without modifying KGSM-managed files.

---

## 3. Current Template Structure

Both templates share the same organizational pattern with 12 sections, 16 command handlers, and identical CLI interfaces. The key structural data:

### manage.native.tp (~1993 lines, 47 functions)

| Section | Lines | % | Coupling |
|---------|-------|---|----------|
| Config & Init | ~118 | 5.9% | Foundation — everything depends on this |
| Help System | ~346 | 17.3% | None — pure documentation |
| Process Management | ~344 | 17.2% | Tight — depends on I/O, UPnP, config |
| Server I/O | ~70 | 3.5% | Moderate — depends on config |
| Version Management | ~80 | 4.0% | Low — depends on config, SteamCMD |
| Download & Deploy | ~134 | 6.7% | Moderate — depends on version |
| Backup Management | ~179 | 9.0% | Low — depends on config, version |
| Network (UPnP) | ~60 | 3.0% | Low — optional, config-gated |
| Logging | ~44 | 2.2% | Low — depends on config |
| Status | ~198 | 9.9% | Reads from all subsystems |
| Command Handlers | ~293 | 14.7% | Dispatches to all modules |
| Main Dispatch | ~99 | 5.0% | Entry point |

### manage.container.tp (~2016 lines, ~70 functions)

Same section layout with additional container-specific functions (`_get_container_process_info`, `_monitor_container_state`). Docker commands are interspersed throughout lifecycle, I/O, download, and status sections rather than isolated.

### Cross-template parity requirements

Per the existing review spec (`manage-templates-review-spec.md`), the templates must maintain:
- 100% CLI interface parity (identical dispatch blocks, handler signatures, JSON output structure).
- Same exit code constants (`EC_SUCCESS`, `EC_ERROR`, `EC_MISSING_ARG`, `EC_INVALID_ARG`).
- Same 12-section structure and ordering.
- Identical `_cmd_*` handler signatures (16 handlers).

---

## 4. Compatibility with Existing Architecture

### Patterns that support modularization

| Pattern | How it helps |
|---------|-------------|
| **Guard-clause loading** (`core/common.sh`) | Proven pattern for idempotent module sourcing; can be reused in manage.d modules |
| **Override injection** (`commands/handlers/files.common.sh`) | Already appends external functions into manage scripts — proves modular function injection works |
| **`export -f` convention** | All library functions already export for subprocess availability — modules can follow this pattern |
| **Template expansion via `eval`** | Flexible enough to generate a slim dispatcher that sources `manage.d/` files |
| **Command/handler separation** | KGSM already separates I/O commands from pure logic — same principle applies here |

### Patterns that create friction

| Pattern | Concern |
|---------|---------|
| **Single-file template expansion** | Currently expands one `.tp` file into one `.sh` file; would need to expand multiple templates or copy pre-built modules |
| **Override injection at end of file** | Currently `grep`s for function names and appends them — would need to know which module file to inject into, or use a dedicated overrides module |
| **Instance portability** | The current single-file design means an instance is fully self-contained; splitting into `manage.d/` adds a directory dependency |

---

## 5. Viability Assessment

**Verdict: Viable, with caveats.**

The `.d` directory pattern is well-established in Linux systems and maps naturally onto the existing section boundaries in the manage templates. The KGSM architecture already uses module loading, guard clauses, and function injection patterns that would translate directly.

### What makes it viable

1. **Clear section boundaries already exist.** The templates are organized into 12 named sections with minimal cross-section function calls. This is not a tangled monolith — it is a well-organized monolith, which is the ideal starting point for modularization.

2. **Low-coupling sections are easy wins.** Help (~346 lines), backup (~179 lines), UPnP (~60 lines), logging (~44 lines), and version management (~80 lines) have minimal dependencies on other sections. These can be extracted immediately with near-zero risk.

3. **Existing patterns provide the blueprint.** `core/common.sh` already demonstrates ordered module loading with guard clauses. The manage.d loader can follow the same pattern.

4. **User hooks become trivially implementable.** The numeric ordering convention creates natural extension points without any additional framework code.

### What makes it non-trivial

1. **Lifecycle management is tightly coupled.** The process management section (~344 lines) calls into I/O, UPnP, update, and cleanup functions. Extracting it requires either accepting cross-module function calls (which is fine — Linux `.d` modules do this) or refactoring the dependency chain.

2. **Shared variable scope is load-bearing.** All modules rely on `instance_*` variables set during config loading. This is not a problem per se (sourced scripts share the parent's scope), but it means module load order is critical and must be enforced.

3. **Template generation pipeline changes.** The current pipeline expands a single `.tp` file. The new pipeline must either:
   - (a) Expand multiple `.tp` files into a `manage.d/` directory, or
   - (b) Ship pre-built module scripts and only template-expand the config module.

   Option (b) is simpler and more maintainable.

4. **Two template variants must stay synchronized.** Every `manage.d/` module needs native and container variants where behavior diverges (lifecycle, I/O, download, deploy, status). Modules where behavior is identical (help, backup, UPnP, logging) can be shared.

---

## 6. Benefits

### Maintenance
- **Targeted edits**: Changing backup logic means editing only `08-backup.sh` (~180 lines) instead of navigating a 2000-line file.
- **Focused code reviews**: PRs touch specific modules, making review scope clear.
- **Reduced merge conflicts**: Parallel development on different modules avoids file-level conflicts.

### Extensibility
- **User hooks**: Drop-in scripts at any priority level (e.g., `05-post-deploy-custom.sh`) without modifying KGSM-managed files. This is a significant UX improvement.
- **Optional features**: Modules like UPnP or auto-update can be conditionally loaded based on config, reducing execution overhead for instances that don't use them.

### Testability
- **Unit-testable modules**: Individual modules can be sourced and tested in isolation (after sourcing config).
- **Focused assertions**: Tests target specific module behavior rather than the entire management script.

### Readability
- **Self-documenting structure**: The filename communicates purpose (`08-backup.sh` is obviously backup logic).
- **Manageable file sizes**: Modules range from ~50 to ~350 lines — well within comfortable reading range.

### Architecture alignment
- **Follows KGSM's own patterns**: Mirrors `core/common.sh` module loading.
- **Follows Linux conventions**: `.d` directories are immediately understood by sysadmins.

---

## 7. Downsides

### Complexity
- **More files to manage**: 12-13 files per instance instead of 1. File operations (copy, permission setting, updates) become loops instead of single commands.
- **Load order sensitivity**: Incorrect ordering causes undefined function/variable errors. Must be enforced by numeric prefixes and validated.
- **Debugging friction**: Stack traces span multiple files. Developers must cross-reference module boundaries when tracing execution flow.

### Performance
- **Sourcing overhead**: 12 `source` calls instead of 1. Each `source` invokes a filesystem read and bash parser pass. On modern systems this is negligible (sub-millisecond per file), but measurable on constrained hardware or network filesystems.
- **No lazy loading benefit**: All modules must be sourced at startup because the dispatcher doesn't know which command will be invoked until after argument parsing. The total code loaded is identical to the monolithic version.

### Portability
- **Directory dependency**: The instance is no longer a single self-contained script. Moving an instance requires copying the `manage.d/` directory alongside the manage script. The current single-file model is more portable.
- **Atomic updates become harder**: Updating the manage script is currently a single file write. With `manage.d/`, a partial update (e.g., power failure mid-copy) could leave an instance in an inconsistent state with mismatched module versions.

### Template pipeline
- **Generation complexity**: The template expansion pipeline must handle multiple output files or adopt a copy-from-source model. Either approach adds complexity to the instance creation handler.

---

## 8. Pitfalls & Risks

### P1: Variable scope leakage between modules
**Risk**: Modules share the same shell scope. A variable set in one module can silently overwrite a variable in another. The current monolithic script has this same property, but modularization makes it less visible because developers edit modules in isolation.
**Mitigation**: Establish naming conventions — module-private variables use `_module_prefix_var` pattern. Document shared variables in the config module header.

### P2: Circular or missing dependencies
**Risk**: Module A sources module B which needs a function from module A. Or a module is accidentally deleted/renamed, breaking the load chain.
**Mitigation**: Enforce strict numeric ordering. The loader should validate that all expected modules exist before sourcing any. Add a manifest or checksum file.

### P3: User hook scripts breaking the instance
**Risk**: User-provided hook scripts in `manage.d/` could redefine core functions, introduce syntax errors, or alter shared state in ways that break the management pipeline.
**Mitigation**: 
- Separate KGSM-managed modules from user hooks (e.g., `manage.d/` for KGSM, `hooks.d/` for users).
- Or prefix KGSM modules with a reserved prefix and document that overwriting them is unsupported.
- Validate hook scripts with `bash -n` before sourcing.

### P4: Partial update inconsistency
**Risk**: If an update replaces some modules but fails before completing, the instance runs with a mix of old and new module versions.
**Mitigation**: Use atomic update strategy — write to a staging directory, then rename. Or version-stamp modules and validate consistency at load time.

### P5: Override injection ambiguity
**Risk**: The current override system appends functions to the end of the manage script. With modules, it's unclear which module should receive the override functions, or whether overrides should become their own module.
**Mitigation**: Make overrides a dedicated module (e.g., `99-overrides.sh`) sourced last, which naturally overrides any function defined in earlier modules. This actually simplifies the override system.

### P6: Divergence between native and container module variants
**Risk**: Shared modules (help, backup, UPnP) may drift apart if maintained as separate copies per template type.
**Mitigation**: For truly shared modules, use a single source file. For divergent modules (lifecycle, I/O, download), maintain separate native/container variants in the template directory and copy the appropriate one during instance creation.

### P7: Instance decoupling guarantee weakened
**Risk**: The current design guarantees instances are fully independent from KGSM after creation. If `manage.d/` modules are symlinked to KGSM source (rather than copied), this guarantee breaks.
**Mitigation**: Always copy modules into the instance directory. Never symlink to KGSM source files. This preserves the decoupling guarantee at the cost of disk space (negligible — these are small text files).

---

## 9. Module Dependency Map

The following shows which modules depend on which, informing the required load order:

```
00-config.sh          ← Foundation (no dependencies)
01-utilities.sh       ← Depends on: 00-config
02-help.sh            ← Depends on: 00-config (for variable interpolation in help text)
03-version.sh         ← Depends on: 00-config, 01-utilities
04-download.sh        ← Depends on: 00-config, 01-utilities, 03-version
05-deploy.sh          ← Depends on: 00-config, 01-utilities
06-lifecycle.sh       ← Depends on: 00-config, 01-utilities, 03-version, 04-download,
                                     05-deploy, 07-io, 09-network
07-io.sh              ← Depends on: 00-config, 01-utilities
08-backup.sh          ← Depends on: 00-config, 01-utilities, 03-version
09-network.sh         ← Depends on: 00-config, 01-utilities
10-logging.sh         ← Depends on: 00-config, 01-utilities
11-status.sh          ← Depends on: 00-config, 01-utilities, 03-version, 06-lifecycle,
                                     08-backup
12-commands.sh        ← Depends on: all above
```

**Note**: `06-lifecycle.sh` has the most dependencies and is the primary source of coupling. It calls into version, download, deploy, I/O, and network modules during start/stop operations. This is inherent to its orchestration role and is not a problem — it is analogous to `main()` calling library functions.

---

## 10. Recommended Module Boundaries

Based on coupling analysis, the modules fall into three tiers:

### Tier 1 — Extract immediately (low coupling, high value)

| Module | Lines | Rationale |
|--------|-------|-----------|
| `02-help.sh` | ~346 | Zero dependencies. Pure text. Largest easy win. |
| `08-backup.sh` | ~179 | Only depends on config and version. Self-contained CRUD operations. |
| `09-network.sh` | ~60 | Optional feature. Config-gated. Completely independent. |
| `10-logging.sh` | ~44 | Pure utility. Trivial extraction. |

### Tier 2 — Extract with care (moderate coupling)

| Module | Lines | Rationale |
|--------|-------|-----------|
| `03-version.sh` | ~80 | Low coupling but called by lifecycle and backup. |
| `04-download.sh` | ~134 | Depends on version. Called by lifecycle during auto-update. |
| `05-deploy.sh` | ~50-100 | Simple but called by download pipeline. |
| `07-io.sh` | ~70 | Called by lifecycle during save-before-stop. |
| `11-status.sh` | ~198 | Reads from multiple subsystems. Aggregator pattern. |

### Tier 3 — Extract last (tight coupling, high complexity)

| Module | Lines | Rationale |
|--------|-------|-----------|
| `06-lifecycle.sh` | ~344 | Orchestrator. Calls into version, download, deploy, I/O, network. Must be extracted after its dependencies. |
| `12-commands.sh` | ~293 | Thin dispatch layer. Depends on all modules. Must be last. |

---

## 11. Comparison with Alternative Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **manage.d/ (proposed)** | Linux convention, user hooks, focused files, testable | More files, load-order sensitivity, update atomicity |
| **Keep monolith, add sections** | Simple, portable, no pipeline changes | Doesn't solve the core readability/maintainability problem |
| **Shared library + thin dispatch** | Maximum code reuse between native/container | Breaks instance decoupling; instances depend on shared library |
| **Compiled/generated single file** | Best of both: modular source, monolithic output | Build step complexity; debugging maps source→generated |

### Note on the compiled/generated approach

An alternative worth considering: maintain modular source files in the KGSM repository but concatenate them into a single manage script during instance creation. This preserves the single-file portability of the current design while gaining all the source-code maintainability benefits. The trade-off is that debugging the generated script requires mental mapping back to the source modules, and user hooks would need a different mechanism.

---

## 12. Conclusions

1. **The approach is viable and well-suited to the existing architecture.** KGSM already uses module loading patterns (`core/common.sh`), guard clauses, and function injection that translate directly to a `manage.d/` system.

2. **The biggest wins are in maintainability and extensibility**, not performance or functionality. The modular version does exactly the same work as the monolith — it just organizes the code better and opens the door to user hooks.

3. **The primary risks are operational, not architectural.** Partial updates, load-order violations, and user hook safety are solvable with validation and conventions, but they add surface area that the monolithic design doesn't have.

4. **Instance decoupling must be preserved.** Modules must be copied into each instance directory, not symlinked. This is non-negotiable per KGSM's design philosophy.

5. **The lifecycle module will be the hardest to extract** due to its orchestration role. It should be the last module extracted, after all its dependencies are stable.

6. **Consider the hybrid approach**: maintain modular source in the repository, generate either a `manage.d/` directory or a concatenated single file at instance creation time. This gives maximum flexibility with a configuration toggle.

7. **Override injection becomes simpler, not harder.** A dedicated `99-overrides.sh` module sourced last naturally overrides earlier function definitions, which is cleaner than the current grep-and-append approach.
