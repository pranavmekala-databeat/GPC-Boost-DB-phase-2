CREATE OR REPLACE FUNCTION public.fn_get_offer_products(
	event_id integer)
    RETURNS TABLE(offerid integer, brand text, partno text, itemclass1 text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    SELECT 
        e."offerId",

        -- brand logic
        CASE 
            WHEN COUNT(DISTINCT p."brand") = 1 
                THEN MAX(p."brand")
            ELSE 'Multiple'
        END AS brand,

        -- part number logic
        CASE 
            WHEN COUNT(DISTINCT p."partNo") = 1
                THEN MAX(p."partNo")
            ELSE 'SKU List'
        END AS partNo,

        -- itemClass1 logic
        CASE 
            WHEN COUNT(DISTINCT p."sku") = 1 
                THEN MAX(e."comOfferCategory1")
            ELSE STRING_AGG(DISTINCT p."itemClass1", ', ')
        END AS itemClass1

    FROM "tEventOfferDetail" e
    join "tEvent" t on t."eventId" =e."eventId"
    JOIN "tProducts" p ON e."sku" = p."sku" and p."country"= t."country"
    WHERE e."eventId" = event_id
    GROUP BY e."offerId"
    ORDER BY e."offerId";
END;
$BODY$;

ALTER FUNCTION public.fn_get_offer_products(event_id integer)
    OWNER TO "gap-az-sec-psql-aes-gap-pps-aa-boost-01-dba";
