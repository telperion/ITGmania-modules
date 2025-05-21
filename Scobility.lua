--[[--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--
-- Scobility in the Songwheel v0.1
-- 
-- Locally caches scobility spice values for the current year of ITL, then
-- calculates the player's scobility coefficients, target scores, and
-- potential RP gain based on their local ITL score table.
--
-- The following changes are made to music select:
-- - The high score box rotation (GS/BS ITG/EX) gets an additional scobility
--   card if the chart currently hovered is present in the current year of
--   ITL. This card contains the following info:
--   - Spice value
--   - Player's current (local) score
--   - Player's target score, as calculated from the spice value
--   - Potential SP, EP, and RP gain, if any are greater than zero
-- - The song wheel item will also be annotated with the potential SP, EP,
--   and RP gain available by achieving the calculated target score.
--
-- In order to use this module, you will need to update Save\Preferences.ini
-- so that the HttpAllowHosts line includes an entry for scobility's API,
-- scobility.azurewebsites.net, and ensure HttpEnabled is set to 1 - e.g.,
-- > HttpAllowHosts=*.groovestats.com,*.itgmania.com,scobility.azurewebsites.net
-- > HttpEnabled=1
--
-- Copyright (c) 2025 Telperion
--
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted, provided that the above
-- copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
-- OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
-- CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--]]--
local t = {}

local year = "2025"
local spice = {}
local spiceUpdateInProgress = false
local spiceUpdateInterval = 3600    -- cache no more often than every hour
local spiceLastUpdatedRelative = -spiceUpdateInterval
local spicePath = "scobility" .. year .. ".json"
local catalogName = "ITL" .. year
local groupName = "ITL Online " .. year

-- I wish these were stored themeside by ITL itself
local diffMap = {}
local styleMap = {}
local titleMap = {}

local coefs = {}
local perfectOffset = 1.003

local hands = {}
local handSP = {
    ["single"] = 75,
    ["double"] = 50,
}
local handEP = {
    ["single"] = {
        [7] = 1,
        [8] = 2,
        [9] = 3,
        [10] = 4,
        [11] = 5,
        [12] = 4,
        [13] = 3,
        [14] = 2,
        [15] = 1,
    },
    ["double"] = {
        [7] = 1,
        [8] = 2,
        [9] = 3,
        [10] = 4,
        [11] = 4,
        [12] = 3,
        [13] = 2,
        [14] = 1,
    },
}

local powBase = 40
local inflect = 40
local cutoffEP = 85.0
local EX2SP = function(expct)
    return (
        100.0 * 
        (math.pow(powBase, expct / inflect) - 1) /
        (math.pow(powBase, 100.0 / inflect) - 1)
    )
end
local SP2EX = function(sppct)
    local century_scale = 100.0 / (math.pow(powBase, 100.0 / inflect) - 1)
    return (
        inflect *
        math.log(sppct / century_scale + 1) /
        math.log(powBase)
    )
end
local EX2EP = function(expct)
    local exClamp = (expct > cutoffEP) and (expct - cutoffEP) or 0
    return (
      (math.pow(100, exClamp / (100.0 - cutoffEP)) - 1) * (1000.0 / 99.0)
    )
end

-- Least squares!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
local dumbassLSQComponents = function(a, b)
    local s, s2, q, sq = 0, 0, 0, 0
    for i, va in ipairs(a) do
        local vb = b[i]
        s = s + va
        s2 = s2 + va * va
        q = q + vb
        sq = sq + va * vb
    end
    return #a, s, s2, q, sq
end

local dumbassLSQFree = function(a, b)
    -- Plain ol' unanchored least squares best-fit.
    local ones, s, s2, q, sq = dumbassLSQComponents(a, b);
    local det = ones * s2 - s * s;
    local c1 = (-s * q + ones * sq) / det;
    local c0 = (s2 * q - s * sq) / det;
    local residual = 0
    for i, va in ipairs(a) do
        local vb = b[i]
        local vr = vb - (c1 * va + c0)
        residual = residual + vr * vr
    end
    return c0, c1, residual
