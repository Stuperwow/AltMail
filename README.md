[README_1.md](https://github.com/user-attachments/files/35315504/README_1.md)
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
  - Quick-select buttons: **All**, **None**, **Mats** (every crafting reagent and trade good), **Consum.**, **Ore**, **Herbs**, **Cloth**, **Ench** and **Leather**. **More** opens the full category list. Shift-click a button (or Shift-pick from More) to add to what's already selected instead of replacing it.
  - **Attach** adds up to 12 selected items (the mail limit). Press Send, then Attach again for the next batch.
- **Bank alt**: right-click an alt to make it your bank alt (it gets a gold "(bank)" tag). Right-click again to unset.
- **Routes**: rules for where things go. Click **Routes** to manage them. Each route sends one of these:
  - **This item**: Alt-click an item in the bag grid to pick it.
  - **Name contains**: for example `Scroll:` catches every mage scroll.
  - **Category**: click the Category button for a pick list. It also shows how many of each you're carrying:
    - **Ore**, **Ore, bars & stone**
    - **Herbs**: every Herbalism herb, Peacebloom through Black Lotus plus the TBC and Wrath herbs
    - **Cloth** (including bolts), **Leather & hides**
    - **Enchanting mats**: dusts, essences, shards and crystals
    - **Elementals**, **Cooking meat & fish**
    - **All reagents & mats**: any crafting reagent or trade good
    - **Trade goods**, **Consumables**, **Gems**, **Recipes**, **BoE gear (green+)**, **Bags**

    Herbs, ore, cloth and enchanting mats match by item type *and* by a built-in item ID list, so they're caught even if Forever tags one differently.

  ...to an alt, or to **Bank alt**, which follows whoever your bank alt is. If an item matches more than one route, a picked item wins over a name match, and a name match wins over a category. Routes that would send to the character you're on are skipped. Untick a route to pause it.
- **Prep mail**: fills in the next recipient and attaches everything your routes send them. When you click **Send**, the next mail is prepped automatically, so you just keep clicking Send until it says "All routed mail sent!". The button shows how many items in your bags have a route. Hover an item in the grid to see where it's routed.

## Commands

| Command | What it does |
|---|---|
| `/altmail` | Hide/show the panel at the mailbox |
| `/altmail list` | Print your saved alts |
| `/altmail routes` | Open the Routes window (at a mailbox) |
