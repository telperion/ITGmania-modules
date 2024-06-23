--[[--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--
-- Dynamic Sudden v0.2
-- 
-- The Sudden option in Uncommon Modifiers is replaced with a dynamically
-- changing amount of Sudden, chosen instantaneously to keep the time interval
-- between the receptors and the sudden horizon constant.
--
-- Current limitations:
--      Won't play nicely with speed/scroll rates
--      Won't play nicely with some mods/FX files
--      Won't play nicely with SSC split timing (sorry, no A4A)
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

local DynamicSuddenActive = {}
local DynamicSuddenEffectiveTime = {}
local DynamicSuddenConversionFactor = {}
local DynamicSuddenReported = false

local CalculateDynamicSuddenConstants = function(player)
    player = player or GAMESTATE:GetMasterPlayerNumber()
    local pn = ToEnumShortString(player)
    local pops = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Song")

    -- Dunno how to do this for course mode yet.
    if GAMESTATE:IsCourseMode() then
        return {}
    end
    local Steps = GAMESTATE:GetCurrentSteps(player)
    if not Steps then
        return {}
    end
    local MusicRate = SL.Global.ActiveModifiers.MusicRate or 1

    local SpeedModType = SL[pn].ActiveModifiers.SpeedModType
    if SpeedModType == "C" then
        pops:Sudden(0, 1000000) -- You probably have Sudden set and don't want it?
        return {}
    end
    local SpeedMod = SL[pn].ActiveModifiers.SpeedMod

    local bpms = GetDisplayBPMs(player, Steps, MusicRate)
    if not (bpms and bpms[1] and bpms[2]) then
        return {}
    end
    local EffectiveSpeedMod = (SpeedModType == "X") and SpeedMod or (SpeedMod / bpms[2])

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
    local _TOTAL_Y_DISTANCE = SCREEN_CENTER_Y +
                                  (pops:Reverse() and
                                      (-SL[pn].ActiveModifiers.NoteFieldOffsetY +
                                          THEME:GetMetric("Player", "ReceptorArrowsYReverse")) or
                                      (SL[pn].ActiveModifiers.NoteFieldOffsetY -
                                          THEME:GetMetric("Player", "ReceptorArrowsYStandard")))
    local mini = pops:Mini()
    local arrow_height = _ARROW_SPACING * EffectiveSpeedMod * (1 - mini * 0.5)
    local beats_on_screen = _TOTAL_Y_DISTANCE / arrow_height
    DynamicSuddenEffectiveTime[player] = beats_on_screen * (60 / bpms[2])
    DynamicSuddenConversionFactor[player] = arrow_height / _CENTER_LINE_Y
    -- Trace("### " .. player .. ": " .. tostring(DynamicSuddenEffectiveTime[player]) .. " sec.")
end

local SuddenUpdater = function(af)
    local all_dynamic_calculated = true
    local needs_reporting = false
    for PlayerNumber in ivalues(GAMESTATE:GetEnabledPlayers()) do
        local pn = ToEnumShortString(PlayerNumber)
        if DynamicSuddenEffectiveTime[PlayerNumber] then
            needs_reporting = true
            local Steps = GAMESTATE:GetCurrentSteps(PlayerNumber)
            if not Steps then
                return
            end
            local TimingData = Steps:GetTimingData()
            if not TimingData then
                return
            end
            local pops = GAMESTATE:GetPlayerState(PlayerNumber):GetPlayerOptions("ModsLevel_Song")
            local time = GAMESTATE:GetSongPosition():GetMusicSecondsVisible()
            local beat = GAMESTATE:GetSongPosition():GetSongBeatVisible()
            local horizon = TimingData:GetBeatFromElapsedTime(time + DynamicSuddenEffectiveTime[PlayerNumber])
            local vertical_in_centerline_units = (horizon - beat) * DynamicSuddenConversionFactor[PlayerNumber]
            if (vertical_in_centerline_units < 0) then
                return
            end
            pops:SuddenOffset(vertical_in_centerline_units - 1, 1000000)
            -- Trace("### "..tostring(time).." sec., "..tostring(beat).." beats, "..tostring(horizon).." futurebeat, "..tostring(vertical_in_centerline_units-1).." shift")
        else
            if DynamicSuddenActive[PlayerNumber] then
                all_dynamic_calculated = false
            end
            CalculateDynamicSuddenConstants(PlayerNumber)
        end
    end
    if all_dynamic_calculated and needs_reporting and not DynamicSuddenReported then
        local report_message = "DynamicSudden active: "
        for PlayerNumber in ivalues(GAMESTATE:GetEnabledPlayers()) do
            if DynamicSuddenActive[PlayerNumber] then
                report_message = report_message .. ToEnumShortString(PlayerNumber) .. "=" ..
                                     string.format("%0.f", DynamicSuddenEffectiveTime[PlayerNumber] * 1000) .. "ms "
            end
        end
        SCREENMAN:SystemMessage(report_message)
        DynamicSuddenReported = true
    end
end

t["ScreenGameplay"] = Def.ActorFrame {
    ModuleCommand = function(self)
        DynamicSuddenActive = {}
        DynamicSuddenEffectiveTime = {}
        DynamicSuddenConversionFactor = {}
        DynamicSuddenReported = false
        for PlayerNumber in ivalues(GAMESTATE:GetEnabledPlayers()) do
            -- Substitute if Sudden was selected at the options screen and we're not on CMod.
            DynamicSuddenActive[PlayerNumber] = (
                GAMESTATE:GetPlayerState(PlayerNumber):GetPlayerOptions("ModsLevel_Preferred"):Sudden() > 0.5
            ) and (
                SL[ToEnumShortString(PlayerNumber)].ActiveModifiers.SpeedModType ~= "C"
            )
        end
        self:SetUpdateFunction(SuddenUpdater)
    end
}

local ReviseOptionText = Def.ActorFrame {
    ModuleCommand = function(self)
        local ScreenOptions = SCREENMAN:GetTopScreen()
        if not ScreenOptions or not ScreenOptions.GetNumRows then return end
        local num_rows = ScreenOptions:GetNumRows()
        
        -- OptionRows on ScreenOptions are 0-indexed, so start counting from 0
        for i=0,num_rows-1 do
            local OptionRow = ScreenOptions:GetOptionRow(i)
            if OptionRow:GetName() == "Appearance" then
                local num_choices = OptionRow:GetNumChoices()
                for i=1,num_choices do
                    local ch = OptionRow:GetChild(""):GetChild("Item")[i]
                    if ch:GetText() == "Sudden" then
                        ch:settext("Dynamic\nSudden")
                          :vertspacing(-6)
                          :zoomy(0.6)
                          :addy(-3)
                        break
                    end
                end
                break
            end
        end
    end
}

t["ScreenPlayerOptions"] = ReviseOptionText
t["ScreenPlayerOptions2"] = ReviseOptionText
t["ScreenPlayerOptions3"] = ReviseOptionText

local DisableUpdater = Def.ActorFrame {
    ModuleCommand = function(self)
        self:SetUpdateFunction(nil)
    end
}
t["ScreenSelectMusic"] = DisableUpdater
t["ScreenEvaluation"] = DisableUpdater

return t
