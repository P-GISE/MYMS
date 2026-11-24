-- 담당자가 DB SQL Editor에서 실행할 읽기 전용 확인. 데이터/정책/권한을 변경하지 않는다.
begin read only;

select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname in ('profiles', 'workout_plans', 'workout_sessions');

select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename in ('profiles', 'workout_plans', 'workout_sessions')
order by tablename, policyname;

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name in ('profiles', 'workout_plans', 'workout_sessions')
  and grantee in ('anon', 'authenticated', 'PUBLIC')
order by table_name, grantee, privilege_type;

select table_name, column_name, column_default, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name in ('workout_plans', 'workout_sessions')
  and column_name in ('user_id', 'points_earned');

select trigger_name, event_manipulation, action_statement
from information_schema.triggers
where event_object_schema = 'public' and event_object_table = 'workout_sessions';

select p.proname, p.prosecdef, p.proconfig
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'delete_my_account';

rollback;
