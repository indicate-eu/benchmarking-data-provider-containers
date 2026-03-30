// Name     06 - Infection Rate
// Version  1.0
//
// Description:
//   This quality indicator compares the incidence of ventilator
//   associated pneumonia and catheter-related infections.

library "IndicateQi06InfectionRate" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include IndicateQiElements called elm
include TimePeriods called T

// Terminology

// Central Venous Catheter: Device, Insertion, Removal, Infection

code "Central Venous Catheter": '4179206' from elm.OMOPSV

code "Insertion of Central Venous Catheter, general": '4052413' from elm.OMOPSV
code "Insertion of Central Venous Catheter via Internal Jugular Vein":
  '4051188' from elm.OMOPSV
code "Insertion of Central Venous Catheter via Subclavian Vein":
  '4052415' from elm.OMOPSV
code "Insertion of Central Venous Catheter via Femoral Vein":
  '4052416' from elm.OMOPSV

concept "Insertion of Central Venous Catheter": {
  "Insertion of Central Venous Catheter, general",
  "Insertion of Central Venous Catheter via Internal Jugular Vein",
  "Insertion of Central Venous Catheter via Subclavian Vein",
  "Insertion of Central Venous Catheter via Femoral Vein"
}

code "Removal of Central Venous Catheter": '4022792' from elm.OMOPSV

code "CRBSI, general":                     '42537216' from elm.OMOPSV
code "Infection of Intravenous Catheter":  '4149606'  from elm.OMOPSV
code "Infection of Hemodialyses Catheter": '764921'   from elm.OMOPSV

concept "Catheter-related Bloodstream Infection": {
  "CRBSI, general",
  "Infection of Intravenous Catheter",
  "Infection of Hemodialyses Catheter"
}

// Ventilation: Procedure, Infection (Pneumonia)

code "Invasive Ventilation": '37158404' from elm.OMOPSV

code "Ventilator associated Pneumonia": '259992' from elm.OMOPSV

context Patient

define "CVC Device Exposures":
  [DeviceExposure: "Central Venous Catheter"] d
    return all d
    sort by deviceExposureStartDatetime

define "CVC Insertion Procedures":
  [ProcedureOccurrence: "Insertion of Central Venous Catheter"] p
    return all p
    sort by procedureDatetime

define "CVC Removal Procedures":
  [ProcedureOccurrence: "Insertion of Central Venous Catheter"] p
    return all p
    sort by procedureDatetime

define "Catheter-related Bloodstream Infection Conditions":
  [ConditionOccurrence: "Catheter-related Bloodstream Infection"] c
    return all c
    sort by conditionStartDatetime

define "Ventilation Procedures":
  [ProcedureOccurrence: "Invasive Ventilation"] p
    return all p
    sort by procedureDatetime

define "Ventilator associated Pneumonia Conditions":
  [ConditionOccurrence: "Ventilator associated Pneumonia"] c
    return all c
    sort by conditionStartDatetime

//

define function incidence(period       Interval<DateTime>,
                          eventCount   Integer,
                          relevantDays Decimal):
  case
    when eventCount > 0 and not (relevantDays > 0) then
      Message(0, true, '400', 'Error', 'In period [' + ToString(start of period) + ', ' + ToString(end of period) + '], event count is ' + ToString(eventCount) + ' but relevant days is ' + ToString(relevantDays))
    else
      // This will be null if relevantDays is 0 but in that case,
      // eventCount is also 0.
      (eventCount / relevantDays) * 1000
  end

// TODO(moringenj): Direct calculation from CVC code (without insertion and removal)
define function "CVC Periods in Period via Device Exposure"(period Interval<DateTime>):
  collapse(
    ("CVC Device Exposures") exposure
      let exposureInterval: (convert exposure to Interval<DateTime>)
        where exposureInterval overlaps period
        return all exposureInterval intersect period
  )

// TODO(moringenj): There are no removal procedures in the MIMIC data
define function "CVC Periods in Period via Insertion and Removal"(period Interval<DateTime>):
  collapse(
    ("CVC Insertion Procedures") insertion
      where insertion.procedureDatetime before (end of period)
      return all (1) _
                   let startTime: convert insertion to DateTime,
                       removal:   First(("CVC Removal Procedures") removal
                                          where (start of convert removal to Interval<DateTime>)
                                                after (start of convert insertion to Interval<DateTime>)
                                          return all removal),
                       cvcPeriod: if removal is null then
                                    Interval[startTime, end of period]
                                  else
                                    Interval[startTime, convert removal to DateTime]

                     return all cvcPeriod intersect period
  )

define function "CVC Periods in Period"(period Interval<DateTime>):
  collapse(Flatten({
    "CVC Periods in Period via Device Exposure"(period),
    "CVC Periods in Period via Insertion and Removal"(period)
  }))

define function "CVC Hours in Period"(period Interval<DateTime>):
  ("CVC Periods in Period"(period)) p aggregate r starting 0:
    r + duration in hours of (p as Interval<DateTime>)

define function "CVC Days in Period"(period Interval<DateTime>):
  "CVC Hours in Period"(period) / 24

define function "Number of CRBSI in Period"(period Interval<DateTime>):
  Count(
    ("Catheter-related Bloodstream Infection Conditions") c
      where (convert c to Interval<DateTime>) overlaps period
      return all if c.conditionEndDatetime is null then
                   Message(c, true, '400', 'Error', 'Condition without end time')
                 else
                   c
  )

define function "CRBSI Incidence in Period"(period Interval<DateTime>):
  incidence(period, "Number of CRBSI in Period"(period), "CVC Days in Period"(period))

// TODO(moringenj): This could be wrong for multiple visits: A
// ventilation procedure start starts during the first visit and has no
// end time would be reported for the second visit as well. We should
// probably try to find the visit in which the procedure starts and take
// the end time from there.
define function "Ventilation Periods in Period"(period Interval<DateTime>):
  collapse(
    ("Ventilation Procedures") p
      where p.procedureDatetime before (end of period)
      return all (1) _
                   let ventilationInterval: if p.procedureEndDatetime is null then
                                              Interval[convert p to DateTime, end of period]
                                            else
                                              convert p to Interval<DateTime>
                     return all ventilationInterval intersect period
  )

define function "Ventilation Hours in Period"(period Interval<DateTime>):
  ("Ventilation Periods in Period"(period)) p aggregate r starting 0:
    r + duration in hours of (p as Interval<DateTime>)

define function "Ventilation Days in Period"(period Interval<DateTime>):
  "Ventilation Hours in Period"(period) / 24

define function "Number of VAP in Period"(period Interval<DateTime>):
  Count(
    ("Ventilator associated Pneumonia Conditions") c
      where (convert c to Interval<DateTime>) overlaps period
      return all if c.conditionEndDatetime is null then
                   Message(c, true, '400', 'Error', 'Condition without end time')
                 else
                   c
  )

define function "VAP Incidence in Period"(period Interval<DateTime>):
  incidence(period,
            "Number of VAP in Period"(period),
            "Ventilation Days in Period"(period))

define function "Overall Incidence in Period"(period Interval<DateTime>):
  (1) _
    let crbsi: "CRBSI Incidence in Period"(period),
        vap:   "VAP Incidence in Period"(period)
      return case
               when crbsi is null then
                 vap
               when vap is null then
                 crbsi
               else
                 vap + crbsi
             end

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  (1) _
    let visitInterval: convert visit to Interval<DateTime>
      return     duration in hours of visitInterval >= 24 hours
             and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     0,
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
