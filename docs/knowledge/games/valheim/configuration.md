# Valheim server configuration reference

Valheim has **no server configuration file**. Everything is set with launch arguments, which on KGSM
live in the instance's `executable_arguments`. Access control is the one exception: three text files
alongside the worlds.

Derived from Iron Gate's "A Guide to Dedicated Servers" and the arguments the shipped
`start_server.sh` documents.

## Changing a setting

```bash
kgsm instances config-get my-valheim executable_arguments
kgsm instances config-set my-valheim 'executable_arguments=<the full new list>'
kgsm restart my-valheim
kgsm instances status my-valheim
```

`config-set` replaces the whole argument list, so start from what `config-get` prints and edit it,
rather than writing a fresh line and dropping the arguments that make the instance work.

Keep `-savedir $instance_saves_dir`, `-world $instance_level_name` and `-name $instance_level_name`
as they are: those `$instance_*` variables are what tie the server to this instance's own files.

## Identity and access

| Argument | Meaning |
|---|---|
| `-name <text>` | The server's display name in the browser list |
| `-password <text>` | **Required.** At least 5 characters, and it must not appear anywhere in `-name` |
| `-public 1\|0` | `1` lists the server in the community browser; `0` means join by address only |
| `-crossplay` | Use the PlayFab backend so non-Steam platforms can join |

A server **will not start** without a password — it exits reporting a bad password. The shipped
blueprint therefore ships `-password CHANGE_ME`, which is a placeholder, not a default to keep. A
public server whose password is the one every KGSM install starts with is open to anyone who has
read this page.

`-crossplay` routes players through relay servers rather than a direct connection, so it does not
need a forwarded port. It also costs some latency compared with a direct Steam connection.

## World

| Argument | Meaning |
|---|---|
| `-world <name>` | The world to load, created if absent |
| `-savedir <path>` | Where worlds and the access lists are kept |
| `-preset <name>` | World difficulty preset: `normal`, `casual`, `easy`, `hard`, `hardcore`, `immersive`, `hammer` |
| `-modifier <key> <value>` | Adjusts one world setting after a preset, e.g. `-modifier raids none` |

`-savedir` is what keeps a KGSM instance self-contained. Without it Valheim writes to
`~/.config/unity3d/IronGate/Valheim`, which is shared by every server the account runs and is
outside the instance — so the instance's backups would capture nothing.

A preset applies when the world is created. Changing it later does not re-shape an existing world.

## Networking

| Argument | Meaning |
|---|---|
| `-port <number>` | The base port |

Valheim uses **UDP**, and binds a listener on **`port + 1`** — with `-port 2456` the socket that
appears is `2457/udp`. The blueprint declares the range the vendor asks to be forwarded.

Change the port only through this argument. KGSM opens and closes the instance's declared ports
around its lifecycle, so a port that disagrees with the blueprint's `ports` produces a server nobody
can reach.

## Access-control lists

Three files live in the save directory — on a KGSM instance that is `saves/`, beside `worlds_local/`.
The server creates them on first start, each with a comment line explaining itself.

| File | Effect |
|---|---|
| `adminlist.txt` | Grants admin powers in-game |
| `bannedlist.txt` | Blocks these players |
| `permittedlist.txt` | **Allow-list.** If it has any entry, everyone not listed is refused |

One platform user ID per line, written `[Platform]_[UserID]` and case-sensitive.

`permittedlist.txt` is the one to be careful with: adding a single person turns the server into an
allow-list and locks out everyone else, including people already playing. An empty file means "no
allow-list", which is not the same as "nobody is permitted".

## What Valheim does not have

- **No console commands.** The server reads nothing on its console, so there is no in-band way to
  save, kick, or list players. `kgsm instances input` has nothing to talk to, and KGSM's
  `kick`/`ban`/`unban` verbs are unavailable — moderation is the list files plus a restart.
- **No configuration file.** Anything you want changed is a launch argument.
- **No save command.** The server autosaves on its own schedule and writes the world when it shuts
  down.
