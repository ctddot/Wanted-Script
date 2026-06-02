# Vehicle Live Tuner

Rayfield-based live vehicle tuner script for Roblox testing in your own experience.

## Files

- `vehicle.lua` - full Rayfield vehicle tuner script
- `loader.lua` - one-line loader template

## Loader

After uploading this repo to GitHub, replace `YOUR_USERNAME` and `YOUR_REPO`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/vehicle.lua"))()
```

## Notes

- Press `K` to toggle the Rayfield UI.
- Press `B` to toggle the controller.
- Press `F12` to eject and clean up.
- This avoids editing read-only vehicle module tables and tunes live chassis/constraint behavior instead.
