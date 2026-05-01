local config = require("agent_review.config")

local M = {}

local state = nil
local configured = false
local lnum_ns = vim.api.nvim_create_namespace("agent_review_lnum")

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "agent-review.nvim" })
end

local function agent_name()
  return config.options.agent_name or "Agent"
end

local function decorate_lnums(buf, win)
  if not (buf and vim.api.nvim_buf_is_valid(buf) and win and vim.api.nvim_win_is_valid(win)) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, lnum_ns, 0, -1)
  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_call(win, function()
    for lnum = 1, count do
      local hl_id = vim.fn.diff_hlID(lnum, 1)
      if hl_id ~= 0 then
        local name = vim.fn.synIDattr(hl_id, "name")
        local target = name == "DiffDelete" and "DiffDeleteLn" or "DiffAddLn"
        vim.api.nvim_buf_set_extmark(buf, lnum_ns, lnum - 1, 0, {
          number_hl_group = target,
        })
      end
    end
  end)
end

local function write_fifo(line)
  if not state or not state.fifo or state.fifo == "" then return end
  pcall(vim.fn.writefile, { line }, state.fifo)
end

local function wipe_buf(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

local function close_review()
  local s = state
  state = nil
  if not s then return end

  if s.tab and vim.api.nvim_tabpage_is_valid(s.tab) then
    local nr = vim.api.nvim_tabpage_get_number(s.tab)
    pcall(vim.cmd, nr .. "tabclose")
  end

  wipe_buf(s.pending_buf)
end

local function flush_comments()
  if not state or not state.comments_file or not state.review_buffers then return end

  local ok, comments = pcall(require, "agent_review.comments")
  if not ok then return end

  local overrides
  if state.pending_buf and state.real_file then
    overrides = { [state.pending_buf] = vim.fn.fnamemodify(state.real_file, ":.") }
  end

  local lines = comments.take_for_buffers(state.review_buffers, overrides)
  if not lines or #lines == 0 then return end

  local existing = {}
  if vim.uv.fs_stat(state.comments_file) then
    existing = vim.fn.readfile(state.comments_file)
  end
  for _, line in ipairs(lines) do
    table.insert(existing, line)
  end
  pcall(vim.fn.writefile, existing, state.comments_file)
end

local function decide(line)
  flush_comments()
  write_fifo(line)
  close_review()
end

local function map(lhs, mode, rhs, opts)
  if not lhs or lhs == "" then return end
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function setup_keymaps()
  local km = config.options.keymaps or {}
  if km.enabled == false then return end

  map(km.pause, "n", function() M.toggle_pause() end, { desc = "Toggle agent review pause" })
  map(km.comment_add, "x", function() require("agent_review.comments").add() end, {
    desc = "Add agent review comment on selection",
  })
  map(km.comment_send, "n", function() require("agent_review.comments").send() end, {
    desc = "Send agent comments",
  })
  map(km.comment_send, "x", function() require("agent_review.comments").add_and_send() end, {
    desc = "Add agent comment on selection and send",
  })
  map(km.comment_clear, "n", function() require("agent_review.comments").clear() end, {
    desc = "Clear all agent comments",
  })
end

local function setup_review_keymaps(bufnr)
  local km = config.options.keymaps or {}
  if km.enabled == false then return end

  local function bmap(lhs, fn, desc)
    if not lhs or lhs == "" then return end
    vim.keymap.set("n", lhs, fn, {
      buffer = bufnr,
      silent = true,
      desc = desc,
    })
  end

  bmap(km.approve, M.approve, "Approve agent change")
  bmap(km.decline_quick, M.decline_quick, "Decline agent change")
  bmap(km.decline_with_comment, M.decline_with_comment, "Decline agent change with comment")
  bmap(km.approve_with_note, M.approve_with_note, "Approve agent change with note")
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("AgentReview", { clear = true })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      if state and state.tab and not vim.api.nvim_tabpage_is_valid(state.tab) then
        flush_comments()
        write_fifo("deny:closed-without-decision")
        wipe_buf(state.pending_buf)
        state = nil
      end
    end,
  })

  if config.options.comments and config.options.comments.peek_on_hold then
    vim.api.nvim_create_autocmd("CursorHold", {
      group = group,
      callback = function()
        require("agent_review.comments").peek()
      end,
    })
  end
end

function M.serverstart()
  local socket = config.socket_path()
  if not socket then
    return nil, "No socket configured. Set $AGENT_REVIEW_NVIM_SOCKET, run inside zellij, or configure server.socket."
  end

  vim.fn.mkdir(vim.fn.fnamemodify(socket, ":h"), "p")
  if vim.uv.fs_stat(socket) then
    pcall(vim.uv.fs_unlink, socket)
  end

  local ok, result = pcall(vim.fn.serverstart, socket)
  if not ok then return nil, result end
  return result or socket
end

function M.socket_path()
  return config.socket_path()
end

