[README.md](https://github.com/user-attachments/files/35216152/README.md)
# AltMail

A World of Warcraft: **Forever** addon that adds a panel next to the mailbox for quickly mailing your alts.

## Install

1. Download **AltMail.zip** from the [Releases](../../releases) page (not the green "Code" button).
2. Unzip it into your Forever `Interface\AddOns` folder, so you end up with `Interface\AddOns\AltMail\AltMail.toc`.
3. Fully restart the game.

## Features

- **One-click recipients** — click an alt to switch to Send Mail and fill in their name and your subject line (default "here mail :)", editable and remembered).
- **Alts learned automatically** — each character adds itself (full first name + surname, e.g. "Stuper Bonkbolt") the first time you log in on it. You can also type a name and click **Add alt**. Shift + right-click removes one. Other-faction alts are hidden. The To: box always gets just the character's name.
- **Mass-attach items** — a grid of your mailable bag items (soulbound items are hidden):
  - Click to select, Shift-click to select every stack of that item.
  - **All**, **None**, and **Mats** (trade goods and reagents) quick-select buttons.
  - **Attach** adds up to 12 selected items (the mail limit). Press Send, then Attach again for the next batch.

## Commands

| Command | What it does |
|---|---|
| `/altmail` | Hide/show the panel at the mailbox |
| `/altmail list` | Print your saved alts |
