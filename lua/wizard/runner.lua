local M = {}
local instructions = 'Apply the requested change to the supplied source file. Preserve all unrelated code. '
  .. 'Respect the exact spelling and letter case requested. Preserve existing whitespace unless asked to change it. '
  .. 'Return the complete updated file contents only, without explanations or Markdown fences.'
function M.build(ctx, content, filename, prompt)
  local p = require('wizard.config').effective(ctx)
  local longest = 2
  for ticks in content:gmatch('`+') do longest = math.max(longest, #ticks) end
  local fence = string.rep('`', longest + 1)
  local user = 'File: ' .. vim.fn.fnamemodify(filename, ':t') .. '\n\n'
    .. fence .. '\n' .. content .. (content:sub(-1) == '\n' and '' or '\n') .. fence .. '\n\nRequested change:\n' .. prompt
  local messages = {
    { role = 'system', content = p.system_prompt or instructions },
    { role = 'user', content = user },
  }
  local body = vim.deepcopy(p.request or {})
  -- The plugin owns the context and output contract. No tools or extra messages.
  body.model, body.stream = p.model, false
  body.tools, body.tool_choice, body.parallel_tool_calls = nil, nil, nil
  body.format, body.response_format, body.text = nil, nil, nil
  body.messages, body.input, body.instructions = nil, nil, nil
  if p.api == 'responses' then body.input, body.store = messages, false
  else body.messages = messages end
  local paths = { ollama = '/api/chat', openai = '/chat/completions', responses = '/responses' }
  local path = p.path or paths[p.api]
  assert(type(path) == 'string' and path:sub(1, 1) == '/' and not path:find('[\r\n?#]'), 'path must be an absolute URL path')
  local headers = { 'Content-Type: application/json', 'Accept: application/json' }
  local h = vim.deepcopy(p.headers or {})
  if p.api_key_env then
    assert(type(p.api_key_env) == 'string', 'api_key_env must be a string')
    local key = vim.env[p.api_key_env]
    assert(key and key ~= '', 'Missing environment variable: ' .. p.api_key_env)
    h.Authorization = 'Bearer ' .. key
  end
  for k, v in pairs(h) do
    assert(type(k) == 'string' and k:match('^[%w_-]+$') and type(v) == 'string' and not v:find('[\r\n]'), 'Invalid HTTP header')
    headers[#headers + 1] = k .. ': ' .. v
  end
  return { url = p.base_url:gsub('/+$', '') .. path, body = body, headers = headers, api = p.api }
end
function M.decode(api, data)
  if type(data) ~= 'table' then return nil, 'Server returned a non-object JSON response' end
  if data.error then
    local e = type(data.error) == 'table' and data.error.message or data.error
    return nil, 'Server error: ' .. tostring(e)
  end
  if api == 'responses' then
    if data.status == 'incomplete' then return nil, 'Model output was truncated; increase the output token limit' end
    local parts = {}
    for _, item in ipairs(data.output or {}) do
      if item.type == 'function_call' then return nil, 'Model returned a tool call instead of file contents' end
      if item.type == 'message' then
        for _, part in ipairs(item.content or {}) do
          if part.type == 'refusal' then return nil, 'Model refused the editing request' end
          if part.type == 'output_text' and type(part.text) == 'string' then parts[#parts + 1] = part.text end
        end
      end
    end
    if #parts == 0 then return nil, 'Server response has no file content' end
    return table.concat(parts)
  end
  local choice = api == 'openai' and (data.choices or {})[1] or nil
  if data.done_reason == 'length' or (choice and choice.finish_reason == 'length') then
    return nil, 'Model output was truncated; increase the output token limit'
  end
  local message = choice and choice.message or (api == 'ollama' and data.message)
  if type(message) ~= 'table' then return nil, 'Server response has no assistant message' end
  if message.tool_calls and next(message.tool_calls) then return nil, 'Model returned a tool call instead of file contents' end
  if type(message.content) ~= 'string' then return nil, 'Server response has no text content' end
  if message.content == '' and message.thinking and message.thinking ~= '' then return nil, 'Model returned reasoning without file contents' end
  return message.content
end
function M.run(ctx, content, filename, prompt, callback)
  local config = require('wizard.config')
  local req = M.build(ctx, content, filename, prompt)
  local timeout = config.options.timeout_ms
  assert(type(timeout) == 'number' and timeout > 0, 'timeout_ms must be a positive number')
  local payload = vim.json.encode(req.body)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p', 448)
  local header_path = root .. '/headers'
  vim.fn.writefile(req.headers, header_path)
  vim.uv.fs_chmod(header_path, 384)
  local argv = { config.options.curl, '--disable', '--silent', '--show-error', '--request', 'POST',
    '--max-time', tostring(timeout / 1000), '--header', '@' .. header_path,
    '--data-binary', '@-', '--write-out', '\n%{http_code}', '--url', req.url }
  local ok, process = pcall(vim.system, argv, { stdin = payload, text = false, timeout = timeout + 1000 }, function(result)
    vim.schedule(function()
      vim.fn.delete(root, 'rf')
      local replacement, err
      if result.code ~= 0 then
        err = 'HTTP request failed (' .. result.code .. '): ' .. (result.stderr or ''):sub(-2000)
      else
        local raw, status = (result.stdout or ''):match('^(.*)\n(%d%d%d)$')
        local valid, data = pcall(vim.json.decode, raw or '')
        if not status then err = 'curl did not return an HTTP status'
        elseif tonumber(status) < 200 or tonumber(status) >= 300 then
          local detail = valid and type(data) == 'table' and data.error
          if type(detail) == 'table' then detail = detail.message end
          err = 'HTTP ' .. status .. (detail and (': ' .. tostring(detail)) or '')
        elseif not valid then err = 'Server returned invalid JSON'
        else
          replacement, err = M.decode(req.api, data)
          if replacement then replacement, err = require('wizard.output').normalize(replacement, filename, content, config.options.strip_code_fences) end
        end
      end
      callback(err, replacement)
    end)
  end)
  if not ok then vim.fn.delete(root, 'rf'); error(process) end
  return { kill = function(_, signal) process:kill(signal); vim.fn.delete(root, 'rf') end }
end
return M
