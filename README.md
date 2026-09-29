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
| 2b | Fixes from trying it, plus target hours: set hours per day and/or week for a project and see a progress bar and time left | ✅ approved |
| 3 | Hours view: every project with a day-by-day breakdown of the week, week and all-time totals, previous/next week buttons | ✅ approved (combined totals removed) |
| 4 | Packaging: build a double-clickable `.app`, optional launch at login, install guide | ✅ approved |

## What it does

- Click the ⏱ icon in the menu bar and type a project name (or pick one from the recent-projects button). Pressing Return adds the project **without** starting the timer, so you can set up several projects (and their targets) ahead of time. Click **Start** (or press ⌘Return) when you want the timer to run.
- While a timer is running, the time shows next to the menu bar icon, and the panel shows the project and a live clock. Press **Stop** (or Return) to stop.
- Below the button you see how much time that project has had **today**, **this week**, and **all time**. Under an hour it shows minutes and seconds (e.g. `4m 12s`) so you can see it counting.
- Click **Set targets** to give a project a goal per day and/or per week (type `2`, `1.5`, `1:30` or `1h 30m`; leave empty for none). Today and This week then show a progress bar and how much time is left, or "Target met ✓".
- Click **All hours…** in the panel for the hours window: every project with its time on each day Sunday–Saturday, its week total (with a progress bar if it has a weekly target) and its all-time total. Use the arrows to look back at earlier weeks. A day turns green once that day's target is met, and a green dot marks the project that's running.
- To rename a project, click the ✏️ pencil icon next to **Set targets** in the panel, or right-click it in the hours window and choose **Rename Project…**. Its time and targets stay with it.
- To delete a project, click the 🗑 trash icon next to **Set targets** in the panel (for the project that's running or typed in the name box), or right-click it in the hours window and choose **Delete Project…**. After you confirm, the project and all its tracked time are removed for good.
- Typing a project name that already exists (ignoring capitals and extra spaces) adds time to that project. A new name creates a new project.
- Only one timer runs at a time. Starting a different project stops the current one.
- Every Start and Stop is saved right away to `~/Library/Application Support/ProjectTimeTracker/data.json`. If the Mac restarts while a timer is running, it keeps counting when you reopen the app.
- Days run midnight to midnight, and weeks run Sunday to Saturday. A session that runs past midnight is split between the two days (and weeks).

## Installing on your Mac

You need macOS 13 (Ventura) or newer, and Apple's free developer tools. To get the tools, open Terminal and run `xcode-select --install`. If it says they're already installed, you're set.

1. Get the project, if you haven't already:

   ```sh
   cd ~/Desktop
   git clone https://github.com/JLKohl/Project-time-tracker-.git
   cd Project-time-tracker-
   ```

2. Build and install the app:

   ```sh
   ./scripts/build-app.sh --install
   ```

   This takes a minute or two. It puts **Project Time Tracker** in your Applications folder and opens it. Look for the ⏱ icon in your menu bar. If a copy was already running (including one started from Terminal), it's closed first so it can be replaced.

3. To have it start by itself whenever you log in, open the panel and tick **Open at login**. If macOS asks, allow it in **System Settings → General → Login Items**.

From now on you can open it like any other app: from Applications, Launchpad or Spotlight (⌘-Space, type "Project Time Tracker"). You don't need Terminal or the project folder to use it. The project folder is only needed to update.

**If macOS says the app can't be opened:** because you built it yourself, this usually doesn't happen. If it does, right-click the app in Applications, choose **Open**, then click **Open** again. You only need to do this once.

### Can't see the ⏱ icon?

If the menu bar is crowded, macOS hides the icons that don't fit, and on MacBooks with a camera notch they can end up behind it. The icon gets wider while a timer is running, so this is more likely then. The tracker is still running and still counting.

- Open **Project Time Tracker** again from Applications, Spotlight or the Dock. When it's already running, this opens the hours window, which shows the running timer with a **Stop** button.
- To make room in the menu bar, quit other menu bar apps you don't need, or hold ⌘ and drag icons you don't want out of the menu bar.
- Once you can see the ⏱ icon, hold ⌘ and drag it to the right, next to the clock. Icons nearest the clock are the last to be hidden, and macOS remembers the position.
- Untick **Show time in menu bar** in the panel to keep the icon narrow. It then shows a filled stopwatch while a timer is running instead of the time.

### Updating to a newer version

```sh
cd ~/Desktop/Project-time-tracker-
git pull
./scripts/build-app.sh --install
```

Your tracked time is kept. It's stored separately, in `~/Library/Application Support/ProjectTimeTracker/data.json`.

### Uninstalling

Quit it from the panel, untick **Open at login** first if it's on, then drag **Project Time Tracker** from Applications to the Trash. To also delete your tracked time, delete the `~/Library/Application Support/ProjectTimeTracker` folder.

## For developers

- `swift run ProjectTimeTracker` runs the app straight from Terminal without installing it. Don't run it at the same time as the installed app: both would write to the same data file.
- `swift test` runs the automatic tests for the tracking logic.
- `./scripts/build-app.sh` (without `--install`) builds the app into the `build` folder only.
- The tracking logic is in `Sources/TimeTrackerCore`, and the menu bar app and hours window are in `Sources/ProjectTimeTracker`.
