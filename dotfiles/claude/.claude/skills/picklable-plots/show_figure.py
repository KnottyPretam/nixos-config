#!/usr/bin/env python3
"""Load and interactively view/annotate pickled matplotlib figures.

Companion to the `save_fig()` helper (see this skill's SKILL.md): any tool that
saves figures with `save_fig()` writes a gzipped *.pkl.gz next to every *.png.
This loader reopens them so you can zoom, read off exact values, and
click-annotate data points. Both gzipped (.pkl.gz) and plain (.pkl) pickles are
accepted — compression is detected automatically.

Usage:
  python show_figure.py path/to/fig.pkl.gz [more.pkl.gz ...]

Interaction (per figure window):
  left-click on a line   : add an annotation showing the curve label and x/y value
  right-click on a marker : delete that annotation
  v                       : toggle visibility of all annotations
  e                       : enable / disable the cursor
  left / right arrows     : step the selected annotation along its line
  w                       : write the annotated figure back to its .pkl (and .png)
  "Annotate" button       : turn off toolbar pan/zoom so left-clicks annotate again

Requires: matplotlib, mplcursors  (pip install matplotlib mplcursors)
"""

import argparse
import gzip
import pickle
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import mplcursors
from matplotlib.widgets import Button

# Keep cursors and widgets alive for the lifetime of the program; otherwise they
# get garbage-collected and interactivity silently stops working.
_CURSORS = []
_WIDGETS = []


def attach_cursor(fig):
    """Attach an mplcursors cursor that adds a persistent annotation on each
    left-click, formatted with the curve's label and the clicked x/y value."""
    cursor = mplcursors.cursor(fig, multiple=True, hover=False)

    @cursor.connect("add")
    def _on_add(sel):
        x, y = sel.target
        label = sel.artist.get_label()
        if not label or label.startswith("_"):
            label = "data"
        sel.annotation.set_text(f"{label}\nx={x:.4g}\ny={y:.4g}")

    _CURSORS.append(cursor)
    return cursor


def add_click_mode_button(fig):
    """Add a small 'Annotate' button that turns off the toolbar's pan/zoom mode,
    so left-clicks go back to adding annotations. While Pan or Zoom is active the
    navigation toolbar swallows clicks, so mplcursors never sees them."""
    tb = fig.canvas.toolbar
    if tb is None:
        return  # headless / no navigation toolbar
    # Overlay a small button in the top-left corner. Mark its axes non-navigatable
    # so pan/zoom won't start on it and its own click handler fires instead.
    bax = fig.add_axes([0.005, 0.955, 0.085, 0.04])
    bax.set_navigate(False)
    btn = Button(bax, "Annotate")

    def _reset(_event):
        mode = str(tb.mode)
        if "pan" in mode:
            tb.pan()
        elif "zoom" in mode:
            tb.zoom()

    btn.on_clicked(_reset)
    _WIDGETS.append(btn)


def _is_gzip(path):
    """True if the file starts with the gzip magic number."""
    with open(path, "rb") as f:
        return f.read(2) == b"\x1f\x8b"


def make_writeback(fig, pkl_path, compressed):
    """Return a key_press handler that re-pickles the (now annotated) figure on 'w',
    in the same (compressed or plain) format it was loaded from. Annotations are plain
    matplotlib artists, so they persist through the pickle; the cursor object is not
    referenced by the figure, so the dump stays clean."""
    # Drop a trailing .gz so e.g. foo.pkl.gz -> foo.png (not foo.pkl.png).
    base = pkl_path.with_suffix("") if pkl_path.suffix == ".gz" else pkl_path
    png_path = base.with_suffix(".png")
    opener = gzip.open if compressed else open

    def _on_key(event):
        if event.key != "w":
            return
        with opener(pkl_path, "wb") as f:
            pickle.dump(fig, f)
        fig.savefig(png_path, dpi=120)
        print(f"wrote {pkl_path} and {png_path}")

    return _on_key


def load_figure(pkl_path):
    compressed = _is_gzip(pkl_path)
    opener = gzip.open if compressed else open
    with opener(pkl_path, "rb") as f:
        fig = pickle.load(f)
    attach_cursor(fig)
    add_click_mode_button(fig)
    fig.canvas.mpl_connect("key_press_event",
                           make_writeback(fig, pkl_path, compressed))
    return fig


def parse_args():
    p = argparse.ArgumentParser(
        description="Interactively view/annotate pickled matplotlib figures.")
    p.add_argument("pkl", nargs="+", type=Path,
                   help="one or more .pkl / .pkl.gz figure files to open")
    return p.parse_args()


def main():
    args = parse_args()
    missing = [str(p) for p in args.pkl if not p.exists()]
    if missing:
        print("ERROR: file(s) not found:\n  " + "\n  ".join(missing))
        sys.exit(1)

    for pkl_path in args.pkl:
        load_figure(pkl_path)
        print(f"opened {pkl_path}")

    print("\nleft-click=annotate  right-click=delete  v=toggle  e=enable/disable  "
          "arrows=move  w=save annotated .pkl/.png")
    print("after using toolbar Pan/Zoom, click the 'Annotate' button to click-annotate again")
    plt.show()


if __name__ == "__main__":
    main()
