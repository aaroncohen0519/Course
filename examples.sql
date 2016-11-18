-- Select clients who do not have a working Google Mobile tracking line configured or provisioned.
SELECT
  client_id,
  status :: TEXT
FROM
  (SELECT
     a.client_id,
     'No Google Mobile Configured' AS status
   FROM analytics.client_static_basic a
     LEFT JOIN control.calltrackingnumberconfiguration c ON a.client_id = c.client_id
     LEFT JOIN control.calltrackingnumber ctn ON ctn.calltrackingnumberconfiguration_id = c.id
   WHERE a.adstationstatus = 0
     AND NOT c.deleted
     AND a.client_type <> X
   GROUP BY a.client_id
   HAVING count(DISTINCT (c.name)) > 0
     AND sum(CASE WHEN c.name LIKE '%Mobile%' THEN 1 ELSE 0 END) = 0) config
UNION
  (SELECT
     a.client_id,
    'No Google Mobile Provisioned' AS status
   FROM analytics.client_static_basic a
     LEFT JOIN control.calltrackingnumberconfiguration c ON a.client_id = c.client_id
     LEFT JOIN control.calltrackingnumber ctn ON ctn.calltrackingnumberconfiguration_id = c.id
   WHERE a.adstationstatus = 0
     AND NOT c.deleted
     AND a.client_type <> X
     AND c.name LIKE '%Mobile%'
   GROUP BY a.client_id
   HAVING sum(CASE WHEN ctn.number IS NULL THEN 1 ELSE 0 END) = sum(CASE WHEN c.name LIKE '%Mobile%' THEN 1 ELSE 0 END))
   
-- Total calls under a number of seconds
SELECT (sub.less_than_x_calls * 1.0 / sub.total_calls) AS pct_calls_less_than_x
FROM (
       SELECT
         count(*)        AS total_calls,
         sum(CASE WHEN extract(EPOCH FROM lcc.callend - lcc.callstart) < X THEN 1 ELSE 0 END) AS less_than_x_calls
       FROM control.lead l
         JOIN control.lead_content_call lcc ON lcc.id = l.id
         JOIN analytics.client_static_basic a ON a.client_id = l.client_id
       WHERE a.segment_name = X
		 AND a.adstationstatus <> 2
		 AND l.primaryattribution = X
		 AND l.createddate <= current_date - interval '1 month'
		 ) sub;

-- Average Imp Weighted Rank by Day for a given segment
SELECT
  sub.day,
  sum(sub.ranktimesimpressions) * 1.0 / sum(sub.impressions) AS imp_w_rank
FROM
  (SELECT
     a.client_id,
     pr.day,
     pr.cost,
     pr.impressions,
     pr.averagerank * pr.impressions AS ranktimesimpressions
   FROM analytics.client_static_basic a
     JOIN control.provider_reports pr
       ON a.client_id = pr.clientid
   WHERE a.segment_name = X
     AND a.client_type = X
     AND a.adstationstatus = 0
     AND pr.day >= current_date - 4
  ) sub
GROUP BY sub.day;

-- Basic query for top 100 volume client-services for a specific subset of clients over a given time period.
SELECT
  a.client_id,
  a.client_name           AS client,
  a.segment_name          AS segment,
  a.budget,
  mile.livedate :: DATE,
  csc.name                AS service_category,
  sum(agg.clicks)         AS sc_clicks_30
FROM analytics.client_static_basic a
  JOIN control.client_product_milestonedates mile ON a.client_id = mile.client_id
   AND mile.product_id = (SELECT id
                          FROM control.product
                          WHERE name = X)
   AND a.adstationstatus = 0
   AND a.budget > X
   AND a.client_type = 'Local'
   AND mile.livedate <= current_date - 30
   AND not a.is_savemode
   AND a.client_id not in (X)
  JOIN control.campaignconfiguration ccc ON a.adconfiguration_id = ccc.adconfiguration_id
  JOIN control.servicecategory csc ON ccc.servicecategory_id = csc.id
  JOIN aggregates.provider_reports_campaignconfig_day agg ON ccc.id = agg.campaignconfiguration_id
   AND agg.day >= current_date - 30
GROUP BY a.client_id, a.client_name, a.segment_name, a.budget, mile.livedate, csc.name
HAVING sum(agg.clicks) > X
ORDER BY sc_clicks_30 DESC
LIMIT 100

--Grabbing audio files for calls over a given time period, based on length.
SELECT
 l.client_id,
 a.client_type,
 l.id                                                  AS lead_id,
 lcc.callstart                                         AS callstart,
 l.createddate :: DATE                                 AS date,
 extract(EPOCH FROM lcc.callend - lcc.callstart)       AS seconds,
 l.primaryattribution,
 l.secondaryattribution,
 'https:X' || audiofileurl AS audiofile
FROM control.lead l
 JOIN control.lead_content_call lcc
  ON l.id = lcc.id
 JOIN analytics.client_static_basic a
  ON l.client_id = a.client_id
WHERE l.createddate >= current_date - INTERVAL '1 month'
  AND extract(EPOCH FROM lcc.callend - lcc.callstart) >= X
  AND primaryattribution = X

--What is our taxonomy for a given service
SELECT
 s.name                         	  AS segment, 
 sg.name                       		  AS servicegroup,
 sc.name                              AS servicecategory,
 coalesce(tax.locale_code, 'All')     AS location,    
 sc.id                                AS servicecategory_id,
 k.phrase                             AS keyphrase,
 (CASE WHEN tl.templatematchtype = 0 THEN 'Broad' 
      WHEN tl.templatematchtype = 1 THEN 'Phrase' 
      ELSE 'Exact' END)               AS match_type
FROM control.templatelisting tl
 JOIN control.templatelistingoutlets tlo ON tlo.templatelisting_id = tl.id
 JOIN control.templatelistingoutlets_outlets tloo ON tlo.id = tloo.templatelistingoutlets_id
 JOIN control.servicecategory_templatelistingoutlets sctl ON sctl.templatelistingoutlets_id = tlo.id
 JOIN control.servicecategory sc ON sc.id = sctl.servicecategory_id
 LEFT JOIN taxonomy.servicecategory_locale tax ON sc.id = tax.servicecategory_id
 JOIN control.servicegroup sg ON sg.id = sc.servicegroup_id
 JOIN control.segment s ON s.id = sc.segment_id
 JOIN control.keyphrase k ON k.id = tl.keyphraseid
WHERE tl.type = 0
  AND tloo.element <> 6
  AND NOT sc.deleted
  AND sg.name = X
GROUP BY s.name, sg.name, sc.name, sc.id, tax.locale_code, k.phrase, tl.templatematchtype
