# Pill-Shaped Dynamic Island for External Displays

## Problem
Claude Island renders its Dynamic Island UI assuming a physical MacBook notch. On external displays (or in clamshell mode), there is no notch, so the `NotchShape` with inward-curving top corners looks wrong - it mimics a notch that doesn't exist.

## Solution
When on a display without a physical notch, render the closed state as a **pill shape** (like iPhone Dynamic Island) that sits within the menu bar height. The expanded state uses rounded pill corners instead of notch-inward corners.

## Architecture

The app already has `hasPhysicalNotch` detection flowing through:
```
NSScreen.hasPhysicalNotch → NotchWindowController → NotchViewModel.hasPhysicalNotch → NotchView
```

We leverage this existing path to switch between notch and pill rendering.

## Changes

### 1. `NotchShape.swift` - Add PillShape
- Add a new `PillShape: Shape` that draws a capsule/rounded-rectangle
- Animatable corner radius for smooth transitions between compact and expanded states
- The pill has uniform corner radius (no inward-curving top corners)

### 2. `Ext+NSScreen.swift` - Fix non-notch sizing
- Change `notchSize` fallback for non-notch displays from `(224, 38)` to `(180, 24)`
- 24pt matches actual menu bar height on external displays
- 180pt gives a comfortable pill width for the crab icon + status indicators
- Add `menuBarHeight` computed property for reliable menu bar height

### 3. `NotchView.swift` - Conditional shape rendering
- Use `PillShape` when `!viewModel.hasPhysicalNotch`
- Adjust `closedNotchSize` to use pill dimensions on non-notch
- Reduce `headerRow` height to match menu bar (24pt) on non-notch
- Adjust expansion width calculations for smaller pill base
- Adjust corner radius constants for pill mode

### 4. `NotchGeometry.swift` - Pill geometry
- Add `isPillMode: Bool` property
- Adjust `notchScreenRect` for pill: smaller, centered rect
- Adjust hit-testing padding for the pill (larger touch target since pill is smaller)

### 5. `NotchWindowController.swift` - Window positioning
- On non-notch: use `level = .mainMenu + 1` instead of `+3` (sit within menu bar, not above it)
- Adjust window frame height for pill mode (don't need 750px for smaller closed state)

### 6. `NotchViewController.swift` - Hit test rects
- Adjust closed-state hit test rect for smaller pill dimensions

## Design Specifications

### Closed Pill (no notch)
- Width: 180pt (compact) / expands with activity indicators
- Height: 24pt (matches menu bar)
- Corner radius: 12pt (half of height = capsule)
- Position: centered horizontally at top of screen
- Background: black, matching Dynamic Island aesthetic

### Expanded Pill (no notch)
- Same opened sizes as current notch mode
- Corner radius: 20pt (smooth rounded rectangle, not notch-inward)
- Same shadow, animation springs, and content layout

### Notch Mode (unchanged)
- All existing behavior preserved on displays with physical notch
