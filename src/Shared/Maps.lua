-- Fallback map config for a prod lobby place that has no config folders of
-- its own (see src/Server/PlaceConfig.lua; tools/maps-to-folders.lua turns
-- this file into those folders). One entry per map, in display order.
--
--   Key        stable id, never shown; sent to the game in teleport data
--   Name       title; the first word takes the accent colour
--   Accent     hex colour for the first word of the title
--   Blurb      flavour text under the title; optional
--   Stats      { label, value } pairs shown under the blurb
--   Platforms  support per platform key from Platform.lua: "warn" shows a
--              notice but still lets them in, "blocked" stops them joining.
--              Unlisted platforms are fully supported
--   Images     landscape art (1024px max) for the map view's preview; crossfades
--   CardImages portrait art for the map's card in the picker; falls back to Images
--              Both take Image asset ids, not Decal ids (a decal's image id is its
--              Texture; pasting a decal id into an ImageLabel in Studio converts it)
--   Backdrop   optional tiny (~128px) copy of the art; Roblox's upscaling
--              blurs it into the full-screen background
--   PlaceIds   every place that runs this map, prod and test. The lobby uses
--              whichever one is in its own universe. A map with no place in
--              this universe shows as coming soon.
--   Vip        { [kind] = placeIds } for VIP servers of this map (kinds are in
--              Protocol.lua); listed only once Protocol.VIP_LISTING is on

return {
	{
		Key = "Beta",
		Name = "Beta Map",
		Accent = "#D9A21B",
		Blurb = "Apocalypse Rising 2’s flagship map, featuring a large playable area with diverse environments and a high-fidelity visual style. Recommended for most players.",
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
		Images = {
			"rbxassetid://100458318643619", -- beta1 ashland
			"rbxassetid://119965385609259", -- beta3 fairview
			"rbxassetid://108090803277875", -- beta4 grain
			"rbxassetid://119672357664079", -- beta7 magnolia
		},
		CardImages = {
			"rbxassetid://90113538973109", -- beta5 beaufort
			"rbxassetid://140317366312469", -- beta6 swamp
		},
		PlaceIds = {
			90014710188160, -- production main (863266079 is the lobby now)
			12123099753, -- Test - Prod main
		},
		Vip = {
			freeroam = {
				105446216022659, -- Prod - VIP Freeroam
				107047742607799, -- its dev/test copy
			},
		},
	},

	{
		Key = "Kin",
		-- Kin is a city on the Reimagined map; the picker calls it Kin Map
		Name = "Kin Map",
		Accent = "#5A9FD8",
		Blurb = "The original Apocalypse Rising map, featuring a smaller playable area, streamlined terrain, and a classic visual style.",
		Stats = {
			{ "RELEASE DATE", "2013" },
			{ "MAX PLAYERS", "16" },
			{ "SIZE", "SMALL" },
			{ "DETAIL", "LOW" },
		},
		Platforms = {},
		Images = {
			"rbxassetid://99622524945108", -- reimagined3 ref
			"rbxassetid://127111331315666", -- reimagined4 vernal
		},
		CardImages = {
			"rbxassetid://83414551442195", -- reimagined1 kin
			"rbxassetid://137147392099225", -- reimagined2 factory
		},
		PlaceIds = {
			81089296768446, -- production retro
		},
	},
}
