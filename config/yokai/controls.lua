-- Native Hyprland controls. Quickshell owns the visual surfaces and selection state.
return function(options)
    options = options or {}
    -- A click alone must not untile a window. Preserve the grab point when dragging.
    hl.config({ binds = { drag_threshold = 6, drag_center_window = false } })
    if _G.yokai_control_blur ~= nil then _G.yokai_control_blur:set_enabled(false) end
    _G.yokai_control_blur = hl.layer_rule({ match = { namespace = "^yokai-control$" }, blur = true, ignore_alpha = 0.15 })
    if _G.yokai_popup_motion ~= nil then _G.yokai_popup_motion:set_enabled(false) end
    _G.yokai_popup_motion = hl.layer_rule({ match = { namespace = "^yokai-popup$" }, no_anim = true })
    if _G.yokai_updates_blur ~= nil then _G.yokai_updates_blur:set_enabled(false) end
    _G.yokai_updates_blur = hl.layer_rule({ match = { namespace = "^yokai-updates$" }, blur = true, ignore_alpha = 0.15, no_anim = true })
    if _G.yokai_telegram_blur ~= nil then _G.yokai_telegram_blur:set_enabled(false) end
    _G.yokai_telegram_blur = hl.layer_rule({ match = { namespace = "^yokai-telegram-setup$" }, blur = true, ignore_alpha = 0.15 })
    local function bind(keys, dispatcher, flags)
        if options.replace then hl.unbind(keys) end
        return hl.bind(keys, dispatcher, flags or {})
    end

    if options.replace then hl.unbind("ALT + space") end
    bind(options.launcherKey or "SUPER + space", hl.dsp.event("yokai:search"))
    bind("SUPER + V", hl.dsp.event("yokai:clipboard"))
    bind("SUPER + L", hl.dsp.event("yokai:lock"))
    for id = 1, 10 do
        local key = tostring(id % 10)
        bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(id) }))
    end
    bind("ALT + Tab", hl.dsp.event("yokai:next"))
    bind("ALT + SHIFT + Tab", hl.dsp.event("yokai:previous"))
    -- Observe both Alt keys without consuming normal application input.
    bind("Alt_L", hl.dsp.event("yokai:finish"), { release = true, ignore_mods = true, non_consuming = true })
    bind("Alt_R", hl.dsp.event("yokai:finish"), { release = true, ignore_mods = true, non_consuming = true })
    local tilingDragActive = false
    local tilingDragWindow = nil
    bind("SUPER + mouse:272", function()
        local starting = not tilingDragActive
        tilingDragActive = starting
        -- Keep native drag uninterrupted. Changing floating state while a drag is
        -- active replaces its layout target and cancels the interaction.
        local result = hl.dispatch(hl.dsp.window.drag())
        if starting then
            tilingDragWindow = hl.get_active_window()
        else
            local window = tilingDragWindow
            tilingDragWindow = nil
            if window ~= nil and window.mapped and window.floating then
                hl.dispatch(hl.dsp.window.float({ window = window, action = "unset" }))
            end
        end
        return result
    end, { mouse = true })

    local dragged = nil
    local originallyFloating = false
    local floatingFrame = nil
    -- Hyprland ends native drag before invoking the mouse-release binding.
    -- Retain the floating geometry while dragging, not after it has been retiled.
    local tracker = hl.timer(function()
        if dragged == nil or not dragged.mapped then return end
        if dragged.floating then
            floatingFrame = { position = dragged.at, size = dragged.size, cursor = hl.get_cursor_pos() }
        end
    end, { timeout = 8, type = "repeat" })
    tracker:set_enabled(false)
    bind("SUPER + SHIFT + mouse:272", function()
        if dragged == nil then
            -- Native drag hit-tests the actual window under the pointer and focuses it.
            local result = hl.dispatch(hl.dsp.window.drag())
            dragged = hl.get_active_window()
            originallyFloating = dragged ~= nil and dragged.floating
            floatingFrame = nil
            tracker:set_enabled(dragged ~= nil)
            return result -- preserve Hyprland's request_release result
        end

        -- Native drag floats tiled windows while moving, then retiles them on release.
        -- Restore the geometry captured before release so the window stays where dropped.
        local window = dragged
        dragged = nil
        tracker:set_enabled(false)
        local frame = floatingFrame
        floatingFrame = nil
        local result = hl.dispatch(hl.dsp.window.drag())
        if frame ~= nil and not originallyFloating and window.mapped then
            local cursor = hl.get_cursor_pos()
            local position, size = frame.position, frame.size
            -- Account for motion between the final sample and the release event.
            position.x = position.x + cursor.x - frame.cursor.x
            position.y = position.y + cursor.y - frame.cursor.y
            hl.dispatch(hl.dsp.window.float({ window = window, action = "set" }))
            hl.dispatch(hl.dsp.window.resize({ window = window, x = size.x, y = size.y, relative = false }))
            hl.dispatch(hl.dsp.window.move({ window = window, x = position.x, y = position.y, relative = false }))
        end
        return result
    end, { mouse = true })
end
