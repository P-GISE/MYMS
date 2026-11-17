begin;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    age_group text check (age_group in ('teens', 'twenties', 'thirties', 'forties', 'fifties', 'sixties', 'older'))
);

create table public.exercises (
    slug text primary key,
    name text not null,
    instructions text[] not null,
    sensor_placement text not null
);

create table public.exercise_levels (
    exercise_slug text not null references public.exercises(slug),
    level smallint not null check (level between 1 and 3),
    target_depth_pct smallint not null check (target_depth_pct between 1 and 100),
    return_depth_pct smallint not null check (return_depth_pct >= 0 and return_depth_pct < target_depth_pct),
    primary key (exercise_slug, level)
);

create table public.recommendation_rules (
    exercise_slug text not null,
    age_group text not null check (age_group in ('teens', 'twenties', 'thirties', 'forties', 'fifties', 'sixties', 'older')),
    experience_level smallint not null check (experience_level between 1 and 3),
    recommended_level smallint not null,
    target_reps smallint not null check (target_reps between 1 and 100),
    target_sets smallint not null check (target_sets between 1 and 10),
    rest_seconds smallint not null check (rest_seconds between 5 and 300),
    reason text not null,
    primary key (exercise_slug, age_group, experience_level),
    foreign key (exercise_slug, recommended_level) references public.exercise_levels(exercise_slug, level)
);

create table public.workout_plans (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
    exercise_slug text not null,
    level smallint not null,
    target_reps smallint not null check (target_reps between 1 and 100),
    target_sets smallint not null check (target_sets between 1 and 10),
    rest_seconds smallint not null check (rest_seconds between 5 and 300),
    sort_order integer not null default 0 check (sort_order >= 0),
    foreign key (exercise_slug, level) references public.exercise_levels(exercise_slug, level)
);

create table public.workout_sessions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
    exercise_slug text not null,
    level smallint not null,
    target_reps smallint not null check (target_reps between 1 and 100),
    target_sets smallint not null check (target_sets between 1 and 10),
    rest_seconds smallint not null check (rest_seconds between 5 and 300),
    valid_reps integer not null check (valid_reps between 1 and target_reps * target_sets),
    completed_sets smallint not null check (completed_sets between 0 and target_sets and completed_sets * target_reps <= valid_reps),
    duration_seconds integer not null check (duration_seconds >= 0),
    finished_at timestamptz not null default now(),
    feedback text check (feedback in ('easy', 'appropriate', 'hard')),
    note text not null default '',
    points_earned integer not null default 0 check (points_earned between 0 and 300),
    foreign key (exercise_slug, level) references public.exercise_levels(exercise_slug, level)
);

create index workout_plans_user_order_idx on public.workout_plans (user_id, sort_order);
create index workout_sessions_user_finished_idx on public.workout_sessions (user_id, finished_at desc);

alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.exercise_levels enable row level security;
alter table public.recommendation_rules enable row level security;
alter table public.workout_plans enable row level security;
alter table public.workout_sessions enable row level security;

revoke all on public.profiles, public.exercises, public.exercise_levels, public.recommendation_rules,
    public.workout_plans, public.workout_sessions from anon, authenticated;
grant select on public.exercises, public.exercise_levels, public.recommendation_rules to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.workout_plans to authenticated;
grant select, insert, delete on public.workout_sessions to authenticated;
grant update (feedback, note) on public.workout_sessions to authenticated;

create policy "Read exercises" on public.exercises for select to authenticated using (true);
create policy "Read exercise levels" on public.exercise_levels for select to authenticated using (true);
create policy "Read recommendation rules" on public.recommendation_rules for select to authenticated using (true);

create policy "Read own profile" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "Create own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "Edit own profile" on public.profiles for update to authenticated
    using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "Read own plans" on public.workout_plans for select to authenticated using ((select auth.uid()) = user_id);
create policy "Create own plans" on public.workout_plans for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Edit own plans" on public.workout_plans for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own plans" on public.workout_plans for delete to authenticated using ((select auth.uid()) = user_id);

create policy "Read own sessions" on public.workout_sessions for select to authenticated using ((select auth.uid()) = user_id);
create policy "Create own sessions" on public.workout_sessions for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Edit own sessions" on public.workout_sessions for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Delete own sessions" on public.workout_sessions for delete to authenticated using ((select auth.uid()) = user_id);

insert into public.exercises (slug, name, instructions, sensor_placement) values
    ('pushup', '푸시업', array['손을 어깨너비로 짚고 팔을 펴세요.', '팔꿈치를 굽혀 가슴을 내리세요.', '바닥을 밀어 시작 자세로 돌아오세요.'], '가슴 아래 바닥에서 센서가 위를 향하게 놓으세요.'),
    ('squat', '스쿼트', array['발을 어깨너비로 벌리고 서세요.', '엉덩이를 뒤로 보내며 무릎을 굽히세요.', '발바닥으로 바닥을 밀며 일어서세요.'], '엉덩이 아래 바닥에서 센서가 위를 향하게 놓으세요.'),
    ('bridge', '힙 브리지', array['등을 대고 누워 무릎을 굽히세요.', '발바닥을 눌러 골반을 들어 올리세요.', '골반을 천천히 내리세요.'], '골반 위 거치대에 센서를 고정하고 아래를 향하게 하세요.'),
    ('knee-raise', '앉아서 무릎 들기', array['의자에 앉고 두 발을 바닥에 두세요.', '한쪽 허벅지를 들어 올리세요.', '발을 천천히 내리세요.'], '측정할 허벅지 위 거치대에 센서를 고정하고 아래를 향하게 하세요.');

insert into public.exercise_levels values
    ('pushup', 1, 35, 15), ('pushup', 2, 50, 15), ('pushup', 3, 65, 15),
    ('squat', 1, 20, 10), ('squat', 2, 30, 10), ('squat', 3, 45, 10),
    ('bridge', 1, 15, 10), ('bridge', 2, 25, 10), ('bridge', 3, 35, 10),
    ('knee-raise', 1, 15, 10), ('knee-raise', 2, 25, 10), ('knee-raise', 3, 35, 10);

insert into public.recommendation_rules
    (exercise_slug, age_group, experience_level, recommended_level, target_reps, target_sets, rest_seconds, reason)
select exercise.slug, age.age_group, experience.level, experience.level,
    exercise.base_reps + 2 * (experience.level - 1) - age.adjustment,
    greatest(1, experience.level - case when age.adjustment = 2 then 1 else 0 end),
    30,
    case when age.adjustment = 0 then '선택한 운동 종류와 경험에 맞춘 시작 계획입니다.'
         else '선택한 운동 경험과 연령대를 반영해 운동량을 조정한 시작 계획입니다.' end
from (values ('pushup', 5), ('squat', 8), ('bridge', 7), ('knee-raise', 6)) as exercise(slug, base_reps)
cross join (values ('teens', 1), ('twenties', 0), ('thirties', 0), ('forties', 0),
                  ('fifties', 1), ('sixties', 2), ('older', 2)) as age(age_group, adjustment)
cross join generate_series(1, 3) as experience(level);

commit;
