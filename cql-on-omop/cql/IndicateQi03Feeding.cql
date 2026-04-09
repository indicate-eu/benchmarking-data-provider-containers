// Name     03 - Feeding
// Version  1.0
//
// Description:
//   Early nutrition of critically ill patients is associated with an
//   improved outcome.  It should start within 24 to 48 hours of admission
//   and should be enough to meet individuals daily calorie requirement.
//   The calorie target is calculated by the insulin requirement and/or
//   phosphate measurements in a blood sample on a daily basis.

library "IndicateQi03Feeding" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include OMOPFunctions
include LocalTimeGermany called L
include TimePeriods called T
include IndicateQiElements called elm
include InsulinDrugs


// unit [cal]
code "Energy Requirement": '4022415' from elm.OMOPSV

code "Contraindication to Enteral Feeding": '4141768' from elm.OMOPSV // observation

// unit [cal]
code "Calorie Intake Total 24 Hour": '3026267' from elm.OMOPSV

// TODO(moringenj): Do we not need this for anything?
/*Calorie intake total:
- 3007882*/

code "CO2 Production Rate": '21490580' from elm.OMOPSV

code "Continuous Venovenous Hemofiltration":    '4051330' from elm.OMOPSV
code "Continuous Venovenous Hemodialysis":      '4051329' from elm.OMOPSV
code "Continuous Venovenous Hemodiafiltration": '4049846' from elm.OMOPSV
code "Intermittent Hemodialysis":               '4051326' from elm.OMOPSV

concept "Renal Replacement Therapy": {
  "Continuous Venovenous Hemofiltration",
  "Continuous Venovenous Hemodialysis",
  "Continuous Venovenous Hemodiafiltration",
  "Intermittent Hemodialysis"
}

code "Phosphate Serum": '3003458' from elm.OMOPSV
code "Phosphate Blood": '3018913' from elm.OMOPSV

concept "Phosphate Measurement": {
  "Phosphate Serum",
  "Phosphate Blood"
}

define "Insulin Drugs": InsulinDrugs."Insulin Drugs"

context Patient

define "Body Mass Index":
  elm."Most Recent Body Weight Measurement"
  / elm."Most Recent Body Height Measurement"

// Measurements and Procedures

define "Phosphate Measurements":
  [Measurement: "Phosphate Measurement"] m
    return all m
    sort by measurementDatetime desc

define "Insulin Exposures":
  [DrugExposure: "Insulin Drugs"]

define "Energy Requirement Measurements":
  [Measurement: "Energy Requirement"] m
    return all m
    sort by measurementDatetime desc

define "CO2 Production Rate Measurements":
  [Measurement: "CO2 Production Rate"]

define "Calorie Intake Measurements":
  [Measurement: "Calorie Intake Total 24 Hour"]

define "Renal Replacement Therapy Procedures":
  [ProcedureOccurrence: "Renal Replacement Therapy"]

define function "Last Phosphate Measurement in Period"(period Interval<DateTime>):
  (1) _
    let lastMeasurement: Last("Phosphate Measurements" m
                                where m.measurementDatetime in period
                                return all m)
      // The specification states that if there is no phosphate
      // measurement in the period, assume it was normal, that is
      // greater than 0.65 mmol/l.
      return if lastMeasurement is null then
               1 'mmol/L'
             else
               convert lastMeasurement to Quantity

define function "Max Insulin Measurement in Period"(period Interval<DateTime>):
  Max("Insulin Exposures" m
        where (convert m to Interval<DateTime>) overlaps period
        // No registered conversion at the moment
        return all OMOPFunctions.ToQuantity(m))

define function "Last Energy Requirement Measurement in Period"(period Interval<DateTime>):
  Last("Energy Requirement Measurements" m
         where m.measurementDatetime in period
         return all m)

define function "Median CO2 Production Rate in Period"(period Interval<DateTime>):
  Median("CO2 Production Rate Measurements" m
           where (convert m to DateTime) in period
           return all convert m to Quantity)

define function "Calorie Intake in Period"(period Interval<DateTime>):
  // There should be exactly one such measurement in each 24-hour period.
  (1) _
    let measurement: First("Calorie Intake Measurements" m
                             where m in period
                             return all m)
      return convert measurement to Quantity

define function "Renal Replacement Therapy Procedure in Period"(period Interval<DateTime>):
  Exists("Renal Replacement Therapy Procedures" p
           where (convert p to Interval<DateTime>) during period
           return all p)

//

define function "Initial Calorie Target via CO2 Production Rate"(previousPeriod Interval<DateTime>):
  Quantity{
    value: "Median CO2 Production Rate in Period"(previousPeriod).value
           * 8.19
           * if "Body Mass Index" < 30 then
              1
             else
              0.6,
    unit: 'kcal'
  }

