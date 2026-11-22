rex.action{
  name = "rexboard_picker",
  title = "Open Rexboard Picker",
  run = function(ctx)
    local result, err = rex.session.new_layer{
      bounds = { 0.1, 0.1, 0.8, 0.8 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = {
          command = { "/opt/homebrew/bin/rexboard", "pick" },
          shell = "none",
          exit = { on_completion = true },
        },
      },
    }
    if err ~= nil then error(err, 0) end
    return result
  end,
}

-- cmd+p is the peek (the main attention surface); the picker takes the peek's old key.
rex.bind("cmd+shift+p", "rexboard_picker")

-- Left Option is remapped to ctrl+alt+cmd (Karabiner), so Rex's alt+cmd defaults
-- are unreachable. Option+hjkl focuses AeroSpace windows everywhere; while Rex is
-- frontmost, Karabiner sends Option+hjkl as Option+arrows instead, which run the
-- navigate actions below. They move between panes, and at the edge of the tab
-- they hand the move to AeroSpace, so one set of keys crosses panes and windows.

--- The focused block of the session's active tab.
local function focused_block(session_id)
  local view = rex.call("session.view", { session_id = session_id })
  for _, w in ipairs(view.windows or {}) do
    if w.window_id == view.active_window_id then return w.focused_block_id end
  end
end

local function aerospace_focus(dir)
  rex.exec({
    "/opt/homebrew/bin/aerospace", "focus",
    "--boundaries-action", "wrap-around-the-workspace", dir,
  })
end

local function navigate(ctx, dir)
  if not ctx.session_id then return aerospace_focus(dir) end
  local start = focused_block(ctx.session_id)
  rex.call("session.focus_direction", { session_id = ctx.session_id, direction = dir })
  if focused_block(ctx.session_id) ~= start then return end
  -- No pane lies that way.
  aerospace_focus(dir)
end

for _, dir in ipairs({ "left", "right", "up", "down" }) do
  rex.action{
    name = "navigate_" .. dir,
    title = "Navigate " .. dir .. " (panes, then AeroSpace windows)",
    category = "Pane",
    run = function(ctx) navigate(ctx, dir) end,
  }
  rex.bind("ctrl+alt+cmd+" .. dir, "navigate_" .. dir)
  rex.bind("ctrl+alt+shift+cmd+" .. dir, "pane.move." .. dir)
end
-- AeroSpace owns Option+f (fullscreen); while Rex is frontmost, Karabiner sends
-- it as Option+z, so the same key zooms the pane to fill its tab.
rex.bind("ctrl+alt+cmd+z", "pane.zoom")
rex.bind("ctrl+alt+shift+cmd+f", "pane.float")
rex.bind("ctrl+alt+shift+cmd+m", "pane.minimize_floating")

local agent_path = os.getenv("HOME") .. "/.local/bin:/opt/homebrew/bin:/usr/local/bin:"
  .. (os.getenv("PATH") or "/usr/bin:/bin")

--- Starts ~/.config/rex/NAME.lua as a script that hears every session. Its errors
--- go to ~/.config/rex/state/NAME.log.
local function start_watcher(name)
  rex.exec.start({
    "/bin/sh", "-c",
    'mkdir -p ~/.config/rex/state; for i in 1 2 3 4 5 6 7 8 9 10; do "$@" && break; sleep 1; done 2>>~/.config/rex/state/"$0".log',
    name,
    os.getenv("HOME") .. "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex",
    "--autostart=false", "do", "--all",
    os.getenv("HOME") .. "/.config/rex/" .. name .. ".lua",
  }, { detach = true, stdout = false, stderr = false })
end

-- Puts focus back on the pane a floating pane was opened from when it closes.
start_watcher("focus-return")
-- Collapses sessions that agents create in the background in the app's sidebar.
start_watcher("collapse-background-sessions")

rex.action{
  name = "rexboard_next",
  title = "Rexboard: next pane that needs me",
  description = "Go to the next agent pane that needs attention and mark it seen",
  category = "Agents",
  run = function(ctx)
    local result, err = rex.exec({ "/opt/homebrew/bin/rexboard", "next" }, {
      env = {
        REX_SESSION = ctx.session_id,
        REX_BLOCK = ctx.block_id,
        REX_CLIENT = ctx.client_id,
        PATH = agent_path,
      },
    })
    if result == nil then error(err, 0) end
    -- Exit 1 means nobody needs you; that is not an error.
  end,
}

