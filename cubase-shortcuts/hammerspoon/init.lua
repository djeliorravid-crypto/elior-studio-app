-- Cubase Plugin Shortcuts (Hammerspoon) - גרסה מבוססת זיהוי צבע
--
-- הרעיון: בקיובייס, סלוטי אינסרט פעילים מוצגים ברקע ציאן/כחול בהיר
-- (כמו "Delay BRIGADE" בסקרין-שוט שלך). הסקריפט סורק את האזור מתחת
-- לנקודת הכיול ומחפש את ה-ROW הכי נמוך עם הרבה פיקסלי ציאן - זה
-- האינסרט האחרון בשימוש. ואז לוחץ קצת מתחתיו (= הסלוט הריק הבא).
--
-- יתרון: לא תלוי בגובה סלוט קבוע, לא נופל לקטעים אחרים באינספקטור
-- (שאינם בצבע ציאן).
--
-- כיול: פעם אחת. רחף עם העכבר מעל מקום *כלשהו* באזור האינסרטים -
-- עדיף בסלוט הראשון מלמעלה - והקש Cmd+⌥+⇧+I.

local plugins = require("plugins")

local CALIBRATION_FILE  = os.getenv("HOME") .. "/.hammerspoon/cubase_calibration.json"
local CUBASE_PATTERNS   = { "cubase", "nuendo" }

-- פרמטרי סריקה
local SCAN_HEIGHT       = 400  -- מספר פיקסלים לסרוק מתחת לנקודת הכיול
local SCAN_WIDTH        = 100  -- רוחב פס הסריקה
local MIN_CYAN_PER_ROW  = 8    -- מינימום פיקסלי ציאן בשורה כדי לחשב כ"פעיל"
local CLICK_BELOW       = 22   -- כמה פיקסלים מתחת לציאן האחרון ללחוץ
local START_OFFSET_Y    = 8    -- מתחילים לסרוק קצת מתחת לכיול
                                 -- (כדי לא לתפוס את האייקון הקטן בכותרת)

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

-- מחזיר את חלון הפרויקט הראשי של Cubase.
-- חשוב להשתמש ב-mainWindow ולא ב-focusedWindow כי אחרי שטוענים
-- פלאגין, חלון הפלאגין מקבל פוקוס - והקואורדינטות שמורות יחסית
-- לחלון הפרויקט, לא לחלון הפלאגין.
local function getCubaseWindow()
    local app = hs.application.frontmostApplication()
    if not app then return nil end
    -- מחפשים את החלון הראשי - העדפה ל-mainWindow, ואחר כך לחלון הגדול ביותר
    local mainWin = app:mainWindow()
    if mainWin then return mainWin end

    -- fallback: החלון הכי גדול (לרוב הפרויקט)
    local windows = app:visibleWindows()
    local largest, largestArea = nil, 0
    for _, w in ipairs(windows) do
        local f = w:frame()
        local area = f.w * f.h
        if area > largestArea then
            largest = w
            largestArea = area
        end
    end
    return largest or app:focusedWindow()
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
    saveCalibration({
        x = math.floor(pos.x - frame.x + 0.5),
        y = math.floor(pos.y - frame.y + 0.5),
    })
    hs.alert.show(
        "✓ כיול נשמר.\n" ..
        "מעכשיו Cmd+P יחפש אינסרט פעיל מתחת לנקודה זו\n" ..
        "ויטען את הפלאגין מיד אחריו.",
        5)
end

local function resetCalibration()
    os.remove(CALIBRATION_FILE)
    hs.alert.show("✓ הכיול אופס. הקש Cmd+⌥+⇧+I לכייל מחדש.", 3)
end

-- ---------------------------------------------------------- color detection

-- "ציאן" = רקע של אינסרט פעיל בקיובייס.
-- אדום נמוך, ירוק בינוני-גבוה, כחול גבוה.
local function isPixelCyan(c)
    if not c then return false end
    return c.red < 0.50 and c.green > 0.50 and c.blue > 0.62
end

local function countCyanInRow(img, y, width)
    local count = 0
    for x = 0, width - 1 do
        if isPixelCyan(img:colorAt({ x = x, y = y })) then
            count = count + 1
        end
    end
    return count
end

