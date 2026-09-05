"""Diagnostics for ComfyUI's live preview pipeline.

Purely observational: it logs and counts, and never changes what ComfyUI
sends. Safe to leave installed, and easy to delete once previews work.

Live previews reach a client only if *every* one of these holds:

  1. ``--preview-method`` is not ``none``. This is ComfyUI's default, and is
     the single most common reason previews never appear.
  2. ``latent_preview.get_previewer()`` returns a previewer for the running
     model - a latent format with no RGB factors yields None even when a
     preview method is set.
  3. The sampler actually calls the preview callback. Custom samplers
     frequently skip it.
  4. ``PromptServer.send_sync`` is called with a preview binary event.
  5. It is addressed to a ``client_id`` that currently has a socket open.
     Previews are unicast, not broadcast - a prompt queued with one
     ``client_id`` while the socket registered another is a silent black
     hole, and looks identical to "previews are off".

Each of those is reported separately, so a run tells you which link broke
instead of leaving you to guess.

Counters are always collected and served as JSON from
``/aperture/diag/preview``. Per-frame log lines (prefixed
``[aperture/preview]``) are off unless ``VERBOSE`` is set to True below -
warnings are never suppressed.
"""

import logging
import time

log = logging.getLogger("aperture.preview")

# Per-frame logging. Off by default: a run emits one line per preview frame,
# which is what you want while diagnosing and noise afterwards. The counters
# behind /aperture/diag/preview accumulate either way, so the endpoint stays
# useful without this - only the running commentary is silenced.
VERBOSE = False

STATS = {
    "previewer_requested": 0,
    "previewer_created": 0,
    "previewer_none": 0,
    "preview_sends": 0,
    "preview_bytes": 0,
    "last_send_at": None,
    "last_event_type": None,
    "last_sid": None,
    "last_previewer_class": None,
    "patched": False,
    "patch_error": None,
}


def _describe_preview_method():
    """What ``--preview-method`` is set to, without assuming it exists."""
    try:
        from comfy.cli_args import args

        method = getattr(args, "preview_method", None)
        size = getattr(args, "preview_size", None)
        name = getattr(method, "value", None) or str(method)
        return {
            "preview_method": name,
            "preview_size": size,
            # `NoPreviews` is the default; anything else means previews are
            # at least switched on.
            "previews_enabled": name not in (None, "none", "NoPreviews",
                                             "LatentPreviewMethod.NoPreviews"),
        }
    except Exception as error:  # noqa: BLE001
        return {"preview_method": None, "error": f"{error}"}


def _socket_state():
    """Which clients are connected, and who previews are being addressed to."""
    try:
        from server import PromptServer

        instance = PromptServer.instance
        sockets = getattr(instance, "sockets", {}) or {}
        return {
            "connected_client_ids": list(sockets.keys()),
            "socket_count": len(sockets),
            # Set from the `client_id` on the /prompt request. If this is not
            # in the list above, previews are being sent to nobody.
            "active_client_id": getattr(instance, "client_id", None),
        }
    except Exception as error:  # noqa: BLE001
        return {"error": f"{error}"}


def _binary_event_names():
    try:
        from server import BinaryEventTypes

        return {
            getattr(BinaryEventTypes, name): name
            for name in dir(BinaryEventTypes)
            if name.isupper() and isinstance(getattr(BinaryEventTypes, name), int)
        }
    except Exception:  # noqa: BLE001
        return {1: "PREVIEW_IMAGE", 2: "UNENCODED_PREVIEW_IMAGE", 3: "TEXT",
                4: "PREVIEW_IMAGE_WITH_METADATA"}


