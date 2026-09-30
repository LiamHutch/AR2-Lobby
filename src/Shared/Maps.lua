-- One entry per playable map, in display order. Adding a map is adding an entry.
--
--   Key        stable id, never shown; sent to the game in teleport data
--   Name       title; the first word takes the accent colour
--   Accent     hex colour for the first word of the title
--   Blurb      flavour text under the title; optional
--   Stats      { label, value } pairs shown under the blurb
--   Platforms  support per platform key from Platform.lua: "warn" shows a
--              notice but still lets them in, "blocked" stops them joining.
--              Unlisted platforms are fully supported
--   Images     preview art (up to 6), 1024px max; crossfades in the map view
--   Backdrop   optional tiny (~128px) copy of the art; Roblox's upscaling
--              blurs it into the full-screen background
--   PlaceIds   every place that runs this map, prod and test. The lobby uses
--              whichever one is in its own universe. A map with no place in
--              this universe shows as coming soon.

return {
	{
		Key = "Beta",
		Name = "Beta Map",
		Accent = "#D9A21B",
		Blurb = "",
		Stats = {
			{ "RELEASE DATE", "2025" },
			{ "MAX PLAYERS", "32" },
			{ "SIZE", "LARGE" },
			{ "DETAIL", "HIGH" },
		},
		Platforms = {
			PlayStation = "blocked", -- crashes on load
			Mobile = "warn",
		},
		-- placeholders from the tourney map list in the game's
		-- ServerScriptService.Classes.CustomMatches until the real set lands
		Images = {
			"rbxassetid://10076994076",
			"rbxassetid://10076992315",
			"rbxassetid://10076991949",
			"rbxassetid://10076991419",
			"rbxassetid://10076990569",
			"rbxassetid://10076989899",
		},
		PlaceIds = {
			863266079, -- Prod - Main
			12123099753, -- Test - Prod main
		},
	},

	{
		Key = "Kin",
		Name = "Kin",
		Accent = "#5A9FD8",
		Blurb = "The original Apocalypse Rising map, featuring a smaller playable area, streamlined terrain, and a classic visual style.",
		Stats = {
			{ "RELEASE DATE", "2013" },
			{ "MAX PLAYERS", "16" },
			{ "SIZE", "SMALL" },
			{ "DETAIL", "LOW" },
		},
		Platforms = {},
		Images = {},
		PlaceIds = {},
	},
}
