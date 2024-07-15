--[[--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--||--
-- Annotations v0.1
-- 
-- Add visuals during gameplay that highlight particular types of tech:
--      Brackets: A line or "tie" connecting the two involved arrows
--      Footswitches: A glow outline around each involved arrow
-- Foot placement, if annotated, is indicated by darkening the half of the
-- arrow that corresponds to the opposite foot - e.g., if the left foot should
-- be used to hit an arrow, the right half of the arrow is darkened.
--
-- Not automatically derived! A simfile that wants to make use of this module
-- has to include an "annotations.json" of prescribed format and contents.
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

t["ScreenGameplay"] = Def.ActorFrame {
    ModuleCommand = function(self)
        local player = GAMESTATE:GetMasterPlayerNumber()
        local pn = ToEnumShortString(player)
        local pops = GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Preferred")

        local current_noteskin = pops:NoteSkin()
        local note_path = NOTESKIN:GetPathForNoteSkin("_down","tap note model",current_noteskin)
        local note_model = lua.ReadFile(note_path)
        Trace(note_model)

        local meshes = {}
        local in_meshes = false
        local current_mesh = nil
        local phase = nil
        local vertex_count = 0
        local normal_count = 0
        local triangle_count = 0
        for line in note_model:gmatch("[^\r\n]+") do
            if line:find("^//") then
                Trace("### Comment: "..line)
            elseif line:find("^Meshes:") then
                Trace("### In meshes")
                in_meshes = true
            elseif line:find("^Materials:") or line:find("^Bones:") then
                Trace("### Out of meshes")
                in_meshes = false
            elseif in_meshes then
                if line:find('^".+" %d+ %d+$') then
                    current_match = line:match('^"(.+)"')
                    phase = "name"
                elseif line:find("^(%d+)$") then
                    if phase == "name" then
                        vertex_count = line:match("^(%d+)$")
                        phase = "vertex"
                    elseif phase == "vertex" then
                        normal_count = line:match("^(%d+)$")
                        phase = "normal"
                    elseif phase == "normal" then
                        triangle_count = line:match("^(%d+)$")
                        phase = "triangle"
                    end
                elseif phase == "vertex" then
                    for flags, x, y, z, u, v, bone in line:gmatch("(%d+)%s+([-.%d]+)%s+([-.%d]+)%s+([-.%d]+)%s+([-.%d]+)%s+([-.%d]+)%s+([-%d]+)") do
                        Trace("### Vertex | Flags: "..flags.." (x, y, z): "..x..", "..y..", "..z.." (u, v): "..u..", "..v.." bone: "..bone)
                    end
                elseif phase == "normal" then
                    for x, y, z in line:gmatch("([-.%d]+)%s+([-.%d]+)%s+([-.%d]+)") do
                        Trace("### Normal | (x, y, z): "..x..", "..y..", "..z)
                    end
                elseif phase == "triangle" then
                    for flags, v1, v2, v3, n1, n2, n3, smoothing in line:gmatch("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)") do
                        Trace("### Triangle | Flags: "..flags.." Vertices: "..v1..", "..v2..", "..v3.." Normals: "..n1..", "..n2..", "..n3.." Smoothing Group: "..smoothing)
                    end
                end
            end
        end
    end
}

return t

