--========================================================--
-- Pilgrammed: Shop module (UMU)
-- Первый список - магазины, второй - товары выбранного магазина.
-- Кнопка покупки использует ту же команду, что и окно магазина в игре
-- (Remotes.Buy), с теми же ограничениями: количество больше 1 только для материалов.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local COLOR_OK = Color3.fromRGB(0, 255, 0)
local COLOR_BAD = Color3.fromRGB(255, 100, 100)
local COLOR_WAIT = Color3.fromRGB(255, 255, 0)
local COLOR_INFO = Color3.fromRGB(0, 200, 255)

local MAX_COST_LINES = 7

local function safeRequire(name)
    local ok, mod = pcall(function()
        return require(ReplicatedStorage:WaitForChild(name, 5))
    end)
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

-- Сколько у игрока нужного ресурса. Правила те же, что в ShopItems.CanBuy.
local function haveAmount(materials, resource, kind)
    if resource == "Gold" then
        local ok, value = pcall(function()
            return player.PlayerStats.Gold.Value
        end)
        return ok and value or 0
    end
    if kind == "Material" or kind == "Materials" then
        if materials and type(materials.GetMaterialCount) == "function" then
            local ok, count = pcall(materials.GetMaterialCount, player, resource)
            if ok and type(count) == "number" then
                return count
            end
        end
        return 0
    end
    if kind then
        local ok, found = pcall(function()
            local folder = player:FindFirstChild(kind)
            return folder and folder:FindFirstChild(resource) ~= nil
        end)
        return (ok and found) and 1 or 0
    end
    return 0
end

