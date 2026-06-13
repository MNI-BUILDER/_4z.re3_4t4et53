-- GROW A GARDEN 2 MONITOR - SeedShop + UI-based Weather, /api/data2, single-pass scraping
print("🌱 Starting GaG2 Monitor (SeedShop + Weather) with single-pass scraping...")

-- Configuration
local API_ENDPOINT = "http://204.12.233.39:3000/api/data2"
local DELETE_ENDPOINT = "http://204.12.233.39:3000/api/data2"
local API_KEY = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

local HttpService = game:GetService("HttpService")
local LocalPlayer = game.Players.LocalPlayer

-- Session and Cache
local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    currentWeather = "None",
    weatherDuration = 0,
    seeds = {}
}

-- UI element patterns to ignore
local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding",
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint",
    "u: ", "shadow", "bevel"
}

local function shouldIgnoreItem(itemName)
    local lowerName = string.lower(itemName)
    for _, pattern in ipairs(IGNORE_PATTERNS) do
        if lowerName:match(pattern) then return true end
    end
    return false
end

-- Discord notification
local function sendToDiscord(content, isError)
    pcall(function()
        local message = {
            content = isError and "💥 **ERROR**" or "📊 **UPDATE**",
            embeds = {{
                description = content,
                color = isError and 16711680 or 65280,
                footer = {text = "Session: " .. Cache.sessionId},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(message)
        })
    end)
end

-- AUTO-DELETE function
local function autoDeleteOnCrash()
    pcall(function()
        request({
            Url = DELETE_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode({
                action = "DELETE_ALL",
                sessionId = Cache.sessionId,
                playerName = LocalPlayer.Name,
                timestamp = os.time()
            })
        })
    end)
end

-- Find the scroll container inside a shop UI, class-agnostic.
-- GaG2 path: SeedShop.Frame.NormalShop  (NormalShop may be Frame OR ScrollingFrame)
local function findContainer(shopUI)
    local frame = shopUI:FindFirstChild("Frame")
    if frame then
        local normal = frame:FindFirstChild("NormalShop")
        if normal then return normal end
        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("ScrollingFrame") then return child end
        end
    end
    for _, child in ipairs(shopUI:GetDescendants()) do
        if child:IsA("ScrollingFrame") or child.Name == "ContentFrame" or child.Name == "NormalShop" then
            return child
        end
    end
    return nil
end

-- Pull the stock number out of an item frame (digs through Main_Frame etc.)
local function readStock(itemFrame)
    for _, desc in ipairs(itemFrame:GetDescendants()) do
        if desc:IsA("TextLabel")
            and (desc.Name == "Stock_Text" or desc.Name == "STOCK_TEXT") then
            return tonumber(desc.Text:match("%d+")) or 0
        end
    end
    return 0
end

-- SINGLE-PASS scrape: walk the container's item children ONCE.
local function collectShop(shopName)
    local result = {}
    local ok = pcall(function()
        local shopUI = LocalPlayer.PlayerGui:FindFirstChild(shopName)
        if not shopUI then return end
        local container = findContainer(shopUI)
        if not container then return end

        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Frame") and not shouldIgnoreItem(item.Name) then
                result[item.Name] = readStock(item)
            end
        end
    end)
    if not ok then return {} end
    return result
end

-- WEATHER (GaG2) - read which frame under WeatherUI.Frame is Visible
local function getActiveWeather()
    local active = {}
    pcall(function()
        local weatherUI = LocalPlayer.PlayerGui:FindFirstChild("WeatherUI")
        if not weatherUI then return end
        local frame = weatherUI:FindFirstChild("Frame")
        if not frame then return end

        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("Frame") and not shouldIgnoreItem(child.Name) and child.Visible then
                table.insert(active, child.Name)
            end
        end
    end)

    if #active == 0 then return "None" end
    return table.concat(active, ", ")
end

-- COLLECT ALL DATA
local function collectAllData()
    local seeds = collectShop("SeedShop")
    local weather = getActiveWeather()

    local data = {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        weather = {type = weather, duration = 0},
        seeds = seeds
    }

    Cache.currentWeather = weather

    local count = 0
    for _ in pairs(seeds) do count = count + 1 end
    print("📊 DATA FOUND: Seeds:" .. (count > 0 and (count .. " items") or "NONE")
        .. " | Weather:" .. weather)

    return data
end

-- SEND TO API
local function sendToAPI(data)
    local success = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        request({
            Url = API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Update-Number"] = tostring(Cache.updateCounter)
            },
            Body = HttpService:JSONEncode(data)
        })
    end)
    print(success and ("✅ API UPDATE #" .. Cache.updateCounter)
                  or ("❌ API FAILED #" .. Cache.updateCounter))
    return success
end

-- HEARTBEAT
local function sendHeartbeat()
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat",
            Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = HttpService:JSONEncode({
                sessionId = Cache.sessionId,
                status = "ALIVE",
                timestamp = os.time()
            })
        })
    end)
end

-- CHANGE DETECTION
local function hasChanges(oldData, newData)
    if oldData.weather.type ~= newData.weather.type then return true end
    for name, stock in pairs(newData.seeds) do
        if oldData.seeds[name] ~= stock then return true end
    end
    for name in pairs(oldData.seeds) do
        if newData.seeds[name] == nil then return true end
    end
    return false
end

-- SETUP
local function setupCrashDetection()
    LocalPlayer.AncestryChanged:Connect(function()
        if not LocalPlayer.Parent then
            autoDeleteOnCrash()
        end
    end)
end

local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- MAIN
local function startMonitoring()
    print("🌱 GaG2 MONITOR STARTED | /api/data2 | Session: " .. Cache.sessionId)

    setupAntiAFK()
    setupCrashDetection()

    local initialData = collectAllData()
    Cache.seeds = initialData.seeds
    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()

    sendToAPI(initialData)
    sendHeartbeat()
    print("🚀 MONITORING LOOP STARTED")

    while true do
        local success, currentData = pcall(collectAllData)
        if success then
            local now = os.time()
            local oldData = {
                weather = {type = Cache.currentWeather, duration = Cache.weatherDuration},
                seeds = Cache.seeds
            }
            local changes = hasChanges(oldData, currentData)

            if sendToAPI(currentData) then
                Cache.seeds = currentData.seeds
                if changes then print("🔄 CHANGES DETECTED & SENT") end
            end

            if (now - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat(); Cache.lastHeartbeat = now
            end
            if (now - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
                sendToDiscord("📊 GaG2 Monitor running - Update #" .. Cache.updateCounter, false)
                Cache.lastDiscordUpdate = now
            end
        else
            print("❌ ERROR:", currentData)
            autoDeleteOnCrash()
            break
        end
        wait(CHECK_INTERVAL)
    end
end

startMonitoring()
