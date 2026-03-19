// Name     02 - Weaning
// Version  1.0
//
// Description:
//   The duration of mechanical ventilation should be as short as
//   possible. Daily spontaneous breathing trials seem to be important for a
//   fast weaning.
//
// Numerator:
//
// Denominator:
//

library "IndicateQi02Weaning" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

include Intervals called I
include LocalTimeGermany called L
include TimePeriods called T

include IndicateQiElements called elm

// TODO(moringenj): shared with IndicateQi01Ventilation
code "Intubated (Tube Present)": '4097216' from elm.OMOPSV

concept "Intubation Tube": {
  "Intubated (Tube Present)"
}

code "Invasive Ventilation Procedure": '37158404' from elm.OMOPSV

concept "Ventilation Procedure": {
  "Invasive Ventilation Procedure"
}

code "Trial of Spontaneous Breathing Procedure": '4308797' from elm.OMOPSV

concept "Trial of Spontaneous Breathing": {
  "Trial of Spontaneous Breathing Procedure"
}

code "Normal Extubation Procedure": '4148972' from elm.OMOPSV

code "Inadvertent Extubation Event": '4231838' from elm.OMOPSV

context Patient

define "Ventilation Procedures":
  [ProcedureOccurrence: "Ventilation Procedure"] p
    where convert p to Interval<DateTime> overlaps elm."Review Period"

define "Ventilation Periods":
  "Ventilation Procedures" p return all convert p to Interval<DateTime>

define "Trial of Spontaneous Breathing Procedures":
  [ProcedureOccurrence: "Trial of Spontaneous Breathing"] p
    where convert p to Interval<DateTime> overlaps elm."Review Period"
    return all p
    sort by procedureDatetime

define "Extubation Procedures":
  [ProcedureOccurrence: "Normal Extubation Procedure"] p
    where (convert p to Interval<DateTime>) overlaps elm."Review Period"
    return all p
    sort by procedureDatetime

define "Inadvertent Extubation Events":
  [Observation: "Inadvertent Extubation Event"] o
    where o during elm."Review Period"
    return all o
    sort by observationDatetime

define "Periods without Ventilation":
  I.SubtractFromInterval(elm."Review Period", "Ventilation Periods")

// Spontaneous Breathing Trial

define function "Is Spontaneous Breathing Trial in Period"(period Interval<DateTime>):
     Exists("Trial of Spontaneous Breathing Procedures" p
              where convert p to Interval<DateTime> overlaps period)
  or Exists("Extubation Procedures" p
              where convert p to Interval<DateTime> overlaps period)
  or Exists("Inadvertent Extubation Events" e
              where convert e to DateTime during period)
  or Exists("Periods without Ventilation" p where p overlaps period)

// Quality Indicator

define function "Ventilated for at least 48 Hours"(procedureIntervals List<Interval<DateTime>>):
  Exists((collapse(procedureIntervals)) i
           where duration in hours of i >= 48
           return all i)

define function "Is in Initial Population"(visit VisitOccurrence):
  (1) _
    let visitInterval: convert visit to Interval<DateTime>
      return     Exists([DeviceExposure: "Intubation Tube"] d
                          where (convert d to Interval<DateTime>)
                                overlaps visitInterval)
             and "Ventilated for at least 48 Hours"(
                   "Ventilation Procedures" p
                     let procedureInterval: convert p to Interval<DateTime>
                       where procedureInterval overlaps visitInterval
                       return all procedureInterval
                 )
             and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     if "Is Spontaneous Breathing Trial in Period"(period) then 1 else 0,
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
