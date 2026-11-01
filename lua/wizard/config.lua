local M = {}
local defaults = {
  presets = {}, defaults = { api = 'ollama' }, curl = 'curl',
  project_file = 'nvim-wizard.json', timeout_ms = 180000, strip_code_fences = true,
  keys = { prompt = '<CR>', models = '<S-CR>', prompt_fallback = '<leader>wp', models_fallback = '<leader>wm' },
}
local selections = {}
local function object(v, label)
  assert(type(v) == 'table' and (next(v) == nil or not vim.islist(v)), label .. ' must be an object')
end
function M.setup(opts)
  opts = opts or {}
  assert(opts.codex == nil and opts.cmd == nil and opts.output_format == nil,
    'Codex settings were removed. Use defaults/presets with api, base_url, model, and request instead.')
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts)
  M.options.presets = opts.presets or {}
  selections = {}
end
function M.name(p) return p.name or p.model end
function M.effective(ctx)
  local p = vim.tbl_deep_extend('force', vim.deepcopy(ctx.defaults), ctx.presets[ctx.index])
  assert(type(p.model) == 'string' and p.model ~= '', 'preset: model is required')
  assert(p.api == 'ollama' or p.api == 'openai' or p.api == 'responses', 'api must be ollama, openai, or responses')
  assert(type(p.base_url) == 'string' and p.base_url:match('^https?://[^/]+'), 'preset: HTTP(S) base_url is required')
  assert(not p.base_url:match('^https?://([^/]+)'):find('@', 1, true), 'Use headers/api_key_env instead of credentials in base_url')
  assert(not p.base_url:find('[\r\n?#]'), 'base_url must not include a query, fragment, or newline')
  assert(p.model_provider == nil and p.output_format == nil, 'Old Codex preset: replace model_provider with api and base_url')
  object(p.request or {}, 'request'); object(p.headers or {}, 'headers')
  assert(p.system_prompt == nil or type(p.system_prompt) == 'string', 'system_prompt must be a string')
  return p
end
function M.resolve(path)
  local o, project, project_path = M.options, {}, nil
  if o.project_file ~= false then
    local dir = vim.fs.dirname(path)
    while dir do
      local candidate = dir .. '/' .. o.project_file
      if vim.fn.filereadable(candidate) == 1 then
        project_path = candidate
        local ok, result = pcall(vim.json.decode, table.concat(vim.fn.readfile(candidate), '\n'))
        assert(ok, 'Invalid JSON in ' .. candidate .. ': ' .. tostring(result))
        object(result, candidate); project = result
        break
      end
      local parent = vim.fs.dirname(dir)
      if parent == dir then break end
      dir = parent
    end
  end
  assert(project.codex == nil, 'Old Codex project configuration: migrate codex to defaults with api, base_url, and request')
  object(project.defaults or {}, 'project defaults')
  local presets = project.presets or o.presets
  assert(type(presets) == 'table' and (next(presets) == nil or vim.islist(presets)), 'presets must be a list')
  assert(#presets > 0, 'No model presets configured. Add presets to setup() or nvim-wizard.json.')
  local ctx = { presets = presets, defaults = vim.tbl_deep_extend('force', vim.deepcopy(o.defaults), project.defaults or {}) }
  local names = {}
  for i, p in ipairs(presets) do
    object(p, 'preset ' .. i)
    ctx.index = i; M.effective(ctx)
    local name = M.name(p)
    assert(type(name) == 'string' and not names[name], 'preset names must be unique strings: ' .. tostring(name))
    names[name] = i
  end
  ctx.key = project_path or ('global:' .. vim.fn.getcwd())
  ctx.index = names[selections[ctx.key]] or 1
  return ctx
end
function M.select(ctx, index) selections[ctx.key] = M.name(ctx.presets[index]) end
M.setup()
return M
