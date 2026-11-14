# Faceless Shorts Library

The library is a local, dependency-free gallery for every rendered MP4. It **does not copy or upload** videos. Instead, it scans the project folder that the engine already uses:

```text
~/faceless-shorts/<short-name>/renders/*.mp4
```

## Start it

From this engine folder:

```bash
bash scripts/library.sh
```

Then open `http://localhost:4173`. The gallery updates when you press **Refresh library**. It scans rendered videos, reads a nearby `script.json` when available, and uses `review/all.jpg` as the card image if you generated one.

### Use another projects folder

```bash
FACELESS_LIBRARY_ROOT=/path/to/my-videos bash scripts/library.sh
```

or:

```bash
bash scripts/library.sh --root /path/to/my-videos --port 4174
```

## Keep videos visible

Always render into your project’s `renders/` directory—the normal engine command already does this:

```bash
node tools/capture.mjs video renders/my-short.mp4
```

If you use `new_video.sh` with its defaults, all new projects go into `~/faceless-shorts`, so they are found automatically. Each card opens an in-browser player with range-enabled video streaming.
