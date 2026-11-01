-- Optional smoke test: LAZY_PATH=/path/to/lazy.nvim nvim --headless -u NONE -l tests/lazy.lua
local root=vim.fn.tempname()
vim.fn.mkdir(root,'p')
assert(vim.env.LAZY_PATH,'Set LAZY_PATH to a lazy.nvim checkout')
vim.opt.rtp:prepend(vim.env.LAZY_PATH)
vim.g.mapleader=' '
vim.go.loadplugins=true
require('lazy').setup({{
  dir=vim.fn.getcwd(),name='nvim-wizard',main='wizard',
  event={'BufReadPost','BufNewFile'},
  cmd={'WizardPrompt','WizardModels','WizardAccept','WizardCancel'},
  keys={{'<leader>wp','<cmd>WizardPrompt<cr>'},{'<leader>wm','<cmd>WizardModels<cr>'}},
  opts={defaults={base_url='http://localhost'},presets={{model='lazy-smoke'}}},
}}, {
  root=root..'/plugins',lockfile=root..'/lock.json',
  install={missing=false},checker={enabled=false},change_detection={enabled=false},
  readme={enabled=false},performance={rtp={reset=false}},
})
vim.cmd('file '..vim.fn.fnameescape(root..'/test.lua'))
assert(not package.loaded.wizard,'plugin should initially be lazy')
if vim.env.WIZARD_TEST_EVENTS == '1' then
  vim.api.nvim_exec_autocmds('BufReadPost',{buffer=0})
  assert(package.loaded.wizard,'file event should load plugin')
  assert(vim.fn.maparg('<CR>','n',false,true).buffer==1,'file event should attach Enter')
  assert(vim.fn.maparg('<S-CR>','n',false,true).buffer==1,'file event should attach Shift Enter')
end
vim.cmd('WizardModels')
assert(package.loaded.wizard,'command should load plugin')
assert(vim.api.nvim_buf_get_lines(0,0,1,false)[1]:find('lazy%-smoke'),'configured preset should appear')
vim.cmd('close')
vim.cmd('WizardPrompt')
vim.cmd('stopinsert')
assert(require('wizard').status().prompt_win,'prompt should be open')
vim.cmd('WizardCancel')
assert(not require('wizard').status(),'cancel should clean session')
print('PASS: lazy.nvim command loading and opts setup')
vim.fn.delete(root,'rf')
vim.cmd('qa!')
