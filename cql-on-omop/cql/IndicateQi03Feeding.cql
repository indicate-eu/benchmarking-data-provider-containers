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
include IndicateQiUtilities called U
include InsulinDrugs
include InsulinIngredients
include InsulinStrength

// Unit should be cal/d but could be reported as just cal in some
// cases.  The function "Maybe Rewrite Calorie Unit" unifies both cases
// to cal/d.
code "Estimated required quantity of energy in 24 hours": '604877' from elm.OMOPSV // observation

code "Contraindication to Enteral Feeding": '2100000009' from elm.OMOPSV // observation

// Unit should be cal/d but could be reported as just cal in some
// cases.  The function "Maybe Rewrite Calorie Unit" unifies both cases
// to cal/d.
code "Calorie Intake Total 24 Hour": '3026267' from elm.OMOPSV // measurement

code "CO2 Production Rate": '21490580' from elm.OMOPSV // measurement

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

code "Phosphate in Serum or Plasma (Moles/volume)": '3003458' from elm.OMOPSV
code "Phosphate in Blood (Moles/volume)":           '3018913' from elm.OMOPSV
code "Phosphate in Blood (Mass/volume)":            '3024232' from elm.OMOPSV

concept "Phosphate Measurement": {
  "Phosphate in Serum or Plasma (Moles/volume)",
  "Phosphate in Blood (Moles/volume)",
  "Phosphate in Blood (Mass/volume)"
}

context Patient

// Measurements and Procedures

define "Phosphate Measurements":
  [Measurement: "Phosphate Measurement"] m
    return all m
    sort by measurementDatetime desc

define "Insulin Exposures":
  [DrugExposure: InsulinDrugs."Insulin Drugs"]

define "Energy Requirement Observations":
  [Observation: "Estimated required quantity of energy in 24 hours"] o
    return all o
    sort by observationDatetime desc

define "Contraindication to Enteral Feeding Observations":
  [Observation: "Contraindication to Enteral Feeding"]

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
               // Source for conversion factor:
               // https://www.imd-berlin.de/leistungsverzeichnis/einheitenrechner
               U."EnsureQuantityIn mol/L"(
                 'Blood Phosphate Measurement', lastMeasurement,
                 'mg/L', 'mmol/L', 0.0323
               )

// Return as a Quantity with unit [IU] the amount of insulin
// administered in exposure scaled by the fraction of exposure that
// temporally overlaps period (e.g. for a exposure of 10 hours of which 5
// hours overlap period, the returned value would be half the amount in
// exposure).
//
// This function works correctly regardless of whether exposure and
// period do actually overlap.  However, the caller should check for an
// overlap first to avoid wasted computation.
define function "Insulin Strength for Period"(exposure DrugExposure,
                                              period   Interval<DateTime>):
  (1) _
    let exposureInterval: convert exposure to Interval<DateTime>,
        overlapInterval:  exposureInterval intersect period,
        overlapRatio:     duration in seconds of overlapInterval
                          / duration in seconds of exposureInterval,
        exposureStrengh:  InsulinStrength."Insulin Exposure"(
                            exposure,
                            InsulinIngredients."Insulin Ingredient Concepts"
                          )
      return overlapRatio * exposureStrengh

define function "Total Insulin Rate in Period"(period Interval<DateTime>):
  (1) _
    let totalInsulin: Sum(
                        "Insulin Exposures" e
                          where (convert e to Interval<DateTime>) overlaps period
                          return all "Insulin Strength for Period"(e, period)
                      ),
        periodHours:  Quantity{
                        value: duration in hours of period,
                        unit:  'h'
                      }
      return totalInsulin / periodHours

define function "Maybe Rewrite Calorie Unit"(quantity Quantity):
  // Assume that energy requirement/intake will be reported with
  // unit cal instead of cal/d in some cases.
  (1) _
    let inCal: convert quantity to 'cal'
      return if inCal is not null then
               Quantity{ value: inCal.value, unit: 'cal/d' }
             else
               quantity

// Return the daily energy requirement as a Quantity with unit kcal/d
// if there is a energy requirement observation in the given period.
// Otherwise return null.
define function "Last Energy Requirement Observation in Period"(period Interval<DateTime>):
  (1) _
    let observation: Last("Energy Requirement Observations" o
                            where o.observationDatetime in period
                            return all o),
        // The following returns null if observation is null.
        // TODO(moringenj): Use error-checking conversion
        quantity:    convert observation to Quantity
      return "Maybe Rewrite Calorie Unit"(quantity)

define function "Median CO2 Production Rate in Period"(period Interval<DateTime>):
  Median("CO2 Production Rate Measurements" m
           where (convert m to DateTime) in period
           return all convert m to Quantity)

