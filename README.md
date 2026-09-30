# OpenStill MCP

Lets an AI app edit your photos in [OpenStill](https://github.com/haon-v2/OpenStill), the photo editor for macOS. It works with Claude Desktop, Claude Code, or any app that supports the [Model Context Protocol](https://modelcontextprotocol.io).

It's optional and not installed with OpenStill. Install it from OpenStill when you want it.

## Install

1. In OpenStill, open **Settings → AI Assistant**.
2. Click **Install OpenStill MCP**. OpenStill downloads the latest release from this repository, checks it against its `SHA256SUMS`, and installs it in `~/Library/Application Support/OpenStill/MCP/`.
3. Connect your AI app:
   - **Claude Desktop:** click **Connect to Claude Desktop**. OpenStill shows the change to Claude Desktop's settings, keeps a backup, and adds an `openstill` server. Restart Claude Desktop.
   - **Claude Code:** click **Copy command** and paste it into a terminal:
     `claude mcp add openstill -- "$HOME/Library/Application Support/OpenStill/MCP/openstill-mcp"`
   - **Other apps:** add a stdio MCP server whose command is the path above, with no arguments.
4. Turn on **Allow AI assistants to edit**. It's off by default, and OpenStill only listens for the MCP while it's on.

## What the AI can do

| Tool | What it does |
| --- | --- |
| `status` | What's open in OpenStill and how many photos are in the library. |
| `list_photos` | Find photos by folder, text, rating, flag, label, keyword, camera, date, or whether they're edited. |
| `get_photo` | A photo's details and its current slider values. |
| `open_photo` | Open a photo in Develop. |
| `preview` | Look at the photo with its edits (a JPEG, 1024 px by default, limited in Settings); `compare: true` shows before and after side by side. |
| `set_adjustments` | Change Develop sliders: exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, vibrance, saturation, clarity, texture, dehaze, sharpness, noise reduction, vignette, straighten, LUT amount. |
| `auto_tone`, `apply_preset`, `crop`, `reset`, `undo` | The same as the buttons in OpenStill. |
| `add_mask_layer` | A masked adjustment: linear, radial, or an AI selection of the subject, sky, background or people, computed on your Mac. The answer shows the selected area in red with its coverage and bounds. |
| `list_mask_layers`, `preview_mask` | See the photo's layers, and where each one applies. |
| `update_mask_layer`, `delete_mask_layer` | Change a layer's sliders, name, visibility or inversion, move or resize a linear or radial one, or remove it. |
| `get_edits`, `edit`, `edit_reference` | Read and change **everything** in Develop — curves, HSL, color grading, detail, glow, grain, point color, lens, transform, calibration, retouch, masks, lens blur… — as one edit document with JSON merge patches. |
| `run_command` | What Develop's buttons do: auto tone, Upright, level horizon, AI noise removal, detail, super resolution, erase, skies, lens blur depth, snapshots, undo. |
| `copy_edits` | Copy and paste settings from one photo to others, choosing sections, like Copy Settings / Sync. |
| `list_presets`, `list_skies` | What `apply_preset` and `run_command apply_sky` can use. |
| `rate`, `flag`, `label`, `add_keywords` | Library metadata for one or several photos. |
| `export` | Export with your export settings. |
| `list_luts`, `apply_lut` | Use the LUTs installed in OpenStill. |
| `import_lut` | Add a free LUT the AI found on the web. OpenStill downloads it over https only, checks every `.cube` file, and refuses anything without a stated free license. The source and license are shown in the LUT browser under **Found by AI**. |

It also offers three prompts: **Edit like…**, **Grade a folder** and **Find LUTs**.

## How edits stay in sync

The MCP never touches your files. Each tool call is sent to the running OpenStill app over a local socket (`~/Library/Application Support/OpenStill/assistant.sock`, which only your Mac user account can open). OpenStill runs it through the same code as its own controls. So every AI edit:

- is one normal undo step,
- appears on screen right away,
- is saved exactly like your own edits.

OpenStill is the only program that writes edits, so the AI's changes and yours can't conflict. If OpenStill isn't running, the MCP opens it in the background. Settings → AI Assistant lists recent AI actions.

## OpenStill's AI features through your AI app

When your AI app supports MCP *sampling*, OpenStill can ask it to answer instead of using the local model. For example, the logo designer can use your connected AI. Image features such as masks, sky replacement, removal and noise reduction always run on your Mac.

## Privacy

- Previews the AI looks at are sent to your AI provider, like any image you share with it. Originals never leave your Mac.
- The MCP makes no network requests of its own. `import_lut` downloads are made by OpenStill, only for links the AI passes to it.

## Build from source

Requires macOS 13 or later and Swift 5.9 or later.

```sh
swift build -c release
swift test
```

The program is `.build/release/openstill-mcp`. It speaks MCP over stdin and stdout.

## Releases

Actions → **Release** → Run workflow with a version (for example `1.0.0`, matching `Server.version`). It tests, builds a universal binary for Apple silicon and Intel, signs it ad hoc, and publishes `openstill-mcp-<version>-macos-universal.zip` with `SHA256SUMS`.

## License

MIT
