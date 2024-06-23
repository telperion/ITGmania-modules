--[[--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--
-- Dynamic Sudden v0.1
-- 
-- Current limitations:
--      Won't play nicely with speed/scroll rates
--      Won't play nicely with some mods/FX files
--
-- Copyright (c) 2024 Telperion
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

local DynamicSuddenUpdateTable = {}
local ApproachSpeed = 4000
local LastCheckedTime = nil

local TabulateDynamicSuddenUpdates = function(player)
	player   = player or GAMESTATE:GetMasterPlayerNumber()
	local pn = ToEnumShortString(player)

    -- Dunno how to do this for course mode yet.
    if GAMESTATE:IsCourseMode() then return {} end
	local Steps = GAMESTATE:GetCurrentSteps(player)
    if not Steps then return {} end
	local MusicRate    = SL.Global.ActiveModifiers.MusicRate or 1

	local SpeedModType = SL[pn].ActiveModifiers.SpeedModType
	local SpeedMod     = SL[pn].ActiveModifiers.SpeedMod

	local bpms = GetDisplayBPMs(player, Steps, MusicRate)
	if not (bpms and bpms[1] and bpms[2]) then return {} end
    local EffectiveSpeedMod = (SpeedModType=="X") and SpeedMod or (SpeedMod / bpms[2])

    -- Parse timing data.
    local TimingData = Steps:GetTimingData()
    local BeatsToBPMs = TimingData:GetBPMsAndTimes(true)       -- As table of {beat, BPM}.
    local TimesToBPMs = {}
    for bt in ivalues(BeatsToBPMs) do 
        -- We want to be able to apply SuddenOffset with some constant delay before a BPM change occurs.
        -- For that, we need the actual times of application, not the beat numbers.
        TimesToBPMs[#TimesToBPMs+1] = {TimingData:GetElapsedTimeFromBeat(bt[1]) * MusicRate, bt[2]}
    end
    
    local so = GAMESTATE:GetSongOptionsObject("ModsLevel_Song")
	local DynamicSuddenTime = SL[pn].ActiveModifiers.DynamicSuddenTime
    if not DynamicSuddenTime then return {} end
    if DynamicSuddenTime < 0 then return {} end
    if DynamicSuddenTime > 10 then return {} end

    -- Set up a mods table of dynamic sudden updates to be applied.
    -- [1]: application time
    -- [2]: SuddenOffset value

    -- Calculating SuddenOffset:
        -- #define CENTER_LINE_Y 160	// from fYOffset == 0
        -- static float GetCenterLine()
        -- {
        -- 	/* Another mini hack: if EFFECT_MINI is on, then our center line is at
        -- 	 * eg. 320, not 160. */
        -- 	const float fMiniPercent = curr_options->m_fEffects[PlayerOptions::EFFECT_MINI];
        -- 	const float fZoom = 1 - fMiniPercent*0.5f;
        -- 	return CENTER_LINE_Y / fZoom;
        -- }
        -- static float GetSuddenEndLine()
        -- {
        --     return GetCenterLine() +
        --         FADE_DIST_Y * SCALE( GetHiddenSudden(), 0.f, 1.f, -0.0f, +0.25f ) +
        --         GetCenterLine() * curr_options->m_fAppearances[PlayerOptions::APPEARANCE_SUDDEN_OFFSET];
        -- }
    -- Default value for sudden offset is 0.
    local _CENTER_LINE_Y = 160
    local _ARROW_SPACING = 64
    local mini = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Song"):Mini()
    local center_line = _CENTER_LINE_Y / (1 - mini * 0.5)
    local arrows_per_centerline_unit = center_line / _ARROW_SPACING
    local beats_per_centerline_unit = arrows_per_centerline_unit / EffectiveSpeedMod
    local last_sudden_offset = nil
    local DynamicSuddenChanges = {}
    for bt in ivalues(TimesToBPMs) do
        local seconds_per_centerline_unit = (60 / bt[2]) * beats_per_centerline_unit
        local sudden_scaling_required = DynamicSuddenTime / seconds_per_centerline_unit
        local adjusted_time = bt[1] - DynamicSuddenTime
        local sudden_offset = sudden_scaling_required - 1
        local approach_rate = 1000000
        if last_sudden_offset then
            approach_rate = math.abs(sudden_offset - last_sudden_offset) / DynamicSuddenTime
        end
        DynamicSuddenChanges[#DynamicSuddenChanges+1] = {adjusted_time, sudden_offset, approach_rate}
        last_sudden_offset = sudden_offset
        Trace("### " .. player .. ": " .. tostring(adjusted_time) .. ", " .. tostring(sudden_offset) .. " (" .. tostring(bt[2]) .. ") ")
    end
    return DynamicSuddenChanges
end

local SuddenUpdater = function(af)
    for PlayerNumber in ivalues(GAMESTATE:GetHumanPlayers()) do
        local pn = ToEnumShortString(PlayerNumber)
        local DynamicSuddenTime = SL[pn].ActiveModifiers.DynamicSuddenTime
        if DynamicSuddenTime then
            local recalc = true
            if DynamicSuddenUpdateTable[PlayerNumber] then
                if #DynamicSuddenUpdateTable[PlayerNumber] > 0 then
                    recalc = false
                end
            end
            if recalc then
                DynamicSuddenUpdateTable[PlayerNumber] = TabulateDynamicSuddenUpdates(PlayerNumber)
            end

            local time = GAMESTATE:GetSongPosition():GetMusicSeconds()
            local pops = GAMESTATE:GetPlayerState(PlayerNumber):GetPlayerOptions("ModsLevel_Song")
            local rolling_point = nil
            for test_point in ivalues(DynamicSuddenUpdateTable[PlayerNumber]) do
                if time < test_point[1] then
                    local update_point = rolling_point or test_point
                    pops:Sudden(1, 1000000)
                    pops:SuddenOffset(update_point[2], update_point[3])
                    --Trace("### " .. PlayerNumber .. " @ " .. tostring(time) .. ": " .. tostring(update_point[1]) .. ", " .. tostring(update_point[2]) .. ") ")               
                    break
                end
                rolling_point = test_point
            end
            LastCheckedTime = time
        end
    end
end

t["ScreenSelectMusic"] = Def.ActorFrame {
    ModuleCommand=function(self)
        self:SetUpdateFunction(nil)
        for PlayerNumber in ivalues(GAMESTATE:GetHumanPlayers()) do
            local pn = ToEnumShortString(PlayerNumber)
            SL[pn].ActiveModifiers.DynamicSuddenTime = 1.000
            LastCheckedTime = nil
            SCREENMAN:SystemMessage("Set DynamicSudden time for " .. PlayerNumber .. " to " .. tostring(SL[pn].ActiveModifiers.DynamicSuddenTime))
        end
    end
}

t["ScreenGameplay"] = Def.ActorFrame {
    ModuleCommand=function(self)
        SCREENMAN:SystemMessage("DynamicSudden active!")
        DynamicSuddenUpdateTable = {}
        self:SetUpdateFunction(SuddenUpdater)
    end,
}


return t