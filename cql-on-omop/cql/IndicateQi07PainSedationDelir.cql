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
//
// Numerator:
//
// Denominator:

library "IndicateQi07PainSedationDelir" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include TimePeriods called T

// Pain Assessment

// BPS (Behavior Pain Scale) codes
// code "BPS Assessment (Procedure)": '?' from elm.OMOPSV
// code "BPS Score (Measurement)": '?' from elm.OMOPSV
// code "BPS Scale (Measurement)": '?' from elm.OMOPSV

// NPRS (Numeric (Pain) Rating Scale) codes
//code "NPRS Assessment (Procedure)": '37174733' from elm.OMOPSV
//code "NPRS Score (Measurement)":    '37151630' from elm.OMOPSV
code "NPRS Scale (Measurement)":    '37151627' from elm.OMOPSV

// VAPS (Visual Analog (Pain) Scale) codes
//code "VAPS Assessment (Procedure)": '40492247' from elm.OMOPSV
//code "VAPS Score (Measurement)":    '40481449' from elm.OMOPSV
code "VAPS Scale (Measurement)":    '4165600'  from elm.OMOPSV

concept "Pain Assessment Measurement": {
    //"BPS Scale (Measurement)",
    "NPRS Scale (Measurement)",
    "VAPS Scale (Measurement)"
}

// Sedation Assessment

// RASS (Richmond Agitation-sedation Scale) codes
//code "RASS Assessment (Procedure)": '1450954' from elm.OMOPSV
//code "RASS Score (Measurement)":    '1450955' from elm.OMOPSV
//code "RASS Scale (Measurement) 1":  '1447532' from elm.OMOPSV
code "RASS Scale (Measurement) 2":  '36684829' from elm.OMOPSV
concept "RASS Scale (Measurement)": {
  /*"RASS Scale (Measurement) 1",*/ "RASS Scale (Measurement) 2"
}

// RSS (Ramsay Sedation Scale) codes
// https://athena.ohdsi.org/search-terms/terms/4105091
// https://athena.ohdsi.org/search-terms/terms/1093862
// https://athena.ohdsi.org/search-terms/terms/1091379
// https://athena.ohdsi.org/search-terms/terms/1091117
//code "RSS Assessment (Procedure)": '?' from elm.OMOPSV
//code "RSS Score (Measurement)":    '?' from elm.OMOPSV
code "RSS Scale (Measurement)":    '4105091' from elm.OMOPSV

concept "Sedation Assessment Measurement": {
  //"RASS Scale (Measurement) 1",
  "RASS Scale (Measurement) 2",
  "RSS Scale (Measurement)"
}

// Delirium Assessment

// CAM (Confusion Assessment Method) codes
// TODO(moringenj): I could not find anything for CAM-ICU
code "CAM Assessment (Procedure)": '1450961' from elm.OMOPSV
code "CAM Score (Measurement)":    '1450962' from elm.OMOPSV
code "CAM Scale (Measurement)":    '1447712' from elm.OMOPSV

// TODO(moringenj): 3D-CAM

// 4AT (4 A's Test for delirium screening) codes
code "4AT Assessment (Procedure)": '3662220' from elm.OMOPSV
code "4AT Score (Measurement)":    '3662221' from elm.OMOPSV
code "4AT Scale (Measurement)":    '3662219' from elm.OMOPSV

// TODO(moringenj): DOS (Delirium Observation Score)

// TODO(moringenj): DRS (Delirium Rating Scale score)

// TODO(moringenj): NU-DESC (Nursing Delirium Screening Scale score)

// TODO(moringenj): DDS (Delirium Detection Score)

// ICDSC (Intensive Care Delirium Screening Checklist Score) codes
code "ICDSC Assessment (Procedure)": '1450964' from elm.OMOPSV
code "ICDSC Score (Measurement)":    '1450965' from elm.OMOPSV
code "ICDSC Scale (Measurement)":    '1447893' from elm.OMOPSV

concept "Delirium Assessment Measurement": {
  "CAM Score (Measurement)",
  "4AT Score (Measurement)",
  "ICDSC Score (Measurement)"
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
  // The weird as List<...> is due to a bug in the type inference of the CQL
  // engine.
  (elm."Measurements with Neighbors"(measurements)
   as List<Tuple{previous Measurement, current Measurement, next Measurement}>) m
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

define function "Is in Initial Population"(visit Interval<DateTime>):
  AgeInYearsAt(convert visit to DateTime) >= 18

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
