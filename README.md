# nvim-wizard

Single-file AI edits in Neovim, with direct HTTP requests to Ollama or compatible APIs. Works with lazy.nvim and LazyVim. Requires Neovim **0.10+** and **curl**. No Codex CLI, agent tools, or extra Neovim dependencies.

Open a prompt, describe a change, then review an editable side-by-side diff. The original stays fixed while you edit or refine the proposal. Accept saves the source file; discard leaves the original buffer and file untouched.

## LazyVim / lazy.nvim

Put this in `lua/plugins/wizard.lua`:

```lua
return {
  'xzxn099/nvim-wizard',
  main = 'wizard',
  event = { 'BufReadPost', 'BufNewFile' },
  cmd = { 'WizardPrompt', 'WizardModels', 'WizardAccept', 'WizardCancel' },
  keys = {
    { '<leader>wp', '<cmd>WizardPrompt<cr>', desc = 'Wizard: prompt' },
    { '<leader>wm', '<cmd>WizardModels<cr>', desc = 'Wizard: model' },
  },
  opts = {
    defaults = {
      api = 'ollama',
      base_url = 'http://ollama.workstation.local',
      request = { options = { temperature = 0, num_ctx = 16384 } },
    },
    presets = {
      { name = 'Small coder', model = 'qwen2.5-coder:0.5b' },
      { name = 'Coder 3B', model = 'qwen2.5-coder:3b' },
      { name = 'GPT OSS', model = 'gpt-oss:20b' },
    },
  },
}
```

For a local checkout, replace the repository string with `dir = '/mnt/host/nvim-wizard'`. Without lazy.nvim, call `require('wizard').setup({ ... })` after adding the plugin to your runtime path. Presets can be supplied entirely through project JSON instead of Lua.

## Workflow

| Key / command | Action |
| --- | --- |
| Enter in a normal file buffer | Open the bottom prompt |
| `<leader>wp` / `:WizardPrompt` | Open the prompt or refine a proposal |
| Enter in the prompt | Submit; Shift-Enter adds a newline if your terminal supports it |
| Esc in the prompt | Close the prompt; retain an existing review |
| Shift-Enter / `<leader>wm` / `:WizardModels` | Select a preset; initially the first is active |
| Enter in the review, normal mode / `:WizardAccept` | Accept the proposal and write the source file |
| Esc in the review, normal mode / `:WizardCancel` | Discard the review or cancel a running request |

Enter and Shift-Enter are buffer-local normal-mode mappings in named, writable file buffers. Help, terminals, quickfix and other plugin buffers keep their own keys. Your lazy.nvim spec must include the file events above so these mappings are ready when a file opens. Some terminals send Shift-Enter as plain Enter; use `<leader>wm` as the fallback in that case. In the prompt, Shift-Enter still adds a newline.

While manually editing the proposal, insert-mode Enter inserts a newline and Esc first returns to normal mode. A second Esc discards. Normal-mode Enter does nothing while a request is running; Esc in the source/review cancels it. Existing source-buffer Esc mappings are restored afterward. `<leader>wa`, `<leader>wx`, and `q` remain review aliases.

The selector immediately selects on a number key. With 10–99 presets use **01, 02, …, 10**; larger lists use the corresponding width. You can also move with `j`/`k` and press Enter.

Review opens in a separate tab: fixed original on the left, editable proposal on the right. Use normal diff navigation (`]c`, `[c`) and editing. Additional prompts receive the **latest proposal**, while the left side stays at the snapshot taken before the first prompt. `:write` in the proposal reminds you to accept explicitly. Closing the review tab discards it. One editing session is active at a time.

The snapshot includes unsaved buffer changes. Cancel preserves them; accept saves the entire proposal. Changes to the original source buffer or disk file during review block acceptance. Normal write hooks, such as format-on-save, still run when accepting.

## Per-project JSON

Add `nvim-wizard.json` to a project or ancestor of the file you edit. Discovery starts at the source file's directory; the nearest JSON wins, regardless of Neovim's working directory.

```json
{
  "defaults": {
    "api": "ollama",
    "base_url": "http://ollama.workstation.local",
    "request": {
      "options": { "temperature": 0, "num_ctx": 16384 }
    }
  },
  "presets": [
    { "name": "Coder 0.5B", "model": "qwen2.5-coder:0.5b" },
    { "name": "Coder 1.5B", "model": "qwen2.5-coder:1.5b" },
    { "name": "Coder 3B", "model": "qwen2.5-coder:3b" },
    { "name": "GPT OSS 20B", "model": "gpt-oss:20b" }
  ]
}
```

Project `defaults` merge over setup `defaults`. A preset merges over both. Project `presets` replace the global list, including an empty list; omit the field to keep the global list. Names must be unique. The selected name is remembered separately for each project during the Neovim session. Configuration is re-read when opening the prompt/selector and submitting.

Project JSON is trusted configuration: it chooses the endpoint receiving your file. Do not commit secrets. Use `api_key_env` for credentials. Disable discovery with `project_file = false`.

## HTTP backends