-- מחזיר את ה-Y (יחסי לפנים החלון של Cubase) של האינסרט הפעיל הכי נמוך,
-- או nil אם אין שום אינסרט פעיל.
local function findLastActiveInsertY()
    local cal = loadCalibration()
    if not cal or not cal.x or not cal.y then return nil end

    local win = getCubaseWindow()
    if not win then return nil end

    local frame = win:frame()
    local startX = frame.x + cal.x - (SCAN_WIDTH / 2)
    local startY = frame.y + cal.y + START_OFFSET_Y

    local screen = hs.screen.mainScreen()
    local img = screen:snapshot(hs.geometry.rect(
        startX, startY, SCAN_WIDTH, SCAN_HEIGHT))
    if not img then return nil end

    -- סורק מלמטה למעלה. מוצא את השורה התחתונה ביותר שעדיין ציאן.
    -- (אבל קודם, מוצא בכלל אם יש ציאן.)
    local bottomCyan = nil
    for y = SCAN_HEIGHT - 1, 0, -1 do
        if countCyanInRow(img, y, SCAN_WIDTH) >= MIN_CYAN_PER_ROW then
            bottomCyan = y
            break
        end
    end

    if not bottomCyan then return nil end

    -- אופציונלי: ממשיכים מטה כל עוד יש ציאן (אם הציאן ממשיך עוד)
    -- לא רלוונטי כי כבר התחלנו מלמטה. bottomCyan הוא כבר הסוף.
    return startY + bottomCyan
end

-- ---------------------------------------------------------- target resolution

local function resolveClickPoint()
    local cal = loadCalibration()
    if not cal or not cal.x or not cal.y then return nil, "no-cal" end

    local win = getCubaseWindow()
    if not win then return nil, "no-window" end

    local frame = win:frame()
    local baseX = frame.x + cal.x

    local lastCyanY = findLastActiveInsertY()
    if lastCyanY then
        -- יש אינסרטים פעילים - לחיצה מיד אחרי הציאן האחרון
        return hs.geometry.point(baseX, lastCyanY + CLICK_BELOW), "below-cyan"
    end

    -- אין אינסרטים פעילים - לחיצה על נקודת הכיול (סלוט 1)
    return hs.geometry.point(baseX, frame.y + cal.y), "slot-1"
end

-- --------------------------------------------------------- plugin invocation

local function openPlugin(pluginName)
    -- שלב 1: מביאים את חלון הפרויקט לקדמה.
    -- חיוני! אחרי שטוענים פלאגין, ה-GUI של הפלאגין נפתח ולעיתים
    -- מכסה חלקית את אזור האינסרטים. אם ה-GUI של הפלאגין (למשל
    -- Pro-Q 4) כולל הרבה כחול, הסקנר ימצא שם ציאן ויקליק במקום
    -- הלא נכון. הבאת חלון הפרויקט לקדמה מסתירה את ה-GUI מאחור.
    local app = hs.application.frontmostApplication()
    if app then
        local mainWin = app:mainWindow()
        if mainWin and not mainWin:isStandard() then
            -- ייתכן שה-mainWindow הוא כעת חלון פלאגין; נחפש את החלון
            -- הראשי בכל החלונות הסטנדרטיים של Cubase
            local windows = app:visibleWindows()
            local largest, largestArea = nil, 0
            for _, w in ipairs(windows) do
                if w:isStandard() then
                    local f = w:frame()
                    local area = f.w * f.h
                    if area > largestArea then
                        largest, largestArea = w, area
                    end
                end
            end
            mainWin = largest
        end
        if mainWin then
            mainWin:focus()
            hs.timer.usleep(250000)  -- 250ms שהפוקוס יתפוס
        end
    end

    -- שלב 2: עכשיו (כש-GUIs של פלאגינים מאחור) סורקים ולוחצים
    local target, source = resolveClickPoint()
    if not target then
        hs.alert.show("צריך לכייל. הקש Cmd+⌥+⇧+I בתוך Cubase.", 4)
        return
    end

    local origMouse = hs.mouse.absolutePosition()

    hs.eventtap.leftClick(target, 40000)
    hs.timer.usleep(220000)

    -- מנקים את שדה החיפוש (קיובייס לפעמים שומר את החיפוש הקודם
    -- שמוביל ל-"Pro-Q 4Pro-Q 4" בהקלדה השנייה)
    hs.eventtap.keyStroke({ "cmd" }, "a")
    hs.timer.usleep(40000)
    hs.eventtap.keyStroke({}, "delete")
    hs.timer.usleep(40000)

    hs.eventtap.keyStrokes(pluginName)
    hs.timer.usleep(250000)
    hs.eventtap.keyStroke({}, "return")

    hs.timer.doAfter(0.5, function()
        hs.mouse.absolutePosition(origMouse)
    end)