rex.bind("cmd+j", "rexboard_next")

rex.action{
  name = "rexboard_peek",
  title = "Rexboard: peek at agent panes",
  description = "Preview agent panes in a float over the current tab; enter goes, ctrl-s marks seen",
  category = "Agents",
  run = function(ctx)
    local result, err = rex.session.new_layer{
      bounds = { 0.08, 0.06, 0.84, 0.88 },
      focus = true,
      layout = rex.layout.block{
        flavor = "com.superlogical.terminal.shell",
        options = {
          command = { os.getenv("HOME") .. "/.config/rex/peek.sh" },
          shell = "none",
          exit = { on_completion = true },
        },
      },
    }
    if err ~= nil then error(err, 0) end
    return result
  end,
}

rex.bind("cmd+p", "rexboard_peek")

-- Work sessions: rexwork (~/dotfiles/agents/rexwork) starts, promotes and lands
-- a session. These actions call it for the focused session.
local REXWORK = os.getenv("HOME") .. "/.local/bin/rexwork"
local TERMINAL = "com.superlogical.terminal"

local function work_env(ctx)
  return {
    REX_SESSION = ctx.session_id,
    REX_BLOCK = ctx.block_id,
    REX_CLIENT = ctx.client_id,
    PATH = agent_path,
    -- Rex runs without XDG_CONFIG_HOME; Tal's shells set it. Without it a Neovim
    -- started from an action loads ~/.config/nvim, not the real config.
    XDG_CONFIG_HOME = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/nikud/xdg_config_home"),
  }
end

--- The focused pane's working directory: the foreground program's, else the shell's.
local function pane_cwd(ctx)
  if ctx.block_id == nil then return nil end
  local info = rex.block.call(TERMINAL, "process", { block_id = ctx.block_id })
  if type(info) == "table" and type(info.foreground) == "table"
    and type(info.foreground.cwd) == "string" and info.foreground.cwd ~= "" then
    return info.foreground.cwd
  end
  local pwd = rex.block.call(TERMINAL, "pwd", { block_id = ctx.block_id })
  if type(pwd) ~= "table" or type(pwd.pwd) ~= "string" then return nil end
  local path = pwd.pwd:match("^file://[^/]*(/.*)$")
  return path and path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
end