define function "Calorie Intake in Period"(period Interval<DateTime>):
  // There should be exactly one such measurement in each 24-hour period.
  (1) _
    let measurements: "Calorie Intake Measurements" m
                        where m in period
                        return all m,
        measurement:  case Count(measurements)
                        when 0 then
                          null
                        when 1 then
                          First(measurements)
                        else
                          Message(First(measurements), true, '400', 'Warning',
                                  'Multiple calorie intake measurements in'
                                  + ' 24-hour period; using first measurement')
                      end,
        // The following returns null if observation is null.
        // TODO(moringenj): Use error-checking conversion
        quantity:     convert measurement to Quantity
      return "Maybe Rewrite Calorie Unit"(quantity)

define function "Renal Replacement Therapy Procedure in Period"(period Interval<DateTime>):
  Exists("Renal Replacement Therapy Procedures" p
           where (convert p to Interval<DateTime>) overlaps period
           return all p)

//

define function "Initial Calorie Target via CO2 Production Rate"(previousPeriod Interval<DateTime>):
  (1) _
    let bodyMassIndex:            elm."Body Mass Index Before"(end of previousPeriod),
        "co2Production":          "Median CO2 Production Rate in Period"(previousPeriod),
        "co2ProductionIn ml/min": convert "co2Production" to 'ml/min'
      return if     bodyMassIndex is not null
                and "co2ProductionIn ml/min" is not null then
               Quantity{
                 value: "co2ProductionIn ml/min".value
                        * 8.19
                        * if bodyMassIndex < 30 'kg/m2' then
                            1
                          else
                            0.6,
                 unit: 'kcal/d'
               }
             else
               null

define function "Initial Calorie Target via BMI"(targetTime DateTime):
  (1) _
    let bodyMassIndex: elm."Body Mass Index Before"(targetTime),
        bodyWeight:    elm."Most Recent Body Weight Measurement Before"(targetTime),
        bodyHeight:    elm."Most Recent Body Height Measurement Before"(targetTime)
      return case
               when bodyMassIndex is not null
                    and bodyWeight is not null
                    and bodyMassIndex < 30 'kg/m2' then
                 24 'kcal/d/kg' * U.EnsureQuantityWithUnit('Body weight', bodyWeight, 'kg')
               when bodyMassIndex is not null
                    and bodyWeight is not null
                    and bodyMassIndex <= 50 'kg/m2' then
                 14 'kcal/d/kg' * U.EnsureQuantityWithUnit('Body weight', bodyWeight, 'kg')
               when bodyHeight is not null then
                 24 'kcal/d/kg'
                 * elm."Ideal Body Weight for Height"(bodyHeight, Patient.genderConcept)
               else
                 null
             end

// Compute the initial calorie target in kcal/d with the given
// temporal interval indicating the previous day.  The previous day is
// important because the initial calorie target can be computed in
// multiple ways, all of which are time-dependent:
//
// * Via a documented energy requirement in which case the newest such
//   observation before the indicated time should be used
//
// * Via the CO2 production rate in which case, again, the newest such
//   observation before the indicate time should be used
//
// * Via the body mass index (BMI) which can use a documented body mass index
//   or a computed ideal body weight (IBW) for deriving the energy requirement.
//   The BMI or IBW are derived from time-dependent observations.
define function "Initial Calorie Target"(previousDay Interval<DateTime>):
  (1) _
    // TODO(moringenj): what temporal interval should we consider for the energy requirement?
    let energyRequirement: "Last Energy Requirement Observation in Period"(previousDay)
      return if energyRequirement is not null then
               energyRequirement
             else if "Median CO2 Production Rate in Period"(previousDay) is not null then
               "Initial Calorie Target via CO2 Production Rate"(previousDay)
             else
               (1) __
                 let viaBMI: "Initial Calorie Target via BMI"(end of previousDay)
                   return if viaBMI is null then
                            Message(null, true, '400', 'Error',
                                    'Could not determine initial calorie target'
                                    + ' via documented energy requirement,'
                                    + ' observed CO2 production rate or body'
                                    + ' mass index (neither documented nor'
                                    + ' computed)')
                          else
                            viaBMI