local commands_defined = false
function M._define_commands()
  if commands_defined then return end
  commands_defined = true

  local function command(name, fn, opts)
    pcall(vim.api.nvim_del_user_command, name)
    vim.api.nvim_create_user_command(name, fn, opts or {})
  end

  command("AgentReviewPause", function() M.toggle_pause() end, { desc = "Toggle agent review pause" })
  command("AgentReviewApprove", function() M.approve() end, { desc = "Approve active agent review" })
  command("AgentReviewDecline", function() M.decline_quick() end, { desc = "Decline active agent review" })
  command("AgentReviewDeclineWithComment", function() M.decline_with_comment() end, {
    desc = "Decline active agent review with comment",
  })
  command("AgentReviewApproveWithNote", function() M.approve_with_note() end, {
    desc = "Approve active agent review with note",
  })
  command("AgentReviewComment", function() require("agent_review.comments").add() end, {
    range = true,
    desc = "Add agent comment for the current visual selection",
  })
  command("AgentReviewSendComments", function() require("agent_review.comments").send() end, {
    desc = "Send pending agent comments",
  })
  command("AgentReviewClearComments", function() require("agent_review.comments").clear() end, {
    desc = "Clear pending agent comments",
  })
  command("AgentReviewSocket", function()
    print(config.socket_path() or "")
  end, { desc = "Print the configured agent-review Neovim socket" })
  command("AgentReviewStart", function(args)
    local ok, decoded = pcall(vim.json.decode, args.args)
    if not ok then
      notify("AgentReviewStart expects a JSON object", vim.log.levels.ERROR)
      return
    end
    M.start(decoded)
  end, {
    nargs = 1,
    desc = "Start an agent review from a JSON payload",
  })
end

function M.setup(opts)
  config.setup(opts)
  configured = true

  M._define_commands()
  require("agent_review.comments").setup()
  setup_autocmds()
  setup_keymaps()

  if config.options.server and config.options.server.enabled then
    local _, err = M.serverstart()
    if err then notify(err, vim.log.levels.WARN) end
  end
end

local function ensure_configured()
  if not configured then
    M.setup({ server = { enabled = false }, keymaps = { enabled = false } })
  end
end

function M.is_active()
  return state ~= nil
end

function M.approve()
  decide("allow")
end

function M.decline_quick()
  decide("deny:declined")
end

function M.decline_with_comment()
  vim.ui.input({ prompt = "Decline reason: " }, function(input)
    if input == nil then return end
    if input == "" then input = "declined" end
    decide("deny:" .. input)
  end)
end

function M.approve_with_note()
  vim.ui.input({ prompt = "Note for later: " }, function(input)
    if input == nil then return end
    if input ~= "" and state and state.notes_file then
      local lines = {}
      if vim.uv.fs_stat(state.notes_file) then
        lines = vim.fn.readfile(state.notes_file)
      end
      table.insert(lines, "- " .. input)
      pcall(vim.fn.writefile, lines, state.notes_file)
    end
    decide("allow")
  end)
end

function M.start(opts)
  ensure_configured()
  opts = opts or {}

  if not opts.file or not opts.pending then
    notify("start() requires { file, pending }", vim.log.levels.ERROR)
    return
  end

  if state then
    decide("deny:concurrent-review")
  end

  state = {
    fifo = opts.fifo,
    notes_file = opts.notes_file,
    comments_file = opts.comments_file,
    real_file = opts.file,
    agent_name = opts.agent_name or agent_name(),
  }

  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()

  vim.cmd("edit " .. vim.fn.fnameescape(opts.file))
  local file_buf = vim.api.nvim_get_current_buf()
  local file_win = vim.api.nvim_get_current_win()

  vim.cmd("vert diffsplit " .. vim.fn.fnameescape(opts.pending))
  local pending_buf = vim.api.nvim_get_current_buf()
  local pending_win = vim.api.nvim_get_current_win()
  state.pending_buf = pending_buf
  state.review_buffers = { file_buf, pending_buf }

  pcall(vim.diagnostic.enable, false, { bufnr = pending_buf })

  vim.schedule(function()
    decorate_lnums(file_buf, file_win)
    decorate_lnums(pending_buf, pending_win)
  end)

  setup_review_keymaps(file_buf)
  setup_review_keymaps(pending_buf)

  notify(string.format("%s review: approve/decline the proposed change", state.agent_name))
end

function M.is_paused()
  return vim.uv.fs_stat(config.options.pause_file) ~= nil
end

function M.toggle_pause()
  local pause_file = config.options.pause_file
  if vim.uv.fs_stat(pause_file) then
    vim.uv.fs_unlink(pause_file)
    notify(agent_name() .. " review: enabled")
  else
    vim.fn.mkdir(vim.fn.fnamemodify(pause_file, ":h"), "p")
    vim.fn.writefile({ "" }, pause_file)
    notify(agent_name() .. " review: paused")
    if state then
      decide("allow")
    end
  end
end

return M