end

local dumbassLSQWithCutPoint = function(a, b, anchor)
    -- Plain' ol unanchored least squares best-fit
    -- (but there's two of them!)
    local a_l = {unpack(a, 1, anchor)}
    local a_r = {unpack(a, anchor+1, #a)}
    local b_l = {unpack(b, 1, anchor)}
    local b_r = {unpack(b, anchor+1, #b)}
    if (#a_l < 2) or (#a_r < 2) then return nil end

    local c0_l, c1_l, res_l = dumbassLSQFree(a_l, b_l);
    local c0_r, c1_r, res_r = dumbassLSQFree(a_r, b_r);
    local horizon_spice = (c1_r - c1_l) / (c0_l - c0_r);
    local horizon_quality = c1_l * horizon_spice + c0_l;
    local timing_power = (horizon_spice > 0) and c0_l or c0_r;
    return {
        ["cut_point"] = anchor,
        ["timing_power"] = timing_power,
        ["horizon_spice"] = horizon_spice,
        ["horizon_quality"] = horizon_quality,
        ["mild_slope"] = c1_l,
        ["hot_slope"] = c1_r,
        ["residual"] = res_l + res_r
    }
end

local dumbassLSQAnchored = function(a, b, anchor)
    -- Solve a special condition of least-squares where a set of points is
    -- broken up into two lines, and the X coordinate of the intersection is
    -- fixed. This makes the independent variables the slopes of the two lines
    -- and the Y coordinate of the intersection.
    -- Here we're choosing the X coordinate as a[anchor].
    local k = a[anchor]
    local a_offset = {}
    local ones = #a
    local q = 0
    for i, v in ipairs(a) do
        a_offset[#a_offset+1] = v - k
        q = q + b[i]
    end
    local a_l = {unpack(a_offset, 1, anchor)}
    local a_r = {unpack(a_offset, anchor+1, #a)}
    local b_l = {unpack(b, 1, anchor)}
    local b_r = {unpack(b, anchor+1, #b)}
    if (#a_l < 2) or (#a_r < 2) then return nil end

    -- Borrow some of the calculations from the naive least squares method.
    local ones_l, s_l, s2_l, q_l, sq_l = dumbassLSQComponents(a_l, b_l)
    local ones_r, s_r, s2_r, q_r, sq_r = dumbassLSQComponents(a_r, b_r)

    -- Special 3x3 symmetric matrix inversion
    local m11 = ones * s2_r - s_r * s_r
    local m12 = s_l * s_r
    local m13 = -s_l * s2_r
    local m22 = ones * s2_l - s_l * s_l
    local m23 = -s2_l * s_r
    local m33 = s2_l * s2_r
    local det =
        ones * s2_r * s2_l -
        s_r * s_r * s2_l -
        s_l * s_l * s2_r
    -- Equivalent formulation of determinant
    -- local det = m11*s2_l + m13*s_l

    -- Evaluate the two slopes and the X coordinate at the anchor.
    local c1_l = (m11 * sq_l + m12 * sq_r + m13 * q) / det
    local c1_r = (m12 * sq_l + m22 * sq_r + m23 * q) / det
    local c0 = (m13 * sq_l + m23 * sq_r + m33 * q) / det

    local residual = 0
    for i, va in ipairs(a_offset) do
        local vb = b[i]
        if i < anchor then
            residual = residual + (vb - (c1_l * va + c0))
        else
            residual = residual + (vb - (c1_r * va + c0))
        end
    end

    return {
        ["c0"] = c0,
        ["c1_l"] = c1_l,
        ["c1_r"] = c1_r,
        ["residual"] = residual,
    }
end

-- Scobilitous piecewise least squares!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
-- Unga bunga!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
local spiceHorizonFit = function(a, b)
    -- Requires independent variable to be sorted.
    local best = nil
    -- local best = {
    --     ["cut_point"] = -1,
    --     ["horizon_spice"] = 0,
    --     ["horizon_quality"] = 0,
    --     ["mild_slope"] = 0,
    --     ["hot_slope"] = 0,
    --     ["timing_power"] = 0,
    --     ["residual"] = 0,
    -- }

    -- Don't unga bunga too close to the edges of the spice spread.
    local horizon_centering = math.floor(math.sqrt(#a))

    -- Test the fitness of the piecewise linear approximation between each
    -- pair of spice values.
    for j = horizon_centering, (#a - horizon_centering) do
        -- Try fitting an unanchored dual least squares first.
        -- If the intersection lands between this pair of spice values, it
        -- automatically wins the optimization for this step of the DP algorithm.
        local best_fit_here = dumbassLSQWithCutPoint(a, b, j)
        if (not best_fit_here) or ((best_fit_here.horizon_spice < a[j]) or (best_fit_here.horizon_spice > a[j+1])) then
            -- The intersection (a.k.a. spice horizon) didn't land between this
            -- pair of spice values, so it can't satisfy the optimization constraint.
            -- Let's evaluate what the best fits are on the boundaries and see which
            -- wins among those two.
            local best_fit_here_l = dumbassLSQAnchored(a, b, j)
            local best_fit_here_r = dumbassLSQAnchored(a, b, j + 1)
            if best_fit_here_l and best_fit_here_r then
                if (best_fit_here_l.residual < best_fit_here_r.residual) then
                    best_fit_here = {
                        ["cut_point"] = j,
                        ["horizon_spice"] = a[j],
                        ["horizon_quality"] = best_fit_here_l.c0,
                        ["mild_slope"] = best_fit_here_l.c1_l,
                        ["hot_slope"] = best_fit_here_l.c1_r,
                        ["timing_power"] = best_fit_here_l.c0 - best_fit_here_l.c1_l * a[j],
                        ["residual"] = best_fit_here_l.residual,
                    }
                else
                    best_fit_here = {
                        ["cut_point"] = j,
                        ["horizon_spice"] = a[j + 1],
                        ["horizon_quality"] = best_fit_here_r.c0,
                        ["mild_slope"] = best_fit_here_r.c1_l,
                        ["hot_slope"] = best_fit_here_r.c1_r,
                        ["timing_power"] = best_fit_here_r.c0 - best_fit_here_r.c1_l * a[j + 1],
                        ["residual"] = best_fit_here_r.residual,
                    }
                end
            end
        end

        if best_fit_here and ((not best) or (best_fit_here.residual < best.residual)) then
            best = best_fit_here;
        end
    end
    return best;
end

local CalculatePlayerData = function(player)
    if not GAMESTATE:GetCurrentStyle() then return end

    local currentStyle = GAMESTATE:GetCurrentStyle():GetName()
    if currentStyle ~= "double" then currentStyle = "single" end
    if PROFILEMAN:IsPersistentProfile(player) then
        local pn = ToEnumShortString(player)
        local pathMap = SL[pn].ITLData["pathMap"]
        local hashMap = SL[pn].ITLData["hashMap"]

        -- lol yikes
        for path, hash in pairs(pathMap) do
            local arr = split("/", path)
            local songSubPath = arr[3] .. "/" .. arr[4]
            local song = SONGMAN:FindSong(songSubPath)
            if song then
                for steps in ivalues(song:GetStepsByStepsType("StepsType_Dance_Single")) do
                    styleMap[hash] = "single"
                    diffMap[hash] = tonumber(steps:GetMeter())
                end
                for steps in ivalues(song:GetStepsByStepsType("StepsType_Dance_Double")) do
                    styleMap[hash] = "double"
                    diffMap[hash] = tonumber(steps:GetMeter())
                end
                titleMap[song:GetDisplayMainTitle()] = hash
            end
        end

        local spicePoints = {}
        local spiceList = {}
        local qualityList = {}
        local handAccumulator = {[-1] = {}}
        for handDiff, handSize in pairs(handEP[currentStyle]) do
            handAccumulator[handDiff] = {}
        end
        
        for hash, data in pairs(hashMap) do
            if diffMap[hash] and styleMap[hash] and styleMap[hash] == currentStyle then
                if spice[hash] then
                    spicePoints[#spicePoints+1] = {
                        ["spice"] = math.log(spice[hash]["spice"]) / math.log(2),
                        ["quality"] = (
                            math.log(spice[hash]["spice"]) -
                            math.log(perfectOffset - data["ex"] * 0.0001)
                        ) / math.log(2)
                    }
                end
                local currentSP = data["passingPoints"] + data["maxScoringPoints"] * EX2SP(data["ex"] * 0.01) * 0.01
                local diff = diffMap[hash]
                handAccumulator[-1][#handAccumulator[-1]+1] = {
                    ["hash"] = hash,
                    ["value"] = currentSP
                }
                handAccumulator[diff][#handAccumulator[diff]+1] = {
                    ["hash"] = hash,
                    ["value"] = data["ex"] * 0.01
                }
            end
        end
        table.sort(spicePoints, function(a, b) return a["spice"] < b["spice"] end)
        for spicePoint in ivalues(spicePoints) do
            spiceList[#spiceList+1] = spicePoint["spice"]
            qualityList[#qualityList+1] = spicePoint["quality"]
        end
        SM("Sample points: "..tostring(#spiceList))

        coefs[pn] = spiceHorizonFit(spiceList, qualityList)
        hands[pn] = {
            ["SP"] = {},
            ["EP"] = {}
        }
        SM(TableToString(coefs[pn]))

        for handDiff, handContents in pairs(handAccumulator) do
            table.sort(handContents, function(a, b) return a["value"] > b["value"] end)
            if handDiff == -1 then
                hands[pn]["SP"] = {unpack(handContents, 1, handSP[currentStyle])}
            else
                hands[pn]["EP"][handDiff] = {unpack(handContents, 1, handEP[currentStyle][handDiff])}
            end
        end
    end
end

-- unfortunately "IsItlSong" is already taken :(
local IsThisSongITL = function(player, song)
    local songPath = song:GetSongDir()
    local group = string.lower(song:GetGroupName())
    local pn = ToEnumShortString(player)
    return (string.find(group, "itl online 2025") or 
        string.find(group, "itl 2025") or 
        SL[pn].ITLData["pathMap"][songPath] ~= nil)
end

local EvaluateScobilityFit = function(player, s)
    local pn = ToEnumShortString(player)
    if not coefs[pn] then return nil end

    if s <= coefs[pn].horizon_spice then
      return coefs[pn].mild_slope * (s - coefs[pn].horizon_spice) + coefs[pn].horizon_quality
    else
      return coefs[pn].hot_slope * (s - coefs[pn].horizon_spice) + coefs[pn].horizon_quality
    end
end

local EvaluateChartForPlayer = function(player, song, chartHash)
    local pn = ToEnumShortString(player)
    local currentStyle = GAMESTATE:GetCurrentStyle():GetName()

    if not coefs[pn] then return nil end

    local pathMap = SL[pn].ITLData["pathMap"]
    local hashMap = SL[pn].ITLData["hashMap"]

    local hash = chartHash
    if not hash then
        local songPath = song:GetSongDir()
        hash = pathMap[songPath]
    end
    if not hash then return nil end
    if not spice[hash] then return nil end
    if not diffMap[hash] then return nil end
    if not styleMap[hash] then return nil end
    if styleMap[hash] ~= currentStyle then return nil end
    local s = math.log(spice[hash]["spice"]) / math.log(2)
    local diff = diffMap[hash]

    local qualityFit = EvaluateScobilityFit(player, s)
    if not qualityFit then return nil end

    local targetEX = 100.0 * (perfectOffset - math.pow(2, s - qualityFit))
    if targetEX > 100 then
        targetEX = 100
    elseif targetEX < 0 then
        targetEX = 0
    else
        targetEX = math.ceil(targetEX * 100) * 0.01
    end

    local currentEX = 0
    local currentSP = 0
    local currentEP = 0
    local targetSP = 0
    local targetEP = 0
    local potentialSP = 0
    local potentialEP = 0
    if hashMap[hash] and hashMap[hash]["ex"] then
        currentEX = hashMap[hash]["ex"] * 0.01
        currentSP = math.floor(hashMap[hash]["passingPoints"] + hashMap[hash]["maxScoringPoints"] * EX2SP(currentEX) * 0.01)
        currentEP = (hashMap[hash]["ex"] == 10000) and 1000 or math.floor(EX2EP(currentEX))
        targetSP = math.floor(hashMap[hash]["passingPoints"] + hashMap[hash]["maxScoringPoints"] * EX2SP(targetEX) * 0.01)
        targetEP = (targetEX == 100) and 1000 or math.floor(EX2EP(targetEX))
    end
    local contributorsSP = {}
    local contributorsEP = {}
    local floorSP = 1000000
    local floorEPEX = 100
    local alreadyContributesSP = false
    local alreadyContributesEP = false
    for topSP in ivalues(hands[pn]["SP"]) do
        contributorsSP[#contributorsSP+1] = topSP["hash"]
        floorSP = math.min(floorSP, topSP["value"])
        if hash == topSP["hash"] then alreadyContributesSP = true end
    end
    for topEP in ivalues(hands[pn]["EP"][diff]) do
        contributorsEP[#contributorsEP+1] = topEP["hash"]
        floorEPEX = math.min(floorEPEX, topEP["value"])
        if hash == topEP["hash"] then alreadyContributesEP = true end
    end

    if alreadyContributesSP then
        potentialSP = targetSP - currentSP
    else
        potentialSP = targetSP - floorSP
    end
    if potentialSP < 0 then potentialSP = 0 end

    if alreadyContributesEP then
        potentialEP = targetEP - currentEP
    else
        potentialEP = targetEP - math.floor(EX2EP(floorEPEX))
    end
    if potentialEP < 0 then potentialEP = 0 end

    return {
        ["qualityFit"] = qualityFit,
        ["targetEX"] = targetEX,
        ["currentSP"] = currentSP,
        ["currentEP"] = currentEP,
        ["currentRP"] = currentSP + currentEP,
        ["targetSP"] = targetSP,
        ["targetEP"] = targetEP,
        ["targetRP"] = targetSP + targetEP,
        ["potentialSP"] = potentialSP,
        ["potentialEP"] = potentialEP,
        ["potentialRP"] = potentialSP + potentialEP,
    }
end


local FetchRelevantMusicWheelItemActors = function(musicWheelItem)
    local a0a = musicWheelItem:GetChild("SongName")
    if not a0a then return nil end
    local a0a1 = a0a:GetChild("Title")
    if not a0a1 then return nil end
    local a0b = musicWheelItem:GetChild("SongNormalPart")
    if not a0b then return nil end
    local a0b1 = a0b:GetChild("")
    result = {
        ["title"] = a0a1:GetText(),
    }
    Trace("### a0b")
    rec_print_children(a0b)
    for i, ai in ipairs(a0b1) do
        Trace("### "..tostring(i))
        rec_print_children(ai)
        if ai then
            local y = ai:GetY()
            if (y == -7) then
                result["P1"] = ai
            elseif (y == 7) then
                result["P2"] = ai
            end
        end
    end
    return result
end


local ScobilityInTheSongwheel = function(player)
    local pn = ToEnumShortString(player)
    local pnOther = (pn == "P1") and "P2" or "P1"
    if not coefs[pn] then return end

    local a0 = SCREENMAN:GetTopScreen()
    if not a0 then return end
    local a1 = a0:GetChild("MusicWheel")
    if not a1 then return end
    local a2 = a1:GetChild("MusicWheelItem")
    if not a2 then return end

    local songsPresent = {}
    for i, ai in ipairs(a2) do
        -- Trace("### "..tostring(i))
        -- rec_print_children(ai)
        local a3 = FetchRelevantMusicWheelItemActors(ai)
        if a3 and a3["title"] then
            if titleMap[a3["title"]] then
                local scobilityInfo = EvaluateChartForPlayer(player, nil, titleMap[a3["title"]])
                if scobilityInfo then
                    if a3[pn] then
                        local hint = "+" .. 
                            tostring(("%.0f"):format(scobilityInfo["potentialRP"])) ..
                            " RP @ " ..
                            tostring(("%.2f"):format(scobilityInfo["targetEX"])) ..
                            "% EX"
                        Trace(">>> " .. a3["title"] .. ": " .. hint)
                        a3[pn]:settext(hint)
                    end
                    if a3[pnOther] and GAMESTATE:GetNumSidesJoined() == 1 then
                        a3[pnOther]:settext("")
                    end
                else
                    if a3[pn] then a3[pn]:settext("hi :)") end
                    Trace(">>> " .. a3["title"] .. ": hi :)")
                end
            else
                Trace(TableToString(titleMap))
            end
        end
    end
end

local ScobilityInTheScorebox = function(player)
end


local CacheSpice = function()
    if spiceUpdateInProgress then return end

    if (GetTimeSinceStart() - spiceLastUpdatedRelative < spiceUpdateInterval) then
        return
    end

    spiceUpdateInProgress = true

    NETWORK:HttpRequest{
        url="https://scobility.azurewebsites.net/catalog/" .. catalogName .. "/chart/all",
        method="GET",
        connectTimeout=60,
        transferTimeout=60,
        onResponse=function(response)
            if response.statusCode then
                local body = nil
                local code = response.statusCode
                if code ~= 200 then
                    SM("scobility: Did not send ITL2025 spice values. (" .. tostring(code) .. ")")
                    return
                end

                body = JsonDecode(response.body)
                if not body.status then
                    SM("scobility: Couldn't retrieve ITL2025 spice values.")
                    return
                end
                if (body.data and not #body.data) then
                    SM("scobility: No ITL2025 spice values retrieved.")
                    return
                end

                spice = body.data
                spiceLastUpdatedRelative = GetTimeSinceStart()
                for player in ivalues(GAMESTATE:GetEnabledPlayers()) do
                    CalculatePlayerData(player)
                end
                SM("scobility: ITL2025 spice values successfully cached.")
                spiceUpdateInProgress = false
            end
        end,
    }
end


af = Def.ActorFrame {
    ModuleCommand=function(self)
        CacheSpice()
    end,
    InitCommand=function(self)
        for player in ivalues(GAMESTATE:GetEnabledPlayers()) do
            CalculatePlayerData(player)
        end
    end,
	CurrentSongChangedMessageCommand=function(self)
        local result = ""
        for player in ivalues(GAMESTATE:GetEnabledPlayers()) do
            local pn = ToEnumShortString(player)
            local song = GAMESTATE:GetCurrentSong()
            if #spice and (not coefs[pn]) then
                SM("scobility: Recalculating...")
                CalculatePlayerData(player)
            end
            if coefs[pn] and song then
                local scobility_target = EvaluateChartForPlayer(player, song, nil)
                if scobility_target then
                    SM(
                        "scobility: Target " ..
                        scobility_target["targetEX"] ..
                        "% EX for +" ..
                        scobility_target["potentialSP"] ..
                        " SP, +" ..
                        scobility_target["potentialEP"] ..
                        " EP = +" ..
                        scobility_target["potentialRP"] ..
                        " RP"
                    )
                end
            end
            ScobilityInTheSongwheel(player)
        end
	end
}

for player in ivalues(PlayerNumber) do
    af[#af+1] = Def.ActorFrame {
        PlayerJoinedMessageCommand=function(self)
            self:visible(GAMESTATE:IsPlayerEnabled(player))
            CalculatePlayerData(player)
        end,
        PlayerUnjoinedMessageCommand=function(self)
            self:visible(GAMESTATE:IsPlayerEnabled(player))
            local pn = ToEnumShortString(player)
            coefs[pn] = nil
        end,
    }
end

t["ScreenSelectMusic"] = af

return t
