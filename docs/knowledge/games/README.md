# Per-game operator guides

One directory per game, holding the knowledge an operator needs to **run** that server on KGSM.
Written for two readers: a person setting up or debugging a server by hand, and the assistant's
retrieval index.

This is a different axis from the rest of `docs/knowledge/`, which explains how to **author a
blueprint**. These documents assume the blueprint exists and the server is installed.

```
games/<game>/setup.md            Installing and running it on KGSM
games/<game>/configuration.md    The game's own settings files and what each knob does
games/<game>/troubleshooting.md  Symptoms, causes, and what to check
```

A game may carry fewer than three documents; add one when there is measured content for it, not to
complete the set.

## Rules for these documents

- **The blueprint owns the mechanical facts.** Ports, Steam app ids, launch arguments, stop commands
  and readiness lines live in `blueprints/<game>.bp.yaml` and are not restated here. Restating them
  creates a second source of truth that drifts, and a reader who trusts the prose over the engine.
  Describe what a setting *means* and what breaks; let the blueprint say what the value *is*.
- **Describe KGSM's workflow, not a manual install.** Public guides begin by creating a user,
  unpacking a tarball and writing a service unit. KGSM has already done that. A document that
  repeats those steps leads people to redo, or undo, what the engine manages.
- **Measured, or not stated.** Every claim here should come from a server that was actually run and
  observed. An error message is quoted from a real log, not paraphrased from memory. This is the
  same rule the blueprints follow.
- **Headings are the retrieval key.** Each chunk is indexed with its heading breadcrumb, so a
  heading phrased the way a person asks the question ("Nobody outside my network can join") is found
  far more reliably than a structural one ("Network configuration").
- **Say what the guides do not cover.** Every game's `setup.md` opens with a scope section naming
  what is out of scope and where the answer actually lies. Similarity alone cannot tell "this
  document answers the question" from "this document is about the same game", so a question a guide
  does not cover still retrieves it — and without a scope section the reader is handed a confident
  answer to something else. Name the excluded topic explicitly, because a sentence that never
  mentions modpacks is not found by someone asking about modpacks.
- **Cite the upstream source and its licence** at the top of each document when it is derived from a
  community wiki or vendor documentation.

## Games covered

| Game | Documents |
|---|---|
| [Factorio](factorio/) | [setup](factorio/setup.md), [configuration](factorio/configuration.md), [troubleshooting](factorio/troubleshooting.md) |
| [Minecraft](minecraft/) | [setup](minecraft/setup.md), [configuration](minecraft/configuration.md), [troubleshooting](minecraft/troubleshooting.md) |
| [Terraria](terraria/) | [setup](terraria/setup.md), [configuration](terraria/configuration.md), [troubleshooting](terraria/troubleshooting.md) |
| [Valheim](valheim/) | [setup](valheim/setup.md), [configuration](valheim/configuration.md), [troubleshooting](valheim/troubleshooting.md) |
