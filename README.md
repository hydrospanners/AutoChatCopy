# AutoChatCopy

Adds a copy button to chat windows and opens a copy-ready text dialog.

## Installation

1. Go to the [Releases](../../releases/latest) page and download the latest `.zip`
2. Extract the **AutoChatCopy** folder into your addons directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\
   ```
3. Log in to WoW or type `/reload` in-game

## Features

- Low-opacity note icon in each chat frame (hover to brighten).
- Per-chat-frame rolling history cache (default: 4096 lines).
- Reads the chat frame's current message history when opening the copy dialog.
- Blizzard `ScrollingEditBoxTemplate` editor for mouse/cursor selection inside the copy dialog.
- Shift-click selection support: click once to set an anchor, then Shift-click another position to select the range.
- Closes the copy dialog shortly after `Ctrl-C`.
- Standard `Esc` frame dismissal support via `UISpecialFrames` when the edit box does not have focus.
- Formatting cleanup for copied output (color, texture, and hyperlink wrappers are stripped).
- Slash commands: `/autochatcopy` and `/accopy`.

## Requirements

- World of Warcraft Retail (Midnight / 12.x+)
