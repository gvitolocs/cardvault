-- Scan Connect grants for the API writer role (the user in the Pi API's
-- MARKETPLACE_WRITER_DATABASE_URL). psql: -v api_role=<role>
-- Applied by pokoin-web scripts/deploy-scan-connect.sh migrate after 082.
grant select, insert, update, delete on
  public.scan_batches,
  public.scan_sessions,
  public.scan_pairings,
  public.scan_rate_limits,
  public.scan_items
to :"api_role";