define "Initial Calorie Target via BMI":
  case
    when "Body Mass Index" < 30 then
      // TODO(moringenj): use time-dependent body weight
      24 'kcal/d/kg' * (convert elm."Most Recent Body Weight Measurement" to Quantity)
    when "Body Mass Index" <= 50 then
      14 'kcal/d/kg' * (convert elm."Most Recent Body Weight Measurement" to Quantity)
    else
      24 'kcal/d/kg'
      * Quantity{
          // TODO(moringenj): use existing "Ideal Body Weight"
          value: (48.4 + 77 * ((convert elm."Most Recent Body Height Measurement" to Quantity) - 1.5 'm').value),
          unit:  'kg'
        }
  end

define function "Initial Calorie Target"(previousDay Interval<DateTime>):
  (1) _
    // TODO(moringenj): what temporal interval should we consider for the energy requirement?
    let energyRequirement: "Last Energy Requirement Measurement in Period"(previousDay)
      return if energyRequirement is not null then
               energyRequirement
             else if "Median CO2 Production Rate in Period"(previousDay) is not null then
               "Initial Calorie Target via CO2 Production Rate"(previousDay)
             else
               "Initial Calorie Target via BMI"

define function "Calorie Target for 24-hour Period"(previousTarget Quantity,
                                                    previousPeriod Interval<DateTime>,
                                                    period         Interval<DateTime>,
                                                    dayOfVisit     Integer):
  (1) _
    let initialCalorieTarget: 57625.88333333 'g.m2.s-3', // "Initial Calorie Target"(previousPeriod)
        rawTarget:            case
                                when dayOfVisit = 0 then
                                  null // No target for first 24-hour period

                                when dayOfVisit = 1 then
                                  0.75 * initialCalorieTarget

                                when     not "Renal Replacement Therapy Procedure in Period"(previousPeriod)
                                     and "Last Phosphate Measurement in Period"(period) < 0.65 'mmol/l'
                                     and "Max Insulin Measurement in Period"(previousPeriod) <= 4 '[IU]/h'
                                     and previousTarget >= 0.5 * initialCalorieTarget then
                                  0.25 * initialCalorieTarget

                                when     "Max Insulin Measurement in Period"(previousPeriod) < 2 '[IU]/h'
                                     /*and previousTarget < initialCalorieTarget*/ then
                                  previousTarget + 0.25 * initialCalorieTarget

                                when     "Max Insulin Measurement in Period"(previousPeriod)
                                         in Interval[2 '[IU]/h', 4 '[IU]/h']
                                     /*and previousTarget > 0 'kcal/d'*/ then
                                  previousTarget - 0.25 * initialCalorieTarget

                                when     "Max Insulin Measurement in Period"(previousPeriod) > 4 '[IU]/h'
                                     /*and previousTarget < 0 'kcal/d'*/ then
                                  previousTarget - 0.5 * initialCalorieTarget

                                else // TODO(moringenj):
                                  Message(null, true, '400', 'Error', 'No matching case; insulin ' + ToString("Max Insulin Measurement in Period"(previousPeriod)) + ' previous target ' + ToString(previousTarget))
                                  //null
                              end
      // Clamp calorie target to [0, Initial Calorie Target]; the
      // value could be outside of this range due to the unchecked
      // additions and subtractions above.
      return Max({0 'kcal/d', Min({rawTarget, initialCalorieTarget})})

define function "24-hour Periods with Results"(periods List<Interval<DateTime>>):
  (periods) p aggregate r starting ({
                                      previousPeriod: null,
                                      previousTarget: null,
                                      dayOfVisit:     0,
                                      results:        {},
                                      debug:          {}
                                    }):
    (1) _
      let target: "Calorie Target for 24-hour Period"(
                    r.previousTarget,
                    r.previousPeriod,
                    p,
                    r.dayOfVisit
                  ),
          actual: "Calorie Intake in Period"(p),
          result: 0.9 * target <= actual and actual <= 1.1 * target,
          debug:  Flatten({r.debug,   {{
                                        previousPeriod: r.previousPeriod,
                                        previousTarget: r.previousTarget,
                                        period:         p,
                                        dayOfVisit:     r.dayOfVisit,
                                        phosphate:      "Last Phosphate Measurement in Period"(p),
                                        insulin:        "Max Insulin Measurement in Period"(r.previousPeriod),
                                        targetIntake:   target,
                                        actualIntake:   actual,
                                        result:         result
                                      }}})
        return {
                 previousPeriod: p,
                 previousTarget: target,
                 dayOfVisit:     r.dayOfVisit + 1,
                 results:        if result then
                                   Flatten({r.results, {}})
                                 else
                                   r.results,
                 debug:          debug
               }

define function "24-hour Periods with appropriate Calorie Intake"(periods List<Interval<DateTime>>):
  "24-hour Periods with Results"(periods).results

// Quality Indicator

define function "Is in Initial Population"(visit VisitOccurrence):
  AgeInYearsAt(start of (convert visit to Interval<DateTime>)) >= 18

// TODO(moringenj): Use contraindication to enteral feeding
define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit),
        goodPeriods:                 "24-hour Periods with appropriate Calorie Intake"(visitWithPeriods.allPeriods)
      return all (visitWithPeriods.periods as List<Interval<DateTime>>) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodPeriods) p where p includes period),
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
