local M = {}
local api = vim.api
local config = require('wizard.config')
local bindings = require('wizard.keys')
local session, selector
local function notify(msg, level) vim.notify('nvim-wizard: ' .. msg, level or vim.log.levels.INFO) end
local function guard(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then notify(tostring(err), vim.log.levels.ERROR) end
  end
end
local function disk(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local text = f:read('*a'); f:close(); return text
end
local function text(buf)
  local sep = vim.bo[buf].fileformat == 'dos' and '\r\n' or '\n'
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), sep) .. (vim.bo[buf].endofline and sep or '')
end
local function put(buf, value)
  value = value:gsub('\r\n', '\n')
  local eol = value:sub(-1) == '\n'
  if eol then value = value:sub(1, -2) end
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(value, '\n', { plain = true }))
  vim.bo[buf].endofline = eol
  vim.bo[buf].fixendofline = false
end
local function close_prompt(s)
  if s.prompt_win and api.nvim_win_is_valid(s.prompt_win) then api.nvim_win_close(s.prompt_win, true) end
  s.prompt_win = nil
  vim.cmd('stopinsert')
end
function M.cancel()
  local s = session
  if not s then return end
  session = nil
  bindings.remove(s.source_buf, '<Esc>')
  if s.process then s.process:kill(15) end
  close_prompt(s)
  if s.group then pcall(api.nvim_del_augroup_by_id, s.group) end
  if s.review_tab and api.nvim_tabpage_is_valid(s.review_tab) then
    local n = api.nvim_tabpage_get_number(s.review_tab)
    pcall(vim.cmd, 'tabclose! ' .. n)
  end
  for _, buf in ipairs({ s.original_buf or -1, s.preview_buf or -1 }) do
    if api.nvim_buf_is_valid(buf) then pcall(api.nvim_buf_delete, buf, { force = true }) end
  end
  if api.nvim_tabpage_is_valid(s.source_tab) then api.nvim_set_current_tabpage(s.source_tab) end
  if api.nvim_win_is_valid(s.source_win) then api.nvim_set_current_win(s.source_win) end
end
function M.accept()
  local s = session
  if not s or not s.preview_buf then return notify('No proposal to accept', vim.log.levels.WARN) end
  if s.process then return notify('Wait for model to finish', vim.log.levels.WARN) end
  if not api.nvim_buf_is_valid(s.source_buf) then return notify('Source buffer was deleted; cancel the review', vim.log.levels.ERROR) end
  if text(s.source_buf) ~= s.original or api.nvim_buf_get_name(s.source_buf) ~= s.path then
    return notify('Source buffer changed during review; refusing to overwrite it', vim.log.levels.ERROR)
  end
  if disk(s.path) ~= s.disk then return notify('File changed on disk during review; refusing to overwrite it', vim.log.levels.ERROR) end
  local replacement = text(s.preview_buf)
  put(s.source_buf, replacement)
  local ok, err = pcall(api.nvim_buf_call, s.source_buf, function() vim.cmd('write') end)
  if not ok then
    put(s.source_buf, s.original)
    vim.bo[s.source_buf].modified = s.modified
    return notify('Write failed: ' .. tostring(err), vim.log.levels.ERROR)
  end
  M.cancel()
  notify('Accepted and saved ' .. vim.fn.fnamemodify(s.path, ':t'))
