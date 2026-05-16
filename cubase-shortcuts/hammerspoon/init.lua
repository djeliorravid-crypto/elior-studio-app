-- Cubase Plugin Shortcuts (Hammerspoon)
-- מאזין לקיצורי מקלדת רק כש-Cubase קדמי, ופותח פלאגינים אוטומטית.
--
-- אסטרטגיית זיהוי סלוט אינסרט פנוי, בסדר הזה:
--   1. AppleScript Accessibility - מנסה לחלץ את מיקום הסלוט מעץ ה-UI של Cubase.
--      אם זה עובד - לא צריך כיול בכלל.
--   2. כיול שמור - מיקום שהמשתמש סימן פעם אחת ידנית (יחסי לחלון Cubase).
--   3. הודעת שגיאה ברורה אם שתי השיטות לא זמינות.

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

local function getCubaseApp()
    local app = hs.application.frontmostApplication()
    if not app then return nil end
    return app
end

local function getCubaseWindow()
    local app = getCubaseApp()
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

-- ---------------------------------------------- accessibility-based detection
--
-- מנסה למצוא סלוט אינסרט פנוי דרך AppleScript + Accessibility API של macOS.
-- אם Cubase חושף את הפקדים שלו ל-AX (לא מובטח), זה ימצא את הסלוט אוטומטית
-- ויחזיר את המיקום שלו על המסך, ללא צורך בכיול.
--
-- מחזיר {x, y} אם הצליח, או nil אם לא.

local AX_FINDER_SCRIPT = [[
on run argv
    set targetPattern to item 1 of argv
    tell application "System Events"
        set procs to (every process whose frontmost is true)
        if (count of procs) = 0 then return "NONE"
        set proc to item 1 of procs
        set procName to (name of proc as string)
        if procName does not contain "Cubase" and procName does not contain "Nuendo" then
            return "NOT_CUBASE"
        end if

        try
            -- חיפוש רקורסיבי עם עומק מוגבל למניעת חיפוש אינסופי
            set found to my findEmpty(proc, 0)
            if found is "" then return "NOT_FOUND"
            return found
        on error errMsg
            return "ERROR:" & errMsg
        end try
    end tell
end run

on findEmpty(elem, depth)
    if depth > 12 then return ""
    try
        set r to ""
        try
            set r to (role of elem as string)
        end try
        set d to ""
        try
            set d to (description of elem as string)
        end try
        set n to ""
        try
            set n to (name of elem as string)
        end try
        set v to ""
        try
            set v to (value of elem as string)
        end try

        -- היוריסטיקה: סלוט אינסרט פנוי לרוב מתואר עם "Insert" / "No Effect"
        -- וערך ריק או "No Effect"
        set combined to r & "|" & d & "|" & n & "|" & v
        if combined contains "No Effect" then
            try
                set p to position of elem
                set sz to size of elem
                set cx to (item 1 of p) + ((item 1 of sz) / 2)
                set cy to (item 2 of p) + ((item 2 of sz) / 2)
                return ((cx as integer) as string) & "," & ((cy as integer) as string)
            end try
        end if
    end try

    try
        set kids to UI elements of elem
        repeat with k in kids
            set sub to my findEmpty(k, depth + 1)
            if sub is not "" then return sub
        end repeat
    end try
    return ""
end findEmpty
]]

local function findInsertViaAccessibility()
    -- מריץ עם timeout קצר כדי לא לתקוע את הסקריפט אם AX איטי
    local ok, result = hs.osascript.applescript(AX_FINDER_SCRIPT)
    if not ok or not result then return nil end
    if type(result) ~= "string" then return nil end
    if result == "NONE" or result == "NOT_CUBASE"
       or result == "NOT_FOUND" or result:sub(1,5) == "ERROR" then
        return nil
    end
    local x, y = result:match("^(%-?%d+),(%-?%d+)$")
    if not x or not y then return nil end
    return hs.geometry.point(tonumber(x), tonumber(y))
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
            return false
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

-- ---------------------------------------------------------- target resolution

