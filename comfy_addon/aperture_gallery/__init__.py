"""Aperture Gallery - a minimal ComfyUI output browser for the Aperture app.

Why this exists
---------------
The general-purpose gallery addons return the *whole* output tree in a single
response, with each entry carrying its embedded prompt and workflow graph. On
a server with 11,000 images that is tens of megabytes of JSON for a phone to
download and parse before it can draw a single thumbnail, and it grows without
bound as the library does.

This serves only what a phone actually needs, and only as much of it as is on
screen:

  * ``/aperture/gallery/list``  - one page of entries, newest first, with
    optional date and filename filters applied *on the server*.
  * ``/aperture/gallery/days``  - per-day counts, so the client can offer a
    date filter without having first downloaded every entry.
  * ``/aperture/gallery/thumb`` - a small JPEG, generated once and cached on
    disk. This is the reason the whole thing is worth writing: a grid of
    thumbnails costs a few hundred kilobytes instead of several gigabytes.

Install by copying the ``aperture_gallery`` folder into ``ComfyUI/custom_nodes``
and restarting ComfyUI. It adds no nodes and does not touch generation.
"""

import hashlib
import os
import time

try:
    from aiohttp import web
except ImportError:  # pragma: no cover - only importable inside ComfyUI
    web = None

try:
    import folder_paths
except ImportError:  # pragma: no cover - only importable inside ComfyUI
    folder_paths = None

try:
    from server import PromptServer
except ImportError:  # pragma: no cover
    PromptServer = None

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

try:
    from . import preview_probe
except Exception:  # noqa: BLE001 - diagnostics must never block the addon
    preview_probe = None


IMAGE_EXTENSIONS = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")

# The directory scan is the only expensive part, so it is cached and reused.
# A short TTL keeps a freshly generated image appearing promptly without
# re-walking the tree on every page request while the user scrolls.
_INDEX_TTL_SECONDS = 20
_index = {"built_at": 0.0, "root": None, "items": []}


def _output_root():
    if folder_paths is not None:
        return folder_paths.get_output_directory()
    return os.path.abspath("output")


def _thumb_root():
    root = os.path.join(_output_root(), ".aperture_thumbs")
    os.makedirs(root, exist_ok=True)
    return root


def _scan(root):
    """Every image under `root`, newest first."""
    items = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Never descend into our own thumbnail cache.
        dirnames[:] = [d for d in dirnames if d != ".aperture_thumbs"]
        for name in filenames:
            if not name.lower().endswith(IMAGE_EXTENSIONS):
                continue
            full = os.path.join(dirpath, name)
            try:
                stat = os.stat(full)
            except OSError:
                # A file can vanish between listing and stat-ing it; skipping
                # is correct here, and far better than failing the request.
                continue
            relative = os.path.relpath(full, root).replace(os.sep, "/")
            subfolder = os.path.dirname(relative)
            items.append(
                {
                    "path": relative,
                    "name": name,
                    "subfolder": subfolder,
                    "mtime": stat.st_mtime,
                    "size": stat.st_size,
                }
            )
    items.sort(key=lambda item: item["mtime"], reverse=True)
    return items


def _index_items(force=False):
    root = _output_root()
    now = time.time()
    stale = now - _index["built_at"] > _INDEX_TTL_SECONDS
    if force or stale or _index["root"] != root:
        _index["items"] = _scan(root)
        _index["built_at"] = now
        _index["root"] = root
    return _index["items"]


def _safe_path(relative):
    """Resolve `relative` inside the output root, or None if it escapes.

    Without this, `?path=../../etc/passwd` would happily serve whatever it
    pointed at - the endpoint takes a client-supplied path, so the check is
    not optional.
    """
    if not relative:
        return None
    root = os.path.abspath(_output_root())
    full = os.path.abspath(os.path.join(root, relative))
    if full != root and not full.startswith(root + os.sep):
        return None
    return full if os.path.isfile(full) else None


def _day_key(mtime):
    return time.strftime("%Y-%m-%d", time.localtime(mtime))


def _filtered(items, since, until, query):
    result = items
    if since is not None:
        result = [i for i in result if i["mtime"] >= since]
    if until is not None:
        result = [i for i in result if i["mtime"] < until]
    if query:
        needle = query.lower()
        result = [i for i in result if needle in i["path"].lower()]
    return result