end
local function review(s, replacement)
  if not s.preview_buf then
    vim.cmd('tabnew')
    s.review_tab = api.nvim_get_current_tabpage()
    s.original_buf = api.nvim_get_current_buf()
    vim.bo[s.original_buf].buftype = 'nofile'
    vim.bo[s.original_buf].bufhidden = 'wipe'
    vim.bo[s.original_buf].swapfile = false
    put(s.original_buf, s.original)
    vim.bo[s.original_buf].filetype = s.filetype
    vim.bo[s.original_buf].modifiable = false
    api.nvim_buf_set_name(s.original_buf, 'wizard://original/' .. s.id .. '/' .. vim.fn.fnamemodify(s.path, ':t'))
    vim.cmd('diffthis')
    vim.cmd('rightbelow vnew')
    s.preview_buf = api.nvim_get_current_buf()
    vim.bo[s.preview_buf].buftype = 'acwrite'
    vim.bo[s.preview_buf].bufhidden = 'hide'
    vim.bo[s.preview_buf].swapfile = false
    vim.bo[s.preview_buf].filetype = s.filetype
    vim.bo[s.preview_buf].fileformat = s.fileformat
    api.nvim_buf_set_name(s.preview_buf, 'wizard://proposal/' .. s.id .. '/' .. vim.fn.fnamemodify(s.path, ':t'))
    api.nvim_create_autocmd('BufWriteCmd', { buffer = s.preview_buf, callback = function()
      notify('Press Enter in normal mode or :WizardAccept to accept and write')
    end })
    for _, buf in ipairs({ s.original_buf, s.preview_buf }) do
      vim.keymap.set('n', '<CR>', guard(function() if not s.process then M.accept() end end), { buffer = buf, desc = 'Wizard: accept and save' })
      vim.keymap.set('n', '<Esc>', M.cancel, { buffer = buf, desc = 'Wizard: discard' })
      if config.options.keys.models then
        vim.keymap.set('n', config.options.keys.models, guard(M.models), { buffer = buf, desc = 'Wizard: select preset' })
      end
      vim.keymap.set('n', '<leader>wa', guard(M.accept), { buffer = buf, desc = 'Wizard: accept and save' })
      vim.keymap.set('n', '<leader>wx', M.cancel, { buffer = buf, desc = 'Wizard: discard' })
      vim.keymap.set('n', 'q', M.cancel, { buffer = buf, desc = 'Wizard: discard' })
    end
    api.nvim_create_autocmd('TabClosed', { callback = function()
      vim.schedule(function()
        if session == s and not api.nvim_tabpage_is_valid(s.review_tab) then M.cancel() end
      end)
    end, once = false, group = s.group })
    vim.cmd('diffthis')
  end
  put(s.preview_buf, replacement)
  api.nvim_set_current_tabpage(s.review_tab)
  for _, win in ipairs(api.nvim_tabpage_list_wins(s.review_tab)) do
    if api.nvim_win_get_buf(win) == s.preview_buf then api.nvim_set_current_win(win); break end
  end
  vim.cmd('diffupdate')
  notify('Review/edit the proposal. Enter accepts, Esc discards, <leader>wp refines (normal mode).')
end
function M.submit(prompt)
  local s = session
  if not s or s.process then return end
  if not prompt or prompt:match('^%s*$') then return end
  close_prompt(s)
  local content = s.preview_buf and text(s.preview_buf) or s.original
  local ctx = config.resolve(s.path)
  local started, process = pcall(require('wizard.runner').run, ctx, content, s.path, prompt, function(err, replacement)
    if session ~= s then return end
    s.process = nil
    bindings.remove(s.source_buf, '<Esc>')
    if err then
      notify(err, vim.log.levels.ERROR)
      if not s.preview_buf then M.cancel() end
      return
    end
    local ok, failure = pcall(review, s, replacement)
    if not ok then notify(tostring(failure), vim.log.levels.ERROR); M.cancel() end
  end)
  if not started then
    notify(tostring(process), vim.log.levels.ERROR)
    if not s.preview_buf then M.cancel() end
    return
  end
  s.process = process
  bindings.set(s.source_buf, '<Esc>', M.cancel, 'Wizard: cancel request')
  notify('Running model with ' .. config.name(ctx.presets[ctx.index]) .. '… (Esc to stop)')
end
function M.prompt()
  if session and session.process then return notify('A request is running; :WizardCancel to stop', vim.log.levels.WARN) end
  if session and session.prompt_win and api.nvim_win_is_valid(session.prompt_win) then
    api.nvim_set_current_win(session.prompt_win); vim.cmd('startinsert'); return
  end
  local s = session
  if not s then
    local buf = api.nvim_get_current_buf()
    assert(vim.bo[buf].buftype == '' and vim.bo[buf].modifiable and not vim.bo[buf].readonly, 'Open a writable file buffer first')
    local path = api.nvim_buf_get_name(buf)
    assert(path ~= '', 'Save/name the current file first')
    config.resolve(path)
    s = { id = tostring(vim.uv.hrtime()), source_buf = buf, source_win = api.nvim_get_current_win(),
      source_tab = api.nvim_get_current_tabpage(), path = path, original = text(buf), disk = disk(path),
      modified = vim.bo[buf].modified, filetype = vim.bo[buf].filetype, fileformat = vim.bo[buf].fileformat }
    s.group = api.nvim_create_augroup('WizardReview', { clear = true })
    session = s
  end
  local ctx = config.resolve(s.path)
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local width = math.max(1, vim.o.columns - 4)
  s.prompt_win = api.nvim_open_win(buf, true, { relative = 'editor', row = math.max(0, vim.o.lines - 6), col = 1,
    width = width, height = 3, style = 'minimal', border = 'rounded',
    title = ' Wizard · ' .. config.name(ctx.presets[ctx.index]) .. ' · Enter submit / Esc close ', title_pos = 'left' })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', function()
    close_prompt(s)
    if not s.preview_buf then session = nil end
  end, { buffer = buf })
  vim.keymap.set({ 'i', 'n' }, '<CR>', guard(function()
    local prompt = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    M.submit(prompt)
  end), { buffer = buf })
  vim.keymap.set('i', '<S-CR>', '<C-o>o', { buffer = buf })
  vim.cmd('startinsert')
