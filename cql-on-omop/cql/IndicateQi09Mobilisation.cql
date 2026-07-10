// Name     09 - Mobilisation
// Version  1.0
//
// Description:
//
//   Critically ill adult ICU patients should be mobilised at least once
//   per eligible ICU day, unless there is a documented order not to
//   mobilize.

library "IndicateQi09Mobilisation" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include TimePeriods called T
include IndicateQiElements called elm

include MobilizationProcedures

code "Order to not Mobilise": '2100000008' from elm.OMOPSV

context Patient

define "Mobilisation Procedures":
  [ProcedureOccurrence: MobilizationProcedures."Mobilization Procedures"] p
    return all p
    sort by procedureDatetime asc

define "Order to not Mobilise Observations":
  [Observation: "Order to not Mobilise"] o
    return all o
    sort by observationDatetime asc

// 24-hour periods

define function "Has Mobilisation"(period Interval<DateTime>):
  Exists("Mobilisation Procedures" p
           where (convert p to Interval<DateTime>) overlaps period
           return all p)

define function "Has Order to not Mobilise"(period Interval<DateTime>):
  Exists("Order to not Mobilise Observations" o
           where (convert o to DateTime) in period
           return all o)

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
      (duration in hours of visitInterval) >= 48
  and AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit)
      return all (visitWithPeriods.fullyContainedPeriods) period
                   let hasMobilisation:    "Has Mobilisation"(period),
                       orderToNotMobilize: "Has Order to not Mobilise"(period)
                     return all elm."Period Result"(
                       period,
                       inInitialPopulationForVisit,
                       case
                         when orderToNotMobilize then null
                         when hasMobilisation    then 1
                         else                         0
                       end,
                       1
                     )

define Result: elm."Overall Result"(Patient, "Visit Results")
