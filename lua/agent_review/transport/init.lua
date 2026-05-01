local config = require("agent_review.config")

local M = {}

local function send_with(kind, body)
  if kind == "custom" then
    local fn = config.options.transport and config.options.transport.send
    if type(fn) ~= "function" then
      return false, "transport.type is custom, but transport.send is not a function"
    end
    local ok, result, err = pcall(fn, body)
    if not ok then return false, result end
    if result == false then return false, err or "custom transport failed" end
    return true, result
  end

  if kind == "zellij" then
    return require("agent_review.transport.zellij").send(body)
  end

  if kind == "clipboard" then
    return require("agent_review.transport.clipboard").send(body)
  end

  return false, "unknown transport: " .. tostring(kind)
end

function M.send(body)
  local opts = config.options.transport or {}
  local kind = opts.type or "zellij"

  if kind == "auto" then
    local ok, msg = send_with("zellij", body)
    if ok then return true, msg end
    local fallback = opts.fallback or "clipboard"
    return send_with(fallback, body)
  end

  local ok, msg = send_with(kind, body)
  if ok then return true, msg end

  local fallback = opts.fallback
  if fallback and fallback ~= kind then
    local f_ok, f_msg = send_with(fallback, body)
    if f_ok then return true, f_msg or ("Fallback transport used after: " .. msg) end
  end

  return false, msg
end

return M
