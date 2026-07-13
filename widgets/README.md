# Economy Assist

`cmd_economy_assist.lua` is a Beyond All Reason LuaUI control widget. It changes
builder priority according to the live aggregate converter state:

- `mmUse < mmCapacity`: builders working on converters become Low priority.
- `mmUse >= mmCapacity`: builders working on power/energy production become Low priority.
- With no completed converters, or without the BAR team rules, neither category is lowered.

The Commander is included. Factories and builders working on other targets are
left unchanged. When a builder changes target or the mode changes, the widget
restores units that it lowered to Normal priority. A short minimum dwell avoids
rapid priority-command changes.

## Install

Copy the Lua file into the BAR LuaUI widget directory:

```bash
cp widgets/cmd_economy_assist.lua \
  "$HOME/.local/state/Beyond All Reason/LuaUI/Widgets/"
```

Restart BAR, or reload the widget from the in-game widget manager. The widget
is disabled by default, so enable `economy-assist` in the widget list.

## Test

1. Build at least one converter and order a constructor or the Commander to build another converter.
2. Drain energy until the existing converter is energy-starved. The converter builder should become Low priority.
3. Restore enough energy for all converters to operate. The converter builder should return to Normal, and a builder working on a power producer should become Low priority.
4. Switch a controlled builder to another target and confirm that it returns to Normal.

The widget uses BAR's aggregate `mmUse`/`mmCapacity` signal, so a shortfall
means at least one converter is not operating at full requested capacity. Set
`DEBUG = true` in the Lua file if transition messages are needed in the BAR log.