| `api` | `base_url` example | Default endpoint |
| --- | --- | --- |
| `ollama` (default) | `http://ollama.workstation.local` | `/api/chat` |
| `openai` | `https://your-provider.example/v1` | `/chat/completions` |
| `responses` | `https://your-provider.example/v1` | `/responses` |

These names identify **wire protocols**, not specific vendors. Strata or another service can use whichever protocol its endpoint implements. Native Ollama gives access to its `options`, `think`, and `keep_alive` fields. OpenAI-compatible services receive their own provider-specific request fields. No authentication or endpoint is inferred from a model name.

All calls are nonstreaming. The plugin expects native Ollama `message.content`, OpenAI Chat Completions `choices[0].message.content`, or Responses `output[].content[].text`. Thinking/reasoning fields are not inserted into the source. Reported token-limit truncation is rejected. Support for a protocol does not imply every server implements every optional field.

```lua
presets = {
  {
    name = 'Ollama coder',
    api = 'ollama',
    base_url = 'http://ollama.workstation.local',
    model = 'qwen2.5-coder:3b',
    request = { options = { temperature = 0, num_ctx = 16384, num_predict = 4096 } },
  },
  {
    name = 'Another provider',
    api = 'openai',
    base_url = 'https://your-provider.example/v1',
    model = 'your-model',
    api_key_env = 'MY_PROVIDER_KEY',
    headers = { ['X-Custom-Header'] = 'value' },
    request = { temperature = 0, max_tokens = 4096 },
  },
}
```

`request` contains the actual API body fields. Keep shared defaults appropriate to all presets: Ollama's `options` object is not an OpenAI Chat Completions option. The plugin always sets model, messages/input, and `stream = false`; it removes tool definitions and structured-output fields. Responses requests force `store = false`. `path` can override the default endpoint path. Headers and an optional bearer token read from `api_key_env` are supported. An unset named credential variable is an error.

Optional `system_prompt` replaces the built-in short file-editing instruction. The user message contains the basename, the entire current buffer/proposal in a fenced block, and the requested change **last**. No conversation history, other files, repository instructions, skills, tools, or filesystem access are supplied.

## Plugin options

```lua
require('wizard').setup({
  presets = {},
  defaults = { api = 'ollama' }, -- shared preset fields; base_url must be supplied
  curl = 'curl',                -- executable path, not a shell command
  timeout_ms = 180000,
  project_file = 'nvim-wizard.json', -- filename or false
  strip_code_fences = true,
  keys = {
    prompt = '<CR>', models = '<S-CR>', -- normal file buffers only
    prompt_fallback = '<leader>wp', models_fallback = '<leader>wm',
  }, -- false disables an individual binding
})
```

A single enclosing Markdown fence is removed from code-file responses. Markdown files and files already containing literal outer fences retain them; disable unwrapping with `strip_code_fences = false`. Incomplete/multiple blocks and recognizable tool-call responses for code files are rejected. Models can still produce incorrect code or prose; inspect the diff. Binary files are unsupported. Intended for UTF-8 text with LF or CRLF line endings.

Requests use curl asynchronously, with the body on stdin and headers in a private temporary file removed on completion/cancellation. Prompts and credentials are not shell-interpolated or placed in command arguments. User curl configuration is disabled, redirects are not followed, and requests have a timeout. Standard network/proxy environment settings apply. The plugin has no analytics, telemetry exporters, catalog sync, background model discovery, or requests to any service beyond the configured endpoint. Provider logging is controlled by the provider itself.

## Migrating from the Codex version

Codex CLI configuration no longer applies. Old `codex`, `cmd`, `model_provider`, and `output_format` settings produce a migration error instead of being silently reused.

- Replace `codex` with shared `defaults`, or put fields in each preset.
- Replace `model_provider` / `model_providers` with `api` and `base_url`.
- For native Ollama, use the server root URL, **without `/v1`**, and `api = 'ollama'`.
- Move `model_context_window` to `request.options.num_ctx` for Ollama.
- Put generation options in `request` according to that API's documentation.
- Remove CLI authentication, sandbox, reasoning, telemetry, and web-search CLI flags. This is a single-file text request, with no tool or search execution.

The machine's `~/tmp/nvim-wizard.json` and the included example have been migrated. Their previous JSON files are saved with `.before-http` suffixes.

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
LAZY_PATH=/path/to/lazy.nvim nvim --headless -u NONE -l tests/lazy.lua
```

Requires Python 3 for the local HTTP fixture. Tests exercise real curl requests against a local HTTP server for all three protocols, plus configuration discovery, selector mappings, prompt data, request options, authentication, fixed output contract, HTTP errors, invalid JSON, truncation, redirects, timeout/cancellation, fence cleanup, editable review, refinement, saving/discarding, conflicts, CRLF, unsaved buffers, failed writes, and review cleanup. No API key, Codex install, external model, or paid request is needed for the automated suite. CI runs Neovim 0.10.4 and 0.11.5.

API references: [Ollama chat](https://docs.ollama.com/api/chat), [Ollama OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).

MIT license.