return function(Window, meta)

    local Tab = Window:CreateTab({
        Name = "Shop",
        Icon = "🛒",
        Order = (meta and meta.Order) or 20,
    })

    local ShopItems = safeRequire("ShopItems")
    local MaterialsModule = safeRequire("MaterialsModule")
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

    local Section = Tab:CreateSection({ Name = "Покупка" })

    if not ShopItems then
        Section:AddLabel({ Text = "⚠️ Модуль ShopItems не найден" })
        return
    end

    local selectedShop = nil
    local selectedItem = nil
    local quantityText = "1"

    ------------------------------------------------------------
    -- Списки
    ------------------------------------------------------------

    local function shopKeys()
        local seen, keys = {}, {}
        for key in pairs(ShopItems.Shops or {}) do
            if not seen[key] then
                seen[key] = true
                table.insert(keys, key)
            end
        end
        local folder = ReplicatedStorage:FindFirstChild("Shops")
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if not seen[child.Name] then
                    seen[child.Name] = true
                    table.insert(keys, child.Name)
                end
            end
        end
        table.sort(keys)
        return keys
    end

    local function itemsOf(shop)
        local names = {}
        local ok, list = pcall(ShopItems.GetShop, shop)
        if ok and type(list) == "table" then
            for _, entry in ipairs(list) do
                local name = typeof(entry) == "Instance" and entry.Name or (type(entry) == "string" and entry or nil)
                if name then
                    table.insert(names, name)
                end
            end
        end
        return names
    end

    local function entryOf(item)
        return item and ShopItems.Dictionary and ShopItems.Dictionary[item] or nil
    end

    local function quantity()
        local entry = entryOf(selectedItem)
        if not entry or entry.Type ~= "Material" then
            return 1
        end
        local n = math.floor(tonumber(quantityText) or 1)
        return math.clamp(n, 1, 250)
    end

    ------------------------------------------------------------
    -- Стоимость
    ------------------------------------------------------------

    local ResultLabel
    local GoldLabel
    local GoldLeftLabel
    local CostLabels = {}

    local function computeCost()
        local entry = entryOf(selectedItem)
        if not entry or type(entry.Cost) ~= "table" then
            return nil
        end
        local qty = quantity()
        local lines, gold, affordable = {}, 0, true
        for _, cost in ipairs(entry.Cost) do
            local resource = cost[1]
            local need = math.max(math.round((tonumber(cost[2]) or 0)), 1) * qty
            local have = haveAmount(MaterialsModule, resource, cost[3])
            local ok = have >= need
            if resource == "Gold" then
                gold = gold + need
            end
            affordable = affordable and ok
            table.insert(lines, { name = resource, need = need, have = have, ok = ok, isGold = resource == "Gold", kind = cost[3] })
        end
        return { entry = entry, qty = qty, lines = lines, gold = gold, affordable = affordable }
    end

    local function refresh()
        local info = computeCost()
        if not info then
            GoldLabel:SetText("Спишется золота: —")
            GoldLabel:SetColor(COLOR_INFO)
            GoldLeftLabel:SetText("Золота у тебя: —")
            for _, label in ipairs(CostLabels) do
                label:SetText(" ")
            end
            return
        end

        local haveGold = haveAmount(MaterialsModule, "Gold")
        GoldLabel:SetText(string.format("Спишется золота: %d", info.gold))
        GoldLabel:SetColor(info.gold <= haveGold and COLOR_OK or COLOR_BAD)
        GoldLeftLabel:SetText(string.format("Золота у тебя: %d → останется %d", haveGold, haveGold - info.gold))
        GoldLeftLabel:SetColor(haveGold - info.gold >= 0 and COLOR_INFO or COLOR_BAD)

        local shown = 0
        for _, line in ipairs(info.lines) do
            if not line.isGold then
                shown = shown + 1
                local label = CostLabels[shown]
                if label then
                    label:SetText(string.format("%s %s: нужно %d, у тебя %d", line.ok and "✅" or "❌", line.name, line.need, line.have))
                    label:SetColor(line.ok and COLOR_OK or COLOR_BAD)
                end
            end
        end
        for i = shown + 1, #CostLabels do
            CostLabels[i]:SetText(" ")
        end
    end

    ------------------------------------------------------------
    -- Интерфейс
    ------------------------------------------------------------

    local ItemDropdown

    local ShopDropdown = Section:AddDropdown({
        Text = "Магазин",
        Options = shopKeys(),
        Callback = function(value)
            if value ~= selectedShop then
                selectedShop = value
                local names = itemsOf(value)
                pcall(function()
                    ItemDropdown:SetValues(names)
                    ItemDropdown:SetValue(names[1])
                end)
                selectedItem = names[1]
                refresh()
            end
        end
    })

    ItemDropdown = Section:AddDropdown({
        Text = "Товар",
        Options = {},
        Callback = function(value)
            selectedItem = value
            refresh()
        end
    })

    Section:AddTextbox({
        Text = "Количество (больше 1 только для материалов)",
        Default = "1",
        Placeholder = "1",
        Callback = function(text)
            quantityText = tostring(text or "1")
            refresh()
        end
    })

    ResultLabel = Section:AddLabel({ Text = "Результат: —" })

    Section:AddButton({
        Text = "🛒 Купить",
        Callback = function()
            local info = computeCost()
            if not selectedItem or not info then
                ResultLabel:SetText("Результат: сначала выбери магазин и товар")
                ResultLabel:SetColor(COLOR_WAIT)
                return
            end
            if not info.affordable then
                local missing = {}
                for _, line in ipairs(info.lines) do
                    if not line.ok then
                        table.insert(missing, line.name)
                    end
                end
                ResultLabel:SetText("Результат: не хватает — " .. table.concat(missing, ", "))
                ResultLabel:SetColor(COLOR_BAD)
                return
            end
            local buy = Remotes and Remotes:FindFirstChild("Buy")
            if not buy or not buy:IsA("RemoteFunction") then
                ResultLabel:SetText("Результат: команда покупки не найдена")
                ResultLabel:SetColor(COLOR_BAD)
                return
            end

            local item, qty = selectedItem, info.qty
            task.spawn(function()
                local ok, result = pcall(function()
                    return buy:InvokeServer(item, qty)
                end)
                if ok and result then
                    ResultLabel:SetText(string.format("Результат: куплено %s x%d", item, qty))
                    ResultLabel:SetColor(COLOR_OK)
                else
                    ResultLabel:SetText("Результат: сервер отказал (" .. item .. ")")
                    ResultLabel:SetColor(COLOR_BAD)
                end
                task.wait(0.3)
                refresh()
            end)
        end
    })

    Section:AddSeparator({ Text = "Стоимость" })

    GoldLabel = Section:AddLabel({ Text = "Спишется золота: —" })
    GoldLeftLabel = Section:AddLabel({ Text = "Золота у тебя: —" })
    for i = 1, MAX_COST_LINES do
        CostLabels[i] = Section:AddLabel({ Text = " " })
    end

    local GuildNote = Section:AddLabel({ Text = " " })

    local function updateNote()
        local entry = entryOf(selectedItem)
        if entry and type(entry.Info) == "table" and entry.Info.Guild then
            GuildNote:SetText("⚠️ Гильдейская скидка не учтена, реальная цена может быть ниже")
            GuildNote:SetColor(COLOR_WAIT)
        else
            GuildNote:SetText(" ")
        end
    end

    -- Золото и материалы меняются: обновляем строки стоимости
    pcall(function()
        player.PlayerStats.Gold.Changed:Connect(function()
            refresh()
        end)
    end)

    local baseRefresh = refresh
    refresh = function()
        baseRefresh()
        updateNote()
    end

    -- Первый магазин выбран сразу
    task.defer(function()
        local keys = shopKeys()
        if keys[1] then
            selectedShop = keys[1]
            local names = itemsOf(keys[1])
            pcall(function()
                ShopDropdown:SetValue(keys[1])
                ItemDropdown:SetValues(names)
                ItemDropdown:SetValue(names[1])
            end)
            selectedItem = names[1]
            refresh()
        end
    end)
end