-- מחזירה את נקודת המסך שעליה צריך ללחוץ, או nil אם אין לנו שום שיטה זמינה.
local function resolveInsertSlotPoint()
    -- 1. ניסיון AX
    local axPoint = findInsertViaAccessibility()
    if axPoint then return axPoint, "ax" end

    -- 2. נפילה לכיול שמור
    local calibration = loadCalibration()
    if calibration then
        local win = getCubaseWindow()
        if win then
            local f = win:frame()
            return hs.geometry.point(f.x + calibration.x, f.y + calibration.y), "calibration"
        end
    end

    return nil, nil
end

-- --------------------------------------------------------- plugin invocation

local function openPlugin(pluginName)
    local target, source = resolveInsertSlotPoint()
    if not target then
        hs.alert.show(
            "אי אפשר למצוא סלוט אינסרט. הקש ⌘⌥⇧I בתוך Cubase כדי לכייל.", 5)
        return
    end

    local origMouse = hs.mouse.absolutePosition()

    -- קליק על הסלוט הפנוי - פותח את חלון בחירת הפלאגין
    hs.eventtap.leftClick(target, 40000)

    -- מחכים שהחלון יופיע ותיבת החיפוש תקבל פוקוס
    hs.timer.usleep(220000)

    -- מקלידים את שם הפלאגין
    hs.eventtap.keyStrokes(pluginName)

    -- מחכים שהחיפוש יתעדכן
    hs.timer.usleep(250000)

    -- Enter -> טוען את התוצאה הראשונה
    hs.eventtap.keyStroke({}, "return")

    -- מחזירים את העכבר למיקומו המקורי
    hs.timer.doAfter(0.5, function()
        hs.mouse.absolutePosition(origMouse)
    end)
end

-- ---------------------------------------------------------------- diagnostics

local function runDiagnostics()
    local lines = { "🔍 Cubase Shortcuts - אבחון:" }

    table.insert(lines, isCubaseFrontmost()
        and "✓ Cubase קדמי"
        or  "✗ Cubase לא קדמי - פתח אותו ונסה שוב")

    local axPoint = findInsertViaAccessibility()
    table.insert(lines, axPoint
        and string.format("✓ זיהוי אוטומטי עובד! סלוט ב-%d, %d",
                          axPoint.x, axPoint.y)
        or  "✗ זיהוי אוטומטי לא זמין (לא נורא - יש כיול)")

    local calibration = loadCalibration()
    table.insert(lines, calibration
        and string.format("✓ כיול שמור: %d, %d", calibration.x, calibration.y)
        or  "✗ אין כיול שמור - הקש ⌘⌥⇧I")

    table.insert(lines, string.format("• %d קיצורי פלאגינים טעונים", #plugins))

    hs.alert.show(table.concat(lines, "\n"), 7)
end

-- מצב בדיקה: רק לוחץ על המיקום שזוהה, בלי להקליד כלום.
-- מאפשר לוודא שהזיהוי מצביע למקום הנכון, בלי "לזהם" את הפרויקט.
local function testClick()
    if not isCubaseFrontmost() then
        hs.alert.show("פתח את Cubase קודם", 2)
        return
    end
    local target, source = resolveInsertSlotPoint()
    if not target then
        hs.alert.show("אין כיול ואין זיהוי אוטומטי. הקש ⌘⌥⇧I לכיול.", 4)
        return
    end
    hs.alert.show(string.format("בדיקה (%s): קליק על %d, %d - סגור את החלון שייפתח",
                                source, target.x, target.y), 3)
    hs.eventtap.leftClick(target, 40000)
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
                return true
            end
        end
        return false
    end
)
pluginTap:start()

-- קיצורים גלובליים (פעילים בכל אפליקציה - אבל פעולותיהם בודקות אם Cubase קדמי)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "i", startCalibration)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "d", runDiagnostics)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "t", testClick)

hs.alert.show("🎚️ Cubase Shortcuts פעיל\n⌘⌥⇧D = אבחון", 3)
