local OPCODE = 110

local tasksWindow = nil
local trackerWindow = nil
local taskButton = nil
local trackerButton = nil

local jsonData = ""
local config = {}
local tasks = {}
local activeTasks = {}
local playerLevel = 0
local waitingForServer = false

local RewardType = {
  Points = 1,
  Experience = 2,
  Gold = 3,
  Item = 4,
  Storage = 5,
  Teleport = 6
}

function init()
  tasksWindow = g_ui.displayUI("radbrtasks")
  tasksWindow:hide()

  -- Registrar opcode
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)

  -- Botão toggle no mainpanel
  taskButton = modules.game_mainpanel.addToggleButton('radbrtaskButton', tr('Tasks'),
                                                      '/images/topbuttons/battle',
                                                      toggle, false, 99)

  -- Setup do tracker (opcional, só se o tracker existir)
  if g_game.isOnline() then
    setupTracker()
  end

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  -- Callbacks da UI
  if tasksWindow then
    if tasksWindow.searchInput then
      tasksWindow.searchInput.onTextChange = onSearch
    end
    if tasksWindow.info and tasksWindow.info.kills and tasksWindow.info.kills.bar and tasksWindow.info.kills.bar.scroll then
      tasksWindow.info.kills.bar.scroll.onValueChange = onKillsValueChange
    end
    if tasksWindow.tasksList then
      tasksWindow.tasksList.onChildFocusChange = onTaskSelected
    end
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  ProtocolGame.unregisterExtendedOpcode(OPCODE, onExtendedOpcode)

  if taskButton then
    taskButton:destroy()
    taskButton = nil
  end

  if trackerButton then
    trackerButton:destroy()
    trackerButton = nil
  end

  if trackerWindow then
    trackerWindow:destroy()
    trackerWindow = nil
  end

  if tasksWindow then
    tasksWindow:destroy()
    tasksWindow = nil
  end

  -- Limpar dados
  config = {}
  tasks = {}
  activeTasks = {}
  playerLevel = 0
  jsonData = ""
  waitingForServer = false
end

function onGameStart()
  setupTracker()
  
  -- Mostrar mensagem se não houver dados ainda
  if not tasks or #tasks == 0 then
    waitingForServer = true
    updateWaitingMessage()
  end
end

function onGameEnd()
  if trackerWindow then
    trackerWindow:destroy()
    trackerWindow = nil
  end

  if trackerButton then
    trackerButton:destroy()
    trackerButton = nil
  end

  tasks = {}
  activeTasks = {}
  config = {}
  jsonData = ""
  waitingForServer = false
end

function setupTracker()
  if trackerWindow or not modules.client_topmenu then
    return
  end

  -- Verificar se getRightPanel existe (API do OTBR)
  if not modules.game_interface or not modules.game_interface.getRightPanel then
    -- Fallback: tentar criar tracker sem painel específico
    return
  end

  pcall(function()
    trackerButton = modules.client_topmenu.addRightGameToggleButton("radbrTrackerButton", tr("Tasks Tracker"), "/images/topbuttons/battle", toggleTracker)
    if trackerButton then
      trackerButton:setOn(true)
    end

    local rightPanel = modules.game_interface.getRightPanel()
    if rightPanel then
      trackerWindow = g_ui.loadUI("radbrtasks_tracker", rightPanel)
      if trackerWindow then
        if trackerWindow.miniwindowScrollBar then
          trackerWindow.miniwindowScrollBar:mergeStyle({["$!on"] = {}})
        end
        if trackerWindow.setContentMinimumHeight then
          trackerWindow:setContentMinimumHeight(120)
        end
        if trackerWindow.setup then
          trackerWindow:setup()
        end
      end
    end
  end)
end

function updateWaitingMessage()
  if not tasksWindow or not tasksWindow.tasksList then
    return
  end

  tasksWindow.tasksList:destroyChildren()
  
  local label = g_ui.createWidget("Label", tasksWindow.tasksList)
  label:setText("Aguardando servidor...")
  label:setTextAlign(AlignCenter)
  label:setId("waitingLabel")
end

