begin;

alter table public.workout_sessions
    add column environment jsonb,
    add column measurement_source text,
    add column arduino_id text,
    add constraint workout_sessions_environment_check
        check (environment is null or jsonb_typeof(environment) = 'object'),
    add constraint workout_sessions_measurement_source_check
        check (measurement_source is null or measurement_source in ('tof', 'imu_test')),
    add constraint workout_sessions_arduino_id_check
        check (arduino_id is null or arduino_id ~ '^[0-9A-F]{16}$');

comment on column public.workout_sessions.environment is
    'Environment snapshot taken when the workout started (JSON object). NULL for records made before this column existed.';
comment on column public.workout_sessions.measurement_source is
    'How reps were measured: tof or imu_test. NULL for records made before this column existed.';
comment on column public.workout_sessions.arduino_id is
    'Unique ID read from the Arduino board, 16 uppercase hex digits. Identifies the device only; it is not proof of ownership.';

commit;
