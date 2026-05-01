local M = {}

function M.send(body)
  vim.fn.setreg("+", body)
  return true, "Copied agent message to clipboard"
end

function M.check()
  return vim.fn.has("clipboard") == 1, "clipboard provider"
end

return M