local function rexwork(ctx, argv, opts)
  local cmd = { REXWORK }
  for _, a in ipairs(argv) do cmd[#cmd + 1] = a end
  local result, err = rex.exec(cmd, { env = work_env(ctx), cwd = opts and opts.cwd, timeout = 120 })
  if result == nil then error("rexwork: " .. tostring(err), 0) end
  if not result.ok then error((result.stderr or ""):gsub("%s+$", ""), 0) end
  return result
end

--- rex.ui answer, or nil. Errors on busy; nil plus "fallback" when no app can ask.
local function ask(fn, spec)
  local answer, reason, detail = fn(spec)
  if answer ~= nil then return answer end
  if reason == "unsupported" or reason == "failed" then
    if detail ~= nil then rex.log("warn", "rexwork: prompt failed: " .. tostring(detail)) end
    return nil, "fallback"
  end
  if reason == "busy" then
    error("Rex is already asking something else. Answer or close that, then try again.", 0)
  end
  return nil, reason -- cancelled, timeout, no_client
end

rex.action{
  name = "work_start",
  title = "Start work…",
  description = "Start a scratch session, or a session where an agent drafts a ticket with you",
  category = "Work",
  keywords = "rexwork session scratch draft ticket linear new",
  run = function(ctx)
    local cwd = pane_cwd(ctx) or os.getenv("HOME")
    local kind, why = ask(rex.ui.pick, {
      title = "Start work",
      items = {
        { id = "scratch claude", title = "Scratch session (Claude)", icon = "terminal" },
        { id = "scratch codex", title = "Scratch session (Codex)", icon = "terminal" },
        { id = "draft claude", title = "Draft a ticket with Claude", icon = "document" },
        { id = "draft codex", title = "Draft a ticket with Codex", icon = "document" },
      },
    })
    if kind == nil and why == "fallback" then
      -- No app can show the palette prompt: ask in a float instead.
      local _, err = rex.session.new_layer{
        bounds = { 0.25, 0.25, 0.5, 0.35 },
        focus = true,
        layout = rex.layout.block{
          flavor = "com.superlogical.terminal.shell",
          options = {
            command = { REXWORK, "start", "--ask", "--focus", "--cwd", cwd },
            cwd = cwd,
            exit = { on_completion = true },
          },
        },
      }
      if err ~= nil then error(err, 0) end
      return
    end
    if kind == nil then return end
    local agent
    kind, agent = kind:match("^(%S+) (%S+)$")
    local name = ask(rex.ui.input, {
      title = kind == "scratch" and "Scratch session name" or "Short name for the ticket draft",
      placeholder = "short-name",
      confirm = "Start",
    })
    if name == nil then return end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return end
    rexwork(ctx, { "start", "--" .. kind, name, "--cwd", cwd, "--agent", agent, "--focus" })
  end,
}

rex.bind("cmd+shift+n", "work_start")

rex.action{
  name = "work_promote",
  title = "Work: promote this session to a ticket",
  description = "Open the ticket draft in Neovim to file it; with no draft, ask the agent to write one",
  category = "Work",
  keywords = "rexwork promote ticket linear draft",
  run = function(ctx)
    if not ctx.session_id then error("no session", 0) end
    rexwork(ctx, { "promote", "--request-draft", "--session", ctx.session_id })
  end,
}

rex.action{
  name = "work_land",
  title = "Work: land this session",
  description = "Push and open the PR (ticketed) or archive (scratch), then close the session",
  category = "Work",
  keywords = "rexwork land pr close archive",
  run = function(ctx)
    if not ctx.session_id then error("no session", 0) end
    -- Dry runs give each choice's exact plan and its digest; the chosen one runs with
    -- --expect DIGEST, so rexwork refuses if the plan changed after Tal saw it.
    -- The dry run refuses Symphony's sessions and says when no branch is attached.
    local function dry(flags)
      local argv = { "land", "--session", ctx.session_id, "--dry-run", "--json" }
      for _, f in ipairs(flags) do argv[#argv + 1] = f end
      local okp, plan = pcall(rex.json.decode, rexwork(ctx, argv).stdout or "")
      if not okp or type(plan) ~= "table" or type(plan.digest) ~= "string" then
        error("rexwork land --dry-run printed no plan", 0)
      end
      return plan
    end
    local first = dry({})
    local nobranch = first.no_branch == true
    local close_flags = nobranch and { "--linear-only" } or {}
    local keep_flags = { "--keep" }
    for _, f in ipairs(close_flags) do keep_flags[#keep_flags + 1] = f end
    local plans = { close = nobranch and dry(close_flags) or first, keep = dry(keep_flags) }
    local function summary(plan) return table.concat(plan.plan or {}, "; ") end
    local what = nobranch and " (no branch or PR: Linear only)" or ""
    local choice = ask(rex.ui.pick, {
      title = "Land this session?" .. what,
      items = {
        { id = "close", title = "Land and close: " .. summary(plans.close), icon = "package" },
        { id = "keep", title = "Land, keep open: " .. summary(plans.keep), icon = "package" },
        { id = "cancel", title = "Cancel" },
      },
    })
    if choice == nil or choice == "cancel" then return end
    local argv = { "land", "--session", ctx.session_id, "--yes", "--expect", plans[choice].digest }
    for _, f in ipairs(choice == "keep" and keep_flags or close_flags) do argv[#argv + 1] = f end
    rexwork(ctx, argv)
  end,
}

rex.action{
  name = "work_review",
  title = "Work: review changes since last review",
  description = "diffreview open for the focused pane's repo, in a Neovim float",
  category = "Work",
  keywords = "diffreview diff review neovim",
  run = function(ctx)
    if not ctx.session_id or not ctx.block_id then error("no focused pane", 0) end
    local cwd = pane_cwd(ctx)
    if cwd == nil then error("can't tell the focused pane's directory", 0) end
    local result, err = rex.exec(
      { os.getenv("HOME") .. "/.local/bin/diffreview", "open", "--session", ctx.session_id,
        "--agent-block", ctx.block_id },
      { env = work_env(ctx), cwd = cwd, timeout = 60 })
    if result == nil then error("diffreview: " .. tostring(err), 0) end
    if not result.ok then error((result.stderr or ""):gsub("%s+$", ""), 0) end
  end,
}

rex.action{
  name = "work_editor",
  title = "Work: show/hide the editor float",
  description = "Minimize the session's docview Neovim float, or show it on this tab",
  category = "Work",
  keywords = "docview editor neovim float document review toggle",
  run = function(ctx)
    if not ctx.session_id then error("no session", 0) end
    local block = ctx.block_id or focused_block(ctx.session_id)
    if block == nil then error("no focused pane", 0) end
    local result, err = rex.exec(
      { os.getenv("HOME") .. "/.local/bin/docview", "toggle", "--session", ctx.session_id, "--block", block },
      { env = work_env(ctx), timeout = 30 })
    if result == nil then error("docview: " .. tostring(err), 0) end
    if result.ok then return end
    local msg = (result.stderr or ""):gsub("%s+$", "")
    if not msg:find("nothing is open", 1, true) then error(msg, 0) end
    -- Nothing open yet: start the editor on the session's objectives.
    local file = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/rexwork/sessions/"
      .. ctx.session_id:gsub("^session:", "") .. "/objectives.md"
    local f = io.open(file, "r")
    if f == nil then error("Nothing is open in the editor, and this session has no objectives file.", 0) end
    f:close()
    result, err = rex.exec(
      { os.getenv("HOME") .. "/.local/bin/docview", "open", file, "--title", "objectives",
        "--session", ctx.session_id, "--agent-block", block },
      { env = work_env(ctx), timeout = 30 })
    if result == nil then error("docview: " .. tostring(err), 0) end
    if not result.ok then error((result.stderr or ""):gsub("%s+$", ""), 0) end
  end,
}
rex.bind("cmd+e", "work_editor")

--- Runs a toggle program for the focused pane's tab: ARGV, then --session S --block B.
local function work_toggle(ctx, what, argv)
  if not ctx.session_id then error("no session", 0) end
  local block = ctx.block_id or focused_block(ctx.session_id)
  if block == nil then error("no focused pane", 0) end
  local cmd = {}
  for _, a in ipairs(argv) do cmd[#cmd + 1] = a end
  for _, a in ipairs({ "--session", ctx.session_id, "--block", block }) do cmd[#cmd + 1] = a end
  local result, err = rex.exec(cmd, { env = work_env(ctx), timeout = 30 })
  if result == nil then error(what .. ": " .. tostring(err), 0) end
  if not result.ok then error((result.stderr or ""):gsub("%s+$", ""), 0) end
end

rex.action{
  name = "work_show_toggle",
  title = "Work: show/hide the picture pane",
  description = "Close this tab's Show pane, or reopen it on the latest picture",
  category = "Work",
  keywords = "show picture pane diagram toggle",
  run = function(ctx)
    work_toggle(ctx, "show", { os.getenv("HOME") .. "/.local/bin/show", "--toggle" })
  end,
}
rex.bind("cmd+i", "work_show_toggle")

rex.action{
  name = "work_bar_toggle",
  title = "Work: show/hide the status bar",
  description = "Close this tab's rexbar status bar, or open it along the bottom",
  category = "Work",
  keywords = "rexbar status bar toggle",
  run = function(ctx)
    work_toggle(ctx, "rexbar", { os.getenv("HOME") .. "/.local/bin/rexbar", "toggle" })
  end,
}
rex.bind("cmd+b", "work_bar_toggle")

require("amber.action")

package.path = os.getenv("HOME") .. "/src/ai-usage/rex/?.lua;" .. package.path
require("ai_usage").setup{ bin = "/Users/tal/.cargo/bin/ai-usage", key = "cmd+shift+u" }

-- evgeny-golubev/rex-extensions (cloned at ~/src/rex-extensions)
-- Saves every session's layout and brings programs back after a server restart.
require("extensions.rex-resume")

-- Leaf's diff review is retired (diffreview replaces it); its reader, PR list
-- and plan review stay. Skip those actions while leaf's managed block runs.
local leaf_define_action = rex.action
local leaf_dropped = { leaf_diff = true, leaf_review_staged = true, leaf_review_branch = true }
rex.action = function(spec)
  if type(spec) == "table" and leaf_dropped[spec.name] then return end
  return leaf_define_action(spec)
end

-- >>> leaf >>>
-- Managed by `leaf rex install`; `leaf rex uninstall` removes it.
-- plugin: 3f4010a57a8d8e3d
dofile("/Users/tal/.config/rex/plugins/leaf/init.lua").setup({ bin = { "/Users/tal/.local/bin/leaf" } })
-- open: idle classic
-- <<< leaf <<<

rex.action = leaf_define_action
