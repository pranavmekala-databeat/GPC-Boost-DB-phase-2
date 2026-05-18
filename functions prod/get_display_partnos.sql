CREATE OR REPLACE FUNCTION public.get_display_partnos(
	p_offer_id integer)
    RETURNS text
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    v_partnos TEXT;
BEGIN
    SELECT STRING_AGG("partNo", ', ')
    INTO v_partnos
    FROM public."tEventOfferDetail"
    WHERE "offerId" = p_offer_id
      AND "displayIndicator" = TRUE;

    RETURN v_partnos;
END;
$BODY$;

ALTER FUNCTION public.get_display_partnos(p_offer_id integer)
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
