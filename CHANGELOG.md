# Changelog

All notable changes to EasyFind: GPS Navigation Extension are documented in this file.

---

## [1.1.0] - 2026-11-02

### Added
- **Elevators**: a route can ride a lift; the step reads "Take the elevator to" and is done once you reach the other level (Undercity's three lifts on every classic client)
- **Names typed without their space**: "rothide mystic" finds Rot Hide Mystic
- **Recent searches**: a place picked for a trip's field joins the recent searches
- **Other extensions** can tell which creatures EasyFind already lists, so they mark those rows instead of adding a second one (with EasyFind 4.2.0)

### Changed
- **Undercity**: directions to Undercity no longer lead into Lordamere Lake and the sewers; they end where the road enters the Ruins of Lordaeron, and spots inside are reached by its elevators. The last stretch to the gate is still being worked on
- **The GPS menu**: the list choices and the beacon sit under Show, the step switches under planning
- **The minimap** draws only the way ahead; the map keeps the walk behind as planned
- **Back onto the route**: off the route, the way back is drawn again from where you stand as you move and joins the route well ahead, so the arrow and the minimap line no longer turn back every few yards; the walk behind you stays drawn
- **Drawn walks** cut straight across open ground instead of running along hidden map tile edges

### Fixed
- **A Lua error while planning a long walk** (Nav.lua line 1405) when the map's ground was read twice at once
- **Creature search**: "greater dusk" finds Greater Duskbat instead of reading Duskwood into it
- **Clear route** also removes the pin at the journey's end
- **City maps**: a walk outside a city is no longer drawn on the city's map, and a road past a city's walls no longer counts as a step through the city
- **The arrival line** lines up with the time line
- **Fewer hitches** while you walk off the route

---

## [1.0.0] - 2026-10-29

### Added
- **Its own addon**: GPS came inside EasyFind until now; it installs on its own as an extension, and your settings carry over
- **Directions**: from where you stand, or a trip planned from any start, through flights, boats, zeppelins, the tram, portals, teleports and your hearthstone, then the walk
- **Where the steps show**: a small window, the map's GPS page, or the objective tracker; an arrow at your character, the route on the map and the minimap, and a beacon where each step leads
- **Trips**: several stops, a search along the route, and routes shared as a link in chat
- **Safety**: a red warning where the route crosses creatures far above your level; on WoW Forever, Classic Era and TBC Anniversary, walks follow the ground and go around dangerous ground when you ask
- **Clients**: retail, WoW Forever, Classic Era, TBC Anniversary and Mists Classic
