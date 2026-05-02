# agent-review.nvim

Neovim UI for reviewing code changes proposed by terminal coding agents.

## Features

- Open an agent-proposed file edit in a diff tab.
- Approve, decline, decline with a reason, or approve with a note.
- Mark code ranges with comments and send them to the agent.
- Zellij transport for sending comments into the adjacent agent pane.
- Clipboard/custom transports for non-Zellij setups.
- `:checkhealth agent_review` diagnostics.

## Installation

With `lazy.nvim` from a local checkout:

```lua
{
  "igor-gorohovsky/agent-review.nvim",
  config = function()
    require("agent_review").setup()
  end,
}
```

## Recommended Zellij layout

A simple layout is included at `zellij/agent-review.kdl`:

```sh
zellij --layout ~/projects/agent-review.nvim/zellij/agent-review.kdl
```

By default, comments are sent by running:

1. `zellij action move-focus right`
2. `zellij action write-chars <payload>`

So the recommended layout keeps Neovim on the left and the agent on the right.

## Configuration

```lua
require("agent_review").setup({
  agent_name = "Claude", -- display name only

  server = {
    enabled = true,
    socket = "auto", -- $AGENT_REVIEW_NVIM_SOCKET or /tmp/nvim-agent-review-$ZELLIJ_SESSION_NAME.sock
  },

  transport = {
    type = "zellij", -- "zellij", "clipboard", "custom", or "auto"
    focus_direction = "right",
    fallback = "clipboard",
  },

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
})
```

Custom transport:

```lua
require("agent_review").setup({
  transport = {
    type = "custom",
    send = function(body)
      -- send body to your agent however you want
      return true
    end,
  },
})
```

## Commands

- `:AgentReviewPause`
- `:AgentReviewApprove`
- `:AgentReviewDecline`
- `:AgentReviewDeclineWithComment`
- `:AgentReviewApproveWithNote`
- `:AgentReviewSendComments`
- `:AgentReviewClearComments`
- `:AgentReviewSocket`
- `:AgentReviewStart {json}`

Run diagnostics with:

```vim
:checkhealth agent_review
```

## Agent hook integration

The core API is:

```lua
require("agent_review").start({
  file = "/absolute/path/to/original/file",
  pending = "/absolute/path/to/proposed/file",
  fifo = "/tmp/agent-review-decision", -- optional
  notes_file = "/tmp/agent-review-notes.md", -- optional
  comments_file = "/tmp/agent-review-comments.md", -- optional
  agent_name = "Claude", -- optional
})
```

When the user decides, the plugin writes one of these lines to `fifo` if provided:

```text
allow
deny:declined
deny:<user reason>
deny:closed-without-decision
deny:concurrent-review
```

A helper script is included:

```sh
bin/agent-review-open \
  --file /path/to/file \
  --pending /path/to/pending-file \
  --fifo /tmp/decision \
  --agent-name Claude
```

The script sends the request to the Neovim server socket created by `setup()`.

## Socket naming

Default socket resolution:

1. `$AGENT_REVIEW_NVIM_SOCKET`
2. configured `server.socket`
3. `/tmp/nvim-agent-review-$ZELLIJ_SESSION_NAME.sock`

Print the current socket path with:

```vim
:AgentReviewSocket
```
