// Name     07 - Pain, Sedation and Delirium
// Version  1.0
//
// Description:
//   Critically ill patients on an intensive care unit are often exposed
//   to painful stimuli.  (Over-)sediation and Delirium is common (up to
//   80 % of all critically ill patients).  Monitoring/Detection is
//   important for early treatment and enforced by national guidelines
//   regularly, at least once per shift.  Due to the lack of monitoring
//   devices the assessment of scores is critical.

library "IndicateQi07PainSedationDelir" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include TimePeriods called T

// Pain Assessment

code "Behavioral Pain Scale (Measurement)":     '2100000007' from elm.OMOPSV
code "Numeric Pain Rating Scale (Measurement)": '37151627' from elm.OMOPSV
code "Visual Analog Pain Scale (Measurement)":  '4165600'  from elm.OMOPSV

concept "Pain Assessment Measurement": {
    "Behavioral Pain Scale (Measurement)",
    "Numeric Pain Rating Scale (Measurement)",
    "Visual Analog Pain Scale (Measurement)"
}

// Sedation Assessment

code "Richmond Agitation-Sedation Scale (Measurement)": '36684829' from elm.OMOPSV
code "Ramsay Sedation Scale (Measurement)":             '4105091' from elm.OMOPSV

concept "Sedation Assessment Measurement": {
  "Richmond Agitation-Sedation Scale (Measurement)",
  "Ramsay Sedation Scale (Measurement)"
}

// Delirium Assessment

code "3-minute Diagnostic Interview for CAM-defined Delirium (3D-CAM)":   '2100000000' from elm.OMOPSV
code "4AT - 4 A's Test (Measurement)":                                    '3662219' from elm.OMOPSV // TODO
code "Confusion Assessment Method for the Intensive Care Unit (CAM-ICU)": '2100000001' from elm.OMOPSV
code "Delirium Detection Score (DDS)":                                    '2100000002' from elm.OMOPSV
code "Delirium Observation Screening (DOS) scale":                        '2100000004' from elm.OMOPSV
code "Delirium Rating Scale-revised-98 (DRS-R-98)":                       '2100000006' from elm.OMOPSV
code "Intensive Care Delirium Screening Checklist (ICDSC)":               '2100000003' from elm.OMOPSV
code "Nursing Delirium Screening Scale (Nu-DESC)":                        '2100000005' from elm.OMOPSV
code "Glasgow Coma Score Total":                                          '3007194' from elm.OMOPSV

concept "Delirium Assessment Measurement": {
  "3-minute Diagnostic Interview for CAM-defined Delirium (3D-CAM)",
  "4AT - 4 A's Test (Measurement)",
  "Confusion Assessment Method for the Intensive Care Unit (CAM-ICU)",
  "Delirium Detection Score (DDS)",
  "Delirium Observation Screening (DOS) scale",
  "Delirium Rating Scale-revised-98 (DRS-R-98)",
  "Intensive Care Delirium Screening Checklist (ICDSC)",
  "Nursing Delirium Screening Scale (Nu-DESC)",
  "Glasgow Coma Score Total"
}

context Patient

define "Pain Assessment Measurements":
  [Measurement: "Pain Assessment Measurement"]

define "Sedation Assessment Measurements":
  [Measurement: "Sedation Assessment Measurement"]

define "Delirium Assessment Measurements":
  [Measurement: "Delirium Assessment Measurement"]

// Assessments

// TODO(moringenj): we don't need the next measurement but making a dedicated
//                  function does not seem worth the effort
define function "Are Conforming Assessments"(measurements List<Tuple{previous Measurement, current Measurement, next Measurement}>,
                                             isFirstShift Boolean):
      Exists(measurements)
  and AllTrue(measurements m
                return all    isFirstShift
                           or (difference in hours
                                 between (convert m.previous to DateTime)
                                 and     (convert m.current  to DateTime)) <= 10 hours)

define function "Measurements during Shift with Neighbors"(
    measurements List<Measurement>,
    shift        Interval<DateTime>
  ):
  (elm."Measurements with Neighbors"(measurements)) m
    where (convert m.current to DateTime) during shift
    return all m

define function "Is Conforming Shift"(shift        Interval<DateTime>,
                                      isFirstShift Boolean):
      "Are Conforming Assessments"("Measurements during Shift with Neighbors"("Pain Assessment Measurements", shift),
                                   isFirstShift)
  and "Are Conforming Assessments"("Measurements during Shift with Neighbors"("Sedation Assessment Measurements", shift),
                                   isFirstShift)
  and "Are Conforming Assessments"("Measurements during Shift with Neighbors"("Delirium Assessment Measurements", shift),
                                   isFirstShift)

// Shifts

define function "Conforming Shifts in Visit"(shifts List<Interval<DateTime>>):
  // Handle the first shift of each ICU visit specially since the
  // first measurement of that first shift does not have a preceding
  // measurement.
  Flatten({
            ({ First(shifts) }) s
              where "Is Conforming Shift"(s, true)
              return all s,
            (Tail(shifts)) s
              where "Is Conforming Shift"(s, false)
              return all s
         })

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  AgeInYearsAt(start of (convert visit to Interval<DateTime>)) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit),
        shifts:                      T."Shifts during Visit"(visit),
        goodShifts:                  "Conforming Shifts in Visit"(shifts)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodShifts) s where s during period),
                     Count((shifts)     s where (s as Interval<DateTime>) during period)
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