define function "Calorie Target for 24-hour Period"(previousTarget Quantity,
                                                    previousPeriod Interval<DateTime>,
                                                    period         Interval<DateTime>,
                                                    dayOfVisit     Integer):
  (1) _
    let initialCalorieTarget: "Initial Calorie Target"(previousPeriod),
        maybePreviousInsulin: "Total Insulin Rate in Period"(previousPeriod),
        previousInsulin:      if maybePreviousInsulin is null then
                                0 '[IU]/h'
                              else
                                maybePreviousInsulin,
        rawTarget:            case
                                when dayOfVisit = 0 then
                                  null // No target for first 24-hour period

                                when dayOfVisit = 1 then
                                  0.75 * initialCalorieTarget

                                when     not "Renal Replacement Therapy Procedure in Period"(previousPeriod)
                                     and "Last Phosphate Measurement in Period"(period) < 0.65 'mmol/l'
                                     and previousInsulin <= 4 '[IU]/h'
                                     and previousTarget >= 0.5 * initialCalorieTarget then
                                  0.25 * initialCalorieTarget

                                when previousInsulin < 2 '[IU]/h' then
                                  previousTarget + 0.25 * initialCalorieTarget

                                when previousInsulin in Interval[2 '[IU]/h', 4 '[IU]/h'] then
                                  previousTarget - 0.25 * initialCalorieTarget

                                when previousInsulin > 4 '[IU]/h' then
                                  previousTarget - 0.5 * initialCalorieTarget

                                else // NOTE(moringenj): should be unreachable
                                  Message(null, true, '400', 'Error',
                                          'No matching case; insulin '
                                          + ToString(previousInsulin) +
                                          ' previous target '
                                          + ToString(previousTarget))
                              end
      // Clamp calorie target to [0, Initial Calorie Target]; the
      // value could be outside of this range due to the unchecked
      // additions and subtractions above.  Exception: the target for
      // day 0 is null.
      return case
               when rawTarget is not null then
                 Max({0 'kcal/d', Min({rawTarget, initialCalorieTarget})})
               when dayOfVisit = 0 then
                 null
               else
                 Message(null, true, '400', 'Error', 'Calorie target is null')
             end

define function "24-hour Periods with Results"(periods List<Interval<DateTime>>):
  (periods) p aggregate r starting ({
                                      previousPeriod: null,
                                      previousTarget: null,
                                      dayOfVisit:     0,
                                      results:        {}
                                    }):
    (1) _
      // In the following, if target is null (which is the case when
      // dayOfVisit is 0), result is true.  If "Calorie Intake in
      // Period"(p) is null, result is also null and then the results
      // property of the accumulator is left unchanged so the period
      // not counted as "good".
      let target: "Calorie Target for 24-hour Period"(
                    r.previousTarget,
                    r.previousPeriod,
                    p,
                    r.dayOfVisit
                  ),
          actual: "Calorie Intake in Period"(p),
          result:    target is null
                  or 0.9 * target <= actual and actual <= 1.1 * target
        return {
                 previousPeriod: p,
                 previousTarget: target,
                 dayOfVisit:     r.dayOfVisit + 1,
                 results:        if result then
                                   Flatten({r.results, {p}})
                                 else
                                   r.results
               }

define function "24-hour Periods with appropriate Calorie Intake"(periods List<Interval<DateTime>>):
  "24-hour Periods with Results"(periods).results

// Quality Indicator

define function "Is in Initial Population"(visitInterval Interval<DateTime>):
  AgeInYearsAt(start of visitInterval) >= 18

define "Visit Results":
  // Timeline for one visit:
  //
  // * Incomplete 24-hour period
  //   Ignored; No QI result
  // * First complete 24-hour period ("day 0", CTD0)
  //   Calorie target CTD0: no calorie target
  //   No QI result
  // * Second complete 24-hour period ("day 1", CTD1)
  //   calorie target CTD1: 0.75 * ICT
  //   QI result unless contraindication
  // * Third complete 24-hour period ("day i", CTDi)
  //   Calorie target CTDi: according to formula
  //   QI result unless contraindication
  // ...
  // * Last complete 24-hour period ("day i", CTDi)
  //   Calorie target CTDi: according to formula
  //   QI result unless contraindication
  // * Incomplete 24-hour period
  //   Ignored; No QI result
  (T."Visits with 24-hour Periods") visitWithPeriods
    let inInitialPopulationForVisit: "Is in Initial Population"(visitWithPeriods.visit),
        goodPeriods:                 "24-hour Periods with appropriate Calorie Intake"(
                                       visitWithPeriods.fullyContainedPeriods
                                     )
      // Produce QI results according to the timeline above:
      // * Skip (no QI result) the first complete 24-hour period
      // * Skip (no QI result) any period which contains a contraindication
      //   observation
      return all (Skip(visitWithPeriods.fullyContainedPeriods, 1)) period
                   where not Exists("Contraindication to Enteral Feeding Observations" o
                                      where o in period
                                      return all o)
                   return all elm."Period Result"(
                     period,
                     inInitialPopulationForVisit,
                     // There is either 0 or 1 good periods during period.
                     // TODO: we can probably change this to p = period later
                     Count((goodPeriods) p where p during period),
                     1
                   )

define Result: elm."Overall Result"(Patient, "Visit Results")
