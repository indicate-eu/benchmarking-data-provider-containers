// Name     06 - Infection Rate
// Version  1.0
//
// Description:
//   This quality indicator compares the incidence of ventilator
//   associated pneumonia and catheter-related infections.

library "IndicateQi06InfectionRate" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

include TimePeriods called T

include IndicateQiElements called elm
include IndicateQiUtilities called U

// Terminology

// Central Venous Catheter Device

code "Central Venous Catheter Device": '4179206' from elm."OMOPSV Hierarchy"

// CVT Infection

code "CRBSI, general":                                                     '42537216' from elm.OMOPSV
code "Infection of Intravenous Catheter":                                  '4149606'  from elm.OMOPSV
code "Infection of Hemodialyses Catheter":                                 '764921'   from elm.OMOPSV
code "Infection associated with totally implantable venous access device": '43021261' from elm.OMOPSV
code "Infection of central venous catheter exit site":                     '4326841'  from elm.OMOPSV
code "Infection of hemodialysis temporary catheter":                       '764924'   from elm.OMOPSV
code "CLABSI - central line associated bloodstream infection":             '42537043' from elm.OMOPSV
code "Candidemia associated with intravascular line":                      '4201197'  from elm.OMOPSV
code "Infection of bloodstream associated with hemodialysis catheter":     '42537495' from elm.OMOPSV
code "Infection of bloodstream associated with temporary hemodialysis catheter": '42537540' from elm.OMOPSV
code "Infection of bloodstream associated with tunneled hemodialysis catheter":  '42537497' from elm.OMOPSV

concept "Catheter-related Bloodstream Infection": {
  "CRBSI, general",
  "Infection of Intravenous Catheter",
  "Infection of Hemodialyses Catheter",
  "Infection associated with totally implantable venous access device",
  "Infection of central venous catheter exit site",
  "Infection of hemodialysis temporary catheter",
  "CLABSI - central line associated bloodstream infection",
  "Candidemia associated with intravascular line",
  "Infection of bloodstream associated with hemodialysis catheter",
  "Infection of bloodstream associated with temporary hemodialysis catheter",
  "Infection of bloodstream associated with tunneled hemodialysis catheter"
}

// Ventilation: Procedure, Infection (Pneumonia)

code "Invasive Ventilation": '37158404' from elm.OMOPSV

code "Ventilator associated Pneumonia": '259992' from elm.OMOPSV

context Patient

define "CVC Device Exposures":
  [DeviceExposure: "Central Venous Catheter Device"] d
    return all d
    sort by deviceExposureStartDatetime

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
      // This call must use the Decimal literal 0.0 (instead of just
      // 0). Otherwise, mismatching types between the branches
      // (Integer for the when branch and Decimal for the else branch)
      // will make the whole case expression evaluate to null.  Not
      // catching the issue at compile-time and/or failing somewhat
      // silently at runtime seems to indicate a defficiency in the CQL
      // engine.
      U.SignalProblemWithValue('In period [' + ToString(start of period) + ', '
                               + ToString(end of period) + '], event count is '
                               + ToString(eventCount) + ' but relevant days is '
                               + ToString(relevantDays),
                               0.0)
    else
      // This will be null if relevantDays is 0 but in that case,
      // eventCount is also 0.
      (eventCount / relevantDays) * 1000
  end

define function "CVC Periods in Period"(period Interval<DateTime>):
  collapse(
    ("CVC Device Exposures") exposure
      let exposureInterval: (convert exposure to Interval<DateTime>)
        where exposureInterval overlaps period
        return all exposureInterval intersect period
  )

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

define function "Ventilation Periods in Period"(period      Interval<DateTime>,
                                                visitPeriod Interval<DateTime>):
  // Consider ventilation procedures that start during the current
  // visit and overlap the period being considered.  For ventilation
  // procedures without an end time, assume the procedure lasts at least
  // until the end of the considered period.  The restriction to the
  // current visit is necessary since otherwise a ventilation procedure
  // without recorded end time started in a previous visit would be
  // selected for each period in all later visits.
  collapse(
    ("Ventilation Procedures") p
      where     p.procedureDatetime during visitPeriod
            and p.procedureDatetime before (end of period)
      return all (1) _
                   let ventilationInterval: if p.procedureEndDatetime is null then
                                              Interval[convert p to DateTime, end of period]
                                            else
                                              convert p to Interval<DateTime>
                     return all ventilationInterval intersect period
  )

define function "Ventilation Hours in Period"(period      Interval<DateTime>,
                                              visitPeriod Interval<DateTime>):
  ("Ventilation Periods in Period"(period, visitPeriod)) p
    aggregate r starting 0:
      r + duration in hours of (p as Interval<DateTime>)

define function "Ventilation Days in Period"(period      Interval<DateTime>,
                                             visitPeriod Interval<DateTime>):
  "Ventilation Hours in Period"(period, visitPeriod) / 24

define function "Number of VAP in Period"(period Interval<DateTime>):
  Count(
    ("Ventilator associated Pneumonia Conditions") c
      where (convert c to Interval<DateTime>) overlaps period
      return all if c.conditionEndDatetime is null then
                   Message(c, true, '400', 'Error', 'Condition without end time')
                 else
                   c
  )

define function "VAP Incidence in Period"(period      Interval<DateTime>,
                                          visitPeriod Interval<DateTime>):
  // TODO(moringenj): explain "days" since really [0, 1]
  incidence(period,
            "Number of VAP in Period"(period),
            "Ventilation Days in Period"(period, visitPeriod))

define function "Overall Incidence in Period"(period      Interval<DateTime>,
                                              visitPeriod Interval<DateTime>):
  (1) _
    let crbsi: "CRBSI Incidence in Period"(period),
        vap:   "VAP Incidence in Period"(period, visitPeriod)
      return case
               when crbsi is null then
                 vap
               when vap is null then
                 crbsi
               else
                 vap + crbsi
             end

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
      duration in hours of visitInterval >= 24
  and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit)
      return all (visitWithPeriods.fullyContainedPeriods) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     0,
                     1 // TODO(moringenj): infection → 1000 , else → 0
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
