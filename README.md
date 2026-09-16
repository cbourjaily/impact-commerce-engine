# commerce-engine

A generic pipeline for pulling product catalogs from Impact.com
affiliate feeds (Impact Radius format) into a local SQLite database.

## Quickstart

1. Impact.com FTP credentials go in `~/.netrc`, `chmod 600` -- this
   isn't committed and needs setting up per machine.
2. `cd commerce-engine && bash shell/update-onp.sh` -- pulls
   the sample retailer's catalog and loads it into
   `database/impact.db`.

## Day-to-day operations

See `commerce-engine/RUNBOOK.txt` -- running the full update,
reloading one retailer manually, checking the database, recovering
from a schema change.