end

-- ---------------------------------------------------------------- diagnostics

local function runDiagnostics()
    local lines = { "🔍 Cubase Shortcuts - אבחון:" }

    table.insert(lines, isCubaseFrontmost()
        and "✓ Cubase קדמי"
        or  "✗ Cubase לא קדמי")

    local cal = loadCalibration()
    if not cal or not cal.x then
        table.insert(lines, "✗ אין כיול - הקש Cmd+⌥+⇧+I")
    else
        table.insert(lines, "✓ כיול: " .. tostring(cal.x) .. ", " .. tostring(cal.y))
        local target, source = resolveClickPoint()
        if target then
            if source == "below-cyan" then
                table.insert(lines, "✓ נמצא אינסרט פעיל - יילחץ מתחתיו")
            else
                table.insert(lines, "• אין אינסרטים פעילים - יילחץ על סלוט 1")
            end
        end
    end

    table.insert(lines, "• " .. tostring(#plugins) .. " קיצורי פלאגינים")
    hs.alert.show(table.concat(lines, "\n"), 7)
end

-- מצב בדיקה - לחיצה בלי הקלדה
local function testClick()
    if not isCubaseFrontmost() then
        hs.alert.show("פתח את Cubase קודם", 2)
        return
    end
    local target = resolveClickPoint()
    if not target then
        hs.alert.show("אין כיול - הקש Cmd+⌥+⇧+I", 3)
        return
    end
    hs.alert.show("בדיקה: לוחץ על המיקום שזוהה. סגור את החלון שייפתח.", 3)
    hs.eventtap.leftClick(target, 40000)
end

-- -------------------------------------------------------- hotkey dispatching
--
-- משתמשים ב-hs.hotkey (Carbon HotKey API) במקום ב-eventtap.
-- hs.hotkey דורש רק הרשאת Accessibility, בעוד ש-eventtap לפעמים
-- דורש גם "ניטור קלט". מפעילים/מכבים את קיצורי הפלאגינים לפי
-- האם Cubase קדמי, כדי שהם לא ייתפסו באפליקציות אחרות.

local pluginHotkeys = {}
for _, plugin in ipairs(plugins) do
    table.insert(pluginHotkeys, hs.hotkey.new(plugin.mods, plugin.key, function()
        local ok, err = pcall(openPlugin, plugin.name)
        if not ok then
            hs.alert.show("שגיאה ב-openPlugin: " .. tostring(err), 4)
        end
    end))
end

local function enablePluginHotkeys()
    for _, hk in ipairs(pluginHotkeys) do hk:enable() end
end

local function disablePluginHotkeys()
    for _, hk in ipairs(pluginHotkeys) do hk:disable() end
end

local function nameMatchesCubase(name)
    if not name then return false end
    local lower = name:lower()
    for _, pattern in ipairs(CUBASE_PATTERNS) do
        if lower:find(pattern, 1, true) then return true end
    end
    return false
end

-- Watcher: מאפשר את הקיצורים רק כשעוברים ל-Cubase, ומכבה כשעוזבים
local appWatcher = hs.application.watcher.new(function(name, eventType)
    if eventType == hs.application.watcher.activated then
        if nameMatchesCubase(name) then
            enablePluginHotkeys()
        else
            disablePluginHotkeys()
        end
    end
end)
appWatcher:start()

-- מצב התחלתי: אם Cubase כבר קדמי בעת טעינת הסקריפט
if isCubaseFrontmost() then enablePluginHotkeys() end

-- קיצורי עזר (גלובליים, פעילים תמיד)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "i", startCalibration)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "d", runDiagnostics)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "t", testClick)
hs.hotkey.bind({ "cmd", "alt", "shift" }, "r", resetCalibration)

hs.alert.show(
    "🎚️ Cubase Shortcuts פעיל\n" ..
    "⌘⌥⇧I = כיול | ⌘⌥⇧D = אבחון | ⌘⌥⇧T = טסט | ⌘⌥⇧R = איפוס", 3)
