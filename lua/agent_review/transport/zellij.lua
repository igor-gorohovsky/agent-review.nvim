local config = require("agent_review.config")

local M = {}

local function bracketed_paste(body)
  return "\27[200~" .. body .. "\27[201~"
end

local function run(args)
  local result = vim.system(args):wait()
  if result.code ~= 0 then
    return false, vim.trim(result.stderr or table.concat(args, " ") .. " failed")
  end
  return true
end

function M.is_available()
  return vim.fn.executable("zellij") == 1 and vim.env.ZELLIJ ~= nil
end

function M.send(body)
  if vim.fn.executable("zellij") ~= 1 then
    return false, "zellij executable not found"
  end
  if not vim.env.ZELLIJ then
    return false, "not running inside zellij"
  end

  local opts = config.options.transport or {}
  local direction = opts.focus_direction
  if direction and direction ~= false and direction ~= "" then
    local ok, err = run({ "zellij", "action", "move-focus", direction })
    if not ok then return false, "zellij move-focus failed: " .. err end
  end

  local ok, err = run({ "zellij", "action", "write-chars", bracketed_paste(body) })
  if not ok then return false, "zellij write-chars failed: " .. err end

  return true
end

return M
