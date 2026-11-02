# Goblin Advisor - roadmap

Current version: 0.5.1 (Retail interface 120105; Forever interface 16001 via `GoblinAdvisor_Camelot.toc`).
Testing happens on Retail now. Forever (Classic+) adjustments follow its launch on Nov 4, 2026.
The addon stays free: no paid features, no in-game ads or donation prompts (Blizzard UI add-on policy).
Forever build title: "Goblin Advisor Forever" (title line in the Camelot toc only; same folder and code).

## Where we are
Phases 1 to 5 are built and pass the headless tests (348 checks). In-game verification is partial: see "Needs testing".

- Dashboard: current character, account gold total with data age, recommended activities (only your professions; unlearned recipes you have the skill for are flagged "learn the recipe first"), profession outlook with an explanation, materials you hold.
- Professions: recipes per profession, profit per craft, compare tool.
- Market: materials and crafting profit lists, search, click any row for an item or recipe detail view (price, source and age, history, reagents with quality tiers, full profit calculation), Back and Market home.
- Gathering: most valuable Mining, Herbalism and Skinning materials for your character.
- Gold Tracker: recorded gold and theoretical loot value kept apart; history per character; Reset history (click twice).
- Characters: gold with copper, professions, last seen, safe Delete (click twice, never the logged-in character), Materials view (who holds what, who should use it), Import / Export of manual prices and character summaries (previewed before applying).
- Data: Auction House scan (read only), manual prices (`/ga setprice`), bank snapshots (character and Warband), bag snapshots.
- Commands: `/ga help` lists them (`/ga chars`, `/ga bank`, `/ga find`, `/ga item`, `/ga scan debug`, `/ga status`, `/ga recipes`).

## Needs testing (in game)
- Gather tab and Gold Tracker: more use.
- `/ga bank` after opening the bank: bank tab ids are unverified. Bag and bank snapshots feed the Materials view.
- AH price unit: `/ga scan debug <itemID>`; toggle "scan price is per unit" in Settings if wrong. Every profit figure depends on this.
- Open each profession window once so recipes record their skill requirement.
- Other characters showing 0 gold: log into each once on 0.5.1, then check `/ga chars`.
- Import / Export text box with a long pasted line.

## Next up
1. Price accuracy: replace "lowest listing" with a sturdier market price (cost to buy the cheapest few units, or a middle value that ignores outliers); flag thin or gapped markets as low confidence; keep the "estimate" wording.
2. Professions tab: more recipes per page; simple columns (Name, Profit, Details link); Details opens the Market detail view (Back and Market home).
3. Add `.pkgmeta`, `.gitignore`, tests folder and this roadmap's housekeeping to the repo for CurseForge packaging.

## Ideas for later
- Ledger tab ("built-in spreadsheet"): record AH sales (mail invoices), purchases and crafts after install; real sale prices next to market estimates; raw sale vs crafting comparison; CSV copy button. Read only. Retail functions first, verify on Forever.
- Sell-through estimate by comparing listings between scans (labelled as an estimate; unverified that listings can be matched).
- Craft shopping list: pick a recipe and quantity; reagents minus what you own (bags and bank); what to buy.
- Selling prompts; price alerts (chat message when a tracked item crosses a target during a scan); profit sparklines in the item detail view.
- Profession leveling planner (separate free companion addon): cheapest or fewest-crafts plan between two skill levels, counting expected crafts from skill-up odds. Needs per-recipe color thresholds and where recipes are learned: wait for Forever launch data. Goblin Advisor only gets a Settings/credits line naming it.
- Guild bank / full item organizer (AO Items style) and AH notifications: deferred.

## Forever launch day
Send: `/ga status`, `/ga recipes`, `/ga scan debug <itemID>`, `/ga bank`. Likely differences: recipe data fields, AH listing format and price unit, bank layout and Warband bank, profession skill model, item category ids for gathering.

## Publishing (CurseForge)
BigWigs packager: `.pkgmeta` (package-as GoblinAdvisor, ignore tests and docs), a license (LICENSE is in the repo), project page text and screenshots, API token as a GitHub secret, tag releases (`v0.5.1`). Keep a changelog. Keep the addon free.

## Repo
GitHub: mikelee0093-prog/GoblinAdvisor. The repo root is the addon folder (`GoblinAdvisor.toc` at the top); keep the folder named `GoblinAdvisor` inside `Interface\AddOns`. Commits can be pushed from Claude sessions that have the repo; run `git pull` locally before committing.
