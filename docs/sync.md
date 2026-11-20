# Optional accounts and sync (M8)

Status: **schema written and guarded by a test; not provisioned, no client code
shipped.** This document records exactly what exists and what does not, so the
optional feature is never mistaken for a working one.

## What may sync

Only two things, both cosmetic:

| Table | Columns | Why |
| --- | --- | --- |
| `public.devices` | `id`, `user_id`, `nickname`, timestamps | A friendly name for a TV, so two phones can label it the same way |
| `public.ui_preferences` | `user_id`, `theme`, `haptics_enabled`, `updated_at` | Small presentation preferences |

Nothing else. No pairing key, no token, no IP address, no MAC address, no SSID,
no room or location. The app is fully functional with no account at all.

## Why the host is not synced

A host (`192.168.1.20`) identifies a network and a device on it. Syncing it
would create a server-side record of where the user watches TV, which the
mission statement rules out. The local credential remains the only link
between a device record and a real TV, and it never leaves the keystore.

The schema test in `packages/remote_core/test/schema_test.dart` fails if a
column name looks like a key, secret, token, MAC, IP, host, SSID or address.

## Security model

* Row Level Security is enabled on both tables.
* Every policy is `auth.uid() = user_id` for both `USING` and `WITH CHECK`, so
  a signed-in user can neither read nor write another account's rows.
* `anon` is revoked from both tables outright, so a future policy mistake still
  does not expose rows to signed-out visitors.
* The migration is `supabase/migrations/0001_preferences.sql`.

## What is deliberately missing

* No Supabase project, keys or client dependency. Creating one is an owner
  action, and the free-tier project would be another external dependency.
* No sign-in UI. Adding auth would put an account prompt in front of a
  local-only remote, which is the opposite of the MVP.
* No two-account isolation test against a live database. That test needs a
  project; until it runs, M8 is **not** signed off.

## To finish M8

1. Create a Supabase project you own and apply the migration with
   `supabase db push`.
2. Add the project URL and anon key as build-time configuration (never in the
   repository).
3. Implement sign-in behind an explicit opt-in and a `SyncClient` that writes
   only the two tables above.
4. Run the two-account test: create accounts A and B, write a nickname as A,
   and prove B cannot read or mutate it (SELECT and UPDATE both return zero
   rows).
5. Re-run the schema guard in CI; it already fails on any suspicious column.

## Decision

Accounts stay **off** in the shipped build. Sync is a post-MVP convenience; a
remote that works with no account is preferable to one that requires a login to
change the volume.
