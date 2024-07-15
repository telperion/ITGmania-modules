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
-- has to include an "annotations.json" of prescribed format.
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
    end
}


return t

