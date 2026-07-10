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

define function "24-hour Period with Conforming Medication"(period Interval<DateTime>):
  Exists("Anticoagulation Drug Exposures" e
           where (convert e to Interval<DateTime>) overlaps period
           return all e)

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
  AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit)
      // To implement the denominator exclusion, the following
      // considers only complete 24-hour periods and skips the first
      // complete 24-hour period.  For each of the considered periods,
      // one of the results 0/1 and 1/1 is generated.
      return all (Skip(visitWithPeriods.fullyContainedPeriods, 1)) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     if "24-hour Period with Conforming Medication"(period) then 1 else 0,
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
