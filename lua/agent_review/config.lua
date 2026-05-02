local M = {}

local function cache_file(name)
  return vim.fn.stdpath("cache") .. "/" .. name
end

M.defaults = {
  agent_name = "Agent",

  server = {
    enabled = true,
    -- Explicit socket path override. Can be a string or function(options).
    socket_path = nil,
    -- If socket_path is nil, derive socket from $ZELLIJ_SESSION_NAME.
    auto_socket = true,
    socket_prefix = "nvim-agent-review-",
    socket_dir = "/tmp",
  },

  pause_file = cache_file("agent-review-paused"),

  keymaps = {
    enabled = true,
    pause = "<Leader>ap",
    approve = "<Leader>aa",
    decline_quick = "<Leader>ad",
    decline_with_comment = "<Leader>aD",
    approve_with_note = "<Leader>an",
    comment_add = "<Leader>ac",
    comment_send = "<Leader>as",
    comment_clear = "<Leader>ax",
  },

  comments = {
    peek_on_hold = true,
    highlight = "AgentReviewCommentNr",
  },

  transport = {
    -- "zellij", "clipboard", "custom", or "auto".
    type = "zellij",
    focus_direction = "right",
    fallback = "clipboard",
    send = nil,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

local function nonempty(value)
  return value and value ~= ""
end

local function sanitize(value)
  return (value:gsub("[^%w_.-]", "_"))
end

function M.socket_path()
  local server = M.options.server or {}
  local socket_path = server.socket_path
  if type(socket_path) == "function" then
    return socket_path(M.options)
  end
  if nonempty(socket_path) then
    return vim.fn.expand(socket_path)
  end

  local explicit_env = vim.env.AGENT_REVIEW_NVIM_SOCKET
  if nonempty(explicit_env) then return explicit_env end

  if server.auto_socket == false then return nil end

  local session = vim.env.ZELLIJ_SESSION_NAME
  if nonempty(session) then
    return string.format(
      "%s/%s%s.sock",
      server.socket_dir or "/tmp",
      server.socket_prefix or "nvim-agent-review-",
      sanitize(session)
    )
  end

  return nil
end

return M
