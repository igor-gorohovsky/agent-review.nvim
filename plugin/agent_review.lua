if vim.g.loaded_agent_review_nvim == 1 then
  return
end
vim.g.loaded_agent_review_nvim = 1

-- Intentionally no side effects here.
-- Call require("agent_review").setup() from your config to define commands,
-- install keymaps/autocmds, and start the optional Neovim socket server.
