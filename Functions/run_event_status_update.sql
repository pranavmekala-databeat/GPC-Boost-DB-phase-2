CREATE OR REPLACE FUNCTION public.run_event_status_update()
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    UPDATE public."tEvent"
    SET "status" = 'Completed',
        "modifiedAt" = CURRENT_TIMESTAMP,
        "modifiedBy" = 'CronJob'
    WHERE "endDate" < CURRENT_DATE
      AND "status" IS DISTINCT FROM 'Completed';

    RAISE NOTICE 'Updated expired events to Completed.';
END;
$BODY$;

ALTER FUNCTION public.run_event_status_update()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
