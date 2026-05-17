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
    local data = hs.json.decode(content)
    -- מיגרציה מפורמט ישן (רק x, y) לפורמט חדש (slot1 / slot2 / slotHeight)
    if data and data.x and not data.slot1 then
        data = { slot1 = { x = data.x, y = data.y } }
    end
    return data
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
--
-- כיול = רישום מיקום הסלוט הריק.
-- הזרימה: המשתמש מציב את הסמן מעל סלוט אינסרט פנוי, ומקיש ⌘⌥⇧I.
-- אנחנו לוקחים את מיקום הסמן הנוכחי ושומרים אותו יחסית לחלון Cubase.
-- אין צורך ב-eventtap, אין "מצב כיול" עם טיימר - כך השיטה עמידה
-- מול הרשאות חסרות של ניטור קלט / מערכי קליק חריגים.

-- כיול דו-שלבי:
--   קריאה ראשונה  -> שומרת את מיקום סלוט 1.
--   קריאה שנייה   -> שומרת את מיקום סלוט 2, ומחשבת ממנו את גובה הסלוט.
-- בעזרת גובה הסלוט הסקריפט יכול לסרוק את כל הסלוטים ולמצוא את הראשון
-- שמתחת לאחרון שבשימוש.

local function startCalibration()
    if not isCubaseFrontmost() then
        hs.alert.show("פתח את Cubase קודם", 2)
        return
    end

    local win = getCubaseWindow()
    if not win then
        hs.alert.show("חלון Cubase לא נמצא", 2)
        return
    end

    local pos = hs.mouse.absolutePosition()
    local frame = win:frame()
    -- שומרים כמספרים שלמים כדי שמסכי Retina (שמחזירים חצאי-פיקסלים)
    -- לא ייצרו שגיאות %d ב-string.format בהמשך.
    local offset = {
        x = math.floor(pos.x - frame.x + 0.5),
        y = math.floor(pos.y - frame.y + 0.5),
    }

    local existing = loadCalibration()

    if not existing or not existing.slot1 then
        -- שלב 1
        saveCalibration({ slot1 = offset })
        hs.alert.show(
            "✓ שלב 1/2 הושלם.\n\n" ..
            "עכשיו רחף עם העכבר מעל סלוט 2 (האחד מתחת)\n" ..
            "והקש שוב Cmd+⌥+⇧+I",
            8)
    else
        -- שלב 2
        existing.slot2 = offset
        existing.slotHeight = math.abs(offset.y - existing.slot1.y)
        saveCalibration(existing)
        hs.alert.show(
            "✓ כיול הושלם!\n" ..
            "גובה סלוט: " .. tostring(existing.slotHeight) .. "px\n" ..
            "עכשיו Cmd+P יעבוד ויחפש את הסלוט הראשון אחרי האחרון שבשימוש.",
            5)
    end
end

local function resetCalibration()
    os.remove(CALIBRATION_FILE)
    hs.alert.show("✓ הכיול אופס. הקש Cmd+⌥+⇧+I פעמיים לכיול מחדש.", 4)
end

-- --------------------------------------------------- detection of used slots
--
-- בודק אם סלוט אינסרט בקואורדינטות נתונות הוא ריק או בשימוש.
-- ההיוריסטיקה: דוגם רצועה אופקית של פיקסלים מעל הקליק center, ובודק אם
-- כולם בצבע אחיד (= רקע = ריק) או בעלי וריאציה (= יש טקסט/אייקון = בשימוש).

local function isSlotEmpty(screenX, screenY)
    local screen = hs.screen.mainScreen()
    if not screen then return true end

    -- דוגמה: רצועה של 60 פיקסלים אופקיים, 5 פיקסלים מעל המרכז.
    -- הזזה למעלה כדי להתחמק מהטקסט "---" שמופיע באמצע סלוט ריק.
    local img = screen:snapshot(hs.geometry.rect(screenX - 30, screenY - 5, 60, 1))
    if not img then return true end

    local first = img:colorAt({ x = 0, y = 0 })
    if not first then return true end

    local tolerance = 0.05
    for x = 1, 59 do
        local c = img:colorAt({ x = x, y = 0 })
        if c and (math.abs(c.red   - first.red)   > tolerance or
                  math.abs(c.green - first.green) > tolerance or
                  math.abs(c.blue  - first.blue)  > tolerance) then
            return false  -- וריאציה בצבע = יש שם משהו
        end
    end
    return true  -- צבע אחיד = ריק
end

