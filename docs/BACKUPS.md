# Backups — dripstone_prod Postgres

Nightly `pg_dump` runs on the CachyOS host as user `powerpc` via a
systemd user timer (`dripstone-backup.timer`, daily, `Persistent=true`).

- Script: `~/.local/bin/dripstone-backup.sh`
- Primary dumps: `/srv/slow/backups/dripstone/dripstone_prod-<TS>.sql.gz`
  (second disk `/srv/slow`, writable by powerpc)
- Copy: `~/backups/dripstone_prod-<TS>.sql.gz`
- Retention: newest 7 in each location (script prunes the rest)
- Format: `pg_dump -U postgres -d dripstone_prod | gzip`
  (password read at runtime from `docker inspect dripstone-prod-db`)

## Restore

```sh
# pick a dump, then:
zcat /srv/slow/backups/dripstone/dripstone_prod-<TS>.sql.gz \
  | docker exec -i -e PGPASSWORD="$PASS" dripstone-prod-db \
    psql -U postgres -d dripstone_prod
```

`$PASS` = value of `POSTGRES_PASSWORD` from
`docker inspect dripstone-prod-db` (container env).
For a clean-room restore, drop + recreate `dripstone_prod` first, or
restore into a scratch DB and swap. Verify with
`docker exec dripstone-prod-db psql -U postgres -d dripstone_prod -c '\dt'`.
