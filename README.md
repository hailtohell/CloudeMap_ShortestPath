# CloudeMap: Shortest Path

> **AI disclaimer:** this plugin's code, its icon and this README were written with an AI
> assistant (Claude, by Anthropic), directed, tested and reviewed in game by a human. Expect the
> occasional rough edge; use it at your own risk.

A plugin for [CloudeMap](https://github.com/hailtohell/CloudeMap) that shows
[Shortest Path Forever](https://github.com/cjber/shortest-path-forever) on CloudeMap's map.
Both addons are required, and CloudeMap must be newer than 0.19.9 (the version that brought its
plugin interface).

## Features

- **Your journey:** the walk you're on follows Shortest Path's arrow; later legs (flights, boats,
  zeppelins, portals) in Shortest Path's colours, the walk in the route colour you picked there.
- **Destination pin:** its tooltip lists each step with its time and the time left.
- **Plan journeys right on CloudeMap:** Ctrl+right-click anywhere on the map and Shortest Path
  routes you there, even in a fight.
- **Transports:** boats, zeppelins, lifts, the Deeprun Tram and portals as pins, on every map and
  at every zoom. Hover a dock to see where it goes, its route, and when it next leaves once
  Shortest Path has seen that ship. The other faction's routes and portals follow Shortest Path's
  own settings.
- **Seamless sea lanes:** boat and zeppelin routes are drawn round the land, also across the sea
  between Kalimdor and the Eastern Kingdoms, never through a continent.
- Each part has its own toggle in CloudeMap's Pins list, under Other addons.

## Credits

From Shortest Path Forever by cjber (GPL-3.0-or-later):

- the transport data, which it builds from wago.tools DB2 and CMaNGOS classic-db;
- the sea lanes, routed on its walking grid;
- half of the icon: CloudeMap's icon and Shortest Path's, split diagonally.

## License

GNU General Public License v3 or later, see `LICENSE`.
