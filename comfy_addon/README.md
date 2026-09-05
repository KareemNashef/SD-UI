# Aperture Gallery — ComfyUI addon

A minimal output browser for the Aperture app.

## Why not a general-purpose gallery addon

The addons on GitHub return the **entire** output tree in one response, each
entry carrying its embedded prompt and workflow graph. On a server with 11,000
images that is tens of megabytes the phone must download and parse before it
can draw a single thumbnail — and it grows as the library does.

This one serves only what is on screen:

| Endpoint | Purpose |
|---|---|
| `GET /aperture/gallery/ping` | Detect the addon without guessing from a 404 |
| `GET /aperture/gallery/days` | Per-day counts, so a date filter needs no full download |
| `GET /aperture/gallery/list` | One page, newest first, filtered **server-side** |
| `GET /aperture/gallery/thumb` | A cached JPEG thumbnail |

`thumb` is the one that matters most: a grid of thumbnails costs a few hundred
kilobytes rather than several gigabytes of full-resolution PNGs.

### `list` parameters

- `offset` (default 0), `limit` (default 60, max 200)
- `since` / `until` — epoch seconds, filtering on file mtime
- `q` — case-insensitive substring match on the relative path
- `refresh=1` — rebuild the directory index now rather than waiting for the
  20-second TTL

Returns `{ total, offset, limit, next_offset, items[] }`, where `next_offset`
is `null` on the last page.

### `thumb` parameters

- `path` — the relative path from a `list` entry
- `w` — target width, 64–1024 (default 256)

Thumbnails are cached under `output/.aperture_thumbs`, keyed by path, mtime and
width, so an overwritten file re-renders instead of serving a stale image.

## Install

Copy the `aperture_gallery` folder into `ComfyUI/custom_nodes/` and restart
ComfyUI. It registers no nodes and does not touch generation — it only adds
the routes above.

Requires Pillow, which ComfyUI already depends on.

## Notes

- Full-resolution images are served by ComfyUI's own `/view` endpoint using the
  `subfolder` and `name` fields from `list`; this addon deliberately doesn't
  duplicate that.
- `path` is resolved and checked against the output root, so a crafted
  `../../` cannot escape it.
- The app falls back to the older `ComfyUI-Gallery` addon when these routes
  are absent, so installing this is an upgrade rather than a requirement.

---

## Preview diagnostics

`preview_probe.py` instruments ComfyUI's live-preview pipeline. It only
observes — it never changes what ComfyUI sends — and is safe to leave
installed.

Live previews reach a client only if every one of these holds:

1. `--preview-method` is not `none` (**this is ComfyUI's default**, and the
   most common reason previews never appear)
2. `latent_preview.get_previewer()` returns a previewer for the running model
3. the sampler actually calls the preview callback — custom samplers often
   don't
4. `PromptServer.send_sync` is called with a preview binary event
5. it is addressed to a `client_id` that currently has an open socket —
   previews are **unicast**, so a mismatch is a silent black hole that looks
   exactly like previews being switched off

Check which link broke:

```bash
curl http://YOUR_SERVER:8188/aperture/diag/preview
```

The `verdict` field reads the counters for you, so the numbers need no
decoding.

Counters are always collected. Per-frame log lines are off by default —
set `VERBOSE = True` at the top of `preview_probe.py` and restart to get a
line per preview. Warnings (a previewer that fails to build, a preview sent
to a client with no socket) are never suppressed.

On Windows, note that PowerShell aliases `curl` to `Invoke-WebRequest`,
which truncates the body in console output. Use `curl.exe`, or:

```powershell
Invoke-RestMethod http://YOUR_SERVER:8188/aperture/diag/preview | ConvertTo-Json -Depth 6
```
