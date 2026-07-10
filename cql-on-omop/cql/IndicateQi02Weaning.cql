// Name     02 - Weaning
// Version  1.0
//
// Description:
//   The duration of mechanical ventilation should be as short as
//   possible. Daily spontaneous breathing trials seem to be important for a
//   fast weaning.

library "IndicateQi02Weaning" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers

include Intervals called I
include TimePeriods called T

include IndicateQiElements called elm

code "Invasive Ventilation Procedure": '37158404' from elm.OMOPSV

concept "Ventilation Procedure": {
  "Invasive Ventilation Procedure"
}

code "Trial of Spontaneous Breathing Procedure": '4308797' from elm.OMOPSV

concept "Trial of Spontaneous Breathing": {
  "Trial of Spontaneous Breathing Procedure"
}

code "Extubation of trachea":  '4148972' from elm.OMOPSV
code "Removal of endotracheal tube": '4150627' from elm.OMOPSV
code "Removal of tracheostomy tube": '4012607' from elm.OMOPSV

concept "Extubation Procedure": {
  "Extubation of trachea",
  "Removal of endotracheal tube",
  "Removal of tracheostomy tube"
}

code "Inadvertent Extubation Event": '4231838' from elm.OMOPSV

context Patient

define "Intubation Tube Exposures":
  [DeviceExposure: elm."Intubation Tube"] e
    where convert e to Interval<DateTime> overlaps elm."Review Period"

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
  [ProcedureOccurrence: "Extubation Procedure"] p
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

// Mechanical Ventilation and Spontaneous Breathing Trials

define function "Mechanical Ventilation Intervals for Visit"(visitInterval Interval<DateTime>):
  // A period of mechanical ventilation is characterized by the
  // presence of an intubation tube and simultaneous ventilation.
  collapse(
    I.IntersectIntervals(
      "Ventilation Procedures" p
        let procedureInterval: convert p to Interval<DateTime>
          where procedureInterval overlaps visitInterval
          return all procedureInterval,
      "Intubation Tube Exposures" e
        let exposureInterval: convert e to Interval<DateTime>
          where exposureInterval overlaps visitInterval
          return all exposureInterval
    )
  )

define function "Is Spontaneous Breathing Trial in Period"(period Interval<DateTime>):
     Exists("Trial of Spontaneous Breathing Procedures" p
              where convert p to Interval<DateTime> overlaps period)
  or Exists("Extubation Procedures" p
              where convert p to Interval<DateTime> overlaps period)
  or Exists("Inadvertent Extubation Events" e
              where convert e to DateTime during period)
  or Exists("Periods without Ventilation" p
              where     p overlaps period
                    and duration in minutes of (convert p to Interval<DateTime>) >= 5)

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
  AgeInYearsAt(start of visitInterval) >= 18

define function "Mechanically Ventilated for at least 48 Hours within"(
    mechanicalVentilationIntervals List<Interval<DateTime>>,
    periodInterval                 Interval<DateTime>
  ):
  // We compute a non-null value for the 24-hour period if a
  // mechanical ventilation episode (ventilation + intubation tube) that
  // overlaps the 24-hour period has been ongoing for at least 48 hours
  // at the start of the period.  A mechanical ventilation episode that
  // has been going on for less time at the start of the 24-hour period
  // does not require any intervention so neither counting the 24-hour
  // period as a failure nor as a success makes sense.
  //
  // Since all expected interventions (trial of spontaneous breathing,
  // extubation, lack of ventilation) require an interruption of the
  // mechanical ventilation, we check whether a mechanical ventilation
  // episode has been ongoing for at least 48 hours by checking whether
  // mechanical ventilation has been performed for at least 47 hours of
  // the 48 hours in question.
  (1) _
    let relevantPeriod: Interval[end of periodInterval - 48 hours,
                                 end of periodInterval],
        hoursInPeriod:  (mechanicalVentilationIntervals) i aggregate r starting 0:
                          r + (duration in hours of (i intersect relevantPeriod))
      return hoursInPeriod >= 47

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visitInterval:                  visitWithPeriods.visit,
        inInitialPopulationForVisit:    "Is in Initial Population"(visitInterval),
        mechanicalVentilationIntervals: "Mechanical Ventilation Intervals for Visit"(
                                          visitInterval
                                        )
      return all (visitWithPeriods.fullyContainedPeriods) period
                   return all elm."Period Result"(
                     period,
                         inInitialPopulationForVisit
                     and "Mechanically Ventilated for at least 48 Hours within"(
                           mechanicalVentilationIntervals, period
                         ),
                     if "Is Spontaneous Breathing Trial in Period"(period) then
                       1
                     else
                       0,
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
