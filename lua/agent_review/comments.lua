local config = require("agent_review.config")

local M = {}

local ns = vim.api.nvim_create_namespace("agent_review_comments")
local group = vim.api.nvim_create_augroup("AgentReviewComments", { clear = true })

local comments = {}
local mark_index = {}
local next_comment_id = 0

local function agent_name()
  return config.options.agent_name or "Agent"
end

local function hl_group()
  return (config.options.comments and config.options.comments.highlight) or "AgentReviewCommentNr"
end

local function ensure_highlight()
  vim.api.nvim_set_hl(0, hl_group(), { fg = "#ff9e64", bold = true, default = true })
end

local function selection_lines()
  local s = vim.fn.line("v")
  local e = vim.fn.line(".")
  if s > e then s, e = e, s end
  return s - 1, e - 1
end

local function exit_visual()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end

local function place_marks(bufnr, s_row, e_row)
  ensure_highlight()
  local ids = {}
  for row = s_row, e_row do
    local id = vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
      number_hl_group = hl_group(),
    })
    table.insert(ids, id)
  end
  return ids
end

local function remove_comment(bufnr, comment_id)
  local entry = comments[bufnr] and comments[bufnr][comment_id]
  if not entry then return end
  for _, mid in ipairs(entry.marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mid)
    if mark_index[bufnr] then mark_index[bufnr][mid] = nil end
  end
  comments[bufnr][comment_id] = nil
end

local function add_with_callback(on_done)
  local s_row, e_row = selection_lines()
  local bufnr = vim.api.nvim_get_current_buf()
  exit_visual()

  vim.schedule(function()
    vim.ui.input({ prompt = "Comment for " .. agent_name() .. ": " }, function(input)
      if not input or input == "" then return end

      comments[bufnr] = comments[bufnr] or {}
      mark_index[bufnr] = mark_index[bufnr] or {}

      local overlapping = vim.api.nvim_buf_get_extmarks(
        bufnr,
        ns,
        { s_row, 0 },
        { e_row, -1 },
        { overlap = true }
      )
      local seen = {}
      for _, mark in ipairs(overlapping) do
        local cid = mark_index[bufnr][mark[1]]
        if cid and not seen[cid] then
          seen[cid] = true
          remove_comment(bufnr, cid)
        end
      end

      local marks = place_marks(bufnr, s_row, e_row)
      next_comment_id = next_comment_id + 1
      local cid = next_comment_id
      comments[bufnr][cid] = { text = input, marks = marks }
      for _, mid in ipairs(marks) do
        mark_index[bufnr][mid] = cid
      end

      if on_done then on_done() end
    end)
  end)
end

function M.add()
  add_with_callback(nil)
end

function M.add_and_send()
  add_with_callback(function()
    M.send()
  end)
end

function M.peek()
  local bufnr = vim.api.nvim_get_current_buf()
  local mapping = comments[bufnr]
  local idx = mark_index[bufnr]
  if not mapping or not idx then return end

  local row = vim.fn.line(".") - 1
  local marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    ns,
    { row, 0 },
    { row, -1 },
    { overlap = true }
  )

  for _, mark in ipairs(marks) do
    local cid = idx[mark[1]]
    local entry = cid and mapping[cid]
    if entry then
      vim.lsp.util.open_floating_preview({ agent_name() .. " comment:", entry.text }, "markdown", {
        border = "rounded",
        focus = false,
        focusable = false,
        close_events = { "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" },
      })
      return
    end
  end
end

local function collect(bufnrs, path_overrides)
  local filter
  if bufnrs then
    filter = {}
    for _, bufnr in ipairs(bufnrs) do filter[bufnr] = true end
  end

  local items = {}
  for bufnr, mapping in pairs(comments) do
    if (not filter or filter[bufnr])
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
    then
      local rel = path_overrides and path_overrides[bufnr]
      if not rel then
        local fname = vim.api.nvim_buf_get_name(bufnr)
        rel = vim.fn.fnamemodify(fname, ":.")
        if rel == "" then rel = "[no name]" end
      end

      for _, entry in pairs(mapping) do
        local rows = {}
        for _, mid in ipairs(entry.marks) do
          local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, mid, {})
          if pos and pos[1] then table.insert(rows, pos[1]) end
        end
        if #rows > 0 then
          table.sort(rows)
          local sr, er = rows[1], rows[#rows]
          local snippet = vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false)
          table.insert(items, {
            file = rel,
            start_line = sr + 1,
            end_line = er + 1,
            snippet = snippet,
            text = entry.text,
          })
        end
      end
    end
  end

  table.sort(items, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.start_line < b.start_line
  end)

  return items
end

local function format_lines(items)
  local lines = {}
  for _, item in ipairs(items) do
    table.insert(lines, string.format("%s:%d-%d", item.file, item.start_line, item.end_line))
    for _, line in ipairs(item.snippet) do
      table.insert(lines, "> " .. line)
    end
    table.insert(lines, "comment: " .. item.text)
    table.insert(lines, "")
  end
  return lines
end

local function format(items)
  return table.concat(format_lines(items), "\n")
end

function M.send()
  local ok, review = pcall(require, "agent_review")
  if ok and review.is_active and review.is_active() then
    vim.notify("Review in progress: comments will be sent with approve/decline", vim.log.levels.INFO)
    return
  end

  local items = collect()
  if #items == 0 then
    vim.notify("No agent comments to send", vim.log.levels.INFO)
    return
  end

  local body = format(items)
  local sent, msg = require("agent_review.transport").send(body)
  if not sent then
    vim.notify("Agent comment send failed: " .. (msg or "unknown error"), vim.log.levels.ERROR)
    return
  end

  M.clear()
  vim.notify(msg or string.format("Sent %d agent comment(s)", #items))
end

function M.take_for_buffers(bufnrs, path_overrides)
  local items = collect(bufnrs, path_overrides)
  if #items == 0 then return nil end
  local lines = format_lines(items)
  M.clear(bufnrs)
  return lines
end

function M.clear(bufnrs)
  if bufnrs then
    for _, bufnr in ipairs(bufnrs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      end
      comments[bufnr] = nil
      mark_index[bufnr] = nil
    end
    return
  end

  for bufnr, _ in pairs(comments) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
  comments = {}
  mark_index = {}
end

function M.setup()
  ensure_highlight()
end

vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(args)
    comments[args.buf] = nil
    mark_index[args.buf] = nil
  end,
})

return M