function toggle()
  if not tasksWindow then
    return
  end

  if taskButton:isOn() then
    tasksWindow:hide()
    taskButton:setOn(false)
  else
    -- Verificar se precisa solicitar dados ao servidor
    if g_game.isOnline() and (not tasks or #tasks == 0) and not waitingForServer then
      waitingForServer = true
      updateWaitingMessage()
      local protocolGame = g_game.getProtocolGame()
      if protocolGame then
        -- Tentar solicitar dados (opcional, pode ser automático)
      end
    end

    -- Docking: encontrar painel disponível
    if not tasksWindow:getParent() then
      local panel = modules.game_interface.findContentPanelAvailable(tasksWindow, tasksWindow:getMinimumHeight())
      if panel then
        panel:addChild(tasksWindow)
      end
    end

    tasksWindow:show()
    tasksWindow:raise()
    tasksWindow:focus()
    taskButton:setOn(true)
  end
end

function onExtendedOpcode(protocol, opcode, buffer)
  -- Tratar dados fragmentados (S = Start, P = Partial, E = End)
  local char = buffer:sub(1, 1)
  local endData = false
  
  if char == "E" then
    endData = true
  end

  local partialData = false
  if char == "S" or char == "P" or char == "E" then
    partialData = true
    buffer = buffer:sub(2)
    jsonData = jsonData .. buffer
  end

  -- Se for dado parcial e não for o final, apenas acumula
  if partialData and not endData then
    return
  end

  -- Decodificar JSON com proteção
  local json_status, json_data = pcall(function()
    return json.decode(endData and jsonData or buffer)
  end)

  if not json_status or not json_data then
    -- Não spammer erro, apenas log silencioso
    g_logger.debug("[RADBR Tasks] Erro ao decodificar JSON")
    jsonData = "" -- Reset em caso de erro
    return
  end

  -- Reset do buffer após decodificar com sucesso
  if endData then
    jsonData = ""
  end

  waitingForServer = false

  local action = json_data.action
  local data = json_data.data

  if action == "config" then
    onTasksConfig(data)
  elseif action == "tasks" then
    onTasksList(data)
  elseif action == "active" then
    onTasksActive(data)
  elseif action == "update" then
    onTaskUpdate(data)
  elseif action == "points" then
    onTasksPoints(data)
  elseif action == "open" then
    toggle()
  elseif action == "close" then
    if tasksWindow then
      tasksWindow:hide()
      if taskButton then
        taskButton:setOn(false)
      end
    end
  end
end

function onTasksConfig(data)
  if not data or not tasksWindow then
    return
  end

  config = data

  if tasksWindow.info and tasksWindow.info.kills and tasksWindow.info.kills.bar then
    if tasksWindow.info.kills.bar.min then
      tasksWindow.info.kills.bar.min:setText(tostring(config.kills and config.kills.Min or 1))
    end
    if tasksWindow.info.kills.bar.max then
      tasksWindow.info.kills.bar.max:setText(tostring(config.kills and config.kills.Max or 100))
    end
    if tasksWindow.info.kills.bar.scroll then
      local min = config.kills and config.kills.Min or 1
      local max = config.kills and config.kills.Max or 100
      tasksWindow.info.kills.bar.scroll:setRange(min, max)
      tasksWindow.info.kills.bar.scroll:setValue(min)
    end
  end
end

function onTasksList(data)
  if not data or not tasksWindow or not tasksWindow.tasksList then
    return
  end

  tasks = data
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return
  end

  local level = localPlayer:getLevel()
  tasksWindow.tasksList:destroyChildren()

  for taskId, task in ipairs(data) do
    local widget = g_ui.createWidget("TaskMenuEntry", tasksWindow.tasksList)
    widget:setId(tostring(taskId))
    
    if widget.preview and task.outfits and task.outfits[1] then
      local outfit = task.outfits[1]
      outfit.shader = "default"
      widget.preview:setOutfit(outfit)
      if widget.preview.setCenter then
        widget.preview:setCenter(true)
      end
    end
    
    if widget.info then
      if widget.info.title then
        widget.info.title:setText(task.name or "")
      end
      if widget.info.level then
        widget.info.level:setText("Level " .. (task.lvl or 0))
      end
      if widget.info.bonus and config.range then
        if not (task.lvl >= level - config.range and task.lvl <= level + config.range) then
          widget.info.bonus:hide()
        else
          widget.info.bonus:show()
        end
      end
    end
  end

  -- Selecionar primeira tarefa se houver
  local firstChild = tasksWindow.tasksList:getChildByIndex(1)
  if firstChild then
    onTaskSelected(nil, firstChild)
  end

  playerLevel = level
end

function onTasksActive(data)
  if not data or not trackerWindow or not trackerWindow.contentsPanel then
    return
  end

  local trackerPanel = trackerWindow.contentsPanel.trackerPanel
  if not trackerPanel then
    return
  end

  for _, active in ipairs(data) do
    local task = tasks[active.taskId]
    if task then
      local widget = g_ui.createWidget("TrackerButton", trackerPanel)
      widget:setId(tostring(active.taskId))
      
      if widget.creature and task.outfits and task.outfits[1] then
        local outfit = task.outfits[1]
        outfit.shader = "default"
        widget.creature:setOutfit(outfit)
        if widget.creature.setCenter then
          widget.creature:setCenter(true)
        end
      end
      
      if widget.label then
        local taskName = task.name or ""
        if taskName:len() > 12 then
          widget.label:setText(taskName:sub(1, 9) .. "...")
        else
          widget.label:setText(taskName)
        end
      end
      
      if widget.kills then
        widget.kills:setText((active.kills or 0) .. "/" .. (active.required or 0))
      end
      
      local percent = 0
      if active.required and active.required > 0 then
        percent = (active.kills or 0) * 100 / active.required
      end
      setBarPercent(widget, percent)
      
      widget.onMouseRelease = onTrackerClick
      activeTasks[active.taskId] = true
    end
  end
end

function onTaskUpdate(data)
  if not data then
    return
  end

  local taskId = data.taskId
  local widget = nil

  -- Atualizar tracker
  if trackerWindow and trackerWindow.contentsPanel and trackerWindow.contentsPanel.trackerPanel then
    widget = trackerWindow.contentsPanel.trackerPanel:getChildById(tostring(taskId))
  end

  if data.status == 1 then
    local task = tasks[taskId]
    if task then
      if not widget and trackerWindow and trackerWindow.contentsPanel and trackerWindow.contentsPanel.trackerPanel then
        widget = g_ui.createWidget("TrackerButton", trackerWindow.contentsPanel.trackerPanel)
        widget:setId(tostring(taskId))
        
        if widget.creature and task.outfits and task.outfits[1] then
          local outfit = task.outfits[1]
          outfit.shader = "default"
          widget.creature:setOutfit(outfit)
          if widget.creature.setCenter then
            widget.creature:setCenter(true)
          end
        end
        
        if widget.label then
          local taskName = task.name or ""
          if taskName:len() > 12 then
            widget.label:setText(taskName:sub(1, 9) .. "...")
          else
            widget.label:setText(taskName)
          end
        end
        
        widget.onMouseRelease = onTrackerClick
        activeTasks[taskId] = true
      end

      if widget then
        if widget.kills then
          widget.kills:setText((data.kills or 0) .. "/" .. (data.required or 0))
        end
        
        local percent = 0
        if data.required and data.required > 0 then
          percent = (data.kills or 0) * 100 / data.required
        end
        setBarPercent(widget, percent)
      end
    end
  elseif data.status == 2 then
    activeTasks[taskId] = nil
    if widget then
      widget:destroy()
    end
  end

  -- Atualizar botões na janela principal
  if tasksWindow and tasksWindow.tasksList then
    local focused = tasksWindow.tasksList:getFocusedChild()
    if focused then
      local focusedTaskId = tonumber(focused:getId())
      if focusedTaskId == taskId then
        if tasksWindow.start then
          tasksWindow.start:setVisible(not activeTasks[taskId])
        end
        if tasksWindow.cancel then
          tasksWindow.cancel:setVisible(activeTasks[taskId] or false)
        end
      end
    end
  end
end

function onTasksPoints(points)
  if tasksWindow and tasksWindow.points then
    tasksWindow.points:setText("Current Tasks Points: " .. (points or 0))
  end
end

function onTrackerClick(widget, mousePosition, mouseButton)
  if mouseButton ~= MouseRightButton then
    return false
  end

  local taskId = tonumber(widget:getId())
  if not taskId then
    return false
  end

  local menu = g_ui.createWidget("PopupMenu")
  if menu then
    menu:setGameMenu(true)
    menu:addOption("Abandon this task", function()
      cancel(taskId)
    end)
    menu:display(mousePosition)
  end

  return true
end

function setBarPercent(widget, percent)
  if not widget or not widget.killsBar then
    return
  end

  local color = "#850C0C"
  if percent > 92 then
    color = "#00BC00"
  elseif percent > 60 then
    color = "#50A150"
  elseif percent > 30 then
    color = "#A1A100"
  elseif percent > 8 then
    color = "#BF0A0A"
  elseif percent > 3 then
    color = "#910F0F"
  end

  widget.killsBar:setBackgroundColor(color)
  
  if widget.killsBar.setPercent then
    widget.killsBar:setPercent(percent)
  elseif widget.killsBar.setValue then
    widget.killsBar:setValue(percent)
  end
end

function onTaskSelected(parent, child, reason)
  if not child or not tasksWindow then
    return
  end

  local taskId = tonumber(child:getId())
  if not taskId then
    return
  end

  local task = tasks[taskId]
  if not task then
    return
  end

  -- Atualizar recompensas
  if tasksWindow.info and tasksWindow.info.rewards then
    tasksWindow.info.rewards:destroyChildren()
    for _, reward in ipairs(task.rewards or {}) do
      local widget = g_ui.createWidget("Label", tasksWindow.info.rewards)
      widget:setTextAlign(AlignCenter)
      
      if reward.type == RewardType.Points then
        widget:setText("Tasks Points: " .. (reward.value or 0))
      elseif reward.type == RewardType.Experience then
        widget:setText("Experience: " .. (reward.value or 0))
      elseif reward.type == RewardType.Gold then
        widget:setText("Gold: " .. (reward.value or 0))
      elseif reward.type == RewardType.Item then
        widget:setText((reward.amount or 0) .. "x " .. (reward.name or ""))
      elseif reward.type == RewardType.Storage then
        widget:setText(reward.desc or "")
      elseif reward.type == RewardType.Teleport then
        widget:setText("Teleport to " .. (reward.desc or ""))
      end
    end
  end

  -- Atualizar monstros
  if tasksWindow.info and tasksWindow.info.monsters then
    tasksWindow.info.monsters:destroyChildren()
    for id, monster in ipairs(task.mobs or {}) do
      local widget = g_ui.createWidget("UICreature", tasksWindow.info.monsters)
      if widget and task.outfits and task.outfits[id] then
        local outfit = task.outfits[id]
        outfit.shader = "default"
        widget:setOutfit(outfit)
        if widget.setCenter then
          widget:setCenter(true)
        end
        if widget.setPhantom then
          widget:setPhantom(false)
        end
        if widget.setTooltip then
          widget:setTooltip(monster)
        end
      end
    end
  end

  -- Atualizar botões
  if activeTasks[taskId] then
    if tasksWindow.start then
      tasksWindow.start:hide()
    end
    if tasksWindow.cancel then
      tasksWindow.cancel:show()
    end
  else
    if tasksWindow.start then
      tasksWindow.start:show()
    end
    if tasksWindow.cancel then
      tasksWindow.cancel:hide()
    end
  end
end

function onKillsValueChange(widget, value, delta)
  if not tasksWindow or not tasksWindow.info or not tasksWindow.info.kills then
    return
  end

  if tasksWindow.info.kills.bar and tasksWindow.info.kills.bar.value then
    tasksWindow.info.kills.bar.value:setText(tostring(value))
  end

  local focused = tasksWindow.tasksList and tasksWindow.tasksList:getFocusedChild()
  if not focused then
    return
  end

  local taskId = tonumber(focused:getId())
  if not taskId then
    return
  end

  local task = tasks[taskId]
  if not task or not config.bonus then
    return
  end

  local bonus = math.floor((math.max(0, value - config.bonus) / config.bonus) + 0.5)
  local bonusesPanel = tasksWindow.info.kills.bonuses

  if bonus == 0 then
    if bonusesPanel then
      if bonusesPanel.none then bonusesPanel.none:show() end
      if bonusesPanel.points then bonusesPanel.points:hide() end
      if bonusesPanel.exp then bonusesPanel.exp:hide() end
      if bonusesPanel.gold then bonusesPanel.gold:hide() end
    end
  else
    if bonusesPanel then
      if bonusesPanel.none then bonusesPanel.none:hide() end
      if bonusesPanel.points then bonusesPanel.points:hide() end
      if bonusesPanel.exp then bonusesPanel.exp:hide() end
      if bonusesPanel.gold then bonusesPanel.gold:hide() end

      for _, reward in ipairs(task.rewards or {}) do
        if reward.type == RewardType.Points and config.points then
          local finalBonus = bonus * config.points
          if bonusesPanel.points then
            bonusesPanel.points:show()
            bonusesPanel.points:setText("+" .. finalBonus .. "% Tasks Points")
          end
        elseif reward.type == RewardType.Experience and config.exp then
          local finalBonus = bonus * config.exp
          if bonusesPanel.exp then
            bonusesPanel.exp:show()
            bonusesPanel.exp:setText("+" .. finalBonus .. "% Exp")
          end
        elseif reward.type == RewardType.Gold and config.gold then
          local finalBonus = bonus * config.gold
          if bonusesPanel.gold then
            bonusesPanel.gold:show()
            bonusesPanel.gold:setText("+" .. finalBonus .. "% Gold")
          end
        end
      end
    end
  end
end

function onSearch()
  if not tasksWindow or not tasksWindow.searchInput or not tasksWindow.tasksList then
    return
  end

  scheduleEvent(function()
    local text = tasksWindow.searchInput:getText():lower()

    if text:len() >= 1 then
      local children = tasksWindow.tasksList:getChildren()
      for i, child in ipairs(children) do
        local found = false
        local taskId = tonumber(child:getId())
        if taskId and tasks[taskId] and tasks[taskId].mobs then
          for _, mob in ipairs(tasks[taskId].mobs) do
            if mob:lower():find(text, 1, true) then
              found = true
              break
            end
          end
        end

        if found then
          child:show()
        else
          child:hide()
        end
      end
    else
      local children = tasksWindow.tasksList:getChildren()
      for _, child in ipairs(children) do
        child:show()
      end
    end
  end, 50)
end

function start()
  if not tasksWindow or not tasksWindow.tasksList then
    return
  end

  local focused = tasksWindow.tasksList:getFocusedChild()
  if not focused then
    return
  end

  local taskId = tonumber(focused:getId())
  if not taskId then
    return
  end

  local kills = 1
  if tasksWindow.info and tasksWindow.info.kills and tasksWindow.info.kills.bar and tasksWindow.info.kills.bar.scroll then
    kills = tasksWindow.info.kills.bar.scroll:getValue()
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(OPCODE, json.encode({action = "start", data = {taskId = taskId, kills = kills}}))
  end
end

function cancel(taskId)
  if not taskId then
    if tasksWindow and tasksWindow.tasksList then
      local focused = tasksWindow.tasksList:getFocusedChild()
      if focused then
        taskId = tonumber(focused:getId())
      end
    end

    if not taskId then
      return
    end
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(OPCODE, json.encode({action = "cancel", data = taskId}))
  end
end

function onTrackerClose()
  if trackerButton then
    trackerButton:setOn(false)
  end
end

function toggleTracker()
  if not trackerWindow then
    return
  end

  if trackerButton and trackerButton:isOn() then
    if trackerWindow.close then
      trackerWindow:close()
    else
      trackerWindow:hide()
    end
    if trackerButton then
      trackerButton:setOn(false)
    end
  else
    if trackerWindow.open then
      trackerWindow:open()
    else
      trackerWindow:show()
    end
    if trackerButton then
      trackerButton:setOn(true)
    end
  end
end

-- Exportar função toggle para uso externo
_G.radbrtasks = {
  toggle = toggle,
  start = start,
  cancel = cancel
}