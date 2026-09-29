# Project Time Tracker

> **About this project:** This app was written by [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant, and directed by [JLKohl](https://github.com/JLKohl). JLKohl came up with the idea, set the requirements, and reviewed and approved each checkpoint. Claude Code wrote the code.

A small Mac app that lives in your menu bar. Type a project name, click **Start**, click **Stop**, and see how many hours you spent on each project today, this week, and in total.

## Why Swift + SwiftUI

- **Native to macOS.** Swift and SwiftUI are Apple's own language and UI toolkit, so the app looks and behaves like a real Mac app (menu bar icon, light and dark mode, keyboard shortcuts).
- **Small and light.** It has no browser engine inside (unlike Electron apps), so it uses very little memory and battery while it sits in your menu bar all day.
- **Nothing extra to install.** It needs only Apple's free developer tools. There are no third-party libraries.
- **Why not a Notification Center widget?** Apple's desktop widgets can't have text boxes, and they only refresh every so often, so you couldn't type a project name or watch a live timer. A menu bar app is always one click away and can do both.

## Checkpoints

| # | Checkpoint | Status |
|---|------------|--------|
| 1 | Core logic: projects, start/stop, saving to disk, daily/weekly/total hours, with tests | ✅ approved (daily hours added) |
| 2 | The widget: menu bar icon with a project name box, Start/Stop button, live timer and today/week/all-time totals | ✅ tried out |
| 2b | Fixes from trying it, plus target hours: set hours per day and/or week for a project and see a progress bar and time left | 🔍 ready for review |
| 3 | Hours view: every project with today/week/all-time, a day-by-day breakdown of the week, previous/next week buttons | ⏳ |
| 4 | Packaging: build a double-clickable `.app`, optional launch at login, install guide | ⏳ |

## What it does

- Click the ⏱ icon in the menu bar, type a project name (or pick one from the recent-projects button), and press **Start** or hit Return.
- While a timer is running, the time shows next to the menu bar icon, and the panel shows the project and a live clock. Press **Stop** (or Return) to stop.
- Below the button you see how much time that project has had **today**, **this week**, and **all time**. Under an hour it shows minutes and seconds (e.g. `4m 12s`) so you can see it counting.
- Click **Set targets** to give a project a goal per day and/or per week (type `2`, `1.5`, `1:30` or `1h 30m`; leave empty for none). Today and This week then show a progress bar and how much time is left, or "Target met ✓".
- Typing a project name that already exists (ignoring capitals and extra spaces) adds time to that project. A new name creates a new project.
- Only one timer runs at a time. Starting a different project stops the current one.
- Every Start and Stop is saved right away to `~/Library/Application Support/ProjectTimeTracker/data.json`. If the Mac restarts while a timer is running, it keeps counting when you reopen the app.
- Days run midnight to midnight, and weeks follow your Mac's region setting (Sunday or Monday start). A session that runs past midnight is split between the two days (and weeks).

## Trying it on your Mac

You need macOS 13 (Ventura) or newer.

1. Install Apple's developer tools, either Xcode from the App Store or, for a smaller download, run `xcode-select --install` in Terminal.
2. In Terminal, go to this folder and run:

   ```sh
   swift run ProjectTimeTracker
   ```

   The first build takes a minute. A ⏱ icon then appears in your menu bar. Leave Terminal open while you use it; press Control-C in Terminal (or **Quit** in the panel) to close it. Checkpoint 4 turns this into a normal app you can double-click.

3. To run the automatic tests:

   ```sh
   swift test
   ```
