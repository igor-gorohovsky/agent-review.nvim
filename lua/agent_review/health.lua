local config = require("agent_review.config")

local M = {}

local function health()
  return vim.health
end

local function start(name)
  local h = health()
  if h.start then h.start(name) else h.report_start(name) end
end

local function ok(msg)
  local h = health()
  if h.ok then h.ok(msg) else h.report_ok(msg) end
end

local function warn(msg)
  local h = health()
  if h.warn then h.warn(msg) else h.report_warn(msg) end
end

local function error(msg)
  local h = health()
  if h.error then h.error(msg) else h.report_error(msg) end
end

local function info(msg)
  local h = health()
  if h.info then h.info(msg) else h.report_info(msg) end
end

function M.check()
  start("agent-review.nvim")

  ok("agent_review module is available")

  local socket = config.socket_path()
  if socket then
    info("Socket: " .. socket)
    if vim.uv.fs_stat(socket) then
      ok("Socket file exists")
    else
      warn("Socket file does not exist yet. Run require('agent_review').setup() in Neovim.")
    end
  else
    warn("No socket path configured. Set $AGENT_REVIEW_NVIM_SOCKET, configure server.socket_path, or run inside zellij.")
  end

  if vim.fn.executable("nvim") == 1 then
    ok("nvim executable found")
  else
    error("nvim executable not found in $PATH")
  end

  if vim.fn.executable("zellij") == 1 then
    ok("zellij executable found")
  else
    warn("zellij executable not found. Use transport='clipboard' or install zellij.")
  end

  if vim.env.ZELLIJ then
    ok("Running inside zellij")
  else
    warn("Not running inside zellij. Zellij transport will not work in this Neovim instance.")
  end

  local transport = config.options.transport or {}
  info("Transport: " .. tostring(transport.type or "zellij"))
  if transport.type == "custom" and type(transport.send) ~= "function" then
    error("transport.type='custom' requires transport.send=function(body) ... end")
  end
end

return M