-- מחזירה את הסלוט הראשון אחרי הסלוט האחרון שבשימוש,
-- או nil אם אין כיול מלא.
local function findSlotAfterLastUsed()
    local cal = loadCalibration()
    if not cal or not cal.slot1 or not cal.slotHeight then
        return nil
    end

    local win = getCubaseWindow()
    if not win then return nil end

    local frame = win:frame()
    local baseX = frame.x + cal.slot1.x
    local baseY = frame.y + cal.slot1.y

    -- סורק את כל 16 הסלוטים, זוכר את האינדקס של האחרון שבשימוש
    local lastUsed = -1
    for n = 0, 15 do
        local slotY = baseY + (n * cal.slotHeight)
        if not isSlotEmpty(baseX, slotY) then
            lastUsed = n
        end
    end

    -- היעד הוא הסלוט אחרי האחרון שבשימוש (או 0 אם הכל ריק).
    -- מגביל ל-15 כדי לא לחרוג מ-16 סלוטים.
    local target = math.min(lastUsed + 1, 15)
    local targetY = baseY + (target * cal.slotHeight)
    return hs.geometry.point(baseX, targetY)
end

-- ---------------------------------------------------------- target resolution

-- מחזירה את נקודת המסך שעליה צריך ללחוץ.
-- סדר העדיפויות:
--   1. סריקה חכמה (כיול דו-שלבי + בדיקת פיקסלים) - הסלוט אחרי האחרון בשימוש
--   2. AppleScript Accessibility - אם Cubase חושף את הסלוט הריק
--   3. נפילה לסלוט 1 קבוע (כיול חד-שלבי בלבד)
local function resolveInsertSlotPoint()
    -- 1. סריקה חכמה (דורש כיול דו-שלבי)
    local smart = findSlotAfterLastUsed()
    if smart then return smart, "smart-scan" end

    -- 2. AppleScript
    local axPoint = findInsertViaAccessibility()
    if axPoint then return axPoint, "ax" end

    -- 3. נפילה לסלוט 1 (כיול חד-שלבי בלבד)
    local cal = loadCalibration()
    if cal and cal.slot1 then
        local win = getCubaseWindow()
        if win then
            local f = win:frame()
            return hs.geometry.point(
                f.x + cal.slot1.x,
                f.y + cal.slot1.y), "slot1-fixed"
        end
    end

    return nil, nil
end

-- --------------------------------------------------------- plugin invocation

local function openPlugin(pluginName)
    local target, source = resolveInsertSlotPoint()
    if not target then
        hs.alert.show(
            "צריך לכייל קודם:\n" ..
            "1. רחף מעל סלוט 1 → Cmd+⌥+⇧+I\n" ..
            "2. רחף מעל סלוט 2 → Cmd+⌥+⇧+I (שוב)",
            6)
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
        and "✓ זיהוי AppleScript עובד"
        or  "✗ זיהוי AppleScript לא זמין (לא נורא)")

    local cal = loadCalibration()
    if not cal or not cal.slot1 then
        table.insert(lines, "✗ אין כיול - הקש Cmd+⌥+⇧+I פעמיים")
    elseif not cal.slotHeight then
        table.insert(lines, "⚠ כיול חלקי - יש סלוט 1, חסר סלוט 2")
        table.insert(lines, "  רחף מעל סלוט 2 והקש שוב Cmd+⌥+⇧+I")
    else
        table.insert(lines, "✓ כיול מלא - גובה סלוט: " .. tostring(cal.slotHeight) .. "px")
    end

    -- בודק כמה סלוטים נמצאו בשימוש כרגע
    if cal and cal.slot1 and cal.slotHeight then
        local win = getCubaseWindow()
        if win then
            local frame = win:frame()
            local baseX = frame.x + cal.slot1.x
            local baseY = frame.y + cal.slot1.y
            local usedCount, lastUsed = 0, -1
            for n = 0, 15 do
                local sy = baseY + (n * cal.slotHeight)
                if not isSlotEmpty(baseX, sy) then
                    usedCount = usedCount + 1
                    lastUsed = n
                end
            end
            table.insert(lines,
                "• " .. tostring(usedCount) ..
                " סלוטים בשימוש. הבא יילך לסלוט " ..
                tostring(math.min(lastUsed + 2, 16)))
        end
    end

    table.insert(lines, string.format("• %d קיצורי פלאגינים טעונים", #plugins))

    hs.alert.show(table.concat(lines, "\n"), 8)
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
    hs.alert.show(
        "בדיקה (" .. source .. "): קליק על " ..
        tostring(math.floor(target.x + 0.5)) .. ", " ..
        tostring(math.floor(target.y + 0.5)) ..
        " - סגור את החלון שייפתח", 3)
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
hs.hotkey.bind({ "cmd", "alt", "shift" }, "r", resetCalibration)

hs.alert.show(
    "🎚️ Cubase Shortcuts פעיל\n" ..
    "⌘⌥⇧I = כיול | ⌘⌥⇧D = אבחון | ⌘⌥⇧R = איפוס", 3)
