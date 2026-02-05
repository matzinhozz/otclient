function postostring(pos)
    return pos.x .. ' ' .. pos.y .. ' ' .. pos.z
end

function dirtostring(dir)
    for k, v in pairs(Directions) do
        if v == dir then
            return k
        end
    end
end

function comma_value(n)
    local left, num, right = string.match(n, '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

function formatTimeBySeconds(totalSeconds)
    local hours = math.floor(totalSeconds / 3600)
    local remainingSeconds = totalSeconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, minutes)
end

function formatTimeByMinutes(totalMinutes)
    local totalSeconds = totalMinutes * 60
    local hours = math.floor(totalSeconds / 3600)
    local remainingSeconds = totalSeconds % 3600
    local minutes = math.floor(remainingSeconds / 60)
    return string.format("%02d:%02d", hours, minutes)
end

function math.cround(value, rd)
    local _round = math.floor(value / rd)
    return _round * rd
end

function formatMoney(amount, separator)
  local patternSeparator = string.format("%%1%s%%2", separator)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", patternSeparator)
    if (k==0) then
      break
    end
  end
  return formatted
end

if not setStringColor then
  function setStringColor(str, color)
    return str  -- ignora a cor e retorna o texto puro
  end
end

function convertLongGold(amount, shortValue, normalized)
    local hasBillion = false
    local hasTrillion = false
  
    local fomarType = 0
    if normalized and amount >= 1000000 then
      amount = math.floor(amount / 1000000)
      fomarType = 1
    elseif normalized and amount >= 10000 then
      amount = math.floor(amount / 1000)
      fomarType = 2
    elseif shortValue and amount > 10000000 then
        fomarType = 1
      amount = math.floor(amount / 1000000)
    elseif shortValue and amount > 1000000 then
        fomarType = 2
      amount = math.floor(amount / 1000)
    elseif amount > 999999999 then
      fomarType = 1
      amount = math.floor(amount / 1000000)
    elseif amount > 99999999 then
      fomarType = 2
      amount = math.floor(amount / 1000)
    end
  
    local formatted = amount
    while true do
      formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
      if (k==0) then
        break
      end
    end
  
    if fomarType == 1 then
      formatted = formatted .. " kk"
    elseif fomarType == 2 then
      formatted = formatted .. " k"
    end
  
    return formatted
end

function translateWheelVocation(id)
	-- Sprawdź czy id jest stringiem i spróbuj przekonwertować
	if type(id) == "string" then
		id = tonumber(id)
	end

	-- Knight family (1 = wheel Knight)
	if id == 1 or id == 11 then
		return 1 -- ek
	elseif id == 2 or id == 12 then
		return 2 -- rp
	elseif id == 3 or id == 13 then
		return 3 -- ms
	elseif id == 4 or id == 14 then
		return 4 -- ed
	elseif id == 5 or id == 15 then
		return 5 -- em
	end

	-- Third promotion / custom vocations (server vocation ids)
	-- Sorcerer wheel: Infernalist (11), Master Infernalist (12), Diabolic Master Infernalist (18)
	if id == 11 or id == 12 or id == 18 then
		return 3
	end
	-- Monk wheel: Knocker (19), Champion Knocker (20), Furious Champion Knocker (21)
	if id == 19 or id == 20 or id == 21 then
		return 5
	end
	-- Knight wheel: Drunou (22), Lord Drunou (23), Gallant Lord Drunou (17)
	if id == 17 or id == 22 or id == 23 then
		return 1
	end
	-- Druid/Paladin third promotions if any (13, 14, 15, 16)
	if id == 13 then return 3 end -- Wise Master Sorcerer
	if id == 14 then return 4 end -- Ancient Elder Druid
	if id == 15 then return 2 end -- Templar Royal Paladin
	if id == 16 then return 1 end -- Glorious Elite Knight

	return 0
end

-- servers may have different id's, change if not working properly (only for protocols 910+)
function getVocationSt(id)
  -- Knight wheel: Knight (1,11), Drunou line (17,22,23), Glorious Elite Knight (16)
  if id == 1 or id == 11 or id == 16 or id == 17 or id == 22 or id == 23 then
    return "K0"
  elseif id == 2 or id == 12 or id == 15 then
    return "P0"
  -- Sorcerer wheel: Sorcerer (3,13), Infernalist line (11,12,18), Wise Master Sorcerer (13)
  elseif id == 3 or id == 13 or id == 11 or id == 12 or id == 18 then
    return "S0"
  elseif id == 4 or id == 14 then
    return "D0"
  -- Monk wheel: Monk (5,15), Knocker line (19,20,21)
  elseif id == 5 or id == 15 or id == 19 or id == 20 or id == 21 then
    return "M0"
  end
  return "N"
end

function getVocationId(name)
  if string.find(name:lower(), "knight") then
    return 11 -- Elite Knight
  elseif string.find(name:lower(), "paladin") then
    return 12 -- Royal Paladin
  elseif string.find(name:lower(), "sorcerer") or string.find(name:lower(), "mag") then
    return 13 -- Master Sorcerer
  elseif string.find(name:lower(), "druid") then
    return 14 -- Elder Druid
  elseif string.find(name:lower(), "monk") then
    return 15 -- Elder Monk
  end

  return 0
end

function roundToTwoDecimalPlaces(num)
  return math.floor(num * 100 + 0.5) / 100
end