def _parse_float(value):
    try:
        return float(value) if value not in (None, "") else None
    except (TypeError, ValueError):
        return None


if PromptServer is not None and web is not None:
    routes = PromptServer.instance.routes

    if preview_probe is not None:
        preview_probe.install()

    @routes.get("/aperture/diag/preview")
    async def aperture_diag_preview(request):
        """Why live previews are or are not reaching the app.

        Reports each link in the chain separately - configuration, whether a
        previewer was created, whether anything was sent, and whether it was
        addressed to a connected client - so a failure names itself instead
        of presenting as a blank canvas.
        """
        if preview_probe is None:
            return web.json_response(
                {"error": "preview probe failed to load"}, status=500
            )
        return web.json_response(preview_probe.report())

    @routes.get("/aperture/gallery/ping")
    async def aperture_gallery_ping(request):
        """Lets the app detect this addon without guessing from a 404 body."""
        return web.json_response({"ok": True, "version": 1})

    @routes.get("/aperture/gallery/days")
    async def aperture_gallery_days(request):
        """Per-day counts, newest day first."""
        items = _index_items(force=request.query.get("refresh") == "1")
        counts = {}
        for item in items:
            key = _day_key(item["mtime"])
            counts[key] = counts.get(key, 0) + 1
        days = [{"day": day, "count": count} for day, count in counts.items()]
        days.sort(key=lambda d: d["day"], reverse=True)
        return web.json_response({"total": len(items), "days": days})

    @routes.get("/aperture/gallery/list")
    async def aperture_gallery_list(request):
        """One page of entries, newest first.

        Filtering happens here rather than on the client so a date-limited
        view costs one small response instead of the whole library.
        """
        query = request.query
        items = _index_items(force=query.get("refresh") == "1")

        filtered = _filtered(
            items,
            _parse_float(query.get("since")),
            _parse_float(query.get("until")),
            query.get("q"),
        )

        try:
            offset = max(0, int(query.get("offset", 0)))
        except ValueError:
            offset = 0
        try:
            limit = int(query.get("limit", 60))
        except ValueError:
            limit = 60
        limit = max(1, min(limit, 200))

        page = filtered[offset : offset + limit]
        return web.json_response(
            {
                "total": len(filtered),
                "offset": offset,
                "limit": limit,
                # Explicit rather than derived, so the client never has to
                # reimplement the end-of-list arithmetic.
                "next_offset": offset + len(page) if offset + len(page) < len(filtered) else None,
                "items": [
                    {
                        "path": item["path"],
                        "name": item["name"],
                        "subfolder": item["subfolder"],
                        "mtime": item["mtime"],
                        "size": item["size"],
                    }
                    for item in page
                ],
            }
        )

    @routes.get("/aperture/gallery/thumb")
    async def aperture_gallery_thumb(request):
        """A cached JPEG thumbnail.

        Generated once per (file, size) and written beside the outputs, so
        scrolling back over the same images costs nothing but a file read.
        """
        relative = request.query.get("path")
        source = _safe_path(relative)
        if source is None:
            return web.json_response({"error": "not found"}, status=404)
        if Image is None:
            return web.json_response({"error": "Pillow is not installed"}, status=500)

        try:
            width = int(request.query.get("w", 256))
        except ValueError:
            width = 256
        width = max(64, min(width, 1024))

        stat = os.stat(source)
        # The mtime is in the key, so an overwritten file re-renders instead
        # of serving a stale thumbnail forever.
        digest = hashlib.sha1(
            f"{relative}|{stat.st_mtime_ns}|{width}".encode("utf-8")
        ).hexdigest()
        cached = os.path.join(_thumb_root(), f"{digest}.jpg")

        if not os.path.isfile(cached):
            try:
                with Image.open(source) as image:
                    image = image.convert("RGB")
                    image.thumbnail((width, width * 4), Image.LANCZOS)
                    image.save(cached, "JPEG", quality=82, optimize=True)
            except Exception as error:  # noqa: BLE001 - report, never 500 the grid
                return web.json_response({"error": str(error)}, status=415)

        return web.FileResponse(
            cached,
            headers={"Cache-Control": "public, max-age=604800"},
        )


# ComfyUI expects these even from an addon that contributes no nodes.
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
__all__ = ["NODE_CLASS_MAPPINGS", "NODE_DISPLAY_NAME_MAPPINGS"]
