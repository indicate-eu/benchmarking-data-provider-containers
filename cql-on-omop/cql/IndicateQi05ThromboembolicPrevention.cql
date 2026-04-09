// Name     05 - Prevention of venous thromboembolism
// Version  1.0
//
// Description:
//   Venous thromboembolism (VTE) is a frequent complication that
//   contributes significantly to morbidity and mortality among critically
//   ill patients.  Pharmacologic thromboprophylaxis should reduce VTE.

library "IndicateQi05ThromboembolicPrevention" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include TimePeriods called T
include IndicateQiElements called elm
include AnticoagulationDrugs

context Patient

define "Anticoagulation Drug Exposures":
  [DrugExposure: "AnticoagulationDrugs"."Anticoagulation Drugs"] e
    return all e
    sort by drugExposureStartDatetime asc

define function "Anticoagulation Drug Exposures during Period"(period Interval<DateTime>):
  ("Anticoagulation Drug Exposures") e
    where (convert e to Interval<DateTime>) overlaps period
    return all e

// 24-hour periods

define function "24-hour Period with Conforming Medication"(period Interval<DateTime>):
  Exists("Anticoagulation Drug Exposures during Period"(period))

define function "24-hour Periods with conforming Medication"(periods List<Interval<DateTime>>):
  Flatten({
    { First(periods) }, // First period always counts as conforming
    (Tail(periods)) p
      where "24-hour Period with Conforming Medication"(p)
      return all p
  })

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  AgeInYearsAt(start of (convert visit to Interval<DateTime>)) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let visit:                       visitWithPeriods.visit,
        inInitialPopulationForVisit: "Is in Initial Population"(visit),
        periods:                     visitWithPeriods.allPeriods,
        goodPeriods:                 "24-hour Periods with conforming Medication"(periods)
      // TODO(moringenj): The weird as List<...> expressions are needed to work
      //                  around a bug in the type inference of the CQL engine
      return all (periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodPeriods) s where s during period),
                     Count((periods)     s where (s as Interval<DateTime>) during period)
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
