# Venue layout showcase

Short, real UI recordings in light mode with English captions. Each chapter
shows a complete workflow and can be embedded independently.

| Workflow | Video | GIF |
| --- | --- | --- |
| Place a table, animate chairs and try a round shape | [MP4](table-basics.mp4) | [GIF](table-basics.gif) |
| Ctrl-drag copies and style the selected row | [MP4](copy-style.mp4) | [GIF](copy-style.gif) |
| Paint a custom table and add chairs one by one | [MP4](custom-table.mp4) | [GIF](custom-table.gif) |
| Drag an arc to the center, edit rows/columns/curvature and try the Flutter viewer | [MP4](arc.mp4) | [GIF](arc.gif) |
| Style a ready-made bus | [MP4](bus.mp4) | [GIF](bus.gif) |
| Choose seats and review tickets on mobile | [MP4](mobile-order.mp4) | [GIF](mobile-order.gif) |

[Continuous MP4](../showcase.mp4) · [WebM](../showcase.webm) ·
[English captions](captions.en.srt)

The clips were recorded on 21 October 2026 from the 0.3 development build.
They show actual pointer and keyboard interactions at the original UI animation
speed. The mobile host runs in a real 390x780 browser viewport with minimal
seating appearance. Its four tables and 32 seats come from the editor's actual
export; two selected places total CZK 500.

Reservations, checkout and payments belong to the integrating application.
The mobile review is a local selection example and creates no order.
The hosted interactive demo and registry package are updated separately.

[Template library screenshot](template-library.png) shows the development catalog rendered through the public web viewer.

Additional examples: [templates](templates.gif), [rows](rows.gif),
[bounded zoom and pan](viewport.gif), and [dark mode](dark-mode.gif).

To browse the clips offline, download the repository and open
[`doc/showcase.html`](../showcase.html) directly in a browser. No server is needed.
