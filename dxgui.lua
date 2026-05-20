local dui = nil
local activeMenu = {}
local activeIndex = 1

table.insert(activeMenu, {
    type = 'submenu',            
    label = 'Test Main Menu',    
    tabs = {
        {
            name = 'test',
            label = 'test_tab', 
            submenu = {
                {
                    type = 'button',
                    label = 'Test Button',
                    onConfirm = function()
                        print('Test Button Pressed')
                    end
                }
            }
        }
    }
})

local function setCurrent()
    if dui then
        -- Guarantee activeIndex is a clean number state
        if type(activeIndex) ~= "number" then activeIndex = 1 end
        
        MachoSendDuiMessage(dui, json.encode({
            action = 'setCurrent',
            current = activeIndex,
            menu = activeMenu
        }))
        
        -- Fixed: Concat forcing string conversion so the engine logger doesn't clip parameters
        print('setCurrent called with index: ' .. tostring(activeIndex))
    end
end

local function isControlPressed(control)
    return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
end

local function isControlJustPressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

local function isControlJustReleased(control)
    return IsControlJustReleased(0, control) or IsDisabledControlJustReleased(0, control)
end

nestedMenus = {}
nestedMenus[1] = { index = 1, menu = activeMenu, label = 'Main Menu' }
activeIndex = 1

local tabStateMap = {}

