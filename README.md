# Project Time Tracker

A small Mac app that lives in your menu bar. Type a project name, click **Start**, click **Stop**, and see how many hours you spent on each project this week and in total.

## Why Swift + SwiftUI

- **Native to macOS.** Swift and SwiftUI are Apple's own language and UI toolkit, so the app looks and behaves like a real Mac app (menu bar icon, light and dark mode, keyboard shortcuts).
- **Small and light.** It has no browser engine inside (unlike Electron apps), so it uses very little memory and battery while it sits in your menu bar all day.
- **Nothing extra to install.** It needs only Apple's free developer tools. There are no third-party libraries.
- **Why not a Notification Center widget?** Apple's desktop widgets can't have text boxes, and they only refresh every so often, so you couldn't type a project name or watch a live timer. A menu bar app is always one click away and can do both.

## Checkpoints

| # | Checkpoint | Status |
|---|------------|--------|
| 1 | Core logic: projects, start/stop, saving to disk, weekly and total hours, with tests | ✅ ready for review |
| 2 | The widget: menu bar icon with a project name box, Start/Stop button and live timer | ⏳ waiting for approval of 1 |
| 3 | Hours view: this week and all-time totals per project, with previous/next week buttons | ⏳ |
| 4 | Packaging: build a double-clickable `.app`, optional launch at login, install guide | ⏳ |

## How it works so far (checkpoint 1)

- Typing a project name that already exists (ignoring capitals and extra spaces) adds time to that project. A new name creates a new project.
- Only one timer runs at a time. Starting a different project stops the current one.
- Every Start and Stop is saved right away to `~/Library/Application Support/ProjectTimeTracker/data.json`. If the Mac restarts while a timer is running, it keeps counting when you reopen the app.
- A week follows your Mac's region setting (Sunday or Monday start). A session that runs past midnight at the end of a week is split between the two weeks.

## Running the tests (on your Mac)

1. Install Apple's developer tools, either Xcode from the App Store or, for a smaller download, run `xcode-select --install` in Terminal.
2. In Terminal, go to this folder and run:

   ```sh
   swift test
   ```
