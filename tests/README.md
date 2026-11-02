# Tests

`run.lua` loads the addon's real Lua files in `.toc` order against a fake WoW client, fires events
and slash commands, and checks the results. It proves the logic runs without Lua errors. It cannot
show how the window looks or what the live game returns; those still need an in-game check.

Run from the repository root with a Lua interpreter: `lua tests/run.lua`
(the suite was last run through Python's `lupa` Lua 5.4 binding; plain `lua` is expected to work but is untested).
