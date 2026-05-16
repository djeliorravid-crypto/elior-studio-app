-- Cubase Plugin Shortcuts (Hammerspoon)
-- מאזין לקיצורי מקלדת רק כש-Cubase קדמי, ופותח פלאגינים אוטומטית
-- באמצעות קליק על סלוט אינסרט פנוי + הקלדה של שם הפלאגין.

local plugins = require("plugins")

local CALIBRATION_FILE = os.getenv("HOME") .. "/.hammerspoon/cubase_calibration.json"
local CUBASE_PATTERNS  = { "cubase", "nuendo" }

-- ---------------------------------------------------------------- utilities

local function isCubaseFrontmost()
    local app = hs.application.frontmostApplication()
    if not app then return false end
    local name = app:name():lower()
    for _, pattern in ipairs(CUBASE_PATTERNS) do
        if name:find(pattern, 1, true) then return true end
    end
    return false
end

local function getCubaseWindow()
    local app = hs.application.frontmostApplication()
    if not app then return nil end
    return app:focusedWindow() or app:mainWindow()
end

local function loadCalibration()
    local f = io.open(CALIBRATION_FILE, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return nil end
    return hs.json.decode(content)
end

local function saveCalibration(data)
    local f = io.open(CALIBRATION_FILE, "w")
    if not f then return false end
    f:write(hs.json.encode(data))
    f:close()
    return true
end

-- --------------------------------------------------------------- calibration

local calibrationTap   = nil
local calibrationTimer = nil

local function cancelCalibration()
    if calibrationTap   then calibrationTap:stop();   calibrationTap   = nil end
    if calibrationTimer then calibrationTimer:stop(); calibrationTimer = nil end
end

local function startCalibration()
    if not isCubaseFrontmost() then
        hs.alert.show("פתח את Cubase קודם", 2)
        return
    end

    cancelCalibration()
    hs.alert.show("מצב כיול: לחץ עם העכבר על סלוט אינסרט פנוי (10 שניות)", 4)

    calibrationTap = hs.eventtap.new(
        { hs.eventtap.event.types.leftMouseDown },
        function(event)
            local pos = event:location()
            local win = getCubaseWindow()
            if not win then
                hs.alert.show("חלון Cubase לא נמצא", 2)
                cancelCalibration()
                return false
            end
            local frame = win:frame()
            local offset = {
                x = pos.x - frame.x,
                y = pos.y - frame.y,
            }
            saveCalibration(offset)
            hs.alert.show(
                string.format("✓ נשמר. סלוט: %d, %d מפינת חלון Cubase",
                              offset.x, offset.y), 3)
            cancelCalibration()
            return false  -- מאפשר לקליק לעבור הלאה לאפליקציה
        end
    )
    calibrationTap:start()

    calibrationTimer = hs.timer.doAfter(10, function()
        if calibrationTap then
            hs.alert.show("הכיול בוטל - לא בוצעה לחיצה", 2)
            cancelCalibration()
        end
    end)
end

-- --------------------------------------------------------- plugin invocation

local function openPlugin(pluginName)
    local calibration = loadCalibration()
    if not calibration then
        hs.alert.show("עוד לא כייל. הקש ⌘⌥⇧I בתוך Cubase לכיול ראשוני", 4)
        return
    end

    local win = getCubaseWindow()
    if not win then
        hs.alert.show("חלון Cubase לא נמצא", 2)
        return
    end

    local frame = win:frame()
    local target = hs.geometry.point(
        frame.x + calibration.x,
        frame.y + calibration.y
    )

    local origMouse = hs.mouse.absolutePosition()

    -- קליק על הסלוט הפנוי - פותח את חלון בחירת הפלאגין
    hs.eventtap.leftClick(target, 40000)

    -- מחכים שהחלון יופיע ותיבת החיפוש תקבל פוקוס
    hs.timer.usleep(220000)  -- 220ms

    -- מקלידים את שם הפלאגין
    hs.eventtap.keyStrokes(pluginName)

    -- מחכים שהחיפוש יתעדכן
    hs.timer.usleep(250000)  -- 250ms

    -- Enter -> טוען את התוצאה הראשונה
    hs.eventtap.keyStroke({}, "return")

    -- מחזירים את העכבר למיקום המקורי כדי שלא יישאר מודבק על הסלוט
    hs.timer.doAfter(0.5, function()
        hs.mouse.absolutePosition(origMouse)
    end)
end

-- -------------------------------------------------------- hotkey dispatching

local function flagsMatch(eventFlags, mods)
    local want = { cmd = false, alt = false, shift = false, ctrl = false }
    for _, m in ipairs(mods) do want[m] = true end
    return (eventFlags.cmd   == true) == want.cmd
       and (eventFlags.alt   == true) == want.alt
       and (eventFlags.shift == true) == want.shift
       and (eventFlags.ctrl  == true) == want.ctrl
end

-- eventtap אחד שמטפל בכל הפלאגינים. הוא בולע את הקיצור רק כש-Cubase קדמי,
-- כך שבכל אפליקציה אחרת הקיצור (למשל Cmd+P = הדפס) ממשיך לעבוד רגיל.
local pluginTap = hs.eventtap.new(
    { hs.eventtap.event.types.keyDown },
    function(event)
        if not isCubaseFrontmost() then return false end

        local keyCode = event:getKeyCode()
        local flags   = event:getFlags()

        for _, plugin in ipairs(plugins) do
            local wantCode = hs.keycodes.map[plugin.key]
            if wantCode == keyCode and flagsMatch(flags, plugin.mods) then
                hs.timer.doAfter(0, function()
                    openPlugin(plugin.name)
                end)
                return true  -- בולע את הקיצור
            end
        end
        return false
    end
)
pluginTap:start()

-- קיצור כיול: ⌘⌥⇧I (גלובלי, פעיל רק כש-Cubase קדמי)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "i", startCalibration)

hs.alert.show("🎚️ Cubase Shortcuts פעיל", 2)
