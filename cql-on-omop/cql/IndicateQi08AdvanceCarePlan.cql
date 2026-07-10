// Name     08 - Advance Care Plan
// Version  1.0
//
// Description:
//
//   Critically ill patients on an intensive care unit or their
//   relatives should be consulted regarding care/treatment plans.

library "IndicateQi08AdvanceCarePlan" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include TimePeriods called T

code "Advance Care Plan Agreed": '36685263' from elm.OMOPSV

code "Consultation with Patient":              '37164964' from elm.OMOPSV
code "Face to Face Consultation with Patient": '37168078' from elm.OMOPSV
code "New Patient Consultation":               '4089048'  from elm.OMOPSV

concept "Consultation with Patient Observation": {
  "Consultation with Patient",
  "Face to Face Consultation with Patient",
  "New Patient Consultation"
}

code "Discussion about Care Plan with Family": '4247376' from elm.OMOPSV

code "Decision Authority Documented": '45877806' from elm.OMOPSV

context Patient

define "Advance Care Plan Agreed Observations":
  [Observation: "Advance Care Plan Agreed"] o
    return all o
    sort by observationDatetime

define "Consultation with Patient Observations":
  [Observation: "Consultation with Patient Observation"] o
    return all o
    sort by observationDatetime

define "Discussion about Care Plan with Family Observations":
  [Observation: "Discussion about Care Plan with Family"] o
    return all o
    sort by observationDatetime

define "Decision Authority Documented Observations":
  [Observation: "Decision Authority Documented"] o
    return all o
    sort by observationDatetime

// This function returns the number of satisfied criteria (between 0 and 3) for
// the 72-hour period starting at startTime.
define function "Number of Satisfied Criteria in Period"(startTime DateTime):
  (1) _
    let "First 72 hours": Interval[startTime, startTime + 72 hours]
      return   if Exists("Advance Care Plan Agreed Observations" o
                           where o in "First 72 hours") then
                 1
               else
                 0
             + if (   Exists("Consultation with Patient Observations" o
                               where o in "First 72 hours")
                   or Exists("Discussion about Care Plan with Family Observations" o
                               where o in "First 72 hours")) then
                 1
               else
                 0
             + if Exists("Decision Authority Documented Observations" o
                           where o in "First 72 hours") then
                 1
               else
                 0

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
      duration in hours of visitInterval >= 72
  and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visitInterval:               visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visitInterval),
        // Count the satisfied criteria for this visit, that is the
        // number of assessments (between 0 and 3) performed within the
        // first 72 hours of the visit.
        numberOfSatisfiedCriteria:   "Number of Satisfied Criteria in Period"(
                                       start of visitInterval
                                     )
      return all (visitWithPeriods.fullyContainedPeriods) period
                   return all elm."Period Result"(
                     period,
                     // From all fully contained 24-hour periods, exclude those
                     // that end within the first 72 hours of the visit since
                     // it is not a sign of non-conformance to perform the
                     // assessments on, say, the third day of the visit (and
                     // apply the initial population criterion).
                         inInitialPopulationForVisit
                     and (end of period)
                         same or after (start of visitInterval + 72 hours),
                     numberOfSatisfiedCriteria,
                     3
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
