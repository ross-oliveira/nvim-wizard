# Manual playground

Run `nvim /mnt/host/nvim-wizard/examples/ollama-small/main.lua`.

The installed Neovim configuration loads this checkout through lazy.nvim.
Press Enter in normal mode and try:

> Change the greeting string from "hello" to "hello from nvim-wizard". Keep everything else unchanged.

Enter submits. In the review, normal-mode Enter accepts/saves and Esc discards.
While editing the proposal in insert mode, Esc leaves insert mode first.
Shift-Enter opens the preset selector; press 1 to select. Space w m is the
fallback for terminals that cannot distinguish Shift-Enter. Space w p refines.
Esc closes the prompt or cancels a running request in its source/review.

The JSON selects qwen3:0.6b on http://ollama.workstation.local with no explicit
port. Requests go directly to /api/chat. No Codex CLI is used. This small model
is for simple edits: inspect the result before accepting.
