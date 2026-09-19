---
name: picklable-plots
description: >-
  Make matplotlib figures in a Python tool re-openable and interactively
  annotatable. Saves each figure as a gzipped pickle (.pkl.gz) alongside its
  .png, and provides a generic show_figure.py viewer with mplcursors click-to-
  annotate, toggle/delete, write-back, and a pan/zoom-reset button. Use when the
  user wants plots they can reopen later to zoom, read exact values, or label
  data points — e.g. "save figures so I can annotate them later", "make these
  plots interactive", "load this figure with show_figure.py", or when adding new
  plotting code to any Python analysis/CLI tool.
---

# Picklable, interactively-annotatable matplotlib figures

This skill adds a small, dependency-light pattern to any Python tool so its
matplotlib figures can be reopened interactively and click-annotated later. It
has two halves:

1. **`save_fig()`** — a helper added to the tool's plotting code. It writes each
   figure as a `*.png` *and* a gzipped pickle `*.png` → `*.pkl.gz` alongside it.
2. **`show_figure.py`** — a standalone viewer (bundled with this skill at
   `show_figure.py`) that reopens those pickles and attaches interactivity.

The tool that *generates* the plots stays fully headless — it never imports
mplcursors and never opens a window. All interactivity lives in
`show_figure.py`, because mplcursors `Cursor` objects are not picklable and must
be re-attached after loading.

## Dependencies

- Generating side (`save_fig`): `matplotlib` only (plus `gzip`, `pickle` from
  the stdlib).
- Viewing side (`show_figure.py`): `matplotlib` + `mplcursors`, and an
  interactive matplotlib backend (a GUI / display). Install with
  `pip install matplotlib mplcursors`.

## How to apply this to a project

### Step 1 — add the `save_fig` helper

Add `import gzip` and `import pickle` to the plotting module, then add this
helper near the other figure code:

```python
def save_fig(fig, outpath, dpi=120):
    """Write a figure as PNG and as a gzipped pickle (.pkl.gz) alongside it,
    then close it. The .pkl.gz can be reopened interactively with show_figure.py."""
    fig.savefig(outpath, dpi=dpi)
    gz_path = outpath.with_suffix(".pkl.gz")   # outpath must be a pathlib.Path
    with gzip.open(gz_path, "wb") as f:
        pickle.dump(fig, f)
    plt.close(fig)
```

Notes:
- `outpath` must be a `pathlib.Path` whose last suffix is the image extension
  (e.g. `.../foo.png`), so `.with_suffix(".pkl.gz")` yields `.../foo.pkl.gz`. If
  the code uses string paths, wrap them: `Path(outpath)`.
- If a call site uses a non-default dpi, pass it through: `save_fig(fig, p, dpi=200)`.

### Step 2 — route existing saves through it

Replace the existing save-and-close pairs:

```python
fig.savefig(outpath, dpi=120)
plt.close(fig)
```

with:

```python
save_fig(fig, outpath)
```

Do this for every figure the tool should make annotatable. **Leave alone** any
bare `plt.close(fig)` that closes an *empty/skipped* figure (no `savefig`
before it) — those should stay plain closes, not pickled.

### Step 3 — drop in the viewer

Copy this skill's `show_figure.py` into the project (it is fully generic — no
project-specific references). Then:

```
python show_figure.py path/to/foo.pkl.gz [more.pkl.gz ...]
```

`show_figure.py` auto-detects gzip by magic bytes, so it also opens plain `.pkl`
files. The `w` key writes an annotated figure back in the same format.

### Step 4 — verify

- **Headless / pickle round-trip** (no GUI needed): run the tool, confirm a
  `.pkl.gz` sits next to each `.png`, then check one reloads as a Figure:
  ```
  MPLBACKEND=Agg python -c "import gzip,pickle,matplotlib.figure as F; \
    fig=pickle.load(gzip.open('out/foo.pkl.gz','rb')); print(type(fig), len(fig.axes))"
  ```
- **Interactive** (needs a display, run by the user): open a `.pkl.gz` with
  `show_figure.py`; confirm left-click annotates (label + x/y), multiple clicks
  keep multiple annotations, right-click deletes one, `v` toggles all, the
  "Annotate" button restores clicking after Pan/Zoom, and `w` writes the
  annotated figure back.

## Interaction reference (in show_figure.py)

| action | effect |
|---|---|
| left-click on a line | add an annotation (curve label + x/y) |
| right-click on a marker | delete that annotation |
| `v` | toggle visibility of all annotations |
| `e` | enable / disable the cursor |
| left / right arrows | step the selected annotation along its line |
| `w` | write the annotated figure back to its `.pkl`/`.pkl.gz` (and `.png`) |
| "Annotate" button | turn off toolbar pan/zoom so left-clicks annotate again |

## Gotchas

- **Why gzip?** Pickled figures embed the full plotted data arrays. Lightweight
  plots compress ~10×; figures backed by dense, near-random float data (e.g.
  raw high-rate FFT input) barely compress. gzip is still a safe default.
- **mplcursors lives only in the viewer.** Don't import it in the generating
  tool — keep that side headless so batch runs need no display.
- **Cursor objects aren't picklable**; that's intentional. The viewer re-attaches
  a fresh cursor on load. Annotations themselves are plain matplotlib artists, so
  they *do* survive the pickle when written back with `w`.
- **`set_navigate(False)`** on the button axes is required so Pan/Zoom doesn't
  swallow the button's own clicks.
