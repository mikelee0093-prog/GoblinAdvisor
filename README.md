# Goblin Advisor

A free, read-only World of Warcraft addon that turns your own Auction House scans into
gold-making advice across all your characters: material prices and trends, crafting profit,
gathering priorities, a gold tracker, and an account-wide character and materials view.

It never buys, sells or posts anything for you, never automates gameplay, and makes no web requests.
Prices come only from your own scans or prices you type in; missing data is shown as "no data".

- Retail (interface 120105): `GoblinAdvisor.toc`
- WoW Forever (interface 16001): `GoblinAdvisor_Camelot.toc`

## Status: beta (0.9.0)
Tested in game on Retail: market prices, professions, characters, Ledger (sales, purchases, unsold items).
Newer parts (Lists tab, crafting comparison) have had lighter testing. Anything marked unverified in
`ROADMAP.md` may behave differently on WoW Forever. Please report problems with the output of
`/ga status` and, for prices, `/ga scan debug <itemID>` (or `/ga ledger debug` at a mailbox).

Features: Dashboard, Professions (profit per craft), Market (search, price detail, history), Gathering,
Gold Tracker, Ledger (real AH sales, purchases, sell-through, crafted vs raw), Lists (shopping list,
watch list with alerts), Characters (account gold, materials, import/export).

## Install
Copy this folder to `World of Warcraft\_retail_\Interface\AddOns\GoblinAdvisor` (the folder must be
named `GoblinAdvisor`), then `/reload`. Type `/ga` in game. `/ga help` lists commands.

See `ROADMAP.md` for status and plans.