end
function M.models()
  vim.cmd('stopinsert')
  local path = session and session.path or api.nvim_buf_get_name(0)
  assert(path ~= '', 'Open a named file first')
  local ctx = config.resolve(path)
  if selector and api.nvim_win_is_valid(selector) then api.nvim_win_close(selector, true) end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local lines, digits = {}, tostring(#ctx.presets):len()
  for i, p in ipairs(ctx.presets) do
    lines[i] = string.format('%0' .. digits .. 'd  %s%s', i, config.name(p), i == ctx.index and '  ●' or '')
  end
  local width = math.min(vim.o.columns - 4, math.max(30, unpack(vim.tbl_map(vim.fn.strdisplaywidth, lines))))
  selector = api.nvim_open_win(buf, true, { relative = 'editor', row = 2, col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width, height = math.min(#lines, math.max(1, vim.o.lines - 6)), style = 'minimal', border = 'rounded',
    title = ' Wizard presets · ' .. digits .. ' digit selection ' })
  local win = selector
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local function choose(i)
    config.select(ctx, i)
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    notify('Selected ' .. config.name(ctx.presets[i]))
  end
  for i = 1, #ctx.presets do
    vim.keymap.set('n', string.format('%0' .. digits .. 'd', i), function() choose(i) end, { buffer = buf, nowait = true })
  end
  vim.keymap.set('n', '<CR>', function() choose(api.nvim_win_get_cursor(win)[1]) end, { buffer = buf })
  vim.keymap.set('n', '<Esc>', function() api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set('n', 'q', function() api.nvim_win_close(win, true) end, { buffer = buf })
end
function M.setup(opts)
  assert(vim.fn.has('nvim-0.10') == 1, 'nvim-wizard requires Neovim 0.10+')
  local lifecycle = api.nvim_create_augroup('WizardLifecycle', { clear = true })
  if session then M.cancel() end
  bindings.clear()
  config.setup(opts)
  api.nvim_create_autocmd('VimLeavePre', { group = lifecycle, callback = M.cancel })
  local function attach(buf)
    if not api.nvim_buf_is_valid(buf) then return end
    local eligible = vim.bo[buf].buftype == '' and vim.bo[buf].modifiable
      and not vim.bo[buf].readonly and api.nvim_buf_get_name(buf) ~= ''
    if not eligible then bindings.clear(buf); return end
    bindings.set(buf, config.options.keys.prompt, guard(function()
      if not (session and session.process) then M.prompt() end
    end), 'Wizard: edit current file')
    bindings.set(buf, config.options.keys.models, guard(M.models), 'Wizard: select preset')
  end
  api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'BufFilePost' }, { group = lifecycle,
    callback = function(args) attach(args.buf) end })
  api.nvim_create_autocmd('OptionSet', { group = lifecycle, pattern = { 'buftype', 'modifiable', 'readonly' },
    callback = function() attach(api.nvim_get_current_buf()) end })
  api.nvim_create_autocmd('BufWipeout', { group = lifecycle,
    callback = function(args) bindings.owned[args.buf] = nil end })
  for _, buf in ipairs(api.nvim_list_bufs()) do attach(buf) end
  for _, item in ipairs({ { 'prompt_fallback', M.prompt, 'Wizard: edit current file' }, { 'models_fallback', M.models, 'Wizard: select preset' } }) do
    local key = config.options.keys[item[1]]
    if key and key ~= '' then vim.keymap.set('n', key, guard(item[2]), { desc = item[3] }) end
  end
  for name, fn in pairs({ WizardPrompt = M.prompt, WizardModels = M.models, WizardAccept = M.accept, WizardCancel = M.cancel }) do
    api.nvim_create_user_command(name, guard(fn), { force = true })
  end
end
function M.status() return session end
return M
