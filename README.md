# qbx_garages

A custom Qbox garage control center with a sleek Nova-themed NUI. Players can view their complete vehicle collection from any compatible garage, retrieve stored vehicles, or respawn an owned vehicle that is already out in the world.

## Features

- Custom dark NUI built with Tailwind CSS and responsive layouts.
- Searchable fleet grid with plate, fuel, engine, body, storage and world status.
- Server-authoritative ownership and garage access validation.
- Retrieve an owned vehicle regardless of which configured garage currently stores it.
- Respawn an already-out vehicle from the garage by safely removing its unoccupied world entity first.
- Existing parking, job/gang access, depot fees, hooks, vehicle types and blips remain supported.
- ox_lib callbacks and qbx_core/qbx_vehicles APIs only.

## Dependencies

- qbx_core
- qbx_vehicles
- ox_lib
- oxmysql

## Installation

1. Place the resource in your resources folder as `qbx_garages`.
2. Ensure the dependencies start before this resource.
3. Add `ensure qbx_garages` to `server.cfg`.
4. Run `refresh` and then `restart qbx_garages` after installation.

## Usage

Walk to a configured garage access point and press `E` to open the Nova garage interface. Search your fleet, then select **Take out** for stored vehicles or **Respawn vehicle** for a vehicle currently out. Use the configured drop-off point to park a vehicle normally.

The UI is defined in `html/ui.html`, `html/style.css`, and `html/script.js`. Garage locations and access rules remain in `config/server.lua`.
