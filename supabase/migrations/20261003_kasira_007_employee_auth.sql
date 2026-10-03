-- KASIRA production migration 007
-- Bind employee records to Supabase Auth users so employee self-service
-- attendance has a real authorization boundary.

alter table public.employees
  add column if not exists user_id uuid references auth.users(id) on delete set null;

create unique index if not exists employees_business_user_uidx
  on public.employees(business_id, user_id)
  where user_id is not null;

drop policy if exists employees_manager_all on public.employees;
create policy employees_manager_all on public.employees
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager']))
with check (public.has_business_role(business_id,array['owner','manager']));

create policy employees_self_read on public.employees
for select to authenticated
using (user_id=(select auth.uid()));

drop policy if exists attendance_manager_cashier_all on public.attendance;
create policy attendance_manager_cashier_all on public.attendance
for all to authenticated
using (public.has_business_role(business_id,array['owner','manager','cashier']))
with check (public.has_business_role(business_id,array['owner','manager','cashier']));

create policy attendance_employee_read on public.attendance
for select to authenticated
using (
  exists (
    select 1 from public.employees e
    where e.id=employee_id
      and e.business_id=business_id
      and e.user_id=(select auth.uid())
  )
);

create policy attendance_employee_insert on public.attendance
for insert to authenticated
with check (
  public.has_business_role(business_id,array['employee'])
  and exists (
    select 1 from public.employees e
    where e.id=employee_id
      and e.business_id=business_id
      and e.user_id=(select auth.uid())
      and e.status='active'
  )
);

create policy attendance_employee_update on public.attendance
for update to authenticated
using (
  public.has_business_role(business_id,array['employee'])
  and exists (
    select 1 from public.employees e
    where e.id=employee_id
      and e.business_id=business_id
      and e.user_id=(select auth.uid())
      and e.status='active'
  )
)
with check (
  public.has_business_role(business_id,array['employee'])
  and exists (
    select 1 from public.employees e
    where e.id=employee_id
      and e.business_id=business_id
      and e.user_id=(select auth.uid())
      and e.status='active'
  )
);

-- Ensure an employee record cannot be linked across businesses.
create or replace function public.validate_employee_user_relation()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
begin
  if new.user_id is not null
     and not exists (
       select 1 from public.memberships m
       where m.business_id=new.business_id
         and m.user_id=new.user_id
     ) then
    raise exception 'employee user is not a member of the business';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validate_employee_user_relation on public.employees;
create trigger trg_validate_employee_user_relation
before insert or update on public.employees
for each row execute function public.validate_employee_user_relation();
