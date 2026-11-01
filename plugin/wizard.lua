if vim.g.loaded_nvim_wizard then return end
vim.g.loaded_nvim_wizard = true
-- Lazy loading by command works even without explicit setup; presets are still required.
for _, name in ipairs({ 'WizardPrompt', 'WizardModels', 'WizardAccept', 'WizardCancel' }) do
  if vim.fn.exists(':' .. name) ~= 2 then
  vim.api.nvim_create_user_command(name, function()
    require('wizard').setup()
    vim.cmd(name)
  end, {})
  end
end
