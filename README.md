<img src="logo.png" alt="Book of Grudges logo" width="160">

# Book of Grudges (Buch des Grolls)

Book of Grudges keeps a list of players who wronged you, logs every incident, and automatically flips them a /rude whenever they cross your path.

Someone ninja-looted your drop, stole your ore node or ganked you at the flight master? Write them into the book. From then on the addon remembers, and so will they.

An addon for World of Warcraft: Forever (interface 16001).

## Features

- **Automatic emotes:** When a listed player becomes your target, your mouseover or shows up as a nameplate, you greet them with an emote. A 60-second cooldown per player keeps it from spamming.
- **Three grudge levels:** Mild Grudge (/rude), Deep Grudge (/spit) and Arch-Enemy (both, plus an alarm sound).
- **Incident log:** Every entry collects dated incidents. Add someone who is already listed and the new incident is appended, so you can always see what went wrong and when.
- **Warnings:** An on-screen message and a sound tell you when a listed player is nearby or joins your party or raid.
- **The book:** A parchment-style window with pages to flip through. Click an entry to change its level, add or edit incidents, forgive, remove or post it.
- **Post to chat:** Share an entry with its incidents in party, raid or guild chat, or whisper it to someone.
- **Right-click menu:** Add players or note another incident directly from the player context menu.
- **Tooltips:** A listed player's tooltip shows their grudge level and latest incidents.
- **Statistics:** Counts how often you have seen each player, plus a best-effort tally of kills and deaths against them.
- **Forgiveness:** Forgive a player to strike them through and stop the emotes, and renew the grudge whenever they earn it again.
- **Export and import:** Share your whole book as a text string. Importing never overwrites existing entries.
- **Minimap button:** Click to open the book, drag to move it.

The book is shared across all your characters. The addon is in German on German clients and in English on all others.

## Installation

Copy or clone this folder into your Forever client so that it ends up at:

```
World of Warcraft/_forever_/Interface/AddOns/BuchDesGrolls
```

The folder must be named `BuchDesGrolls`.

## Commands

| Command | What it does |
| --- | --- |
| `/grudge` | Open or close the book |
| `/grudge target [reason]` | Add your current target, optionally with a reason |
| `/grudge add Name: reason` | Add a player by name (the colon separates name and reason) |
| `/grudge remove [Name]` | Remove a player (without a name: your current target) |
| `/grudge forgive [Name]` | Forgive a player (without a name: your current target) |
| `/grudge export` | Show your book as a text string to copy |
| `/grudge import` | Paste another player's export |
| `/grudge help` | List all commands |

Names with a surname work as they appear in game, for example `/grudge add Elodia Bloodreign: stole my kill`.

`/groll` and `/bdg` work as well, and the German command words (`ziel`, `del`, `vergib`) are accepted on every client.

## Notes

- The kill and death tally is approximate: it only counts honorable kills and deaths that show up in the death recap.
- Emotes and chat posts can be blocked by the game in some situations, such as during combat in instances.

## Tests

The addon logic has a smoke test that runs outside the game against a stubbed WoW API:

```
npm install --no-save fengari
node tests/run.js
```
