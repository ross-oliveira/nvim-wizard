local M = {}
local function tool_call(value)
  if type(value) ~= 'table' then return false end
  if type(value.name) == 'string' and value.arguments ~= nil then return true end
  if value.type == 'function_call' or value.tool_calls ~= nil then return true end
  if type(value['function']) == 'table' and value['function'].name then return true end
  if vim.islist(value) and #value > 0 then return tool_call(value[1]) end
  return false
end
function M.normalize(value, filename, original, strip_fences)
  if value:find('\0', 1, true) then return nil, 'Model returned binary content' end
  -- Preserve literal fences in Markdown and in files already containing an outer fence.
  local ext = filename:match('%.([^./]+)$') or ''
  local markdown = ({ md = true, markdown = true, mdx = true, qmd = true, rmd = true })[ext:lower()]
  if strip_fences ~= false and not markdown and not original:match('^%s*```') and not original:match('^%s*~~~') then
    local lines = vim.split(value, '\n', { plain = true })
    local first, last = 1, #lines
    while first <= last and lines[first]:match('^%s*$') do first = first + 1 end
    while last >= first and lines[last]:match('^%s*$') do last = last - 1 end
    local opening = (lines[first] or ''):match('^%s*(```+)[^`]*$')
      or (lines[first] or ''):match('^%s*(~~~+)[^~]*$')
    if opening then
      local closing
      for i = first + 1, last do
        local fence = lines[i]:match('^%s*([`~]+)%s*$')
        if fence and #fence >= #opening and fence == opening:sub(1, 1):rep(#fence) then closing = i; break end
      end
      if closing ~= last then return nil, 'Model returned incomplete or multiple Markdown blocks instead of one file' end
      local body = {}
      for i = first + 1, last - 1 do body[#body + 1] = lines[i] end
      value = table.concat(body, '\n')
      if #body > 0 then value = value .. '\n' end
    end
  end
  local ok, decoded = pcall(vim.json.decode, value)
  local json_file = ext:lower():match('^json') ~= nil
  if ok and tool_call(decoded) and not json_file and value ~= original then
    return nil, 'Model returned a tool call instead of file contents. Retry the prompt or select a larger model.'
  end
  if value:match('^%s*<tool_call>') then
    return nil, 'Model returned a tool call instead of file contents. Retry the prompt or select a larger model.'
  end
  return value
end
return M
