# SteamCMD downloads: server app id, client app id, and account ownership

Games distributed through Steam are installed with SteamCMD (`steamcmd +app_update <id>`). Three
blueprint fields describe that install, and the distinction between them is subtle and load-bearing —
getting it wrong either installs the wrong files or wrongly refuses to install at all.

## Two different app ids

A game on Steam has two separate Steam applications, with two different app ids:

- **The client app id** — the game players buy and launch to connect. This is the id shown on the
  store page. It goes in `client_steam_app_id`.
- **The dedicated-server app id** — a *separate* application containing just the server files, the one
  named in the `steamcmd +app_update <id>` command. This goes in `steam_app_id`.

These are almost always different numbers. In the catalog: Valheim's server is `896660`, its client
`892970`; Core Keeper's server `1963720`, client `1621690`; Necesse's server `1169370`, client
`1169040`; Barotrauma's server `1026340`, client `602960`; Palworld's server `2394010`, client
`1623730`.

**Install against the server id, never the client id.** A store-page or SteamDB URL carries the client
id; using it downloads the game, not the server. `steam_app_id` is set only from a genuine
server-download context — the `+app_update` command or documentation that explicitly names the
dedicated-server app id.

If a game is not installed through SteamCMD at all (its server downloads from the vendor's own site,
handled by a per-game override script), `steam_app_id` is `0`. Factorio, Terraria and Minecraft are
catalog examples: `steam_app_id: 0`, with the client id recorded in `client_steam_app_id` for
reference.

## Account ownership: anonymous vs owned downloads

`is_steam_account_required` records whether downloading the *server* needs a Steam account that owns
the game. It matters because most automated and headless installs log in anonymously
(`steamcmd +login anonymous`).

The reliable signal is the relationship between the two app ids:

- **A dedicated-server app id different from the client id ⇒ a free standalone server application
  exists ⇒ ownership is not required.** It downloads anonymously. This is the common case — every
  game listed above has `is_steam_account_required: false`.
- **The server downloading under the *same* app id as the paid client ⇒ the server ships inside the
  game, there is no separate free server app ⇒ ownership is required.** Starbound is the catalog
  example: `steam_app_id: 211820` and `client_steam_app_id: 211820` are identical, and
  `is_steam_account_required: true`. Its files download only through an account that owns the game, so
  an anonymous install cannot fetch them.

Other signals that ownership is required: the SteamCMD command logs in with a personal account
(`+login <username>`) rather than `+login anonymous`, or documentation states the *server* files
cannot be downloaded anonymously.

Generic "you must own the game to play" wording describes the **client**, not the server download, and
on its own does not mean ownership is required to host — a game with a distinct free server app id is
still installable anonymously despite such wording.
