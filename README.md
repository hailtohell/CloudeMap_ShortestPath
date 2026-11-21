# CloudeMap: Shortest Path

> **AI disclaimer:** written with an AI assistant (Claude, by Anthropic), directed, tested and
> reviewed in game by a human.

A plugin for [CloudeMap](https://github.com/hailtohell/CloudeMap) that shows
[Shortest Path Forever](https://github.com/cjber/shortest-path-forever) on CloudeMap's map.
Both addons are required.

## Features

- **Your journey:** the walk you're on follows Shortest Path's arrow; later legs (flights, boats,
  zeppelins, portals) in Shortest Path's colours, the walk in the route colour you picked there.
- **Destination pin:** its tooltip lists each step with its time and the time left.
- **Shift+click on CloudeMap** plans a journey to that spot.
- **Transports:** boats, zeppelins, lifts, the Deeprun Tram and portals as pins; hover a dock to see
  where it goes and its route. The other faction's routes and portals follow Shortest Path's own
  settings.
- Each part has its own toggle in CloudeMap's Pins list, under Other addons.

No departure times: Shortest Path works them out from its own sightings, which it keeps private.

## Credits

Transport data copied from Shortest Path Forever by cjber (GPL-3.0-or-later), which builds it from
wago.tools DB2 and CMaNGOS classic-db.

## License

GNU General Public License v3 or later, see `LICENSE`.
