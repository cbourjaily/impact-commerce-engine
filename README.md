# commerce-engine

A generic pipeline for pulling product catalogs from Impact.com
affiliate feeds (Impact Radius format) into a local SQLite database.

## Quickstart

1. Impact.com FTP credentials go in `~/.netrc`, `chmod 600` -- this
   isn't committed and needs setting up per machine.
2. `cd backend/commerce-engine && bash shell/update-onp.sh` -- pulls
   the sample retailer's catalog and loads it into
   `database/impact.db`.

## Adding your own retailers

See `backend/commerce-engine/UPDATING-CATALOGS.txt` -- walks through
adding a new retailer (with or without custom parsing) and adding a
new field to the schema.

## Day-to-day operations

See `backend/commerce-engine/RUNBOOK.txt` -- running the full update,
reloading one retailer manually, checking the database, recovering
from a schema change.
