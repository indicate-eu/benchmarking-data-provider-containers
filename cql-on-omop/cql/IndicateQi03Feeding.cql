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
include InsulinIngredients


// unit [cal]
code "Energy Requirement":                                '4022415' from elm.OMOPSV
code "Estimated required quantity of energy in 24 hours": '604877' from elm.OMOPSV

concept "Energy Requirement (Observation)": {
  "Energy Requirement",
  "Estimated required quantity of energy in 24 hours"
}

code "Contraindication to Enteral Feeding": '4141768' from elm.OMOPSV // observation

// unit [cal]
code "Calorie Intake Total 24 Hour": '3026267' from elm.OMOPSV

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

code "Phosphate in Serum (Moles/volume)": '3003458' from elm.OMOPSV
code "Phosphate in Blood (Moles/volume)": '3018913' from elm.OMOPSV
code "Phosphate in Blood (Mass/volume)":  '3024232' from elm.OMOPSV

concept "Phosphate Measurement": {
  "Phosphate in Serum (Moles/volume)",
  "Phosphate in Blood (Moles/volume)",
  "Phosphate in Blood (Mass/volume)"
}

define "Insulin Drugs": InsulinDrugs."Insulin Drugs"

define "Insulin Ingredient Concepts": InsulinIngredients."Insulin Ingredient Concepts"

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

define "Energy Requirement Observations":
  [Observation: "Energy Requirement (Observation)"] o
    return all o
    sort by observationDatetime desc

define "CO2 Production Rate Measurements":
  [Measurement: "CO2 Production Rate"]

define "Calorie Intake Measurements":
  [Measurement: "Calorie Intake Total 24 Hour"]

define "Renal Replacement Therapy Procedures":
  [ProcedureOccurrence: "Renal Replacement Therapy"]

// TODO(moringenj): will be replaced by utility library
define function "Convert g/L to mmol/L"(quantity Quantity):
  (1) _
    let scaled: convert quantity to 'mg/L'
      return Quantity{value: 0.0323 * scaled.value, unit: 'mmol/L'}

define function "Ensure Phosphate in mmol/L"(phosphate Quantity):
  case
    when Matches(phosphate.unit, '.*g/.*L') then
      "Convert g/L to mmol/L"(phosphate)
    when Matches(phosphate.unit, '.*mol/.*L') then
      phosphate
    else
      Message(null, true, '400', 'Error', 'Unit is "' + (if phosphate.unit is null then 'null' else phosphate.unit) + '" but must be either "mol/L" or convertible to "g/L"')
  end

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
               "Ensure Phosphate in mmol/L"(convert lastMeasurement to Quantity)

// NOTE(moringenj): In some databases, insulin dosages come out as [U]
// instead of [IU].  As far as I can tell, those are supposed to have the
// same semantics but the UCUM service that the CQL engine uses for unit
// conversion can only handle [IU] but not [U].
define function "Convert [U] to [IU]"(quantity Quantity):
  case
    when quantity.unit = '[IU]' then
      quantity
    when quantity.unit = '[U]' then
      Quantity{value: quantity.value, unit: '[IU]'}
    else
      (1) _
        let converted: convert quantity to '[IU]'
          return if converted is null then
                   Message(null as Quantity, true, '400', 'Warning', 'Unit of Insulin quantities must be [IU] or [U] or convertible to [IU], but ' + ToString(quantity) + ' is not convertible')
                 else
                   converted
  end

define function "DrugExposure to Insulin Dose in [IU]"(drugExposure DrugExposure):
  (1) _
    let quantity: OMOPFunctions.IngredientExposure(
                    drugExposure,
                    "Insulin Ingredient Concepts"
                  )
      return "Convert [U] to [IU]"(quantity)

define function "Max Insulin Rate in Period"(period Interval<DateTime>):
  (1) _
    let totalInsulin: Sum("Insulin Exposures" e
                            where (convert e to Interval<DateTime>) overlaps period
                            // No registered conversion at the moment
                            return all "DrugExposure to Insulin Dose in [IU]"(e)),
        periodHours:  Quantity{
                        value: duration in hours of period,
                        unit:  'h'
                      }
      return totalInsulin / periodHours

define function "Last Energy Requirement Observation in Period"(period Interval<DateTime>):
  Last("Energy Requirement Observations" o
         where o.observationDatetime in period
         return all o)

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
    let energyRequirement: "Last Energy Requirement Observation in Period"(previousDay)
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
    let initialCalorieTarget:    "Initial Calorie Target"(previousPeriod),
        maybePreviousMaxInsulin: "Max Insulin Rate in Period"(previousPeriod),
        previousMaxInsulin:      if maybePreviousMaxInsulin is null then
                                   0 '[IU]/h'
                                 else
                                   maybePreviousMaxInsulin,
        rawTarget:               case
                                   when dayOfVisit = 0 then
                                     null // No target for first 24-hour period

                                   when dayOfVisit = 1 then
                                     0.75 * initialCalorieTarget

                                   when     not "Renal Replacement Therapy Procedure in Period"(previousPeriod)
                                        and "Last Phosphate Measurement in Period"(period) < 0.65 'mmol/l'
                                        and previousMaxInsulin <= 4 '[IU]/h'
                                        and previousTarget >= 0.5 * initialCalorieTarget then
                                     0.25 * initialCalorieTarget

                                   when previousMaxInsulin < 2 '[IU]/h' then
                                     previousTarget + 0.25 * initialCalorieTarget

                                   when previousMaxInsulin in Interval[2 '[IU]/h', 4 '[IU]/h'] then
                                     previousTarget - 0.25 * initialCalorieTarget

                                   when previousMaxInsulin > 4 '[IU]/h' then
                                     previousTarget - 0.5 * initialCalorieTarget

                                   else // TODO(moringenj): should be unreachable
                                     Message(null, true, '400', 'Error', 'No matching case; insulin ' + ToString(previousMaxInsulin) + ' previous target ' + ToString(previousTarget))
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
                                        insulin:        "Max Insulin Rate in Period"(r.previousPeriod),
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

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
  AgeInYearsAt(start of visitInterval) >= 18

// TODO(moringenj): Use contraindication to enteral feeding
define "Visit Results":
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit),
        goodPeriods:                 "24-hour Periods with appropriate Calorie Intake"(visitWithPeriods.allPeriods)
      return all (visitWithPeriods.periods) period
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     Count((goodPeriods) p where p includes period),
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
