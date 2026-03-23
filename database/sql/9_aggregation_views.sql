-- Add index on cds_cdm.observation.observation_datetime
-- May speed up the aggregation views defined below
CREATE INDEX idx_observation_observation_datetime_1
ON cds_cdm.observation (observation_datetime);

-- Daily aggregation
CREATE VIEW cds_cdm.quality_indicator_daily_average AS
SELECT   MAX(observation_id)                                        AS observation_id,
         observation_concept_id,
         DATE_TRUNC('day', observation_datetime)                    AS period_start,
         DATE_TRUNC('day', observation_datetime) + INTERVAL '1 day' AS period_end,
         AVG(value_as_number)                                       AS average_value,
         COUNT(*)                                                   AS observation_count
FROM     cds_cdm.observation
WHERE    observation_concept_id >= 2_000_100_100 -- only quality indicator observations
GROUP BY observation_concept_id,
         DATE_TRUNC('day', observation_datetime)
ORDER BY period_start, observation_concept_id;

-- Weekly aggregation
CREATE VIEW cds_cdm.quality_indicator_weekly_average AS
SELECT   MAX(observation_id)                                          AS observation_id,
         observation_concept_id,
         DATE_TRUNC('week', observation_datetime)                     AS period_start,
         DATE_TRUNC('week', observation_datetime) + INTERVAL '1 week' AS period_end,
         AVG(value_as_number)                                         AS average_value,
         COUNT(*)                                                     AS observation_count
FROM     cds_cdm.observation
WHERE    observation_concept_id >= 2_000_100_100 -- only quality indicator observations
GROUP BY observation_concept_id,
         DATE_TRUNC('week', observation_datetime)
ORDER BY period_start, observation_concept_id;

-- Monthly aggregation
CREATE VIEW cds_cdm.quality_indicator_monthly_average AS
SELECT   MAX(observation_id)                                            AS observation_id,
         observation_concept_id,
         DATE_TRUNC('month', observation_datetime)                      AS period_start,
         DATE_TRUNC('month', observation_datetime) + INTERVAL '1 month' AS period_end,
         AVG(value_as_number)                                           AS average_value,
         COUNT(*)                                                       AS observation_count
FROM     cds_cdm.observation
WHERE    observation_concept_id >= 2_000_100_100 -- only quality indicator observations
GROUP BY observation_concept_id,
         DATE_TRUNC('month', observation_datetime)
ORDER BY period_start, observation_concept_id;

-- Yearly aggregation
CREATE VIEW cds_cdm.quality_indicator_yearly_average AS
SELECT   MAX(observation_id)                                          AS observation_id,
         observation_concept_id,
         DATE_TRUNC('year', observation_datetime)                     AS period_start,
         DATE_TRUNC('year', observation_datetime) + INTERVAL '1 year' AS period_end,
         AVG(value_as_number)                                         AS average_value,
         COUNT(*)                                                     AS observation_count
FROM     cds_cdm.observation
WHERE    observation_concept_id >= 2_000_100_100 -- only quality indicator observations
GROUP BY observation_concept_id,
         DATE_TRUNC('year', observation_datetime)
ORDER BY period_start, observation_concept_id;