def install():
    """Wraps the two functions that decide whether a preview is produced."""
    if STATS["patched"]:
        return
    names = _binary_event_names()
    preview_events = {
        value for value, name in names.items() if "PREVIEW" in name
    } or {1, 2, 4}

    try:
        import latent_preview
        from server import PromptServer

        # --- 2/3: is a previewer even created for this run? ---
        original_get_previewer = latent_preview.get_previewer

        def traced_get_previewer(device, latent_format):
            STATS["previewer_requested"] += 1
            previewer = original_get_previewer(device, latent_format)
            if previewer is None:
                STATS["previewer_none"] += 1
                log.warning(
                    "[aperture/preview] get_previewer -> None "
                    "(latent_format=%s). Previews are off, or this model's "
                    "latent format has no preview support.",
                    type(latent_format).__name__,
                )
            else:
                STATS["previewer_created"] += 1
                STATS["last_previewer_class"] = type(previewer).__name__
                _info(
                    "[aperture/preview] get_previewer -> %s (latent_format=%s)",
                    type(previewer).__name__,
                    type(latent_format).__name__,
                )
            return previewer

        latent_preview.get_previewer = traced_get_previewer

        # --- 4/5: is a preview actually sent, and to whom? ---
        original_send_sync = PromptServer.send_sync

        def traced_send_sync(self, event, data, sid=None):
            try:
                if event in preview_events:
                    STATS["preview_sends"] += 1
                    STATS["last_send_at"] = time.time()
                    STATS["last_event_type"] = names.get(event, event)
                    STATS["last_sid"] = sid
                    STATS["preview_bytes"] += _payload_size(data)
                    sockets = getattr(self, "sockets", {}) or {}
                    delivered = sid is None or sid in sockets
                    _info(
                        "[aperture/preview] send event=%s sid=%s payload=%s "
                        "delivered=%s open_sockets=%s",
                        names.get(event, event),
                        sid,
                        _payload_shape(data),
                        delivered,
                        list(sockets.keys()),
                    )
                    if not delivered:
                        log.warning(
                            "[aperture/preview] preview addressed to a "
                            "client_id with no open socket - it will be "
                            "dropped. Queued client_id and websocket "
                            "client_id do not match.",
                        )
            except Exception as error:  # noqa: BLE001
                # Diagnostics must never break a generation.
                log.debug("[aperture/preview] trace failed: %s", error)
            return original_send_sync(self, event, data, sid)

        PromptServer.send_sync = traced_send_sync

        STATS["patched"] = True
        info = _describe_preview_method()
        log.info(
            "[aperture/preview] probe installed. preview_method=%s "
            "previews_enabled=%s",
            info.get("preview_method"),
            info.get("previews_enabled"),
        )
    except Exception as error:  # noqa: BLE001
        STATS["patch_error"] = f"{error}"
        log.warning("[aperture/preview] could not install probe: %s", error)


def _info(message, *args):
    """Per-frame commentary, suppressed unless VERBOSE.

    Warnings are never suppressed - a previewer that fails to build, or a
    preview addressed to a client with no socket, are the two findings worth
    interrupting someone for.
    """
    if VERBOSE:
        log.info(message, *args)


def _payload_size(data):
    """Byte count of a preview payload, or 0 when it isn't countable.

    Always an int: this is summed into a counter, and returning a string for
    the un-encoded case (which arrives as a PIL image, not bytes) made the
    addition throw. The exception was caught, so the only symptom was
    `preview_bytes` quietly freezing while everything else looked healthy.
    """
    try:
        if isinstance(data, (bytes, bytearray, memoryview)):
            return len(data)
    except Exception:  # noqa: BLE001
        pass
    return 0


def _payload_shape(data):
    """A readable description of the payload, for the log line only."""
    try:
        if isinstance(data, (bytes, bytearray, memoryview)):
            return f"{len(data)}B"
        # Unencoded previews arrive as ("JPEG", PIL.Image, max_size).
        if isinstance(data, (tuple, list)) and len(data) >= 2:
            size = getattr(data[1], "size", None)
            return f"{data[0]} image {size}" if size else f"{type(data[1]).__name__}"
    except Exception:  # noqa: BLE001
        pass
    return type(data).__name__


def report():
    """Everything known about the preview pipeline, as one JSON blob."""
    return {
        "config": _describe_preview_method(),
        "sockets": _socket_state(),
        "stats": dict(STATS),
        "verdict": _verdict(),
    }


def _verdict():
    """A plain reading of the counters, so the numbers need no decoding."""
    config = _describe_preview_method()
    if config.get("previews_enabled") is False:
        return ("Previews are disabled on this server. Restart ComfyUI with "
                "--preview-method auto (or taesd).")
    if not STATS["patched"]:
        return ("Probe not installed - could not wrap ComfyUI's preview "
                "functions. See patch_error.")
    if STATS["previewer_requested"] == 0:
        return ("No sampler has asked for a previewer yet. Run a generation, "
                "then check again.")
    if STATS["previewer_created"] == 0:
        return ("A previewer was requested but never created, so nothing can "
                "be produced. Usually --preview-method none, or a latent "
                "format without preview support.")
    if STATS["preview_sends"] == 0:
        return ("A previewer exists but no preview was ever sent. The sampler "
                "in this workflow is most likely not calling the preview "
                "callback - common with custom sampler nodes.")
    sockets = _socket_state().get("connected_client_ids") or []
    if STATS["last_sid"] is not None and STATS["last_sid"] not in sockets:
        return ("Previews are being produced and sent, but to a client_id "
                "with no open socket - so they are dropped before reaching "
                "the app.")
    return ("Previews are being produced and sent to a connected client. If "
            "the app still shows none, the problem is on the app side.")
