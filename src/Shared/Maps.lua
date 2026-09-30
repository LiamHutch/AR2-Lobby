-- Fallback map config for a prod lobby place that has no config modules of
-- its own (see src/Server/PlaceConfig.lua; each entry here is the same table
-- a config module returns). One entry per map, in display order.
--
--   Key        stable id, never shown; sent to the game in teleport data
--   Name       title; the first word takes the accent colour
--   Accent     hex colour for the first word of the title
--   Blurb      flavour text under the title; optional
--   Stats      { label, value } pairs shown under the blurb
--   Tags       { text, colour? } pairs shown under the title on the picker
--              card; colour is hex, missing is a dull grey
--   Platforms  support per platform key from Platform.lua (PC, Xbox, PS4,
--              PS5, Mobile; "PlayStation" means both): "warn" shows a notice
--              but still lets them in, "blocked" stops them joining. Unlisted
--              platforms are fully supported. Roblox can't tell PS4 from PS5,
--              so when only one is supported PlayStation players get a warning
--              naming the other, not a block
--   Images     the map's art (1024x576), cycled on both its picker card and the
--              map view's preview. Image asset ids, not Decal ids (a decal's
--              image id is its Texture; pasting a decal id into an ImageLabel in
--              Studio converts it)
--   CardImages optional art for the picker card only, 756x1024 (the card's
--              shape), full-bleed with no darkened margins; the map view
--              still uses Images. Missing uses Images on the card too
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
		-- the Beta Map; the key stays Beta, the game and teleport data use it
		Name = "Halsey Islands",
		Accent = "#D9A21B",
		Blurb = "Apocalypse Rising 2’s flagship map, featuring a large playable area with diverse environments and a high-fidelity visual style. Recommended for most players.",
		Stats = {
			{ "RELEASE DATE", "2025" },
			{ "MAX PLAYERS", "32" },
			{ "SIZE", "LARGE" },
			{ "DETAIL", "HIGH" },
		},
		Tags = {
			{ "Recommended", "#8FC46A" },
			{ "Main", "#D9A21B" },
		},
		Platforms = {
			PS4 = "blocked", -- crashes on load; PS5 is fine
			Mobile = "blocked",
		},
		Images = {
			"rbxassetid://100458318643619", -- beta1 ashland
			"rbxassetid://119965385609259", -- beta3 fairview
			"rbxassetid://108090803277875", -- beta4 grain
			"rbxassetid://90113538973109", -- beta5 beaufort
			"rbxassetid://140317366312469", -- beta6 swamp
			"rbxassetid://119672357664079", -- beta7 magnolia
		},
		CardImages = {
			"rbxassetid://72133014912064", -- 1 ashland
			"rbxassetid://119317650646372", -- 2 RT
			"rbxassetid://128816300628380", -- 3 fairview
			"rbxassetid://93788575839107", -- 4 magnolia
			"rbxassetid://107603186796265", -- 5 grain
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
		-- the Kin Map (Reimagined, on the retro build)
		Name = "Kin Flats",
		Accent = "#5A9FD8",
		Blurb = "The original Apocalypse Rising map, featuring a smaller playable area, streamlined terrain, and a classic visual style.",
		Stats = {
			{ "RELEASE DATE", "2013" },
			{ "MAX PLAYERS", "16" },
			{ "SIZE", "SMALL" },
			{ "DETAIL", "LOW" },
		},
		Tags = {
			{ "Demo" },
			{ "Lite" },
		},
		Platforms = {},
		Images = {
			"rbxassetid://83414551442195", -- reimagined1 kin
			"rbxassetid://137147392099225", -- reimagined2 factory
			"rbxassetid://99622524945108", -- reimagined3 ref
			"rbxassetid://127111331315666", -- reimagined4 vernal
		},
		PlaceIds = {
			81089296768446, -- production retro
		},
	},
}
