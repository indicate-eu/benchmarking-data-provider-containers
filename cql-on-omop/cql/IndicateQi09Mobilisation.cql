// Name     09 - Mobilisation
// Version  1.0
//
// Description:
//
//
// Numerator:
//   Number of 24-hour periods with mobilisation procedure.
//
// Denominator:
//   Number of 24-hour periods.

library "IndicateQi09Mobilisation" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include TimePeriods called T
include IndicateQiElements called elm

code Mobilisation: '4327195' from elm.OMOPSV

code "Order to not Mobilise": '4266013' from elm.OMOPSV

context Patient

define "Mobilisation Procedures":
  [ProcedureOccurrence: "Mobilisation"] p
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

define function "Is in Initial Population"(visit VisitOccurrence):
      (duration in hours of (convert visit to Interval<DateTime>)) >= 48
  and AgeInYearsAt(convert visit to DateTime) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit as VisitOccurrence),
        periods:                     visitWithPeriods.allPeriods
      // TODO(moringenj): The weird as List<...> expressions are needed to work
      //                  around a bug in the type inference of the CQL engine
      return all (periods as List<Interval<DateTime>>) period
                   let hasMobilisation: "Has Mobilisation"(period),
                       noMobilisation:  "Has Order to not Mobilise"(period)
                     return all elm."Period Result"(
                       period,
                       inInitialPopulationForVisit,
                       case
                         when noMobilisation  then null
                         when hasMobilisation then 1
                         else                      0
                       end,
                       1
                     )

define Result: elm."Overall Result"(Patient, "Visit Results")
