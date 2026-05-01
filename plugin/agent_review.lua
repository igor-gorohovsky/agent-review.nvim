if vim.g.loaded_agent_review_nvim == 1 then
  return
end
vim.g.loaded_agent_review_nvim = 1

-- Define user commands without starting the socket server or installing keymaps.
-- Call require("agent_review").setup() from your config to enable the plugin.
require("agent_review")._define_commands()
