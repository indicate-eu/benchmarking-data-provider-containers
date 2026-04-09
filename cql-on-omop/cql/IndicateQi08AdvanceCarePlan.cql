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

code "Consultation with Patient": '37164964' from elm.OMOPSV

code "Decision Authority Documented": '1032192' from elm.OMOPSV

context Patient

define "Advance Care Plan Agreed Observations":
  [Observation: "Advance Care Plan Agreed"] o
    return all o
    sort by observationDatetime

define "Consultation with Patient Observations":
  [Observation: "Consultation with Patient"] o
    return all o
    sort by observationDatetime

define "Decision Authority Documented Observations":
  [Observation: "Decision Authority Documented"] o
    return all o
    sort by observationDatetime

define function "Is Conforming Visit"(period Interval<DateTime>):
  (1) _
    let "First 72 hours": Interval[start of period,
                                   start of period + 72 hours]
      return     Exists("Advance Care Plan Agreed Observations" o
                          where o in "First 72 hours")
             and Exists("Consultation with Patient Observations" o
                          where o in "First 72 hours")
             and Exists("Decision Authority Documented Observations" o
                          where o in "First 72 hours")

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  (1) _
    let visitInterval: convert visit to Interval<DateTime>
      return     duration in hours of visitInterval >= 72
             and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit as VisitOccurrence),
        conformingVisit:             "Is Conforming Visit"(visit),
        periodCount:                 Count(visitWithPeriods.periods)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     if conformingVisit then 1 else 0,
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
