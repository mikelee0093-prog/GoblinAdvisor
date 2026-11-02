# Goblin Advisor - roadmap

Current version: 0.8.0 (Ledger sell-through, Lists tab with shopping list and watch list; all new mail/AH behaviour UNVERIFIED in game) (Retail interface 120105; Forever interface 16001 via `GoblinAdvisor_Camelot.toc`).
Testing happens on Retail now. Forever (Classic+) adjustments follow its launch on Nov 4, 2026.
The addon stays free: no paid features, no in-game ads or donation prompts (Blizzard UI add-on policy).
Forever build title: "Goblin Advisor Forever" (title line in the Camelot toc only; same folder and code).

## Where we are
Phases 1 to 5 are built and pass the headless tests (370 checks). In-game verification is partial: see "Needs testing".

- Dashboard: current character, account gold total with data age, recommended activities (only your professions; unlearned recipes you have the skill for are flagged "learn the recipe first"), profession outlook with an explanation, materials you hold.
- Professions: summary plus a recipe table (Name, Profit per craft, Details >); clicking a recipe opens the Market detail view and Back returns here; compare tool.
- Market: materials and crafting profit lists, search, click any row for an item or recipe detail view (price, source and age, history, reagents with quality tiers, full profit calculation), Back and Market home.
- Gathering: most valuable Mining, Herbalism and Skinning materials for your character.
- Gold Tracker: recorded gold and theoretical loot value kept apart; history per character; Reset history (click twice).
- Characters: gold with copper, professions, last seen, safe Delete (click twice, never the logged-in character), Materials view (who holds what, who should use it), Import / Export of manual prices and character summaries (previewed before applying).
- Market price: average of the cheapest ~15% of listed units, ignoring low-ball listings; thin markets (few units or listings) are flagged with an orange * and warnings.
- Data: Auction House scan (read only), manual prices (`/ga setprice`), bank snapshots (character and Warband), bag snapshots.
- Commands: `/ga help` lists them (`/ga chars`, `/ga bank`, `/ga find`, `/ga item`, `/ga scan debug`, `/ga status`, `/ga recipes`).

## Needs testing (in game)
- New market price and thin-market flags: compare a few items with the Auction House (`/ga scan debug <itemID>`).
- Professions tab: recipe table layout and the Details link / Back behaviour.
- Gather tab and Gold Tracker: more use.
- `/ga bank` after opening the bank: bank tab ids are unverified. Bag and bank snapshots feed the Materials view.
- AH price unit: `/ga scan debug <itemID>`; toggle "scan price is per unit" in Settings if wrong. Every profit figure depends on this.
- Open each profession window once so recipes record their skill requirement.
- Other characters showing 0 gold: log into each once on 0.5.1, then check `/ga chars`.
- Import / Export text box with a long pasted line.

## Next up
1. Verify the Ledger in game (sell-through too: expired/cancelled mail subjects and `GetInboxItem` order are unverified): open the mailbox after AH activity, run `/ga ledger debug`, confirm invoices are read and buyer invoices exist for commodity buys.
2. Check the new market price against real listings in game (`/ga scan debug <itemID>` now shows cheapest listing, units and listings).
3. Publish to CurseForge: project page, screenshots, API token as a GitHub secret, tag a release.

## Ideas for later
- DONE in 0.7.0 (mail sales/purchases, by item, transactions, CSV; crafts not yet recorded): Ledger tab ("built-in spreadsheet"): record AH sales (mail invoices), purchases and crafts after install; real sale prices next to market estimates; raw sale vs crafting comparison; CSV copy button. Read only. Retail functions first, verify on Forever.
- DONE in 0.8.0: real sell-through from expired/cancelled mail (Ledger). Scan-to-scan listing comparison dropped.
- DONE in 0.8.0: Craft shopping list (Lists tab, `/ga shop`, "Add to shopping list" in Market recipe view). Later: split "own" by character, bank-only vs bags.
- Selling prompts; price alerts DONE in 0.8.0 (Watch list: Lists tab, `/ga watch`, chat message after a scan; watched items are added to scans); profit sparklines in the item detail view.
- Profession leveling planner (separate free companion addon): cheapest or fewest-crafts plan between two skill levels, counting expected crafts from skill-up odds. Needs per-recipe color thresholds and where recipes are learned: wait for Forever launch data. Goblin Advisor only gets a Settings/credits line naming it.
- Guild bank / full item organizer (AO Items style) and AH notifications: deferred.

## Forever launch day
Send: `/ga status`, `/ga recipes`, `/ga scan debug <itemID>`, `/ga bank`. Likely differences: recipe data fields, AH listing format and price unit, bank layout and Warband bank, profession skill model, item category ids for gathering.

## Publishing (CurseForge)
BigWigs packager: `.pkgmeta` is in the repo (package-as GoblinAdvisor, ignores tests and notes), a license (LICENSE is in the repo), project page text and screenshots, API token as a GitHub secret, tag releases (`v0.5.1`). Keep a changelog. Keep the addon free.

## Repo
GitHub: mikelee0093-prog/GoblinAdvisor. The repo root is the addon folder (`GoblinAdvisor.toc` at the top); keep the folder named `GoblinAdvisor` inside `Interface\AddOns`. Commits can be pushed from Claude sessions that have the repo; run `git pull` locally before committing.
