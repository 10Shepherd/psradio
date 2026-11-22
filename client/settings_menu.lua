--[[
    The settings menu, opened with /radiosetting. It is an ox_lib menu, not part
    of the radio's own display: it works whether the radio is shown or hidden,
    on or off.

    Nothing is decided here. Moving a row posts the one setting that changed to
    the server, which validates it, saves it and answers with the whole set —
    so what the menu shows is what the server stored. Rows redraw themselves if
    the server's answer differs from what was asked for.

    The animations are one tick box each, built from the list the server sent
    (Config.animations.styles). Only one animation can play, so ticking one
    unticks the others and unticking it leaves none.

    Adding a setting means one entry in ROWS and one locale string.
]]
PSR = PSR or {}

local Menu = {
    id = 'psradio_settings',
    open = false,
    rows = {},                      -- the visible rows, in menu order
    shown = {},                     -- what each row is displaying, by index
    cursor = 1,                     -- the row the player is on, to put it back
    settings = {},
    models = {},
    anim = { enabled = false, styles = {} },
    text = function(key) return key end,
    onChange = function() end,      -- set by client/main.lua
}
PSR.SettingsMenu = Menu

local function available()
    return lib ~= nil and type(lib.registerMenu) == 'function'
end

-- A list of percentages in steps of 5, the same step as the radio's own keys.
local PERCENTS = {}
for value = 0, 100, 5 do PERCENTS[#PERCENTS + 1] = value end

local function percentOptions()
    local out = {}
    for index, value in ipairs(PERCENTS) do out[index] = { value = value, label = value .. '%' } end
    return out
end

-- id        this row, for telling one build of the menu from the next
-- key       what the server calls the setting
-- labelKey  locale key for the row's label
-- kind      'list' (scroll left / right through options) or 'check'
-- when      left out, or a test for whether the row applies to this player
-- options   for a list row: { value = <what the server stores>, label = <shown> }
-- checked   for a check row: whether the box is ticked
-- value     for a check row: what to store for a tick / an empty box
-- expand    instead of a row: the rows to put here, built from server data
local ROWS = {
    {
        id = 'volume', key = 'volume', labelKey = 'set_volume', kind = 'list',
        options = percentOptions,
    },
    {
        id = 'toneVolume', key = 'toneVolume', labelKey = 'set_tone_volume', kind = 'list',
        options = percentOptions,
    },
    {
        id = 'fx', key = 'fx', labelKey = 'set_fx', kind = 'list',
        options = function(t)
            return {
                { value = 'full',  label = t('set_fx_full') },
                { value = 'light', label = t('set_fx_light') },
                { value = 'off',   label = t('set_fx_off') },
            }
        end,
    },
    {
        id = 'rogerBeep', key = 'rogerBeep', labelKey = 'set_roger', kind = 'check',
        checked = function() return Menu.settings.rogerBeep == true end,
        value = function(checked) return checked end,
    },
    -- One tick box per animation the server defines.
    { expand = function()
        local out = {}
        if not Menu.anim.enabled then return out end
        for _, style in ipairs(Menu.anim.styles) do
            local id = style.id
            out[#out + 1] = {
                id = 'anim:' .. id,
                key = 'animStyle',
                kind = 'check',
                label = Menu.text('menu_anim_row', style.label or id),
                descriptionKey = 'set_animations_desc',
                checked = function() return Menu.settings.animStyle == id end,
                -- Ticking this animation picks it, which unticks whichever was
                -- on. Unticking the one that is on leaves no animation; an
                -- untick of any other box means the menu was out of date, and
                -- nil leaves the setting alone.
                value = function(checked)
                    if checked then return id end
                    return Menu.settings.animStyle == id and 'off' or nil
                end,
            }
        end
        return out
    end },
    {
        id = 'pttMode', key = 'pttMode', labelKey = 'set_ptt_mode', kind = 'list',
        options = function(t)
            return {
                { value = 'hold',   label = t('set_ptt_hold') },
                { value = 'toggle', label = t('set_ptt_toggle') },
            }
        end,
    },
    {
        -- Only worth showing when the codeplug allows a choice.
        id = 'model', key = 'model', labelKey = 'set_model', kind = 'list',
        when = function() return #Menu.models > 1 end,
        options = function()
            local out = {}
            for index, model in ipairs(Menu.models) do
                out[index] = { value = model.id, label = model.name }
            end
            return out
        end,
    },
}

local function visibleRows()
    local out = {}
    for _, row in ipairs(ROWS) do
        if row.expand then
            for _, built in ipairs(row.expand()) do out[#out + 1] = built end
        elseif not row.when or row.when() then
            out[#out + 1] = row
        end
    end
    return out
end

-- Which option a row is sitting on, and 1 when the stored value is not one of
-- them (a model the codeplug dropped, an animation the config no longer has).
local function indexOf(options, value)
    for index, option in ipairs(options) do
        if option.value == value then return index end
    end
    return 1
end

-- What the row shows right now: a tick, or the value under the cursor.
local function displayValue(row)
    if row.kind == 'check' then return row.checked() end
    return Menu.settings[row.key]
end

local function buildOptions()
    local t = Menu.text
    Menu.rows = visibleRows()
    Menu.shown = {}
    local options = {}

    for index, row in ipairs(Menu.rows) do
        local option = { label = row.label or t(row.labelKey), close = false }
        if row.descriptionKey then option.description = t(row.descriptionKey) end
        Menu.shown[index] = displayValue(row)
        if row.kind == 'check' then
            option.checked = row.checked()
        else
            local list = row.options(t)
            local labels = {}
            for i, entry in ipairs(list) do labels[i] = entry.label end
            option.values = labels
            option.defaultIndex = indexOf(list, Menu.settings[row.key])
        end
        options[index] = option
    end

    options[#options + 1] = { label = t('menu_close'), icon = 'xmark' }
    return options
end

-- Brings an open menu back in line with the settings.
--
-- lib.setMenuOptions never reaches an open menu: it only writes the Lua-side
-- options, and ox_lib's menu reads the tick boxes and the scroll positions from
-- Lua just once, when it is shown. So anything that has to become visible while
-- the menu is open means writing the options and showing the menu again, with
-- the cursor put back where the player left it. That is what unticks the
-- animation they had on when they tick another one.
--
-- Showing the menu again is not free, so it only happens when a row is actually
-- out of date: the row the player just moved is already right on screen, and
-- their own scrolling never triggers this.
local function syncOpen(cursor)
    if not (Menu.open and available()) then return end

    local rows = visibleRows()
    local stale = #rows ~= #Menu.rows
    if not stale then
        for index, row in ipairs(rows) do
            if Menu.rows[index].id ~= row.id then stale = true break end
        end
    end
    if not stale then
        for index, row in ipairs(Menu.rows) do
            if Menu.shown[index] ~= displayValue(row) then stale = true break end
        end
    end
    if not stale then return end

    lib.setMenuOptions(Menu.id, buildOptions())
    lib.showMenu(Menu.id, cursor or Menu.cursor)
end

-- Posts one setting. The row the player moved has already drawn itself, so it
-- is recorded as shown; only the other rows can need redrawing. The server's
-- answer is what sticks, and redraws a row if it differs.
local function apply(index, row, value)
    if value == nil or Menu.settings[row.key] == value then return end
    Menu.settings[row.key] = value
    if index then
        Menu.cursor = index
        Menu.shown[index] = displayValue(row)
    end
    syncOpen(index)
    Menu.onChange({ [row.key] = value })
end

local function register()
    lib.registerMenu({
        id = Menu.id,
        title = Menu.text('menu_title'),
        position = 'top-left',
        onClose = function() Menu.open = false end,
        onSelected = function(selected) Menu.cursor = selected end,
        onSideScroll = function(selected, scrollIndex)
            local row = Menu.rows[selected]
            if not row or row.kind ~= 'list' then return end
            local option = row.options(Menu.text)[scrollIndex]
            if option then apply(selected, row, option.value) end
        end,
        onCheck = function(selected, checked)
            local row = Menu.rows[selected]
            if not row or row.kind ~= 'check' then return end
            apply(selected, row, row.value(checked))
        end,
        options = buildOptions(),
    }, function(selected)
        -- The only row that does anything on a press is Close; the rest are
        -- handled as they are scrolled or ticked.
        if selected > #Menu.rows then Menu.close() end
    end)
end

-- The settings, models and animations the server reported. Called whenever any
-- of them change, open or not.
function Menu.setData(settings, models, anim)
    Menu.settings = type(settings) == 'table' and settings or {}
    Menu.models = type(models) == 'table' and models or {}
    Menu.anim = type(anim) == 'table' and anim or { enabled = false, styles = {} }
    syncOpen()
end

function Menu.isOpen()
    return Menu.open
end

function Menu.close()
    if not Menu.open then return end
    Menu.open = false
    if available() and lib.getOpenMenu() == Menu.id then lib.hideMenu() end
end

function Menu.show()
    if not available() then return false end
    register()
    Menu.open = true
    Menu.cursor = 1
    lib.showMenu(Menu.id)
    return true
end

function Menu.toggle()
    if Menu.open then
        Menu.close()
        return true
    end
    return Menu.show()
end