CreateThread(function()
    dui = MachoCreateDui("http://localhost:5173/")
    MachoShowDui(dui)
    
    _G.changeMenuPosition = function(position) 
        if dui then 
            MachoSendDuiMessage(dui, json.encode({ action = 'position', position = position })) 
        end 
    end 
    
    _G.changeBanner = function(banner) 
        if dui then 
            MachoSendDuiMessage(dui, json.encode({ action = 'banner', banner = banner })) 
        end 
    end 

    Wait(1000) 
    setCurrent()
    
    local showing = true
    local currentSubMenuRefresher = nil
    local isDynamicSubMenu = false
    local menuStateMap = {}
    local baseDelay = 250
    local minDelay = 50
    local speedupStep = 30
    local holdTimers = {
        ['ArrowLeft'] = {lastTime = 0, delay = 100},
        ['ArrowRight'] = {lastTime = 0, delay = 100},
    }

    _G.clientMenuShowing = true

    while _G.clientMenuShowing do
        if _G.isInputActive and _G.isInputActive() then Wait(0) goto continue end
        if _G.wasInputJustOpened and _G.wasInputJustOpened() then Wait(0) goto continue end
        if _G.wasInputJustClosed and _G.wasInputJustClosed() then Wait(0) goto continue end

        if isControlJustReleased(137) then
            showing = not showing
            MachoSendDuiMessage(dui, json.encode({ action = 'setVisible', visible = showing }))
        elseif showing then
            local now = GetGameTimer()
            for control, bind in pairs({
                ['ArrowUp'] = 188,
                ['ArrowDown'] = 187,
                ['ArrowLeft'] = 189,
                ['ArrowRight'] = 190,
                ['Backspace'] = 194,
                ['Enter'] = 191,
                ['Q'] = 44,
                ['E'] = 38
            }) do
                if control == 'ArrowLeft' or control == 'ArrowRight' then
                    local timer = holdTimers[control]
                    if isControlPressed(bind) then
                        if now - timer.lastTime >= timer.delay then
                            timer.lastTime = now
                            timer.delay = math.max(minDelay, timer.delay - speedupStep)
                            local activeData = activeMenu[activeIndex]
                            if activeData then 
                                if control == 'ArrowLeft' then
                                    if activeData.type == 'scroll' then
                                        local selected = (activeData.selected or 1) - 1
                                        if selected <= 0 then selected = #activeData.options end
                                        activeData.selected = selected
                                        if activeData.onChange then activeData.onChange(activeData.options[selected]) end
                                    elseif activeData.type == 'slider' then
                                        local newValue = math.max(activeData.min or 0, math.min(activeData.max or 100, (activeData.value or 0) - 1))
                                        activeData.value = newValue
                                        if activeData.onChange then activeData.onChange(newValue) end
                                    end
                                else
                                    if activeData.type == 'scroll' then
                                        local selected = (activeData.selected or 1) + 1
                                        if selected > #activeData.options then selected = 1 end
                                        activeData.selected = selected
                                        if activeData.onChange then activeData.onChange(activeData.options[selected]) end
                                    elseif activeData.type == 'slider' then
                                        local newValue = math.max(activeData.min or 0, math.min(activeData.max or 100, (activeData.value or 0) + 1))
                                        activeData.value = newValue
                                        if activeData.onChange then activeData.onChange(newValue) end
                                    end
                                end
                            end
                            setCurrent()
                        end
                    else
                        timer.delay = baseDelay
                        timer.lastTime = 0
                    end

                elseif isControlJustPressed(bind) then
                    if control == 'ArrowDown' then
                        repeat
                            activeIndex = activeIndex + 1
                            if activeIndex > #activeMenu then activeIndex = 1 end
                        until not activeMenu[activeIndex] or activeMenu[activeIndex].type ~= "divider"
                        setCurrent()

                    elseif control == 'ArrowUp' then
                        repeat
                            activeIndex = activeIndex - 1
                            if activeIndex < 1 then activeIndex = #activeMenu end
                        until not activeMenu[activeIndex] or activeMenu[activeIndex].type ~= "divider"
                        setCurrent()

                    elseif control == 'Enter' then
                        local activeData = activeMenu[activeIndex]

                        if activeData and activeData.type == 'submenu' then
                            nestedMenus[#nestedMenus+1] = { index = activeIndex, menu = activeMenu, label = activeData.label }

                            if activeData.submenu then
                                activeIndex = 1
                                activeMenu = activeData.submenu

                                currentTabs = nil
                                setCurrent()

                            elseif activeData.tabs then
                                currentTabs = activeData.tabs
                                local names = {}
                                for _, t in ipairs(currentTabs) do table.insert(names, t.name) end
                                MachoSendDuiMessage(dui, json.encode({ action = 'setTabs', tabs = names }))

                                local menuLabel = activeData.label or "Default"
                                local saved = tabStateMap[menuLabel]
                                if saved then
                                    currentTabIndex = math.min(saved.tab or 0, #currentTabs - 1)
                                    local currentSub = currentTabs[currentTabIndex+1] and currentTabs[currentTabIndex+1].submenu
                                    activeIndex = math.min(saved.index or 1, currentSub and #currentSub or 1)
                                else
                                    currentTabIndex = 0
                                    activeIndex = 1
                                end

                                MachoSendDuiMessage(dui, json.encode({ action = 'setTabIndex', index = currentTabIndex }))
                                activeMenu = currentTabs[currentTabIndex + 1].submenu or {}
                                setCurrent()

                            else
                                isBusy = true
                                local getSubMenuFunc = activeData.getSubMenu
                                if getSubMenuFunc then
                                    currentSubMenuRefresher = getSubMenuFunc
                                    isDynamicSubMenu = true

                                    getSubMenuFunc(function(setMenu)
                                        isBusy = false
                                        menuStateMap[activeData.label or ''] = activeIndex

                                        local restoreIndex = menuStateMap[activeData.label or ''] or 1
                                        activeIndex = math.min(restoreIndex, #setMenu)
                                        if activeIndex < 1 then activeIndex = 1 end

                                        activeMenu = setMenu
                                        setCurrent()
                                    end)
                                end
                            end

                        elseif activeData then
                            if activeData.type == 'checkbox' then
                                activeData.checked = not activeData.checked
                                setCurrent()
                                if activeData.onConfirm then activeData.onConfirm(activeData.checked) end

                            elseif activeData.onConfirm then
                                if activeData.type == 'scroll' then
                                    if activeData.options then activeData.onConfirm(activeData.options[activeData.selected or 1]) end
                                elseif activeData.type == 'slider' then
                                    activeData.onConfirm(activeData.value)
                                elseif activeData.type == 'button' then
                                    activeData.onConfirm()
                                end
                            end
                        end

                    elseif control == 'Backspace' then
                        local lastMenu = nestedMenus[#nestedMenus]

                        if lastMenu then
                            if currentTabs then
                                local lastMenuLabel = lastMenu.label or "Default"
                                tabStateMap[lastMenuLabel] = {
                                    tab = currentTabIndex,
                                    index = activeIndex
                                }
                            end

                            table.remove(nestedMenus)
                            activeIndex = lastMenu.index or 1
                            activeMenu = lastMenu.menu

                            if #nestedMenus <= 1 then
                                currentTabs = nil
                                MachoSendDuiMessage(dui, json.encode({ action = 'setTabs', tabs = {"Main Menu"} }))
                            end

                            setCurrent()
                        else
                            showing = false
                            MachoSendDuiMessage(dui, json.encode({
                                action = 'setVisible',
                                visible = false
                            }))
                        end

                        currentSubMenuRefresher = nil
                        isDynamicSubMenu = false

                    elseif control == 'Q' and currentTabs then
                        currentTabIndex = currentTabIndex - 1
                        if currentTabIndex < 0 then currentTabIndex = #currentTabs - 1 end
                        activeMenu = currentTabs[currentTabIndex + 1].submenu or activeMenu
                        activeIndex = 1
                        MachoSendDuiMessage(dui, json.encode({ action = 'setTabIndex', index = currentTabIndex }))
                        setCurrent()

                        local currentLabel = (nestedMenus[#nestedMenus] and nestedMenus[#nestedMenus].label) or "Default"
                        tabStateMap[currentLabel] = { tab = currentTabIndex, index = activeIndex }

                    elseif control == 'E' and currentTabs then
                        currentTabIndex = currentTabIndex + 1
                        if currentTabIndex >= #currentTabs then currentTabIndex = 0 end
                        activeMenu = currentTabs[currentTabIndex + 1].submenu or activeMenu
                        activeIndex = 1
                        MachoSendDuiMessage(dui, json.encode({ action = 'setTabIndex', index = currentTabIndex }))
                        setCurrent()

                        local currentLabel = (nestedMenus[#nestedMenus] and nestedMenus[#nestedMenus].label) or "Default"
                        tabStateMap[currentLabel] = { tab = currentTabIndex, index = activeIndex }
                    end
                end
            end
        end
        ::continue::
        Wait(0)
    end

    if dui then
        MachoDestroyDui(dui)
    end
    dui = nil
end)
