# Object layout API migration boundary

Version 0.2 adds VenueLayoutDocument schemaVersion 1. This is a different type
from the preserved VenueSeatDocument grid schema 1. It never reinterprets a grid
as free coordinates, nor silently upgrades stored documents. Existing grid
controllers/widgets remain public for existing consumers.

## Breaking changes when adopting object layouts

`VenueLayout*` is not a drop-in replacement for `VenueSeat*`. Keep an existing
grid integration on `VenueSeatDocument`, its controller and widgets, or explicitly
update all three to the object API. Keep object-layout JSON separate from stored
grid JSON. Applications that need to convert existing plans must implement and
validate that conversion themselves; changing `schemaVersion` is insufficient.
Upgrading the package alone does not require converting existing grid plans.

New hosts use VenueLayoutDocument + VenueLayoutController and the object widgets.
The pure `venue_layout_core` package and JS runtime share the same schema, source
manifest and exact scene protocol. IDs are UUIDs independent of array order.
Nodes materialize geometry; generators only edit explicit nodes.

Unknown schema throws UnsupportedLayoutSchema carrying the original map. Keep
that original payload read-only and offer export; do not serialize it through an
older reader. Coordinates/angles quantize to 1/1024; colors are #RRGGBBAA.

Selection, camera and pending state are session data. Prices, products, occupancy,
capacity and reservations are host data. Use the presentation maps and callbacks,
not new fields in portable geometry. Hosts may register history participants for
editable metadata; live availability never belongs in geometry undo.

Stage A does not migrate Festapp or its pins/fonts/assets/SQL/setup/orders. The
local demo's success/conflict/timeout/resource and storage responses are synthetic.
No database atomicity, authorization, real inventory, payments, ticket issuance,
cancellation or customer relocation is proved by these mock callbacks. Stage B
requires a new task. Registry distribution of `venue_seat_picker` 0.2.0 and
`venue_layout_core` 0.1.0 is separate from activating this API in a host app;
publishing the packages does not migrate any host data or deploy a host app.
