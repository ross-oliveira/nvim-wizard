local M = {}
local groups = {
  NormalFloat = 'WizardFloat',
  FloatBorder = 'WizardFloatBorder',
  FloatTitle = 'WizardFloatTitle',
  FloatFooter = 'WizardFloatFooter',
}
function M.refresh()
  for source, target in pairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = source, link = false })
    hl.bg, hl.ctermbg, hl.reverse = nil, nil, nil
    vim.api.nvim_set_hl(0, target, hl)
  end
end
function M.transparent(win)
  M.refresh()
  vim.wo[win].winhighlight = table.concat({
    'Normal:WizardFloat', 'NormalNC:WizardFloat', 'NormalFloat:WizardFloat',
    'FloatBorder:WizardFloatBorder', 'FloatTitle:WizardFloatTitle',
    'FloatFooter:WizardFloatFooter', 'EndOfBuffer:WizardFloat',
  }, ',')
  vim.wo[win].fillchars = 'eob: '
end
return M
