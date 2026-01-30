# macOS Tahoe (26) & Liquid Glass — Design Reference

> **NOTE:** The app currently targets **macOS 15 Sequoia (15.6.1)**, not macOS 26 Tahoe.
> Liquid Glass APIs (`.glassEffect()`, `GlassEffectContainer`, `.glass` button style, etc.) are macOS 26+ only.
> This document is retained for future reference when the app migrates to macOS 26.
> Current UI should use standard SwiftUI components: `NavigationSplitView`, `.sidebar` list style, regular toolbar, `Settings` scene — all available on Sequoia.

## Overview
macOS Tahoe is version 26, released September 15, 2025. Current: 26.2 (Dec 2025), 26.3 expected late Jan 2026. All Apple OS versions now use unified "26" numbering.

**Liquid Glass** is the new design language — translucent material with real-time light bending, specular highlights, and adaptive shadows. Apple's biggest visual redesign since iOS 7. Unified across iOS 26, iPadOS 26, macOS 26, watchOS 26, tvOS 26, visionOS 26.

## Key UI Changes for Mac Apps

### Windows
- **26pt corner radius** for application windows
- Transparent menu bar (shows wallpaper/content behind)
- Refined Liquid Glass window chrome

### Sidebar
- Floating Liquid Glass appearance
- Subtly tinted based on content underneath
- Larger icons at top level, smaller for nested items
- Detail view inset by sidebar width in NavigationSplitView
- Content can display underneath the sidebar

### Toolbar
- More translucent with Liquid Glass
- Button groupings always visible (not hover-only)
- New `ToolbarSpacer` for custom spacing

### Settings/Preferences
- SwiftUI `Settings` scene (Command+Comma, auto menu item)
- `Form` with `.grouped` style — more compact in sidebars/inspectors
- `@AppStorage` for UserDefaults binding
- Known bug: `openSettings` broken on Tahoe for `MenuBarExtra` apps

### Three Appearance Modes
- Light, Dark, and new **Clear/Transparent** mode
- "Auto" is first option in System Settings
- All Liquid Glass degrades gracefully with "Reduce Transparency"

## SwiftUI Liquid Glass APIs

### `.glassEffect()` Modifier
```swift
// Basic
Button("Action") { }
    .glassEffect()

// Variants
.glassEffect(.regular)          // Standard
.glassEffect(.clear)            // More transparent
.glassEffect(.identity)         // Minimal
.glassEffect(.regular.tint(.blue))        // Tinted
.glassEffect(.regular.interactive())      // Interactive response
```

### GlassEffectContainer
Combines multiple glass shapes that can morph between states:
```swift
GlassEffectContainer(spacing: 32) {
    HStack {
        Button("Home") { }.glassEffect()
        Button("Settings") { }.glassEffect()
    }
}
```

### Morphing with IDs
```swift
.glassEffectID("myID", in: namespace)
.glassEffectUnion  // Combine across distances
```

### Button Styles
```swift
Button("Secondary") { }
    .buttonStyle(.glass)             // Secondary actions

Button("Primary") { }
    .buttonStyle(.glassProminent)    // Primary actions (accent tinted)
```

### Concentric Corners
```swift
RoundedRectangle(cornerRadius: .containerConcentric)
// Automatically maintains corner concentricity within containers
```

## Key SwiftUI Updates (Xcode 26 / Swift 6.2)

### Navigation & Layout
| Component | Change |
|---|---|
| `NavigationSplitView` | Automatic Liquid Glass sidebar |
| Sidebar safe area | Detail inset by sidebar width |
| `Form` (`.grouped`) | More compact in sidebar/inspector |
| Search field | Fixed to toolbar, `searchToolbarBehavior()` to minimize |
| `ToolbarSpacer` | New view for toolbar spacing |
| Lists | Performance 10x+ on macOS (10,000+ items smooth) |
| Inspector | Enhanced Liquid Glass layering |

### New Capabilities
- **WebView**: Native SwiftUI HTML/CSS/JS view
- **Rich TextEditor**: Supports `AttributedString`
- **`@Animatable` macro**: Auto-synthesizes `Animatable` conformance
- **`buttonBorderShape(_:)`**: Now works on macOS
- **`buttonSizing(_:)`**: New modifier for button/picker/menu sizing
- **`backgroundExtensionEffect`**: Extend views outside safe area without clipping

### Concurrency
- `@MainActor` as default compile-time and runtime
- Module-level `@MainActor` isolation (Swift 6.2)
- New `Observations` type — bridges `@Observable` with `AsyncSequence`
- `@Observable` auto-tracking in UIKit/AppKit by default

### Automatic Adoption
Apps compiled with Xcode 26 auto-adopt Liquid Glass. Opt out:
```swift
// Info.plist
UIDesignRequiresCompatibility = true

// Per-app testing
defaults write com.example.app com.apple.SwiftUI.DisableSolarium -bool YES
```

## Design Guidelines for This App

### Structure
- `NavigationSplitView` two-column (sidebar + detail)
- Sidebar: Monitor section (Dashboard, Event Log, Diagnostics) + Configuration section (Cameras, Keyers, ProPresenter)
- Toolbar: Recording controls, export actions
- Settings: Separate `Settings` scene with `Form` `.grouped`
- Inspector (optional): Connection detail / event detail panel

### Liquid Glass Usage Rules
- **DO** use for navigation and controls (sidebar, toolbar, buttons, tabs)
- **DO NOT** use for main content (lists, tables, media, event log)
- Test with all three appearance modes (Light, Dark, Clear)
- Test with "Reduce Transparency" enabled

### Status Indicators
- SF Symbols: `wifi`, `wifi.slash`, `network`, `antenna.radiowaves.left.and.right`
- Use hierarchical/palette rendering (not monochrome)
- `.glass` button style for status controls

### SF Symbols 7
- 6,900+ symbols, 9 weights, 3 scales
- Draw On/Off animations
- Variable Draw for progress
- Gradient rendering

## WWDC Sessions
- Session 323: Build a SwiftUI app with the new design
- Session 356: Get to know the new design system
- Session 337: What's new in SF Symbols 7
