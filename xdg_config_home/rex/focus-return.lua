-- When a floating pane closes, Rex hands focus to the tab's last tiled pane.
-- This watcher puts focus back on the tiled pane that last had it. init.lua
-- starts it on every config load (`rex do --all focus-return.lua`); a second
-- copy quits.

local client_label = "focus-return"

--- Window ID -> { focused = block ID, floats = set of block IDs,
--- last_tiled = the tiled block that last had focus }.
local windows = {}

local function scan(session_id)
	if not session_id then
		return
	end
	local view = rex.call("session.view", { session_id = session_id })
	for _, w in ipairs(view and view.windows or {}) do
		local tiled, floats, first = {}, {}, nil
		for _, layer in ipairs(w.layers or {}) do
			local set = layer.kind == "tiled" and tiled or floats
			for _, b in ipairs(layer.blocks or {}) do
				set[b.block_id] = true
				if layer.kind == "tiled" and not first then
					first = b.block_id
				end
			end
		end
		local prev = windows[w.window_id] or { floats = {} }
		local focused = w.focused_block_id
		-- Where focus belongs: the tiled pane that last had it, or the tab's first one.
		local home = prev.last_tiled and tiled[prev.last_tiled] and prev.last_tiled or first
		local float_closed = prev.focused and prev.floats[prev.focused] and not floats[prev.focused]
		if float_closed and tiled[focused] and home and focused ~= home then
			rex.call("session.focus_block", { session_id = session_id, block_id = home })
			focused = home
		elseif tiled[focused] then
			home = focused
		end
		windows[w.window_id] = { focused = focused, floats = floats, last_tiled = home }
	end
end

for _, c in ipairs(rex.call("client.list").clients or {}) do
	if c.info and c.info.label == client_label then
		rex.stop(0)
	end
end
rex.call("client.set_label", { label = client_label })

for _, s in ipairs(rex.call("session.list").sessions or {}) do
	rex.call("session.attach", { session_id = s.session_id })
	scan(s.session_id)
end

rex.on("session_created", function(_, ev)
	rex.call("session.attach", { session_id = ev.session_id })
	scan(ev.session_id)
end)

for _, event in ipairs({ "session_view_changed", "block_created", "block_closed", "active_window_changed" }) do
	rex.on(event, function(ctx)
		scan(ctx.session_id)
	end)
end
