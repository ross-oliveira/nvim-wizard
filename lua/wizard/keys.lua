-- Keep buffer-local overrides reversible, including a user's existing Esc mapping.
local M = { owned = {} }
local api = vim.api
local function raw(key) return api.nvim_replace_termcodes(key, true, true, true) end
local function lookup(buf, key)
  for _, map in ipairs(api.nvim_buf_get_keymap(buf, 'n')) do
    if raw(map.lhs) == raw(key) then return map end
  end
end
function M.set(buf, key, callback, desc)
  if not key or key == '' then return end
  M.owned[buf] = M.owned[buf] or {}
  if M.owned[buf][key] then return end
  M.owned[buf][key] = { previous = lookup(buf, key), desc = desc }
  vim.keymap.set('n', key, callback, { buffer = buf, desc = desc, silent = true })
end
function M.remove(buf, key)
  local saved = M.owned[buf] and M.owned[buf][key]
  if not saved then return end
  M.owned[buf][key] = nil
  if not api.nvim_buf_is_valid(buf) then return end
  local current = lookup(buf, key)
  if not current or current.desc ~= saved.desc then return end
  api.nvim_buf_del_keymap(buf, 'n', key)
  if saved.previous then
    saved.previous.buffer = 1
    api.nvim_buf_call(buf, function() vim.fn.mapset('n', false, saved.previous) end)
  end
end
function M.clear(buf)
  local buffers = buf and { buf } or vim.tbl_keys(M.owned)
  for _, b in ipairs(buffers) do
    for _, key in ipairs(vim.tbl_keys(M.owned[b] or {})) do M.remove(b, key) end
    M.owned[b] = nil
  end
end
return M
