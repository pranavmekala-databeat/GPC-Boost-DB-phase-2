CREATE OR REPLACE PROCEDURE public.run_inbound_cron()
LANGUAGE plpgsql
AS $BODY$
BEGIN
    -- Step 1
    BEGIN
        CALL public.sp_inbound_independent();
        RAISE NOTICE 'Step 1 completed';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Step 1 FAILED: %', SQLERRM;
        RAISE EXCEPTION 'Aborting: Rolling back entire batch';
    END;

    -- Step 2
    BEGIN
        CALL public.sp_tblprod_dpdt();
        RAISE NOTICE 'Step 2 completed';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Step 2 FAILED: %', SQLERRM;
        RAISE EXCEPTION 'Aborting: Rolling back entire batch';
    END;

    -- Step 3
    BEGIN
        CALL public.sp_products_upsert();
        RAISE NOTICE 'Step 3 completed';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Step 3 FAILED: %', SQLERRM;
        RAISE EXCEPTION 'Aborting: Rolling back entire batch';
    END;

    -- Step 4
    BEGIN
        CALL public.sp_price_product_rules_upsert();
        RAISE NOTICE 'Step 4 completed';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Step 4 FAILED: %', SQLERRM;
        RAISE EXCEPTION 'Aborting: Rolling back entire batch';
    END;

    -- Step 5
    BEGIN
        CALL public.sp_process_salesy1();
        RAISE NOTICE 'Step 5 completed';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Step 5 FAILED: %', SQLERRM;
        RAISE EXCEPTION 'Aborting: Rolling back entire batch';
    END;

    RAISE NOTICE 'All steps completed successfully.';

END;
$BODY$;
ALTER PROCEDURE public.run_inbound_cron()
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
