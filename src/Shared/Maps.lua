-- One entry per playable map, in display order. Adding a map is adding an entry.
--
--   Key       stable id, never shown; sent to the game in teleport data
--   Name      card title; the first word takes the accent colour
--   Accent    hex colour for the first word of the title
--   Images    card art asset ids, crossfades when there is more than one
--   Stats     short strings shown on hover, e.g. "8 km²"; optional
--   PlaceIds  every place that runs this map, prod and test. The lobby uses
--             whichever one is in its own universe. A map with no place in
--             this universe shows as coming soon.

return {
	{
		Key = "Beta",
		Name = "Beta Map",
		Accent = "#D9A21B",
		Images = {},
		Stats = {},
		PlaceIds = {
			863266079, -- Prod - Main
			12123099753, -- Test - Prod main
		},
	},

	{
		Key = "Demo",
		Name = "Demo Map",
		Accent = "#5A9FD8",
		Images = {},
		Stats = {},
		PlaceIds = {},
	},
}
