# Factorio server-settings.json reference

`server-settings.json` controls how a Factorio server presents itself and behaves at runtime: its
name, who may join, autosaves, pausing, and network tuning. A KGSM Factorio instance does **not**
use one unless you create it and point the instance at it — see [`setup.md`](setup.md).

The game ships a fully commented template at `install/data/server-settings.example.json` inside the
instance. Keys beginning `_comment_` are documentation and are ignored.

Derived from the Factorio Wiki, "Multiplayer" (CC BY-NC-SA 3.0) and the shipped example file.

## Listing and identity

| Field | Meaning |
|---|---|
| `name` | The server name shown in the game listing |
| `description` | Longer blurb shown in the listing |
| `tags` | List of category tags for the listing |

## Who can join

| Field | Meaning |
|---|---|
| `visibility.public` | Publish to Factorio's official matching server so anyone can find it |
| `visibility.lan` | Broadcast on the local network |
| `username` / `password` | Your **factorio.com account** credentials — required for `public` visibility |
| `token` | An auth token, usable instead of `password`. Prefer it over storing your account password |
| `game_password` | The password *players* must enter to join. Empty means anyone may join |
| `require_user_verification` | Only allow clients holding a valid factorio.com account |
| `max_players` | Connection limit. `0` is unlimited; admins can join a full server |
| `ignore_player_limit_for_returning_players` | Players who already played this map may join past the limit |

Both visibility modes can be off. The server still runs, and players connect by entering the host's
address directly.

`username`/`token` authenticate **your server to Factorio**. `game_password` gates **players joining
your server**. They are unrelated, and confusing the two is the usual reason a server either fails
to publish or is unexpectedly open to everyone.

## Pausing and autosaves

| Field | Meaning |
|---|---|
| `auto_pause` | Pause the game while no players are connected |
| `auto_pause_when_players_connect` | Pause while someone is in the middle of joining |
| `only_admins_can_pause_the_game` | Restrict manual pausing to admins |
| `autosave_interval` | Minutes between autosaves |
| `autosave_slots` | How many autosaves to cycle through before overwriting |
| `autosave_only_on_server` | Write autosaves only on the server, not on every client |
| `non_blocking_saving` | Fork to autosave instead of stalling the game. The developers mark this **highly experimental**, with an explicit risk of losing saves — leave it off unless you accept that |

`auto_pause` is why an idle server looks frozen: with nobody connected there is nothing to simulate.
That is normal, not a hang.

## Moderation

| Field | Meaning |
|---|---|
| `allow_commands` | Who may run console commands: `true`, `false`, or `admins-only` |
| `afk_autokick_interval` | Minutes of inactivity before a kick. `0` never kicks |

Admins are **not** listed here — they live in `server-adminlist.json`.

## Network tuning

Leave these alone unless diagnosing a specific problem.

| Field | Meaning |
|---|---|
| `max_upload_in_kilobytes_per_second` | Upload cap. `0` is unlimited |
| `max_upload_slots` | Concurrent upload slots. `0` is unlimited |
| `minimum_latency_in_ticks` | Artificial latency floor. One tick is 16ms at default speed |
| `max_heartbeats_per_second` | Network tick rate, between 6 and 240 |
| `minimum_segment_size`, `maximum_segment_size`, and their `_peer_count` partners | How long network messages are split across ticks as the player count changes |

## Applying a change

The file is read **once, at startup**. Editing it while the server runs changes nothing until a
restart:

```bash
kgsm restart my-factorio
kgsm instances status my-factorio
```

Always check status afterwards. Factorio validates this file during startup and **exits** if it is
malformed, while KGSM still reports the restart itself as successful.

## Related files

These live beside the server log, not inside `server-settings.json`:

- `server-adminlist.json` — usernames with admin rights, e.g. `["playerone"]`
- `server-whitelist.json` — when present, only these players may join
- `server-banlist.json` — blocked players

`map-gen-settings.json` and `map-settings.json` are different again: they shape a world at creation
time (ore density, biter evolution, pollution) and have no effect on an already-generated save.
