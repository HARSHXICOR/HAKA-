grant usage on schema public, private to service_role;
grant all privileges on all tables in schema public, private to service_role;
grant usage, select on all sequences in schema public, private to service_role;

alter default privileges in schema public
  grant all privileges on tables to service_role;
alter default privileges in schema private
  grant all privileges on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to service_role;
alter default privileges in schema private
  grant usage, select on sequences to service_role;
