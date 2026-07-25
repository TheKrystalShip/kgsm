# KGSM knowledge base

Reference knowledge about how native Linux dedicated game servers are set up, and how KGSM
blueprints express that. It is written for two readers: a person hand-authoring or debugging a
blueprint, and the assistant's retrieval index (every `.md` here is indexed for RAG).

The authority for the blueprint *schema and fields* is [`../blueprints.md`](../blueprints.md); the
authority for a *specific game* is its shipped `blueprints/<game>.bp.yaml`. These documents explain
the **patterns and reasoning** behind those fields — the parts that generalise from one game to the
next — so a new blueprint can be built correctly the first time.

| Document | Covers |
|---|---|
| [`native-server-launch.md`](native-server-launch.md) | How a native server is launched: wrapper scripts vs raw binaries, interpreter-run servers, the executable subdirectory, headless arguments, readiness detection, stop commands |
| [`steam-downloads.md`](steam-downloads.md) | SteamCMD installs: the dedicated-server app id vs the client app id, anonymous vs account-owned downloads |
| [`game-reference.md`](game-reference.md) | Annotated real examples from the shipped catalog, grouped by the pattern each one illustrates |

Two facts hold throughout and are not repeated in every section:

- **Every value is measured or documented, never guessed.** A field whose value is unknown is left
  at its schema default (an empty string, `0`, or `null`) — never filled with a plausible-looking
  invention. A wrong value that looks right is worse than an honest blank.
- **Launch arguments may reference KGSM's `$instance_*` variables**, which the engine substitutes
  when an instance is created (`$instance_level_name`, `$instance_saves_dir`,
  `$instance_install_dir`, and the rest). These are the *only* variables available; see
  [`../blueprints.md`](../blueprints.md) for the full list. No other `$NAME` token exists — anything
  else resolves to an empty string at runtime.
